import AuthenticationServices
import SwiftData
import SwiftUI

/// Links an account to one tab of a Google spreadsheet:
/// Google account -> spreadsheet -> tab -> column mapping.
struct SheetSetupView: View {
    @Bindable var account: ExpenseAccount
    var remapOnly = false

    enum Step: Equatable {
        case connection
        case spreadsheet(email: String)
        case tab(email: String, file: SpreadsheetFile, tabs: [SheetTab])
        case mapping(email: String, file: SpreadsheetFile, tab: SheetTab)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .connection
    @State private var history: [Step] = []

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .connection:
                    ConnectionStep { go(.spreadsheet(email: $0)) }
                case .spreadsheet(let email):
                    SpreadsheetStep(account: account, email: email) { file, tabs in
                        if tabs.count == 1 { go(.mapping(email: email, file: file, tab: tabs[0])) } else { go(.tab(email: email, file: file, tabs: tabs)) }
                    }
                case .tab(let email, let file, let tabs):
                    TabStep(account: account, file: file, tabs: tabs) { go(.mapping(email: email, file: file, tab: $0)) }
                case .mapping(let email, let file, let tab):
                    ColumnMappingStep(account: account, email: email, file: file, tab: tab) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if history.isEmpty {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button { step = history.removeLast() } label: { Label("Back", systemImage: "chevron.left") }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!history.isEmpty)
        .onAppear(perform: start)
    }

    private func go(_ next: Step) {
        history.append(step)
        withAnimation { step = next }
    }

    private func start() {
        if remapOnly, let email = account.connectionEmail, let id = account.spreadsheetId, let title = account.sheetTitle {
            step = .mapping(email: email, file: SpreadsheetFile(id: id, name: account.spreadsheetName ?? "Spreadsheet"), tab: SheetTab(id: account.sheetId ?? 0, title: title))
        } else if let email = account.connectionEmail, Keychain.load(for: email) != nil {
            step = .spreadsheet(email: email)
            history = [.connection]
        }
    }
}

// MARK: Steps

