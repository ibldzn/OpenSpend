import Foundation
import Observation
import SwiftData
import WidgetKit

/// Two-way sync between local expenses and one Google Sheets tab per account.
///
/// Each row carries a hidden "OpenSpend ID" column so rows can be matched after the
/// user sorts, inserts or edits the sheet by hand. Every sync reads the whole tab:
/// Sheets has no change feed, and one values.get per chunk is cheap.
@MainActor
@Observable
final class ExpenseSyncService {
    static let shared = ExpenseSyncService()

    enum Status: Equatable {
        case idle
        case syncing(accountName: String)
        case success(String)
        case failed(String)
    }

    struct Result {
        var pulledNew = 0
        var pulledChanged = 0
        var removed = 0
        var pushed = 0
    }

    var status: Status = .idle
    private(set) var syncing: Set<UUID> = []
    private var rerun: Set<UUID> = []
    private var lastFetch: [UUID: Date] = [:]
    private let minimumAutoFetchInterval: TimeInterval = 60

    var isSyncing: Bool { !syncing.isEmpty }

    /// Sync unless one ran recently. Used on appear / foreground.
    func autoSync(_ account: ExpenseAccount, context: ModelContext) async {
        if let last = lastFetch[account.id], Date().timeIntervalSince(last) < minimumAutoFetchInterval { return }
        await sync(account, context: context)
    }

    /// `full` discards the local copy of synced rows and rebuilds it from the sheet.
    @discardableResult
    func sync(_ account: ExpenseAccount, context: ModelContext, full: Bool = false, quiet: Bool = false) async -> Result? {
        guard account.isLinked else { return nil }
        guard !syncing.contains(account.id) else {
            rerun.insert(account.id)
            return nil
        }
        syncing.insert(account.id)
        if !quiet { status = .syncing(accountName: account.name) }
        defer { syncing.remove(account.id) }

        do {
            let result = try await performSync(account, context: context, full: full)
            lastFetch[account.id] = Date()
            account.lastSyncedAt = Date()
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
            DebugLogger.shared.log("Synced \(account.name): +\(result.pulledNew) ~\(result.pulledChanged) -\(result.removed) pushed \(result.pushed)")
            if !quiet { status = .success("Synced with Google Sheets") }
            if rerun.remove(account.id) != nil {
                syncing.remove(account.id)
                return await sync(account, context: context, quiet: quiet)
            }
            return result
        } catch {
            rerun.remove(account.id)
            DebugLogger.shared.log("Error syncing \(account.name): \(error.localizedDescription)")
            if !quiet { status = .failed(error.localizedDescription) }
            return nil
        }
    }

    func syncAll(context: ModelContext, quiet: Bool) async -> Result {
        var total = Result()
        let accounts = (try? context.fetch(FetchDescriptor<ExpenseAccount>())) ?? []
        for a in accounts where a.isLinked {
            if let r = await sync(a, context: context, quiet: quiet) {
                total.pulledNew += r.pulledNew
                total.pulledChanged += r.pulledChanged
                total.removed += r.removed
                total.pushed += r.pushed
            }
        }
        return total
    }

    // MARK: Core

