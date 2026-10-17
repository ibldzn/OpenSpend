import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = false
    @AppStorage(SettingsKey.lastSeenVersion, store: AppGroup.defaults) private var lastSeenVersion = ""
    @State private var router = AppRouter()
    @State private var showWhatsNew = false
    @State private var updateChecker = UpdateChecker()

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else if accounts.isEmpty {
                AccountSetupView()
            } else {
                HomeView()
            }
        }
        .environment(router)
        .environment(updateChecker)
        .onOpenURL { router.handle($0) }
        .task {
            await updateChecker.check()
            // Show "What's New" once per version, but not on a fresh install.
            if lastSeenVersion.isEmpty {
                lastSeenVersion = AppInfo.version
            } else if lastSeenVersion != AppInfo.version && Changelog.entries.first?.version == AppInfo.version {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: { lastSeenVersion = AppInfo.version }) {
            WhatsNewView(entry: Changelog.entries[0])
        }
    }
}

/// First-run screen when no account exists yet.
struct AccountSetupView: View {
    var body: some View {
        NavigationStack {
            ChooseAccountTypeView(isFirstAccount: true)
        }
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
