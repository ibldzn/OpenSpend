import Charts
import SwiftData
import SwiftUI

struct SummaryCard: View {
    @Bindable var account: ExpenseAccount
    var total: Double
    var count: Int
    var currency: String
    var expenses: [Expense]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    Picker("Period", selection: $account.filterPeriod) {
                        ForEach(FilterPeriod.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(account.filterPeriod.spentTitle)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count) \(count == 1 ? "expense" : "expenses")")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Text(Money.format(total, currency: currency))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText(value: total))
                .animation(.snappy, value: total)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            ExpenseGraphView(expenses: expenses, period: account.filterPeriod)
                .frame(height: 120)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))
                .overlay(Text("No spending to chart").font(.footnote).foregroundStyle(.secondary))
        } else {
            Chart(buckets, id: \.date) { b in
                BarMark(x: .value("Date", b.date, unit: unit), y: .value("Spent", b.total))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
            }
            .chartXScale(domain: domain)
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Color(.separator).opacity(0.4)) } }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(format: xFormat, centered: true) }
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
                    Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                }

                ForEach(account.homeSelectedCategoryNames + account.homeSelectedPaymentNames, id: \.self) { name in
                    Chip(title: name, icon: "xmark", selected: true) {
                        account.homeSelectedCategoryNames.removeAll { $0 == name }
                        account.homeSelectedPaymentNames.removeAll { $0 == name }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
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

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title.isEmpty ? "Untitled" : expense.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                let detail = (expense.categories + expense.payments).joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.format(expense.amount, currency: expense.currency))
                    .font(.body.weight(.semibold).monospacedDigit())
                HStack(spacing: 4) {
                    if expense.syncState != .synced {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(expense.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(.rect)
        .padding(.vertical, 2)
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
                    EmptyStateView(icon: "magnifyingglass", title: "Search", message: "Find expenses by title, notes, category, payment method or tag.")
                        .listRowBackground(Color.clear)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: text).listRowBackground(Color.clear)
                } else {
                    Section("\(results.count) results · \(Money.format(results.reduce(0) { $0 + $1.amount }, currency: Settings.defaultCurrency))") {
                        ForEach(results) { e in
                            Button { selected = e } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    ExpenseRow(expense: e, icon: categories.first { $0.name == e.categories.first }?.iconName ?? "tag")
                                    Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $text, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search expenses")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { ExpenseFormView(account: account, mode: .edit($0)) }
        }
    }
}