private struct ConnectionStep: View {
    var onPick: (String) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuth
    @Query(sort: \GoogleConnection.createdAt) private var connections: [GoogleConnection]
    @State private var signingIn = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    IconBadge(systemName: "tablecells", tint: .green, size: 56)
                    Text("Connect Google Sheets").font(.title3.bold())
                    Text("Sign in with Google so OpenSpend can read and write the spreadsheet you choose. Only spreadsheet names in your Drive are listed.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if !connections.isEmpty {
                Section("Signed-in Google accounts") {
                    ForEach(connections) { c in
                        Button { onPick(c.email) } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(c.displayName).foregroundStyle(.primary)
                                    Text(c.email).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: signIn) {
                    HStack {
                        Label("Sign in with Google", systemImage: "plus.circle.fill")
                        Spacer()
                        if signingIn { ProgressView() }
                    }
                }
                .disabled(signingIn)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .appScreen()
        .navigationTitle("Google Account")
    }

    private func signIn() {
        signingIn = true
        error = nil
        Task {
            defer { signingIn = false }
            do {
                let who = try await GoogleAuth.shared.signIn(using: webAuth)
                if !connections.contains(where: { $0.email == who.email }) {
                    context.insert(GoogleConnection(email: who.email, displayName: who.name))
                    try? context.save()
                }
                onPick(who.email)
            } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
                // User closed the sheet.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct SpreadsheetStep: View {
    let account: ExpenseAccount
    let email: String
    var onPick: (SpreadsheetFile, [SheetTab]) -> Void

    @State private var files: [SpreadsheetFile] = []
    @State private var search = ""
    @State private var loading = false
    @State private var opening: String?
    @State private var error: String?
    @State private var showCreate = false
    @State private var newTitle = "OpenSpend Expenses"

    var body: some View {
        List {
            Section {
                Button { showCreate = true } label: { Label("Create New Spreadsheet", systemImage: "doc.badge.plus") }
            } footer: {
                Text("Creates a spreadsheet with the columns OpenSpend needs, ready to use.")
            }

            Section {
                if loading && files.isEmpty {
                    HStack { ProgressView(); Text("Fetching your spreadsheets…").foregroundStyle(.secondary) }
                } else if files.isEmpty {
                    Text(search.isEmpty ? "No spreadsheets found." : "No spreadsheets match \"\(search)\".").foregroundStyle(.secondary)
                }
                ForEach(files) { f in
                    Button { open(f) } label: {
                        HStack {
                            Image(systemName: "tablecells").foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(f.name).foregroundStyle(.primary)
                                if let m = f.modifiedTime { Text("Edited \(m.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if opening == f.id { ProgressView() }
                        }
                    }
                    .disabled(opening != nil)
                }
            } header: {
                Text("Your spreadsheets")
            } footer: {
                if let error { Text(error).foregroundStyle(.red) } else { Text("Pull to refresh if a spreadsheet is missing.") }
            }
        }
        .appScreen()
        .navigationTitle("Select a Spreadsheet")
        .searchable(text: $search, prompt: "Search Drive")
        .refreshable { await load() }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
        .alert("New Spreadsheet", isPresented: $showCreate) {
            TextField("Name", text: $newTitle)
            Button("Create", action: create)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            files = try await SheetsAPI(email: email).listSpreadsheets(search: search)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ f: SpreadsheetFile) {
        opening = f.id
        Task {
            defer { opening = nil }
            do {
                let meta = try await SheetsAPI(email: email).tabs(spreadsheetId: f.id)
                onPick(SpreadsheetFile(id: f.id, name: meta.title, modifiedTime: f.modifiedTime), meta.tabs)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let headers = SheetField.allCases.map(\.defaultHeader) + [SheetCodec.idHeader]
                let made = try await SheetsAPI(email: email).createSpreadsheet(title: title, sheetTitle: "Expenses", headers: headers)
                onPick(SpreadsheetFile(id: made.id, name: title, modifiedTime: Date()), [made.tab])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct TabStep: View {
    let account: ExpenseAccount
    let file: SpreadsheetFile
    let tabs: [SheetTab]
    var onPick: (SheetTab) -> Void
    @Query private var accounts: [ExpenseAccount]

    var body: some View {
        List {
            Section {
                ForEach(tabs) { tab in
                    let owner = accounts.first { $0.id != account.id && $0.spreadsheetId == file.id && $0.sheetTitle == tab.title }
                    Button { onPick(tab) } label: {
                        HStack {
                            Image(systemName: "tablecells").foregroundStyle(.green)
                            Text(tab.title).foregroundStyle(.primary)
                            Spacer()
                            if let owner { Text("Used by \(owner.name)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(owner != nil)
                }
            } header: {
                Text(file.name)
            } footer: {
                Text("Each sheet can belong to one account.")
            }
        }
        .appScreen()
        .navigationTitle("Choose a Sheet")
    }
}

private struct ColumnMappingStep: View {
    @Bindable var account: ExpenseAccount
    let email: String
    let file: SpreadsheetFile
    let tab: SheetTab
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var accounts: [ExpenseAccount]
    @State private var header: [String] = []
    @State private var map = ColumnMap()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            if loading {
                HStack { ProgressView(); Text("Reading columns…").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(SheetField.required) { row($0) }
                } header: {
                    Text("Required")
                } footer: {
                    Text("Map each field to a column in \"\(tab.title)\". Row 1 is treated as the header.")
                }
                Section {
                    ForEach(SheetField.optional) { row($0) }
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Categories, payment methods and tags are stored as comma-separated text.")
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .appScreen()
        .navigationTitle("Map Columns")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else {
                    Button("Save", action: save).bold().disabled(!map.isComplete || loading)
                }
            }
        }
        .task { await loadHeader() }
    }

    private func row(_ field: SheetField) -> some View {
        HStack {
            Picker(field.label, selection: Binding(get: { map[field] ?? "" }, set: { map[field] = $0.isEmpty ? nil : $0 })) {
                if !field.isRequired || map[field] == nil { Text("None").tag("") }
                ForEach(header.filter { $0.caseInsensitiveCompare(SheetCodec.idHeader) != .orderedSame && !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
            }
            if map[field] == nil {
                Button("Create") { Task { await createColumn(field) } }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
            }
        }
    }

    private func loadHeader() async {
        defer { loading = false }
        if let owner = accounts.first(where: { $0.id != account.id && $0.spreadsheetId == file.id && $0.sheetTitle == tab.title }) {
            error = "This sheet is already used by \"\(owner.name)\"."
            return
        }
        do {
            let row = try await SheetsAPI(email: email).values(spreadsheetId: file.id, range: SheetCodec.a1(sheet: tab.title, "1:1")).first ?? []
            header = row.map { SheetCodec.string($0) }
            map = account.spreadsheetId == file.id && account.sheetTitle == tab.title ? (account.columnMap ?? autoMap()) : autoMap()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Guess columns by name.
    private func autoMap() -> ColumnMap {
        let synonyms: [SheetField: [String]] = [
            .title: ["title", "name", "description", "merchant", "item", "expense"],
            .amount: ["amount", "price", "cost", "total", "value"],
            .date: ["date", "time", "when", "day"],
            .currency: ["currency"],
            .category: ["category", "categories", "type"],
            .payment: ["payment", "payment method", "method", "account", "paid with"],
            .notes: ["notes", "note", "memo", "comment"],
            .tags: ["tags", "tag", "labels"],
        ]
        var m = ColumnMap()
        for field in SheetField.allCases {
            m[field] = header.first { h in synonyms[field, default: []].contains(h.lowercased().trimmingCharacters(in: .whitespaces)) }
        }
        return m
    }

    /// Adds a header cell for a missing field at the end of row 1.
    private func createColumn(_ field: SheetField) async {
        var name = field.defaultHeader
        if header.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { name += " (OpenSpend)" }
        let col = SheetCodec.columnLetter(header.count)
        do {
            try await SheetsAPI(email: email).update(spreadsheetId: file.id, range: SheetCodec.a1(sheet: tab.title, "\(col)1"), values: [[name]])
            header.append(name)
            map[field] = name
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        saving = true
        if account.modelContext == nil { context.insert(account) }
        let sheetChanged = account.spreadsheetId != file.id || account.sheetTitle != tab.title
        if sheetChanged { ExpenseStore.clearExpenses(of: account, context: context) }
        if account.name == "Google Sheets" || account.name.isEmpty { account.name = file.name }
        account.connectionEmail = email
        account.spreadsheetId = file.id
        account.spreadsheetName = file.name
        account.sheetTitle = tab.title
        account.sheetId = tab.id
        account.columnMap = map
        account.updatedAt = Date()
        try? context.save()
        AppGroup.defaults.set(account.id.uuidString, forKey: SettingsKey.activeAccountId)
        Task {
            await ExpenseSyncService.shared.sync(account, context: context, full: true)
            saving = false
            onDone()
        }
    }
}

// MARK: Manage connections

/// Lists Google sign-ins and any accounts whose link points at a removed sign-in.
struct ManageConnectionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuth
    @Query(sort: \GoogleConnection.createdAt) private var connections: [GoogleConnection]
    @Query(sort: \ExpenseAccount.sortOrder) private var accounts: [ExpenseAccount]
    @State private var toRemove: GoogleConnection?
    @State private var error: String?

    private var staleAccounts: [ExpenseAccount] {
        let emails = Set(connections.map(\.email))
        return accounts.filter { $0.type == .sheets && $0.hasSpreadsheet && ($0.connectionEmail.map { !emails.contains($0) || Keychain.load(for: $0) == nil } ?? true) }
    }

    var body: some View {
        List {
            Section {
                if connections.isEmpty { Text("No Google accounts are connected.").foregroundStyle(.secondary) }
                ForEach(connections) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.displayName)
                        Text(c.email).font(.caption).foregroundStyle(.secondary)
                        let used = accounts.filter { $0.connectionEmail == c.email }.map(\.name)
                        if !used.isEmpty { Text("Used by: \(used.joined(separator: ", "))").font(.caption2).foregroundStyle(Palette.textMuted) }
                        if Keychain.load(for: c.email) == nil { Text("Signed out — reconnect").font(.caption2).foregroundStyle(.orange) }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { toRemove = c }
                            .tint(Palette.danger)
                    }
                }
                Button { signIn() } label: { Label("Add Google Account", systemImage: "plus.circle.fill") }
            } header: {
                Text("Google accounts")
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }

            if !staleAccounts.isEmpty {
                Section {
                    ForEach(staleAccounts) { a in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(a.name)
                                Text(a.spreadsheetName ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unlink") {
                                ExpenseStore.clearExpenses(of: a, context: context)
                                a.clearSheetLink()
                                a.connectionEmail = nil
                                try? context.save()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Stale links")
                } footer: {
                    Text("These accounts point at a Google sign-in that is gone. Unlink to free the spreadsheet, or sign in again with the same Google account.")
                }
            }
        }
        .appScreen()
        .navigationTitle("Google Accounts")
        .alert("Remove \(toRemove?.email ?? "")?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out & Remove", role: .destructive) {
                if let c = toRemove {
                    Task { await GoogleAuth.shared.signOut(email: c.email) }
                    context.delete(c)
                    try? context.save()
                }
            }
        } message: {
            Text("Accounts using it stop syncing until you reconnect. Expenses already in the app and in your sheets are kept.")
        }
    }

    private func signIn() {
        Task {
            do {
                let who = try await GoogleAuth.shared.signIn(using: webAuth)
                if !connections.contains(where: { $0.email == who.email }) {
                    context.insert(GoogleConnection(email: who.email, displayName: who.name))
                    try? context.save()
                }
            } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
