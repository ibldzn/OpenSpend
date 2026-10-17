import AppIntents
import SwiftUI

/// Edit these to point at your own support channels.
enum AppLinks {
    static let supportEmail = "support@example.com"
    static let website = URL(string: "https://example.com")!
    static let social: [(name: String, icon: String, url: URL)] = [
        ("X / Twitter", "at", URL(string: "https://x.com/")!),
        ("Instagram", "camera", URL(string: "https://instagram.com/")!),
        ("Threads", "bubble.left", URL(string: "https://threads.net/")!),
    ]
    static let appStoreLookupBundleId = Bundle.main.bundleIdentifier ?? ""
}

struct HelpAndFeedbackView: View {
    @Environment(\.openURL) private var openURL

    private let faq: [(String, String)] = [
        ("Which spreadsheet columns do I need?", "Title, Amount and Date are required. Currency, Category, Payment Method, Notes and Tags are optional. OpenSpend adds a \"OpenSpend ID\" column to match rows; don't edit it."),
        ("Can I edit expenses in Google Sheets?", "Yes. Changes, new rows and deleted rows come back on the next sync. Pull down on the home screen to sync now."),
        ("Why is an expense showing a sync icon?", "It hasn't reached Google Sheets yet, usually because you were offline. It uploads on the next successful sync."),
        ("My spreadsheet isn't listed.", "Pull to refresh, or search its name. The spreadsheet must be in the Google Drive of the account you signed in with."),
        ("Does OpenSpend delete my sheet data?", "Only rows for expenses you delete in the app. Removing an account or spreadsheet link never deletes anything in Google Sheets."),
    ]

    var body: some View {
        List {
            Section("Common questions") {
                ForEach(faq, id: \.0) { q, a in
                    DisclosureGroup(q) { Text(a).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            Section {
                Button {
                    let body = "\n\n—\nVersion \(AppInfo.version) (\(AppInfo.build)), iOS \(UIDevice.current.systemVersion)"
                    var c = URLComponents(string: "mailto:\(AppLinks.supportEmail)")!
                    c.queryItems = [.init(name: "subject", value: "OpenSpend Feedback"), .init(name: "body", value: body)]
                    if let url = c.url { openURL(url) }
                } label: { Label("Email Support", systemImage: "envelope") }
                Link(destination: AppLinks.website) { Label("Website", systemImage: "globe") }
            }
        }
        .navigationTitle("Help & Feedback")
    }
}

struct FollowUsView: View {
    var body: some View {
        List(AppLinks.social, id: \.name) { s in
            Link(destination: s.url) {
                HStack { Label(s.name, systemImage: s.icon); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.tertiary) }
            }
        }
        .navigationTitle("Follow Us")
    }
}

struct TutorialsView: View {
    var body: some View {
        List {
            NavigationLink { SetupGuideView() } label: { Label("Connect a Google Sheet", systemImage: "tablecells") }
            NavigationLink { ShortcutsGuideView() } label: { Label("Log expenses with Shortcuts", systemImage: "bolt.fill") }
            NavigationLink { WidgetsGuideView() } label: { Label("Add a home screen widget", systemImage: "square.grid.2x2") }
        }
        .navigationTitle("Tutorials")
    }
}

private struct GuideStep: View {
    var number: Int
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Color.accentColor, in: .circle)
            Text(text).font(.subheadline)
        }
    }
}

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                GuideStep(number: 1, text: "Open Settings › Manage Accounts › Create new account › Google Sheets.")
                GuideStep(number: 2, text: "Sign in with Google and pick a spreadsheet, or create a new one.")
                GuideStep(number: 3, text: "Map your columns. Title, Amount and Date are required.")
                GuideStep(number: 4, text: "Done. Expenses you add appear as new rows, and edits in the sheet sync back.")
            }
        }
        .navigationTitle("Connect a Google Sheet")
    }
}

struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                ShortcutPreview()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("Add Expense shortcut") {
                GuideStep(number: 1, text: "Open the Shortcuts app and search for OpenSpend, or say \"Add expense in OpenSpend\" to Siri.")
                GuideStep(number: 2, text: "Add it to the Action Button, Control Center or the Lock Screen for one-tap logging.")
            }
            Section {
                GuideStep(number: 1, text: "In Shortcuts, open Automation › New › Wallet.")
                GuideStep(number: 2, text: "Pick your cards and choose Run Immediately.")
                GuideStep(number: 3, text: "Add the OpenSpend \"Add Expense\" action. Set Title to Merchant and Amount to Amount from the Shortcut Input.")
                GuideStep(number: 4, text: "Every tap to pay now offers to log the expense.")
            } header: {
                Text("Log automatically when you tap to pay")
            }
            Section {
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Shortcuts")
    }
}

