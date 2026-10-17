import Charts
import SwiftData
import SwiftUI

/// Period total, set as plain type on the background.
struct HeroCard: View {
    var period: FilterPeriod
    var total: Double
    var count: Int
    var currency: String
    var expenses: [Expense]

    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Average per elapsed day in the period.
    private var dailyAverage: Double {
        let now = Date()
        let start = period.interval()?.start ?? expenses.map(\.date).min() ?? now
        let days = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: now).day ?? 0) + 1
        return total / Double(days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // Side by side normally; stacked at accessibility text sizes.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.sm)) : AnyLayout(HStackLayout())
            layout {
                Text(period.spentTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textMuted)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(count) \(count == 1 ? "expense" : "expenses")")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(Palette.textMuted)
            }

            Text(Money.format(total, currency: currency))
                .font(.system(size: amountSize, weight: .semibold).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(Palette.primary)
                .contentTransition(.numericText(value: total))
                .animation(Motion.select, value: total)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if period != .today {
                Text("\(Money.format(dailyAverage, currency: currency)) per day on average")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Trend chart plus where the money went.
struct InsightsCard: View {
    var expenses: [Expense]
    var period: FilterPeriod
    var currency: String
    var iconForCategory: [String: String]

    private var breakdown: [(name: String, total: Double)] {
        let grouped = Dictionary(grouping: expenses) { $0.categories.first ?? "Uncategorized" }
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
        guard grouped.count > 4 else { return grouped }
        return Array(grouped.prefix(3)) + [("Other", grouped.dropFirst(3).reduce(0) { $0 + $1.1 })]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(title: "Spending trend")
            ExpenseGraphView(expenses: expenses, period: period)
                .frame(height: 128)

            if !expenses.isEmpty {
                Divider().overlay(Palette.border)
                SectionHeader(title: "Top categories")
                let sum = max(breakdown.reduce(0) { $0 + $1.total }, 0.0001)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(breakdown.enumerated()), id: \.element.name) { i, item in
                            Palette.ramp[min(i, Palette.ramp.count - 1)]
                                .frame(width: max(4, geo.size.width * item.total / sum - 2))
                        }
                    }
                    .clipShape(.capsule)
                }
                .frame(height: 10)
                .accessibilityHidden(true)

                VStack(spacing: Space.md) {
                    ForEach(Array(breakdown.enumerated()), id: \.element.name) { i, item in
                        HStack(spacing: Space.md) {
                            // Swatch ties the row to its bar segment; the name carries the meaning.
                            RoundedRectangle(cornerRadius: 2).fill(Palette.ramp[min(i, Palette.ramp.count - 1)])
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text((item.total / sum).formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.textMuted)
                            Text(Money.format(item.total, currency: currency))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .card()
    }
}

/// Bar chart of spending across the selected period.
struct ExpenseGraphView: View {
    var expenses: [Expense]
    var period: FilterPeriod

    private var unit: Calendar.Component {
        switch period {
        case .today: .hour
        case .thisWeek, .thisMonth: .day
        case .thisYear: .month
        case .allTime: .month
        }
    }

    private var buckets: [(date: Date, total: Double)] {
        let cal = Calendar.withWeekStart(Settings.weekStartDay)
        let dict = Dictionary(grouping: expenses) { cal.dateInterval(of: unit, for: $0.date)?.start ?? $0.date }
        return dict.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        if expenses.isEmpty {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Palette.fill.opacity(0.6))
                .overlay(Label("No spending to chart yet", systemImage: "chart.bar").font(.footnote.weight(.medium)).foregroundStyle(Palette.textMuted))
        } else {
            Chart(buckets, id: \.date) { b in
                BarMark(x: .value("Date", b.date, unit: unit), y: .value("Spent", b.total))
                    .foregroundStyle(Palette.primary)
                    .cornerRadius(2)
            }
            .accessibilityLabel("Spending trend chart")
            .chartXScale(domain: domain)
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Palette.border) } }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(format: xFormat, centered: true).foregroundStyle(Palette.textMuted) }
            }
        }
    }

    private var domain: ClosedRange<Date> {
        if let i = period.interval() { return i.start...i.end }
        let first = buckets.first?.date ?? Date()
        return first...max(Date(), first.addingTimeInterval(86400))
    }

    private var xFormat: Date.FormatStyle {
        switch period {
        case .today: .dateTime.hour()
        case .thisWeek: .dateTime.weekday(.narrow)
        case .thisMonth: .dateTime.day()
        case .thisYear, .allTime: .dateTime.month(.narrow)
        }
    }
}

