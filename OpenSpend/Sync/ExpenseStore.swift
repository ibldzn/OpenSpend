import Foundation
import SwiftData
import WidgetKit

/// All local writes go through here so sync state and widgets stay consistent.
@MainActor
enum ExpenseStore {
    @discardableResult
    static func create(_ fields: ExpenseFields, in account: ExpenseAccount, context: ModelContext, syncNow: Bool = true) -> Expense {
        let e = Expense(accountId: account.id, title: fields.title, amount: fields.amount, currency: fields.currency, date: fields.date,
                        categories: fields.categories, payments: fields.payments, notes: fields.notes, tags: fields.tags)
        e.syncState = account.type == .sheets ? .pendingCreate : .synced
        context.insert(e)
        finish(account, context: context, syncNow: syncNow)
        return e
    }

    static func update(_ e: Expense, with fields: ExpenseFields, in account: ExpenseAccount, context: ModelContext) {
        e.apply(fields)
        if account.type == .sheets && e.syncState == .synced { e.syncState = .pendingUpdate }
        finish(account, context: context, syncNow: true)
    }

    static func delete(_ e: Expense, in account: ExpenseAccount, context: ModelContext) {
        if account.type == .sheets && e.syncState != .pendingCreate {
            e.isTrashed = true
            e.syncState = .pendingDelete
        } else {
            context.delete(e)
        }
        finish(account, context: context, syncNow: true)
    }

    /// Removes the account and everything scoped to it from the app. Never touches the sheet.
    static func deleteAccount(_ account: ExpenseAccount, context: ModelContext) {
        let id = account.id
        try? context.delete(model: Expense.self, where: #Predicate { $0.accountId == id })
        try? context.delete(model: ExpenseCategory.self, where: #Predicate { $0.accountId == id })
        try? context.delete(model: ExpensePayment.self, where: #Predicate { $0.accountId == id })
        context.delete(account)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Drops all local expenses for an account (used when changing or unlinking its sheet).
    static func clearExpenses(of account: ExpenseAccount, context: ModelContext) {
        let id = account.id
        try? context.delete(model: Expense.self, where: #Predicate { $0.accountId == id })
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Renaming an option rewrites the name on every expense that uses it.
    static func renameOption(kind: OptionKind, from old: String, to new: String, in account: ExpenseAccount, context: ModelContext) {
        guard old != new else { return }
        for e in EntityData.expenses(accountId: account.id) {
            var touched = false
            switch kind {
            case .category:
                if let i = e.categories.firstIndex(of: old) { e.categories[i] = new; touched = true }
            case .payment:
                if let i = e.payments.firstIndex(of: old) { e.payments[i] = new; touched = true }
            }
            if touched && account.type == .sheets && e.syncState == .synced { e.syncState = .pendingUpdate }
        }
        finish(account, context: context, syncNow: true)
    }

    private static func finish(_ account: ExpenseAccount, context: ModelContext, syncNow: Bool) {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        if syncNow && account.isLinked {
            Task { await ExpenseSyncService.shared.sync(account, context: context) }
        }
    }
}