/// Static mock of the shortcut confirmation, for the guide screens.
struct ShortcutPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tablecells.badge.ellipsis").foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Color.accentColor, in: .rect(cornerRadius: 7))
                Text("OpenSpend").font(.subheadline.bold())
                Spacer()
            }
            Text("Confirm expense details:").font(.footnote).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading) {
                    Text("Morning coffee").font(.headline)
                    Text("Food · Card").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(4.5, currency: Settings.defaultCurrency)).font(.title3.bold())
            }
            HStack {
                Text("Cancel").frame(maxWidth: .infinity).padding(10).background(Color(.tertiarySystemFill), in: .capsule)
                Text("Add").bold().foregroundStyle(.white).frame(maxWidth: .infinity).padding(10).background(Color.accentColor, in: .capsule)
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding()
        .background(LinearGradient(colors: [.accentColor.opacity(0.35), .purple.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 24))
    }
}

struct WidgetsGuideView: View {
    var body: some View {
        List {
            Section {
                WidgetPreviewMock()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Add a widget") {
                GuideStep(number: 1, text: "Touch and hold an empty spot on your Home Screen, then tap Edit › Add Widget.")
                GuideStep(number: 2, text: "Search for OpenSpend and pick a size.")
                GuideStep(number: 3, text: "Touch and hold the widget › Edit Widget to choose the account, period and categories.")
            }
        }
        .navigationTitle("Widgets")
    }
}

struct WidgetPreviewMock: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spent This Month").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(842.10, currency: Settings.defaultCurrency)).font(.title2.bold()).minimumScaleFactor(0.5)
                Spacer()
                Text("Personal").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(width: 150, height: 150, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 4) {
                Text("Spent Today").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(23.40, currency: Settings.defaultCurrency)).font(.title2.bold()).minimumScaleFactor(0.5)
                Spacer()
                Text("Personal").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(width: 150, height: 150, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        }
    }
}

// MARK: What's new

struct ChangelogEntry: Identifiable {
    var id: String { version }
    var version: String
    var date: String
    var greeting: String
    var points: [String]
}

enum Changelog {
    /// Newest first. The first entry is shown once after updating to its version.
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "1.0.0", date: "2026-10-18", greeting: "Welcome to OpenSpend",
                       points: [
                           "Log expenses in seconds and keep them in a Google Sheet you own.",
                           "Edits made in the spreadsheet sync back to the app.",
                           "Smart Suggestions pick a category and payment method from the title.",
                           "Add expenses from Siri, Shortcuts, or automatically when you tap to pay.",
                           "Home and Lock Screen widgets show what you've spent.",
                       ]),
    ]
}

struct ChangelogView: View {
    var body: some View {
        List(Changelog.entries) { e in
            NavigationLink { WhatsNewView(entry: e, embedded: true) } label: {
                VStack(alignment: .leading) {
                    Text("Version \(e.version)").font(.headline)
                    Text(e.date).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("What's New")
    }
}

struct WhatsNewView: View {
    var entry: ChangelogEntry
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(entry.greeting).font(.largeTitle.bold())
                Text("Version \(entry.version)").font(.subheadline).foregroundStyle(.secondary)
                ForEach(entry.points, id: \.self) { p in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        Text(p)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if !embedded {
                Button("Continue") { dismiss() }.buttonStyle(.large).padding(20)
            }
        }
        .navigationTitle(embedded ? "Version \(entry.version)" : "")
    }
}

// MARK: Update check

/// Asks the App Store lookup API whether a newer version is published.
@Observable
final class UpdateChecker {
    struct Update { var version: String; var url: URL }
    var available: Update?

    @MainActor
    func check() async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(AppLinks.appStoreLookupBundleId)"),
              let response = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String,
              let link = (result["trackViewUrl"] as? String).flatMap(URL.init(string:)) else { return }
        if version.compare(AppInfo.version, options: .numeric) == .orderedDescending {
            available = Update(version: version, url: link)
        }
    }
}
