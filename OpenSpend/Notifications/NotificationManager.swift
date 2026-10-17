import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    enum Permission { case unknown, notDetermined, granted, denied }

    var permission: Permission = .unknown
    private let center = UNUserNotificationCenter.current()
    private let reminderId = "daily-reminder"

    func refresh() async {
        let s = await center.notificationSettings()
        switch s.authorizationStatus {
        case .notDetermined: permission = .notDetermined
        case .denied: permission = .denied
        default: permission = .granted
        }
    }

    @discardableResult
    func request() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refresh()
        if granted { rescheduleDailyReminder() }
        return granted
    }

    /// Daily "log your spending" nudge, with today's total so far in the body.
    func rescheduleDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
        guard Settings.bool(SettingsKey.dailyReminderEnabled) else { return }
        let minutes = AppGroup.defaults.integer(forKey: SettingsKey.dailyReminderMinutes)
        var when = DateComponents()
        when.hour = minutes / 60
        when.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.title = "Anything to log today?"
        content.body = "Take a few seconds to add today's expenses."
        content.sound = .default
        // ponytail: repeating trigger means the body is static; schedule per-day requests if you want live totals.
        center.add(UNNotificationRequest(identifier: reminderId, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }

    func notifySynced(count: Int) {
        guard Settings.bool(SettingsKey.syncAlertsEnabled), permission != .denied else { return }
        let content = UNMutableNotificationContent()
        content.title = "Synced from Google Sheets"
        content.body = count == 1 ? "1 new expense was added from your spreadsheet." : "\(count) new expenses were added from your spreadsheet."
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct NotificationSettingsView: View {
    @State private var manager = NotificationManager.shared
    @AppStorage(SettingsKey.dailyReminderEnabled, store: AppGroup.defaults) private var reminder = false
    @AppStorage(SettingsKey.dailyReminderMinutes, store: AppGroup.defaults) private var reminderMinutes = 20 * 60
    @AppStorage(SettingsKey.syncAlertsEnabled, store: AppGroup.defaults) private var syncAlerts = true
    @Environment(\.openURL) private var openURL

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            reminderMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        }
    }

    var body: some View {
        Form {
            Section {
                switch manager.permission {
                case .granted:
                    Label("Notifications Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied:
                    Label("Notifications Disabled", systemImage: "bell.slash").foregroundStyle(.orange)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                default:
                    Button("Enable Notifications") { Task { await manager.request() } }
                }
            } footer: {
                Text(manager.permission == .denied
                     ? "Notifications are off. Turn them on in iOS Settings to get reminders and sync alerts."
                     : "Get reminders to log spending and a heads-up when new rows arrive from your spreadsheet.")
            }

            Section {
                Toggle("Daily Reminder", isOn: $reminder)
                if reminder {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                Toggle("Sync Alerts", isOn: $syncAlerts)
            } footer: {
                Text("Sync alerts appear when background sync finds new expenses added in Google Sheets.")
            }
            .disabled(manager.permission != .granted)
        }
        .navigationTitle("Notifications")
        .task { await manager.refresh() }
        .onChange(of: reminder) { manager.rescheduleDailyReminder() }
        .onChange(of: reminderMinutes) { manager.rescheduleDailyReminder() }
    }
}
