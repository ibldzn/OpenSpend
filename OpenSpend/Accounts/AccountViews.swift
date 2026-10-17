import SwiftData
import SwiftUI

/// Choose between a Google Sheets-backed account and a local-only one.
struct ChooseAccountTypeView: View {
    var isFirstAccount = false
    var onCreated: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @AppStorage(SettingsKey.activeAccountId, store: AppGroup.defaults) private var activeAccountId = ""
    @State private var showLocalName = false
    @State private var localName = ""
    @State private var sheetsAccount: ExpenseAccount?
    @State private var lastSheetsAccount: ExpenseAccount?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                        .frame(width: 88, height: 88)
                        .background(Palette.surface, in: .circle)
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text(isFirstAccount ? "Create your first account" : "Create new account")
                        .font(.title2.bold())
                    Text("An account keeps its own expenses, categories and payment methods.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)

                typeCard(icon: "tablecells", tint: Palette.primary, title: "Google Sheets",
                         detail: "Sync every expense to a spreadsheet in your Google Drive. Edits made in the sheet come back to the app.") {
                    createSheetsAccount()
                }
                typeCard(icon: "iphone", tint: Palette.primary, title: "Local",
                         detail: "Keep expenses on this device only. No sign-in needed.") {
                    showLocalName = true
                }

                if showLocalName {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account name").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textMuted)
                        TextField("Account name", text: $localName)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(createLocal)
                            .padding(.horizontal, Space.md)
                            .frame(minHeight: 48)
                            .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.md))
                        Button("Create Account", action: createLocal)
                            .buttonStyle(.large)
                            .disabled(localName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .card()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear { nameFocused = true }
                }
            }
            .padding(20)
            .animation(Motion.enter, value: showLocalName)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetsAccount, onDismiss: sheetsSetupDismissed) { a in
            SheetSetupView(account: a).onAppear { lastSheetsAccount = a }
        }
    }

    private func typeCard(icon: String, tint: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: icon, tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.textMuted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textMuted).padding(.top, 4)
            }
            .card()
        }
        .buttonStyle(ScaleOnPressStyle())
        .foregroundStyle(.primary)
    }

    private func createLocal() {
        let name = localName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let a = ExpenseAccount(name: name, type: .local, sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(a)
        DefaultOptions.seed(for: a, context: context)
        try? context.save()
        activeAccountId = a.id.uuidString
        Haptics.success()
        onCreated?()
    }

    private func createSheetsAccount() {
        let a = ExpenseAccount(name: "Google Sheets", type: .sheets, sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1, iconName: "tablecells")
        // Inserted by the mapping step on save, so backing out leaves nothing behind.
        sheetsAccount = a
    }

    private func sheetsSetupDismissed() {
        guard let a = lastSheetsAccount, a.modelContext != nil else { return }
        activeAccountId = a.id.uuidString
        onCreated?()
    }
}

enum DefaultOptions {
    static func seed(for a: ExpenseAccount, context: ModelContext) {
        let cats = [("Food", "fork.knife"), ("Groceries", "cart"), ("Transport", "car"), ("Shopping", "bag"),
                    ("Bills", "doc.text"), ("Entertainment", "film"), ("Health", "heart"), ("Other", "tag")]
        let pays = [("Cash", "banknote"), ("Card", "creditcard"), ("Apple Pay", "applelogo"), ("Bank Transfer", "building.columns")]
        for (i, c) in cats.enumerated() { context.insert(ExpenseCategory(accountId: a.id, name: c.0, iconName: c.1, sortOrder: i)) }
        for (i, p) in pays.enumerated() { context.insert(ExpensePayment(accountId: a.id, name: p.0, iconName: p.1, sortOrder: i)) }
    }
}

