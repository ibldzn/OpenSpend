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
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: Space.lg, bottom: Space.sm, trailing: Space.lg))
                }

                Section {
                    VStack(spacing: Space.lg) {
                        PillPicker(options: FilterPeriod.allCases, selection: Bindable(account).filterPeriod) { $0.shortTitle }
                        HeroCard(period: period, total: total, count: filtered.count, currency: defaultCurrency, expenses: filtered)
                            .staggeredAppear(1)
                        // Hidden when empty: the empty state below already says there's nothing yet.
                        if !filtered.isEmpty {
                            InsightsCard(expenses: filtered, period: period, currency: defaultCurrency, iconForCategory: iconForCategory)
                                .staggeredAppear(2)
                        }
                        if !categories.isEmpty || !payments.isEmpty {
                            FilterBar(account: account, categories: categories.map(\.name), payments: payments.map(\.name))
                                .staggeredAppear(3)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Space.lg, bottom: Space.sm, trailing: Space.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if filtered.isEmpty {
                    Section {
                        EmptyStateView(icon: "tray",
                                       title: expenses.isEmpty ? "No expenses yet" : "Nothing here",
                                       message: expenses.isEmpty ? "Tap Add Expense to log your first one." : "No expenses match this period or filter.")
                            .card()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: Space.lg, bottom: 0, trailing: Space.lg))
                    .listRowBackground(Color.clear)
                }

                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.items) { e in
                            Button { selectedExpense = e } label: {
                                ExpenseRow(expense: e, icon: e.categories.first.flatMap { iconForCategory[$0] } ?? "tag")
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.surface)
                            .swipeActions {
                                Button(role: .destructive) { expenseToDelete = e } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } header: {
                        SectionHeader(title: dayLabel(group.day), trailing: Money.format(group.items.reduce(0) { $0 + $1.amount }, currency: defaultCurrency))
                            .textCase(nil)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, -Space.xs)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Space.lg)
            .appScreen()
            .contentMargins(.bottom, 110, for: .scrollContent)
            .refreshable { await ExpenseSyncService.shared.sync(account, context: context) }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .overlay(alignment: .bottom) { addButton }
            .syncToast()
            .toolbar(.hidden, for: .navigationBar)
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
            HStack(spacing: Space.md) {
                IconBadge(systemName: "tablecells", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action required").font(.subheadline.weight(.semibold))
                    Text("Choose a spreadsheet to start syncing.").font(.footnote).foregroundStyle(Palette.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textMuted)
            }
            .card()
        }
        .buttonStyle(ScaleOnPressStyle())
    }

    private var addButton: some View {
        Button(action: startCreate) {
            Label("Add Expense", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Palette.onPrimary)
                .padding(.horizontal, Space.xl)
                .frame(minHeight: 52)
                .background(Palette.cta, in: .capsule)
                // Separates the button from content scrolling underneath, without a glow.
                .overlay(Capsule().strokeBorder(Palette.background, lineWidth: 4).padding(-4))
        }
        .buttonStyle(ScaleOnPressStyle())
        .padding(.bottom, Space.sm)
    }

    /// Top bar: search, account switcher, settings.
    private var header: some View {
        HStack(spacing: Space.md) {
            CircleIconButton(systemName: "magnifyingglass", label: "Search") { showSearch = true }
            Spacer(minLength: 0)
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
                HStack(spacing: Space.sm) {
                    Image(systemName: account.iconName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 28, height: 28)
                        .background(Palette.primary, in: .circle)
                    Text(account.name).font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.textMuted)
                }
                .padding(.leading, Space.sm)
                .padding(.trailing, Space.md)
                .frame(minHeight: 44)
                .background(Palette.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                .foregroundStyle(Palette.primary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .accessibilityLabel("Account: \(account.name)")
            .accessibilityHint("Switch account")
            Spacer(minLength: 0)
            CircleIconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        // Solid enough that scrolled content never collides with the status bar.
        .background(Palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }
}

/// "Today"/"Yesterday", otherwise a short date.
private func dayLabel(_ day: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return "Today" }
    if cal.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}
