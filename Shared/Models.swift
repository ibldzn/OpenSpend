import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case local
    case sheets
}

enum SyncState: String, Codable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete
}

@Model
final class ExpenseAccount {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "wallet.bifold"
    var typeRaw: String = AccountType.local.rawValue
    var sortOrder: Int = 0
    var homeFilterPeriodRaw: String = FilterPeriod.thisMonth.rawValue
    var homeSelectedCategoryNames: [String] = []
    var homeSelectedPaymentNames: [String] = []
    // Google Sheets link (only for .sheets accounts)
    var connectionEmail: String?
    var spreadsheetId: String?
    var spreadsheetName: String?
    var sheetTitle: String?
    var sheetId: Int?
    var columnMapData: Data?
    var lastSyncedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, type: AccountType, sortOrder: Int, iconName: String = "wallet.bifold") {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.sortOrder = sortOrder
        self.iconName = iconName
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .local }
        set { typeRaw = newValue.rawValue }
    }

    var filterPeriod: FilterPeriod {
        get { FilterPeriod(rawValue: homeFilterPeriodRaw) ?? .thisMonth }
        set { homeFilterPeriodRaw = newValue.rawValue }
    }

    var columnMap: ColumnMap? {
        get { columnMapData.flatMap { try? JSONDecoder().decode(ColumnMap.self, from: $0) } }
        set { columnMapData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var hasSpreadsheet: Bool { spreadsheetId != nil && sheetTitle != nil }
    var isLinked: Bool { type == .sheets && hasSpreadsheet && columnMap != nil && connectionEmail != nil }

    func clearSheetLink() {
        spreadsheetId = nil
        spreadsheetName = nil
        sheetTitle = nil
        sheetId = nil
        columnMapData = nil
        lastSyncedAt = nil
    }
}

@Model
final class ExpenseCategory {
    @Attribute(.unique) var id: UUID = UUID()
    var accountId: UUID = UUID()
    var name: String = ""
    var iconName: String = "tag"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(accountId: UUID, name: String, iconName: String, sortOrder: Int) {
        self.id = UUID()
        self.accountId = accountId
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}

@Model
final class ExpensePayment {
    @Attribute(.unique) var id: UUID = UUID()
    var accountId: UUID = UUID()
    var name: String = ""
    var iconName: String = "creditcard"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(accountId: UUID, name: String, iconName: String, sortOrder: Int) {
        self.id = UUID()
        self.accountId = accountId
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}

@Model
final class Expense {
    @Attribute(.unique) var id: UUID = UUID()
    var accountId: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var currency: String = "USD"
    var date: Date = Date()
    var categories: [String] = []
    var payments: [String] = []
    var notes: String = ""
    var tags: [String] = []
    /// Soft delete while a remote delete is pending.
    var isTrashed: Bool = false
    var syncStateRaw: String = SyncState.synced.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), accountId: UUID, title: String, amount: Double, currency: String, date: Date,
         categories: [String] = [], payments: [String] = [], notes: String = "", tags: [String] = []) {
        self.id = id
        self.accountId = accountId
        self.title = title
        self.amount = amount
        self.currency = currency
        self.date = date
        self.categories = categories
        self.payments = payments
        self.notes = notes
        self.tags = tags
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    var fields: ExpenseFields {
        ExpenseFields(title: title, amount: amount, currency: currency, date: date,
                      categories: categories, payments: payments, notes: notes, tags: tags)
    }

    func apply(_ f: ExpenseFields) {
        title = f.title
        amount = f.amount
        currency = f.currency
        date = f.date
        categories = f.categories
        payments = f.payments
        notes = f.notes
        tags = f.tags
        updatedAt = Date()
    }
}

/// A Google account the user signed in with. Tokens live in the Keychain, keyed by email.
@Model
final class GoogleConnection {
    @Attribute(.unique) var email: String = ""
    var displayName: String = ""
    var createdAt: Date = Date()

    init(email: String, displayName: String) {
        self.email = email
        self.displayName = displayName
    }
}