struct ManageAccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @AppStorage(SettingsKey.activeAccountId, store: AppGroup.defaults) private var activeAccountId = ""
    @State private var showAdd = false
    @State private var accountToDelete: ExpenseAccount?
    @State private var showCannotDelete = false

    var body: some View {
        List {
            Section {
                ForEach(accounts) { a in
                    HStack(spacing: 12) {
                        IconBadge(systemName: a.iconName, tint: a.type == .sheets ? .green : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name)
                            Text(a.type == .sheets ? (a.spreadsheetName.map { "Sheets · \($0)" } ?? "Sheets · not linked") : "Local")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if a.id.uuidString == activeAccountId || (activeAccountId.isEmpty && a.id == accounts.first?.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.brand).bold()
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { activeAccountId = a.id.uuidString; Haptics.tap() }
                    .swipeActions {
                        Button(role: .destructive) {
                            if accounts.count <= 1 { showCannotDelete = true } else { accountToDelete = a }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Tap an account to switch to it. Drag to reorder.")
            }

            Section {
                Button { showAdd = true } label: { Label("Create new account", systemImage: "plus.circle.fill") }
            }
        }
        .appScreen()
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack { ChooseAccountTypeView(onCreated: { showAdd = false }) }
        }
        .alert("Cannot Delete Account", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need at least one account. Create another account before deleting this one.")
        }
        .confirmationDialog("Delete \(accountToDelete?.name ?? "account")?", isPresented: Binding(get: { accountToDelete != nil }, set: { if !$0 { accountToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { if let a = accountToDelete { delete(a) } }
        } message: {
            Text(accountToDelete?.type == .sheets
                 ? "Removes the account and its expenses, categories and payment methods from this app. Your Google Sheet is not changed."
                 : "This permanently removes the account and all its expenses.")
        }
    }

    private func move(from: IndexSet, to: Int) {
        var ordered = accounts
        ordered.move(fromOffsets: from, toOffset: to)
        for (i, a) in ordered.enumerated() { a.sortOrder = i }
        try? context.save()
    }

    private func delete(_ a: ExpenseAccount) {
        let wasActive = a.id.uuidString == activeAccountId
        ExpenseStore.deleteAccount(a, context: context)
        if wasActive { activeAccountId = accounts.first { $0.id != a.id }?.id.uuidString ?? "" }
    }
}

struct AccountSettingsView: View {
    @Bindable var account: ExpenseAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @AppStorage(SettingsKey.activeAccountId, store: AppGroup.defaults) private var activeAccountId = ""
    @State private var showSheetSetup = false
    @State private var showRemap = false
    @State private var showFullSyncConfirm = false
    @State private var showRemoveSheetConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showCannotDelete = false

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $account.name)
                NavigationLink {
                    ScrollView { IconGridView(icons: IconCatalog.account, selection: $account.iconName).padding() }
                        .appScreen()
                        .navigationTitle("Icon")
                } label: {
                    HStack { Text("Icon"); Spacer(); Image(systemName: account.iconName).foregroundStyle(Color.brand) }
                }
                LabeledContent("Type", value: account.type == .sheets ? "Google Sheets" : "Local")
            }

            if account.type == .sheets {
                Section {
                    if account.hasSpreadsheet {
                        LabeledContent("Spreadsheet", value: account.spreadsheetName ?? "—")
                        LabeledContent("Sheet", value: account.sheetTitle ?? "—")
                        LabeledContent("Google Account", value: account.connectionEmail ?? "—")
                        if let last = account.lastSyncedAt {
                            LabeledContent("Last Synced", value: last.formatted(.relative(presentation: .named)))
                        }
                        Button("Edit Column Mapping") { showRemap = true }
                        Button("Change Spreadsheet") { showSheetSetup = true }
                        Button("Force Full Sync") { showFullSyncConfirm = true }
                        Button("Remove This Spreadsheet", role: .destructive) { showRemoveSheetConfirm = true }
                    } else {
                        Button("Choose a Spreadsheet") { showSheetSetup = true }
                    }
                } header: {
                    Text("Google Sheets")
                } footer: {
                    Text("The app reads the whole sheet on each sync. Use Force Full Sync if expenses look out of date.")
                }
            }

            Section {
                NavigationLink { ManageOptionsView(kind: .category, account: account) } label: { Label("Categories", systemImage: "tag") }
                NavigationLink { ManageOptionsView(kind: .payment, account: account) } label: { Label("Payment Methods", systemImage: "creditcard") }
            }

            Section {
                Button("Delete This Account", role: .destructive) {
                    if accounts.count <= 1 { showCannotDelete = true } else { showDeleteConfirm = true }
                }
            }
        }
        .appScreen()
        .navigationTitle("Account Settings")
        .onChange(of: account.name) { try? context.save() }
        .sheet(isPresented: $showSheetSetup) { SheetSetupView(account: account) }
        .sheet(isPresented: $showRemap) { SheetSetupView(account: account, remapOnly: true) }
        .alert("Force Full Sync?", isPresented: $showFullSyncConfirm) {
            Button("Sync") { Task { await ExpenseSyncService.shared.sync(account, context: context, full: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All expenses will be reloaded from the sheet. This may take a while for large sheets.")
        }
        .alert("Remove Spreadsheet?", isPresented: $showRemoveSheetConfirm) {
            Button("Remove", role: .destructive) {
                ExpenseStore.clearExpenses(of: account, context: context)
                account.clearSheetLink()
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Expenses from this spreadsheet will be removed from the app. Nothing is deleted from Google Sheets.")
        }
        .alert("Cannot Delete Account", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need at least one account. Create another account before deleting this one.")
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                let next = accounts.first { $0.id != account.id }
                ExpenseStore.deleteAccount(account, context: context)
                activeAccountId = next?.id.uuidString ?? ""
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.type == .sheets
                 ? "This will remove all expenses, payment methods and categories of this account from the app. Your Google Sheet is not changed."
                 : "This will permanently remove all expenses, payment methods and categories of this account.")
        }
    }
}

// MARK: Categories & payment methods

struct OptionItem: Identifiable {
    var id: UUID
    var name: String
    var iconName: String
}

struct ManageOptionsView: View {
    let kind: OptionKind
    let account: ExpenseAccount
    @Environment(\.modelContext) private var context
    @Query private var categories: [ExpenseCategory]
    @Query private var payments: [ExpensePayment]
    @State private var editing: OptionItem?
    @State private var showAdd = false
    @State private var toDelete: OptionItem?

    init(kind: OptionKind, account: ExpenseAccount) {
        self.kind = kind
        self.account = account
        let id = account.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.accountId == id }, sort: \ExpenseCategory.sortOrder)
        _payments = Query(filter: #Predicate<ExpensePayment> { $0.accountId == id }, sort: \ExpensePayment.sortOrder)
    }

    private var items: [OptionItem] {
        kind == .category
            ? categories.map { OptionItem(id: $0.id, name: $0.name, iconName: $0.iconName) }
            : payments.map { OptionItem(id: $0.id, name: $0.name, iconName: $0.iconName) }
    }

    private var noun: String { kind == .category ? "Category" : "Payment Method" }

    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(icon: kind == .category ? "tag" : "creditcard",
                               title: kind == .category ? "No Categories" : "No Payment Methods",
                               message: "Tap + to add one.")
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                Button { editing = item } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: item.iconName, size: 32)
                        Text(item.name).foregroundStyle(.primary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { toDelete = item } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .onMove(perform: move)
        }
        .appScreen()
        .navigationTitle(kind == .category ? "Categories" : "Payment Methods")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(isPresented: $showAdd) { NavigationStack { OptionEditorView(kind: kind, account: account, editing: nil) } }
        .sheet(item: $editing) { item in NavigationStack { OptionEditorView(kind: kind, account: account, editing: item) } }
        .confirmationDialog("Delete \(toDelete?.name ?? "")?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete \(noun)", role: .destructive) { if let t = toDelete { delete(t) } }
        } message: {
            Text("Existing expenses keep this name. It just won't be offered as an option anymore.")
        }
    }

    private func move(from: IndexSet, to: Int) {
        switch kind {
        case .category:
            var o = categories; o.move(fromOffsets: from, toOffset: to)
            for (i, c) in o.enumerated() { c.sortOrder = i }
        case .payment:
            var o = payments; o.move(fromOffsets: from, toOffset: to)
            for (i, p) in o.enumerated() { p.sortOrder = i }
        }
        try? context.save()
    }

    private func delete(_ item: OptionItem) {
        switch kind {
        case .category: if let c = categories.first(where: { $0.id == item.id }) { context.delete(c) }
        case .payment: if let p = payments.first(where: { $0.id == item.id }) { context.delete(p) }
        }
        try? context.save()
    }
}

