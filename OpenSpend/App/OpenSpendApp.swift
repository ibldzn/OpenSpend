import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct OpenSpendApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if SharedModelContainer.isUITesting { AppGroup.defaults.removePersistentDomain(forName: AppGroup.id) }
        Settings.register()
        DemoData.seedIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SharedModelContainer.shared)
        .backgroundTask(.appRefresh(BackgroundSync.identifier)) {
            await BackgroundSync.run()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundSync.schedule()
                NotificationManager.shared.rescheduleDailyReminder()
            }
        }
    }
}

enum BackgroundSync {
    static let identifier = (Bundle.main.bundleIdentifier ?? "OpenSpend") + ".refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()
        let result = await ExpenseSyncService.shared.syncAll(context: SharedModelContainer.shared.mainContext, quiet: true)
        if result.pulledNew > 0 {
            NotificationManager.shared.notifySynced(count: result.pulledNew)
        }
    }
}

/// Cross-view navigation requests (deep links, shortcuts, widget taps).
@Observable
final class AppRouter {
    var showCreateExpense = false

    /// openspend://add opens the new expense sheet.
    func handle(_ url: URL) {
        guard url.scheme == "openspend" else { return }
        if url.host == "add" { showCreateExpense = true }
    }
}