struct FilterBar: View {
    @Bindable var account: ExpenseAccount
    var categories: [String]
    var payments: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    if !categories.isEmpty {
                        Section("Categories") {
                            ForEach(categories, id: \.self) { name in
                                toggle(name, in: \.homeSelectedCategoryNames)
                            }
                        }
                    }
                    if !payments.isEmpty {
                        Section("Payment Methods") {
                            ForEach(payments, id: \.self) { name in
                                toggle(name, in: \.homeSelectedPaymentNames)
                            }
                        }
                    }
                    if isFiltering {
                        Button("Clear Filters", role: .destructive) {
                            account.homeSelectedCategoryNames = []
                            account.homeSelectedPaymentNames = []
                        }
                    }
                } label: {
                    Label(isFiltering ? "Filtered" : "Filter", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isFiltering ? Palette.onPrimary : Palette.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(isFiltering ? Palette.primary : Palette.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(isFiltering ? Color.clear : Palette.border, lineWidth: 1))
                }

                ForEach(account.homeSelectedCategoryNames + account.homeSelectedPaymentNames, id: \.self) { name in
                    Chip(title: name, icon: "xmark", selected: true) {
                        account.homeSelectedCategoryNames.removeAll { $0 == name }
                        account.homeSelectedPaymentNames.removeAll { $0 == name }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var isFiltering: Bool { !account.homeSelectedCategoryNames.isEmpty || !account.homeSelectedPaymentNames.isEmpty }

    private func toggle(_ name: String, in keyPath: ReferenceWritableKeyPath<ExpenseAccount, [String]>) -> some View {
        let on = account[keyPath: keyPath].contains(name)
        return Button {
            if on { account[keyPath: keyPath].removeAll { $0 == name } } else { account[keyPath: keyPath].append(name) }
        } label: {
            Label(name, systemImage: on ? "checkmark.circle.fill" : "circle")
        }
    }
}

struct ExpenseRow: View {
    var expense: Expense
    var icon: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the amount moves under the title instead of squeezing it.
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: Space.md) {
            IconBadge(systemName: icon, tint: Palette.tint(for: expense.categories.first ?? ""), size: 44)
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs)) : AnyLayout(HStackLayout(spacing: Space.sm))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.title.isEmpty ? "Untitled" : expense.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(stacked ? 3 : 1)
                    let detail = (expense.categories + expense.payments).joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(.footnote).foregroundStyle(Palette.textMuted).lineLimit(stacked ? 3 : 1)
                    }
                }
                if !stacked { Spacer(minLength: Space.sm) }
                VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                    Text(Money.format(expense.amount, currency: expense.currency))
                        .font(.body.weight(.medium).monospacedDigit())
                        .fixedSize()
                    HStack(spacing: Space.xs) {
                        if expense.syncState != .synced {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Palette.warning)
                                .accessibilityLabel("Waiting to sync")
                        }
                        Text(expense.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Palette.textMuted)
                    }
                }
            }
            if stacked { Spacer(minLength: 0) }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the expense")
    }
}

struct SearchView: View {
    let account: ExpenseAccount
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @State private var text = ""
    @State private var selected: Expense?
    @State private var isSearching = true

    init(account: ExpenseAccount) {
        self.account = account
        let id = account.id
        _expenses = Query(filter: #Predicate<Expense> { $0.accountId == id && !$0.isTrashed }, sort: \Expense.date, order: .reverse)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.accountId == id })
    }

    private var results: [Expense] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return expenses.filter { e in
            ([e.title, e.notes] + e.categories + e.payments + e.tags).contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if text.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search your expenses", message: "Find expenses by title, notes, category, payment method or tag.")
                        .listRowBackground(Color.clear)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: text).listRowBackground(Color.clear)
                } else {
                    Section("\(results.count) \(results.count == 1 ? "result" : "results") · \(Money.format(results.reduce(0) { $0 + $1.amount }, currency: Settings.defaultCurrency))") {
                        ForEach(results) { e in
                            Button { selected = e } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    ExpenseRow(expense: e, icon: categories.first { $0.name == e.categories.first }?.iconName ?? "tag")
                                    Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(Palette.textMuted)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.surface)
                        }
                    }
                }
            }
            .appScreen()
            .searchable(text: $text, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search expenses")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { ExpenseFormView(account: account, mode: .edit($0)) }
            // Search is the whole point of this screen: closing the field closes the screen.
            .onChange(of: isSearching) { _, active in if !active && selected == nil { dismiss() } }
        }
    }
}
