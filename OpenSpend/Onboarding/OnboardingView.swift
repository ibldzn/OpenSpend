import SwiftUI

struct OnboardingView: View {
    enum Page: Int, CaseIterable {
        case introduction, sync, shortcuts, widgets, notifications
    }

    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = false
    @State private var page: Page = .introduction
    @State private var notifications = NotificationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Page.allCases, id: \.self) { p in
                    content(for: p).tag(p).padding(.horizontal, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            bottomSection
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task { await notifications.refresh() }
    }

    @ViewBuilder
    private func content(for p: Page) -> some View {
        switch p {
        case .introduction:
            OnboardingPage(icon: "tablecells.badge.ellipsis", tint: .accentColor, title: "Welcome to OpenSpend",
                           message: "A simple, quick way to track what you spend.") {
                VStack(spacing: 10) {
                    sampleRow("Groceries", "cart", 54.20)
                    sampleRow("Lunch with Sam", "fork.knife", 18.00)
                    sampleRow("Train pass", "tram", 32.50)
                }
            }
        case .sync:
            OnboardingPage(icon: "arrow.triangle.2.circlepath", tint: .green, title: "Lives in Google Sheets",
                           message: "Connect a spreadsheet and every expense becomes a row. Edit the sheet and the app follows. Prefer to stay offline? Use a local account.") {
                EmptyView()
            }
        case .shortcuts:
            OnboardingPage(icon: "bolt.fill", tint: .yellow, title: "Log with Shortcuts",
                           message: "Say \"Add expense in OpenSpend\", or set up an automation that logs a purchase every time you tap to pay.") {
                ShortcutPreview().scaleEffect(0.9)
            }
        case .widgets:
            OnboardingPage(icon: "square.grid.2x2", tint: .teal, title: "Spending at a Glance",
                           message: "Home and Lock Screen widgets show how much you've spent today, this week or this month.") {
                WidgetPreviewMock().scaleEffect(0.85)
            }
        case .notifications:
            OnboardingPage(icon: "bell.badge.fill", tint: .orange, title: "Stay in the Loop",
                           message: "Get a daily reminder to log spending, and a note when new rows arrive from your spreadsheet.") {
                EmptyView()
            }
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { p in
                    Capsule().fill(p == page ? Color.accentColor : Color(.tertiaryLabel))
                        .frame(width: p == page ? 20 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 8)

            if page == .notifications {
                Button(notifications.permission == .granted ? "Get Started" : "Enable Notifications") {
                    Task {
                        if notifications.permission != .granted { await notifications.request() }
                        finish()
                    }
                }
                .buttonStyle(.large)
                if notifications.permission != .granted {
                    Button("Continue without notifications", action: finish)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Continue") { page = Page(rawValue: page.rawValue + 1) ?? .notifications }
                    .buttonStyle(.large)
                Button("Skip") { page = .notifications }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func sampleRow(_ title: String, _ icon: String, _ amount: Double) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(Money.format(amount, currency: Settings.defaultCurrency)).font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func finish() {
        Haptics.success()
        hasCompletedOnboarding = true
    }
}

private struct OnboardingPage<Extra: View>: View {
    var icon: String
    var tint: Color
    var title: String
    var message: String
    @ViewBuilder var extra: Extra

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: appeared)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            extra.padding(.top, 8)
            Spacer()
        }
        .onAppear { appeared.toggle() }
    }
}
