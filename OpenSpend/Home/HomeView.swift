import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @AppStorage(SettingsKey.activeAccountId, store: AppGroup.defaults) private var activeAccountId = ""

    private var active: ExpenseAccount? {
        accounts.first { $0.id.uuidString == activeAccountId } ?? accounts.first
    }

    var body: some View {
        if let account = active {
            AccountScopedHomeView(account: account, accounts: accounts)
                .id(account.id)
        }
    }
}

struct AccountScopedHomeView: View {
    let account: ExpenseAccount
    let accounts: [ExpenseAccount]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.activeAccountId, store: AppGroup.defaults) private var activeAccountId = ""
    @AppStorage(SettingsKey.defaultCurrency, store: AppGroup.defaults) private var defaultCurrency = "USD"

    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var payments: [ExpensePayment]

    @State private var showCreate = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showManageAccounts = false
    @State private var showSheetSetup = false
    @State private var showNotLinkedAlert = false
    @State private var selectedExpense: Expense?
    @State private var expenseToDelete: Expense?

    init(account: ExpenseAccount, accounts: [ExpenseAccount]) {
        self.account = account
        self.accounts = accounts
        let id = account.id
        _expenses = Query(filter: #Predicate<Expense> { $0.accountId == id && !$0.isTrashed }, sort: \Expense.date, order: .reverse)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.accountId == id }, sort: \ExpenseCategory.sortOrder)
        _payments = Query(filter: #Predicate<ExpensePayment> { $0.accountId == id }, sort: \ExpensePayment.sortOrder)
    }

    private var period: FilterPeriod { account.filterPeriod }
    private var selectedCategories: Set<String> { Set(account.homeSelectedCategoryNames) }
    private var selectedPayments: Set<String> { Set(account.homeSelectedPaymentNames) }

    private var filtered: [Expense] {
        let interval = period.interval()
        return expenses.filter { e in
            (interval.map { e.date >= $0.start && e.date < $0.end } ?? true)
                && (selectedCategories.isEmpty || !selectedCategories.isDisjoint(with: e.categories))
                && (selectedPayments.isEmpty || !selectedPayments.isDisjoint(with: e.payments))
        }
    }

    // ponytail: totals ignore per-expense currency (no FX rates); add conversion if multi-currency totals matter.
    private var total: Double { filtered.reduce(0) { $0 + $1.amount } }

    private var groups: [(day: Date, items: [Expense])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!) }
    }

    private var iconForCategory: [String: String] {
        Dictionary(categories.map { ($0.name, $0.iconName) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            List {
                if account.type == .sheets && !account.isLinked {
                    Section { connectBanner }
                }

                Section {
                    SummaryCard(account: account, total: total, count: filtered.count, currency: defaultCurrency, expenses: filtered)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if !categories.isEmpty || !payments.isEmpty {
                    Section {
                        FilterBar(account: account, categories: categories.map(\.name), payments: payments.map(\.name))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if filtered.isEmpty {
                    Section {
                        EmptyStateView(icon: "tray",
                                       title: expenses.isEmpty ? "No expenses yet" : "Nothing here",
                                       message: expenses.isEmpty ? "Tap + to log your first expense." : "No expenses match this period or filter.")
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.items) { e in
                            Button { selectedExpense = e } label: {
                                ExpenseRow(expense: e, icon: e.categories.first.flatMap { iconForCategory[$0] } ?? "tag")
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { expenseToDelete = e } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayLabel(group.day))
                            Spacer()
                            Text(Money.format(group.items.reduce(0) { $0 + $1.amount }, currency: defaultCurrency))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .refreshable { await ExpenseSyncService.shared.sync(account, context: context) }
            .overlay(alignment: .bottom) { addButton }
            .syncToast()
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCreate) { ExpenseFormView(account: account, mode: .create) }
            .sheet(item: $selectedExpense) { ExpenseFormView(account: account, mode: .edit($0)) }
            .sheet(isPresented: $showSettings) { SettingsView(account: account) }
            .sheet(isPresented: $showManageAccounts) { NavigationStack { ManageAccountsView() } }
            .sheet(isPresented: $showSheetSetup) { SheetSetupView(account: account) }
            .fullScreenCover(isPresented: $showSearch) { SearchView(account: account) }
            .alert("Choose a spreadsheet first", isPresented: $showNotLinkedAlert) {
                Button("Choose Spreadsheet") { showSheetSetup = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This account syncs with Google Sheets. Pick a spreadsheet before adding expenses.")
            }
            .confirmationDialog("Delete this expense?", isPresented: Binding(get: { expenseToDelete != nil }, set: { if !$0 { expenseToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let e = expenseToDelete { ExpenseStore.delete(e, in: account, context: context) }
                }
            } message: {
                Text(account.type == .sheets ? "The row will also be removed from your Google Sheet." : "This cannot be undone.")
            }
            .task { await ExpenseSyncService.shared.autoSync(account, context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await ExpenseSyncService.shared.autoSync(account, context: context) } }
            }
            .onChange(of: router.showCreateExpense, initial: true) { _, show in
                if show { router.showCreateExpense = false; startCreate() }
            }
        }
    }

    private func startCreate() {
        if account.type == .sheets && !account.isLinked { showNotLinkedAlert = true } else { showCreate = true }
    }

    private var connectBanner: some View {
        Button { showSheetSetup = true } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "tablecells", tint: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action required").font(.subheadline.weight(.semibold))
                    Text("Choose a spreadsheet to start syncing.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: startCreate) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.gradient, in: .circle)
                .shadow(color: .accentColor.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(ScaleOnPressStyle())
        .padding(.bottom, 12)
        .accessibilityLabel("Add Expense")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Search")
        }
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(accounts) { a in
                    Button {
                        activeAccountId = a.id.uuidString
                    } label: {
                        Label(a.name, systemImage: a.id == account.id ? "checkmark" : a.iconName)
                    }
                }
                Divider()
                Button { showManageAccounts = true } label: { Label("Manage Accounts", systemImage: "person.2") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: account.iconName).font(.footnote)
                    Text(account.name).font(.headline)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
    }
}

/// "Today"/"Yesterday", otherwise a short date.
private func dayLabel(_ day: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return "Today" }
    if cal.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}
