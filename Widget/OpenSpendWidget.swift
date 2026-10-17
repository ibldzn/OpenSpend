import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

enum WidgetPeriod: String, AppEnum {
    case today, thisWeek, thisMonth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [WidgetPeriod: DisplayRepresentation] = [
        .today: "Today",
        .thisWeek: "This Week",
        .thisMonth: "This Month",
    ]

    var filter: FilterPeriod {
        switch self {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        }
    }
}

struct FilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spending"
    static let description = IntentDescription("View your total spending.")

    @Parameter(title: "Account") var account: AccountEntity?
    @Parameter(title: "Period", default: .thisMonth) var period: WidgetPeriod
    @Parameter(title: "Categories") var categories: [CategoryEntity]?
}

struct SpendEntry: TimelineEntry {
    var date: Date
    var title: String
    var total: Double
    var count: Int
    var currency: String
    var accountName: String
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpendEntry {
        SpendEntry(date: Date(), title: FilterPeriod.thisMonth.spentTitle, total: 842.10, count: 12, currency: "USD", accountName: "Personal")
    }

    func snapshot(for configuration: FilterIntent, in context: Context) async -> SpendEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: FilterIntent, in context: Context) async -> Timeline<SpendEntry> {
        let e = await entry(for: configuration)
        // Refresh at the next period boundary or in 30 minutes, whichever comes first.
        let boundary = configuration.period.filter.interval()?.end ?? Date().addingTimeInterval(1800)
        return Timeline(entries: [e], policy: .after(min(boundary, Date().addingTimeInterval(1800))))
    }

    @MainActor
    private func entry(for config: FilterIntent) -> SpendEntry {
        let period = config.period.filter
        let currency = Settings.defaultCurrency
        guard let account = EntityData.account(id: config.account?.id) ?? EntityData.activeAccount() else {
            return SpendEntry(date: Date(), title: period.spentTitle, total: 0, count: 0, currency: currency, accountName: "No account")
        }
        let wanted = Set((config.categories ?? []).filter { $0.accountId == account.id.uuidString }.map(\.name))
        let items = EntityData.expenses(accountId: account.id).filter {
            period.contains($0.date) && (wanted.isEmpty || !wanted.isDisjoint(with: $0.categories))
        }
        return SpendEntry(date: Date(), title: period.spentTitle, total: items.reduce(0) { $0 + $1.amount },
                          count: items.count, currency: currency, accountName: account.name)
    }
}

struct OpenSpendWidgetView: View {
    var entry: SpendEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.title): \(Money.format(entry.total, currency: entry.currency))")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.title).font(.caption2).widgetAccentable()
                Text(Money.format(entry.total, currency: entry.currency)).font(.headline).minimumScaleFactor(0.6)
                Text(entry.accountName).font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "creditcard").font(.caption)
                Text(entry.total, format: .number.notation(.compactName).precision(.fractionLength(0...1))).font(.headline).minimumScaleFactor(0.5)
            }
        case .systemMedium:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    Text(Money.format(entry.total, currency: entry.currency))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
                    Spacer()
                    Text("\(entry.count) expenses · \(entry.accountName)").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Link(destination: URL(string: "openspend://add")!) {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(Palette.cta, in: .circle)
                }
                .accessibilityLabel("Add Expense")
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Text(Money.format(entry.total, currency: entry.currency))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white).minimumScaleFactor(0.4).lineLimit(1)
                Spacer()
                Text(entry.accountName).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OpenSpendWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenSpendWidget", intent: FilterIntent.self, provider: Provider()) { entry in
            OpenSpendWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Palette.heroStart, Palette.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Spending")
        .description("View your total spending.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct OpenSpendWidgetBundle: WidgetBundle {
    var body: some Widget {
        OpenSpendWidget()
    }
}