struct OptionEditorView: View {
    let kind: OptionKind
    let account: ExpenseAccount
    let editing: OptionItem?
    var onCreated: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    init(kind: OptionKind, account: ExpenseAccount, editing: OptionItem?, onCreated: ((String) -> Void)? = nil) {
        self.kind = kind
        self.account = account
        self.editing = editing
        self.onCreated = onCreated
        _name = State(initialValue: editing?.name ?? "")
        _icon = State(initialValue: editing?.iconName ?? (kind == .category ? "tag" : "creditcard"))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    IconBadge(systemName: icon, size: 40)
                    TextField("Name", text: $name).focused($nameFocused).font(.headline)
                }
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section("Icon") {
                IconGridView(icons: kind == .category ? IconCatalog.category : IconCatalog.payment, selection: $icon)
                    .padding(.vertical, 6)
                Button("Reset to Default Icon") {
                    icon = kind == .category ? IconCatalog.guessCategoryIcon(name) : IconCatalog.guessPaymentIcon(name)
                }
            }
        }
        .appScreen()
        .navigationTitle(editing == nil ? (kind == .category ? "Add Category" : "Add Payment Method") : (kind == .category ? "Edit Category" : "Edit Payment Method"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { if editing == nil { nameFocused = true } }
        .onChange(of: name) { _, n in
            if editing == nil && (icon == "tag" || icon == "creditcard") {
                icon = kind == .category ? IconCatalog.guessCategoryIcon(n) : IconCatalog.guessPaymentIcon(n)
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let id = account.id
        let existing: [(UUID, String)]
        switch kind {
        case .category:
            existing = ((try? context.fetch(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.accountId == id }))) ?? []).map { ($0.id, $0.name) }
        case .payment:
            existing = ((try? context.fetch(FetchDescriptor<ExpensePayment>(predicate: #Predicate { $0.accountId == id }))) ?? []).map { ($0.id, $0.name) }
        }
        if existing.contains(where: { $0.1.caseInsensitiveCompare(n) == .orderedSame && $0.0 != editing?.id }) {
            error = "An option with this name already exists."
            return
        }

        if let editing {
            switch kind {
            case .category:
                if let c = try? context.fetch(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.accountId == id })).first(where: { $0.id == editing.id }) {
                    c.name = n; c.iconName = icon
                }
            case .payment:
                if let p = try? context.fetch(FetchDescriptor<ExpensePayment>(predicate: #Predicate { $0.accountId == id })).first(where: { $0.id == editing.id }) {
                    p.name = n; p.iconName = icon
                }
            }
            ExpenseStore.renameOption(kind: kind, from: editing.name, to: n, in: account, context: context)
        } else {
            switch kind {
            case .category: context.insert(ExpenseCategory(accountId: id, name: n, iconName: icon, sortOrder: existing.count))
            case .payment: context.insert(ExpensePayment(accountId: id, name: n, iconName: icon, sortOrder: existing.count))
            }
            onCreated?(n)
        }
        try? context.save()
        dismiss()
    }
}
