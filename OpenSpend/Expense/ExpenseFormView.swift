import SwiftData
import SwiftUI

struct ExpenseFormView: View {
    enum Mode {
        case create
        case edit(Expense)
    }

    let account: ExpenseAccount
    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.titleSuggestionsEnabled, store: AppGroup.defaults) private var titleSuggestionsEnabled = true
    @AppStorage(SettingsKey.enableSmartSuggestions, store: AppGroup.defaults) private var smartSuggestionsEnabled = true

    @Query private var categories: [ExpenseCategory]
    @Query private var payments: [ExpensePayment]
    @Query private var history: [Expense]

    @State private var title: String
    @State private var amountString: String
    @State private var date: Date
    @State private var currency: String
    @State private var notes: String
    @State private var tags: [String]
    @State private var tagInput = ""
    @State private var selectedCategories: [String]
    @State private var selectedPayments: [String]
    @State private var autoCategory: String?
    @State private var autoPayment: String?
    @State private var suggestions: [TitleSuggestion] = []
    @State private var showDatePicker = false
    @State private var showCurrencyPicker = false
    @State private var addingOption: OptionKind?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case title, amount, tag, notes }

    init(account: ExpenseAccount, mode: Mode) {
        self.account = account
        self.mode = mode
        let id = account.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.accountId == id }, sort: \ExpenseCategory.sortOrder)
        _payments = Query(filter: #Predicate<ExpensePayment> { $0.accountId == id }, sort: \ExpensePayment.sortOrder)
        _history = Query(filter: #Predicate<Expense> { $0.accountId == id && !$0.isTrashed }, sort: \Expense.date, order: .reverse)

        let f: ExpenseFields
        if case .edit(let e) = mode {
            f = e.fields
        } else {
            f = ExpenseFields(title: "", amount: 0, currency: Settings.defaultCurrency, date: Date())
        }
        _title = State(initialValue: f.title)
        _amountString = State(initialValue: f.amount == 0 ? "" : Self.editableAmount(f.amount))
        _date = State(initialValue: f.date)
        _currency = State(initialValue: f.currency)
        _notes = State(initialValue: f.notes)
        _tags = State(initialValue: f.tags)
        _selectedCategories = State(initialValue: f.categories)
        _selectedPayments = State(initialValue: f.payments)
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var amount: Double? { AmountParser.parse(amountString) }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && amount != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    amountField.staggeredAppear(0)
                    detailsCard.staggeredAppear(1)
                    optionSection(.category).staggeredAppear(2)
                    optionSection(.payment).staggeredAppear(3)
                    moreCard.staggeredAppear(4)
                    if isEditing {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete Expense", systemImage: "trash")
                                .font(.headline)
                                .foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.danger.opacity(0.12), in: .rect(cornerRadius: Radius.md))
                        }
                        .buttonStyle(ScaleOnPressStyle())
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreen()
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label(isEditing ? "Save Changes" : "Save Expense", systemImage: "checkmark")
                }
                .buttonStyle(.large)
                .disabled(!canSave)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(.bar)
            }
            .navigationTitle(isEditing ? "Edit Expense" : "New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showDatePicker) { DatePickerSheet(date: $date) }
            .sheet(isPresented: $showCurrencyPicker) { NavigationStack { CurrencyPickerView(selection: $currency) } }
            .sheet(item: $addingOption) { kind in
                NavigationStack { OptionEditorView(kind: kind, account: account, editing: nil) { name in toggle(name, kind) } }
            }
            .deleteConfirmation("Delete this expense?", message: account.type == .sheets ? "The row will also be removed from your Google Sheet." : "This cannot be undone.", isPresented: $showDeleteConfirm) {
                if case .edit(let e) = mode {
                    ExpenseStore.delete(e, in: account, context: context)
                    dismiss()
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task(id: title) { await titleChanged() }
            .onAppear { if !isEditing { focus = .title } }
        }
    }

    // MARK: Fields

    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 52

    private var amountField: some View {
        VStack(spacing: Space.md) {
            Text("Amount").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(Money.symbol(for: currency))
                    .font(.system(size: amountSize * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textMuted)
                    .accessibilityHidden(true)
                TextField("0", text: $amountString)
                    .font(.system(size: amountSize, weight: .bold, design: .rounded).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .fixedSize()
                    .accessibilityLabel("Amount in \(currency)")
            }
            Button { showCurrencyPicker = true } label: {
                HStack(spacing: Space.xs) {
                    Text(currency).font(.footnote.weight(.bold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, Space.md)
                .frame(minHeight: 32)
                .background(Palette.primary.opacity(0.12), in: .capsule)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(ScaleOnPressStyle())
            .accessibilityLabel("Currency: \(currency)")
        }
        .frame(maxWidth: .infinity)
        .card(padding: Space.xl, radius: Radius.xl)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Palette.textMuted)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            fieldLabel("Title")
            VStack(alignment: .leading, spacing: 0) {
                TextField("What is the expense about?", text: $title)
                    .font(.body.weight(.medium))
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .amount }
                    .padding(.horizontal, Space.md)
                    .frame(minHeight: 48)
                if focus == .title && !suggestions.isEmpty {
                    Divider().overlay(Palette.border)
                    ForEach(suggestions) { s in
                        Button { apply(s) } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.primary)
                                Text(s.title).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Text(Money.format(s.amount, currency: s.currency)).foregroundStyle(Palette.textMuted).monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.horizontal, Space.md)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills in the amount, category and payment method")
                    }
                }
            }
            .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.md))
            .animation(Motion.select, value: suggestions)

            fieldLabel("Date")
            Button { showDatePicker = true } label: {
                HStack(spacing: Space.md) {
                    Image(systemName: "calendar").foregroundStyle(Palette.primary)
                    Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textMuted)
                }
                .padding(.horizontal, Space.md)
                .frame(minHeight: 48)
                .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.md))
                .contentShape(.rect)
            }
            .buttonStyle(ScaleOnPressStyle())
            .accessibilityLabel("Date, \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        .card()
    }

    private func optionSection(_ kind: OptionKind) -> some View {
        let options: [(String, String)] = kind == .category ? categories.map { ($0.name, $0.iconName) } : payments.map { ($0.name, $0.iconName) }
        let selected = kind == .category ? selectedCategories : selectedPayments
        let auto = kind == .category ? autoCategory : autoPayment
        return VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text(kind == .category ? "Category" : "Payment Method").font(.headline)
                Spacer()
                if auto != nil && selected.contains(auto ?? "") {
                    Label("Suggested", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                }
            }
            FlowLayout {
                ForEach(options, id: \.0) { name, icon in
                    Chip(title: name, icon: icon, selected: selected.contains(name), suggested: auto == name && selected.contains(name)) {
                        toggle(name, kind)
                        if kind == .category { autoCategory = nil } else { autoPayment = nil }
                    }
                }
                Chip(title: "New", icon: "plus", selected: false) { addingOption = kind }
                    .accessibilityLabel(kind == .category ? "New category" : "New payment method")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var moreCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            fieldLabel("Tags")
            FlowLayout {
                ForEach(tags, id: \.self) { tag in
                    Chip(title: tag, icon: "xmark", selected: true) { tags.removeAll { $0 == tag } }
                        .accessibilityLabel("Remove tag \(tag)")
                }
                TextField("Add tag", text: $tagInput)
                    .focused($focus, equals: .tag)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .frame(minWidth: 120, minHeight: 40)
                    .padding(.horizontal, Space.md)
                    .background(Palette.fill.opacity(0.6), in: .capsule)
            }
            fieldLabel("Notes")
            TextField("Anything worth remembering", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .focused($focus, equals: .notes)
                .padding(Space.md)
                .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.md))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Actions

    private func toggle(_ name: String, _ kind: OptionKind) {
        Haptics.tap()
        switch kind {
        case .category:
            if let i = selectedCategories.firstIndex(of: name) { selectedCategories.remove(at: i) } else { selectedCategories.append(name) }
        case .payment:
            if let i = selectedPayments.firstIndex(of: name) { selectedPayments.remove(at: i) } else { selectedPayments.append(name) }
        }
    }

    private func addTag() {
        let t = tagInput.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && !tags.contains(t) { tags.append(t) }
        tagInput = ""
    }

    private func apply(_ s: TitleSuggestion) {
        title = s.title
        if amountString.isEmpty { amountString = Self.editableAmount(s.amount) }
        currency = s.currency
        let validCats = Set(categories.map(\.name)), validPays = Set(payments.map(\.name))
        selectedCategories = s.categories.filter(validCats.contains)
        selectedPayments = s.payments.filter(validPays.contains)
        if tags.isEmpty { tags = s.tags }
        autoCategory = nil
        autoPayment = nil
        suggestions = []
        focus = .amount
    }

    /// Debounced: refresh title suggestions, then infer category / payment.
    private func titleChanged() async {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        suggestions = titleSuggestionsEnabled && focus == .title ? SuggestionEngine.shared.titleSuggestions(for: title, in: history) : []

        guard smartSuggestionsEnabled, !isEditing else { return }
        // Only overwrite a selection the engine made itself. Checked again after each await,
        // since the user may tap a chip while inference is running.
        func auto(_ selected: [String], _ auto: String?) -> Bool { selected.isEmpty || selected == [auto].compactMap { $0 } }

        if auto(selectedCategories, autoCategory) {
            let hit = await SuggestionEngine.shared.infer(.category, title: title, options: categories.map(\.name), history: history, accountId: account.id)
            guard !Task.isCancelled else { return }
            if auto(selectedCategories, autoCategory) {
                autoCategory = hit
                selectedCategories = hit.map { [$0] } ?? []
            }
        }
        if auto(selectedPayments, autoPayment) {
            let hit = await SuggestionEngine.shared.infer(.payment, title: title, options: payments.map(\.name), history: history, accountId: account.id)
            guard !Task.isCancelled else { return }
            if auto(selectedPayments, autoPayment) {
                autoPayment = hit
                selectedPayments = hit.map { [$0] } ?? []
            }
        }
    }

    private func save() {
        addTag()
        guard let amount else { errorMessage = "Enter a valid amount."; return }
        let fields = ExpenseFields(title: title.trimmingCharacters(in: .whitespaces), amount: amount, currency: currency, date: date,
                                   categories: selectedCategories, payments: selectedPayments,
                                   notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
        switch mode {
        case .create: ExpenseStore.create(fields, in: account, context: context)
        case .edit(let e): ExpenseStore.update(e, with: fields, in: account, context: context)
        }
        Haptics.success()
        dismiss()
    }

    private static func editableAmount(_ v: Double) -> String {
        v.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}

extension OptionKind: Identifiable {
    var id: Self { self }
}

struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .appScreen()
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Now") { date = Date() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
