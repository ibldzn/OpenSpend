import Foundation
import SwiftData

enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group.com.example.OpenSpend"
    static let defaults = UserDefaults(suiteName: id) ?? .standard
}

/// Keys for settings shared between the app, intents and the widget (stored in `AppGroup.defaults`).
enum SettingsKey {
    static let activeAccountId = "activeAccountId"
    static let defaultCurrency = "defaultCurrency"
    static let weekStartDay = "weekStartDay"
    static let confirmExpenseDetails = "confirmExpenseDetails"
    static let enableGoBack = "enableGoBack"
    static let enableSmartSuggestions = "enableSmartSuggestions"
    static let titleSuggestionsEnabled = "expenseTitleSuggestionsEnabled"
    static let rowsPerRequest = "rowsPerRequest"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let lastSeenVersion = "lastSeenVersion"
    static let dailyReminderEnabled = "dailyReminderEnabled"
    static let dailyReminderMinutes = "dailyReminderMinutes"
    static let syncAlertsEnabled = "syncAlertsEnabled"
}

enum Settings {
    static func register() {
        AppGroup.defaults.register(defaults: [
            SettingsKey.defaultCurrency: Locale.current.currency?.identifier ?? "USD",
            SettingsKey.weekStartDay: WeekStartDay.monday.rawValue,
            SettingsKey.confirmExpenseDetails: true,
            SettingsKey.enableGoBack: true,
            SettingsKey.enableSmartSuggestions: true,
            SettingsKey.titleSuggestionsEnabled: true,
            SettingsKey.rowsPerRequest: 500,
            SettingsKey.dailyReminderMinutes: 20 * 60,
            SettingsKey.syncAlertsEnabled: true,
        ])
    }

    static var defaultCurrency: String { AppGroup.defaults.string(forKey: SettingsKey.defaultCurrency) ?? "USD" }
    static var weekStartDay: WeekStartDay {
        WeekStartDay(rawValue: AppGroup.defaults.string(forKey: SettingsKey.weekStartDay) ?? "") ?? .monday
    }
    static var activeAccountId: UUID? {
        AppGroup.defaults.string(forKey: SettingsKey.activeAccountId).flatMap(UUID.init(uuidString:))
    }
    static func bool(_ key: String) -> Bool { AppGroup.defaults.bool(forKey: key) }
}

enum SharedModelContainer {
    static let schema = Schema([ExpenseAccount.self, ExpenseCategory.self, ExpensePayment.self, Expense.self, GoogleConnection.self])

    /// Set by UI tests: start from an empty in-memory store.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    static let shared: ModelContainer = {
        if isUITesting {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        // SwiftData traps (not throws) when the app group is missing from the entitlements,
        // e.g. unsigned simulator builds. Resolve the folder ourselves and fall back to the
        // app's own container; the widget then just can't see the data.
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: base.appending(path: "OpenSpend.store"), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }()
}