    private func performSync(_ account: ExpenseAccount, context: ModelContext, full: Bool) async throws -> Result {
        guard let email = account.connectionEmail, let spreadsheetId = account.spreadsheetId,
              let sheet = account.sheetTitle, let map = account.columnMap else { return Result() }
        let api = SheetsAPI(email: email)
        let accountId = account.id
        var result = Result()

        // 1. Header row; add the ID column if this sheet has never been synced.
        var header = try await api.values(spreadsheetId: spreadsheetId, range: SheetCodec.a1(sheet: sheet, "1:1")).first?.map { SheetCodec.string($0) } ?? []
        let indexes = try SheetCodec.indexes(header: header, map: map)
        let idIndex: Int
        if let i = SheetCodec.idIndex(header: header) {
            idIndex = i
        } else {
            idIndex = header.count
            header.append(SheetCodec.idHeader)
            try await api.update(spreadsheetId: spreadsheetId, range: SheetCodec.a1(sheet: sheet, "\(SheetCodec.columnLetter(idIndex))1"), values: [[SheetCodec.idHeader]])
        }

        // 2. Data rows, chunked by the "rows per request" setting.
        let chunk = max(50, AppGroup.defaults.integer(forKey: SettingsKey.rowsPerRequest))
        var rows: [DecodedRow] = []
        var start = 2
        while true {
            let end = start + chunk - 1
            let page = try await api.values(spreadsheetId: spreadsheetId, range: SheetCodec.a1(sheet: sheet, "A\(start):ZZ\(end)"))
            if page.isEmpty { break }
            for (offset, raw) in page.enumerated() {
                if let r = SheetCodec.decode(row: raw, rowNumber: start + offset, indexes: indexes, idIndex: idIndex, defaultCurrency: Settings.defaultCurrency) {
                    rows.append(r)
                }
            }
            start = end + 1
        }

        // 3. Give hand-entered rows (or rows with a mangled ID) an ID.
        var idWrites: [(range: String, values: [[Any]])] = []
        var seen = Set<String>()
        for i in rows.indices {
            if let id = rows[i].id, UUID(uuidString: id) != nil, !seen.contains(id) {
                seen.insert(id)
                continue
            }
            let id = UUID().uuidString
            rows[i].id = id
            seen.insert(id)
            idWrites.append((SheetCodec.a1(sheet: sheet, "\(SheetCodec.columnLetter(idIndex))\(rows[i].rowNumber)"), [[id]]))
        }
        try await api.batchUpdateValues(spreadsheetId: spreadsheetId, data: idWrites)

        var remote: [UUID: DecodedRow] = [:]
        for r in rows { if let id = r.id.flatMap(UUID.init(uuidString:)) { remote[id] = r } }

        // 4. Push local changes.
        let local = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.accountId == accountId }))) ?? []
        var updates: [(range: String, values: [[Any]])] = []
        var appends: [[Any]] = []
        var deleteRows: [Int] = []
        var pushedExpenses: [Expense] = []
        var deletedExpenses: [Expense] = []
        let lastCol = SheetCodec.columnLetter(max(header.count - 1, idIndex))
        for e in local {
            switch e.syncState {
            case .synced: continue
            case .pendingDelete:
                if let r = remote[e.id] { deleteRows.append(r.rowNumber); remote[e.id] = nil }
                deletedExpenses.append(e)
            case .pendingUpdate, .pendingCreate:
                if let r = remote[e.id] {
                    let row = SheetCodec.encode(e.fields, id: e.id.uuidString, indexes: indexes, idIndex: idIndex, base: r.raw)
                    updates.append((SheetCodec.a1(sheet: sheet, "A\(r.rowNumber):\(lastCol)\(r.rowNumber)"), [row]))
                    remote[e.id]?.fields = e.fields
                } else {
                    // New, or deleted from the sheet while edited here: the local edit wins.
                    appends.append(SheetCodec.encode(e.fields, id: e.id.uuidString, indexes: indexes, idIndex: idIndex))
                    remote[e.id] = DecodedRow(rowNumber: 0, id: e.id.uuidString, fields: e.fields, raw: [])
                }
                pushedExpenses.append(e)
            }
            result.pushed += 1
        }
        try await api.batchUpdateValues(spreadsheetId: spreadsheetId, data: updates)
        try await api.append(spreadsheetId: spreadsheetId, sheet: sheet, values: appends)
        if let sheetId = account.sheetId {
            try await api.deleteRows(spreadsheetId: spreadsheetId, sheetId: sheetId, rows: deleteRows)
        }
        // Only now that every write succeeded do local records count as synced.
        pushedExpenses.forEach { $0.syncState = .synced }
        deletedExpenses.forEach { context.delete($0) }

        // 5. Pull remote state into the local store.
        var byId: [UUID: Expense] = [:]
        for e in local where !e.isDeleted { byId[e.id] = e }
        if full {
            for (id, e) in byId where e.syncState == .synced && remote[id] == nil {
                context.delete(e)
                byId[id] = nil
            }
        }
        for (id, r) in remote {
            if let e = byId[id] {
                if e.fields != r.fields && e.syncState == .synced {
                    e.apply(r.fields)
                    result.pulledChanged += 1
                }
            } else {
                let e = Expense(id: id, accountId: accountId, title: r.fields.title, amount: r.fields.amount, currency: r.fields.currency,
                                date: r.fields.date, categories: r.fields.categories, payments: r.fields.payments,
                                notes: r.fields.notes, tags: r.fields.tags)
                context.insert(e)
                result.pulledNew += 1
            }
        }
        for (id, e) in byId where remote[id] == nil && e.syncState == .synced {
            context.delete(e)
            result.removed += 1
        }

        // 6. Options typed into the sheet become categories / payment methods.
        mergeOptions(Set(remote.values.flatMap(\.fields.categories)), into: account, kind: .category, context: context)
        mergeOptions(Set(remote.values.flatMap(\.fields.payments)), into: account, kind: .payment, context: context)
        return result
    }

    private func mergeOptions(_ names: Set<String>, into account: ExpenseAccount, kind: OptionKind, context: ModelContext) {
        let accountId = account.id
        switch kind {
        case .category:
            let existing = (try? context.fetch(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.accountId == accountId }))) ?? []
            let known = Set(existing.map { $0.name.lowercased() })
            for (i, n) in names.sorted().enumerated() where !known.contains(n.lowercased()) {
                context.insert(ExpenseCategory(accountId: accountId, name: n, iconName: IconCatalog.guessCategoryIcon(n), sortOrder: existing.count + i))
            }
        case .payment:
            let existing = (try? context.fetch(FetchDescriptor<ExpensePayment>(predicate: #Predicate { $0.accountId == accountId }))) ?? []
            let known = Set(existing.map { $0.name.lowercased() })
            for (i, n) in names.sorted().enumerated() where !known.contains(n.lowercased()) {
                context.insert(ExpensePayment(accountId: accountId, name: n, iconName: IconCatalog.guessPaymentIcon(n), sortOrder: existing.count + i))
            }
        }
    }
}

enum OptionKind {
    case category, payment
}
