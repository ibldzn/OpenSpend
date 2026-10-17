import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct SettingsView: View {
    let account: ExpenseAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(UpdateChecker.self) private var updateChecker
    @AppStorage(SettingsKey.defaultCurrency, store: AppGroup.defaults) private var defaultCurrency = "USD"
    @AppStorage(SettingsKey.weekStartDay, store: AppGroup.defaults) private var weekStartDay = WeekStartDay.monday.rawValue
    @State private var logoTaps = 0
    @AppStorage("showAdvancedSettings") private var showAdvanced = false
    @State private var web: IdentifiableURL?

    var body: some View {
        NavigationStack {
            List {
                header

                if let update = updateChecker.available {
                    Section {
                        Button { web = IdentifiableURL(url: update.url) } label: {
                            SettingsRow(icon: "arrow.down.circle", color: .blue, title: "Update to \(update.version)") {
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Account") {
                    NavigationLink { AccountSettingsView(account: account) } label: {
                        SettingsRow(icon: account.iconName, color: .indigo, title: account.name) {
                            Text(account.type == .sheets ? "Sheets" : "Local")
                        }
                    }
                    NavigationLink { ManageAccountsView() } label: {
                        SettingsRow(icon: "person.2", color: .blue, title: "Manage Accounts")
                    }
                    NavigationLink { ManageConnectionsView() } label: {
                        SettingsRow(icon: "tablecells", color: .green, title: "Google Accounts")
                    }
                }

                Section("Preferences") {
                    NavigationLink { CurrencyPickerView(selection: $defaultCurrency) } label: {
                        SettingsRow(icon: "dollarsign.circle", color: .green, title: "Default Currency") { Text(defaultCurrency) }
                    }
                    Picker(selection: $weekStartDay) {
                        ForEach(WeekStartDay.allCases) { Text($0.title).tag($0.rawValue) }
                    } label: {
                        SettingsRow(icon: "calendar", color: .red, title: "Week Starts On")
                    }
                    NavigationLink { SmartSuggestionsSettingsView() } label: {
                        SettingsRow(icon: "sparkles", color: .purple, title: "Smart Suggestions")
                    }
                    NavigationLink { ShortcutSettingsView() } label: {
                        SettingsRow(icon: "square.stack.3d.up", color: .pink, title: "Shortcuts")
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        SettingsRow(icon: "bell.badge", color: .orange, title: "Notifications")
                    }
                }

                Section("Get More Out of OpenSpend") {
                    NavigationLink { WidgetsGuideView() } label: {
                        SettingsRow(icon: "square.grid.2x2", color: .teal, title: "Widgets")
                    }
                    NavigationLink { ShortcutsGuideView() } label: {
                        SettingsRow(icon: "bolt.fill", color: .yellow, title: "Shortcuts & Tap to Pay")
                    }
                    NavigationLink { TutorialsView() } label: {
                        SettingsRow(icon: "graduationcap", color: .cyan, title: "Tutorials")
                    }
                }

                Section("Support") {
                    NavigationLink { HelpAndFeedbackView() } label: {
                        SettingsRow(icon: "questionmark.bubble", color: .blue, title: "Help & Feedback")
                    }
                    NavigationLink { FollowUsView() } label: {
                        SettingsRow(icon: "heart", color: .pink, title: "Follow Us")
                    }
                    NavigationLink { ChangelogView() } label: {
                        SettingsRow(icon: "newspaper", color: .gray, title: "What's New")
                    }
                }

                if showAdvanced {
                    Section {
                        NavigationLink { AdvancedSettingsView() } label: {
                            SettingsRow(icon: "wrench.and.screwdriver", color: .gray, title: "Advanced")
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text("Version \(AppInfo.version) (\(AppInfo.build))").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() } }
            .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
            .onChange(of: weekStartDay) { WidgetCenterReload.now() }
        }
    }

    /// App mark. Tapping it seven times toggles the Advanced section.
    private var header: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 18))
                    .onTapGesture {
                        logoTaps += 1
                        if logoTaps >= 7 { showAdvanced.toggle(); logoTaps = 0; Haptics.success() }
                    }
                Text("OpenSpend").font(.title3.bold())
                Text("Expenses that live in your spreadsheet.").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
    }
}

enum WidgetCenterReload {
    static func now() { WidgetCenter.shared.reloadAllTimelines() }
}

struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private static let all: [(code: String, name: String)] = Locale.Currency.isoCurrencies
        .map { ($0.identifier, Locale.current.localizedString(forCurrencyCode: $0.identifier) ?? $0.identifier) }
        .sorted { $0.name < $1.name }

    private var filtered: [(code: String, name: String)] {
        search.isEmpty ? Self.all : Self.all.filter { $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(filtered, id: \.code) { c in
            Button {
                selection = c.code
                Haptics.tap()
                dismiss()
            } label: {
                HStack {
                    Text(Money.symbol(for: c.code)).frame(width: 40, alignment: .leading).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(c.name).foregroundStyle(.primary)
                        Text(c.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.code == selection { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).bold() }
                }
            }
        }
        .searchable(text: $search, prompt: "Search currencies")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SmartSuggestionsSettingsView: View {
    @AppStorage(SettingsKey.enableSmartSuggestions, store: AppGroup.defaults) private var smart = true
    @AppStorage(SettingsKey.titleSuggestionsEnabled, store: AppGroup.defaults) private var titles = true

    var body: some View {
        Form {
            Section {
                Toggle("Suggest Category & Payment", isOn: $smart)
            } footer: {
                Text("While you type a title, OpenSpend picks a likely category and payment method. It learns from your past expenses and runs fully on device.")
            }
            Section {
                Toggle("Title Suggestions", isOn: $titles)
            } footer: {
                Text("Show matching past expenses under the title field. Picking one fills in the amount, category and payment method.")
            }
        }
        .navigationTitle("Smart Suggestions")
    }
}

struct ShortcutSettingsView: View {
    @AppStorage(SettingsKey.confirmExpenseDetails, store: AppGroup.defaults) private var confirm = true
    @AppStorage(SettingsKey.enableGoBack, store: AppGroup.defaults) private var goBack = true

    var body: some View {
        Form {
            Section {
                Toggle("Confirm Expense Details", isOn: $confirm)
            } footer: {
                Text("Ask for confirmation before the Add Expense shortcut saves. Turn off to save immediately.")
            }
            Section {
                Toggle("Show Go Back Option", isOn: $goBack)
            } footer: {
                Text("Adds a Go Back choice when the shortcut asks for the account, category or payment method.")
            }
            Section {
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Shortcuts")
    }
}

struct AdvancedSettingsView: View {
    @AppStorage(SettingsKey.rowsPerRequest, store: AppGroup.defaults) private var rowsPerRequest = 500
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = true
    @AppStorage(SettingsKey.lastSeenVersion, store: AppGroup.defaults) private var lastSeenVersion = ""

    var body: some View {
        Form {
            Section {
                Stepper("Rows per request: \(rowsPerRequest)", value: $rowsPerRequest, in: 100...5000, step: 100)
            } footer: {
                Text("How many sheet rows are read per Google Sheets request. Lower values help on slow connections.")
            }
            Section {
                NavigationLink("Debug Console") { DebugConsoleView() }
                Button("Show Onboarding Again") { hasCompletedOnboarding = false }
                Button("Show What's New Again") { lastSeenVersion = "0" }
            }
        }
        .navigationTitle("Advanced")
    }
}

struct DebugConsoleView: View {
    @State private var logger = DebugLogger.shared
    @State private var search = ""
    @State private var copied = false

    private var entries: [DebugLogger.Entry] {
        let all = logger.entries.reversed()
        return search.isEmpty ? Array(all) : all.filter { $0.message.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(entries) { e in
            VStack(alignment: .leading, spacing: 2) {
                Text(e.timestamp.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                Text(e.message).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .overlay { if entries.isEmpty { ContentUnavailableView("No logs", systemImage: "terminal") } }
        .searchable(text: $search)
        .navigationTitle("Debug Console")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = logger.entries.map { "\($0.timestamp.ISO8601Format()) \($0.message)" }.joined(separator: "\n")
                    copied = true
                }
                Button("Clear", role: .destructive) { logger.clear() }
            }
        }
    }
}
