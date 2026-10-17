import Foundation
import SwiftData

/// Sample data for UI tests and screenshots (`-uiTesting -seedDemo`). Never runs otherwise.
@MainActor
enum DemoData {
    static func seedIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), args.contains("-seedDemo") else { return }
        let context = SharedModelContainer.shared.mainContext

        let account = ExpenseAccount(name: "Personal", type: .local, sortOrder: 0)
        context.insert(account)
        DefaultOptions.seed(for: account, context: context)

        let cal = Calendar.current
        let samples: [(String, Double, String, String, Int, Int)] = [
            ("Groceries at FreshMart", 64.80, "Groceries", "Card", 0, 18),
            ("Morning coffee", 4.50, "Food", "Apple Pay", 0, 8),
            ("Train pass top-up", 25.00, "Transport", "Card", 1, 9),
            ("Lunch with team", 18.40, "Food", "Card", 1, 13),
            ("Electricity bill", 82.15, "Bills", "Bank Transfer", 2, 10),
            ("Movie night", 24.00, "Entertainment", "Apple Pay", 3, 20),
            ("Running shoes", 119.00, "Shopping", "Card", 5, 16),
            ("Pharmacy", 12.30, "Health", "Cash", 6, 11),
            ("Weekly groceries", 71.25, "Groceries", "Card", 7, 17),
            ("Taxi home", 16.90, "Transport", "Apple Pay", 8, 23),
            ("Dinner out", 46.00, "Food", "Card", 9, 20),
            ("Streaming subscription", 11.99, "Entertainment", "Card", 11, 7),
        ]
        for (title, amount, category, payment, daysAgo, hour) in samples {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            let date = cal.date(bySettingHour: hour, minute: 15, second: 0, of: day)!
            context.insert(Expense(accountId: account.id, title: title, amount: amount, currency: Settings.defaultCurrency,
                                   date: date, categories: [category], payments: [payment]))
        }
        try? context.save()
        AppGroup.defaults.set(account.id.uuidString, forKey: SettingsKey.activeAccountId)
        AppGroup.defaults.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        AppGroup.defaults.set(AppInfo.version, forKey: SettingsKey.lastSeenVersion)
    }
}
