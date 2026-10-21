import AppIntents
import SwiftData
import SwiftUI

enum AddExpenseError: Error, CustomLocalizedStringResourceConvertible {
    case noAccount
    case notLinked
    case syncFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccount: "No account found. Open OpenSpend to set up an account."
        case .notLinked: "This account has no spreadsheet yet. Open OpenSpend and choose one first."
        case .syncFailed(let m): "Saved in OpenSpend, but Google Sheets didn't accept it yet: \(m). It will retry on the next sync."
        }
    }
}

/// Accepts T or T? and yields T?, so we don't depend on how the SDK types optional parameter values.
private func flat<T>(_ v: T?) -> T? { v }

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Add a new expense to OpenSpend.")
    static let openAppWhenRun = false

    @Parameter(title: "Title") var expenseTitle: String?
    @Parameter(title: "Amount") var amount: Double?
    @Parameter(title: "Account") var account: AccountEntity?
    @Parameter(title: "Category") var category: CategoryEntity?
    @Parameter(title: "Payment Method") var payment: PaymentEntity?
    @Parameter(title: "Date", kind: .dateTime) var date: Date?
    @Parameter(title: "Show Created Expense", default: true) var showCreatedExpense: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$expenseTitle) for \(\.$amount)") {
            \.$account
            \.$category
            \.$payment
            \.$date
            \.$showCreatedExpense
        }
    }

    private enum Step { case title, amount, account, category, payment, done }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let goBackEnabled = Settings.bool(SettingsKey.enableGoBack)
        let allAccounts = EntityData.accounts()
        guard !allAccounts.isEmpty else { throw AddExpenseError.noAccount }

        var title = expenseTitle?.trimmingCharacters(in: .whitespaces) ?? ""
        var value = amount
        var chosenAccount: ExpenseAccount? = EntityData.account(id: account?.id)
        var chosenCategory: String? = category?.name
        var chosenPayment: String? = payment?.name
        var asked: [Step] = []        // steps resolved in this run, for Go Back
        var forceAsk: Set<Step> = []  // steps the user went back to: ask instead of inferring
        var step = Step.title

        func back() {
            guard let prev = asked.popLast() else { return }
            forceAsk.insert(prev)
            switch prev {
            case .account: chosenAccount = nil
            case .category: chosenCategory = nil
            case .payment: chosenPayment = nil
            default: break
            }
            step = prev
        }

        while step != .done {
            switch step {
            case .title:
                if title.isEmpty {
                    title = flat(try await $expenseTitle.requestValue("What is the expense about?"))?.trimmingCharacters(in: .whitespaces) ?? ""
                }
                step = .amount

            case .amount:
                if value == nil { value = flat(try await $amount.requestValue("How much did you spend?")) }
                step = .account

            case .account:
                if chosenAccount == nil {
                    if allAccounts.count == 1 {
                        chosenAccount = allAccounts[0]
                    } else {
                        var options = allAccounts.map(AccountEntity.init)
                        if goBackEnabled && !asked.isEmpty { options.append(.goBack) }
                        let picked = flat(try await $account.requestDisambiguation(among: options, dialog: "Which account?"))
                        if picked?.id == goBackEntityId { back(); continue }
                        chosenAccount = EntityData.account(id: picked?.id)
                        asked.append(.account)
                    }
                }
                guard let a = chosenAccount else { throw AddExpenseError.noAccount }
                if a.type == .sheets && !a.isLinked { throw AddExpenseError.notLinked }
                step = .category

            case .category:
                let a = chosenAccount!
                let options = EntityData.categories(accountId: a.id)
                if let c = chosenCategory, !options.contains(where: { $0.name == c }) { chosenCategory = nil }
                if chosenCategory == nil && !options.isEmpty {
                    if Settings.bool(SettingsKey.enableSmartSuggestions),
                       let guess = await SuggestionEngine.shared.infer(.category, title: title, options: options.map(\.name), history: EntityData.expenses(accountId: a.id), accountId: a.id),
                       !forceAsk.contains(.category) {
                        chosenCategory = guess
                        asked.append(.category)
                    } else {
                        var entities = options.map(CategoryEntity.init)
                        if goBackEnabled && !asked.isEmpty { entities.insert(.goBack, at: 0) }
                        let picked = flat(try await $category.requestDisambiguation(among: entities, dialog: "Which category?"))
                        if picked?.id == goBackEntityId { back(); continue }
                        chosenCategory = picked?.name
                        asked.append(.category)
                    }
                }
                step = .payment

            case .payment:
                let a = chosenAccount!
                let options = EntityData.payments(accountId: a.id)
                if let p = chosenPayment, !options.contains(where: { $0.name == p }) { chosenPayment = nil }
                if chosenPayment == nil && !options.isEmpty {
                    if Settings.bool(SettingsKey.enableSmartSuggestions),
                       let guess = await SuggestionEngine.shared.infer(.payment, title: title, options: options.map(\.name), history: EntityData.expenses(accountId: a.id), accountId: a.id),
                       !forceAsk.contains(.payment) {
                        chosenPayment = guess
                        asked.append(.payment)
                    } else {
                        var entities = options.map(PaymentEntity.init)
                        if goBackEnabled && !asked.isEmpty { entities.insert(.goBack, at: 0) }
                        let picked = flat(try await $payment.requestDisambiguation(among: entities, dialog: "Which payment method?"))
                        if picked?.id == goBackEntityId { back(); continue }
                        chosenPayment = picked?.name
                        asked.append(.payment)
                    }
                }
                step = .done

            case .done:
                break
            }
        }

        let a = chosenAccount!
        let fields = ExpenseFields(title: title, amount: value ?? 0, currency: Settings.defaultCurrency, date: date ?? Date(),
                                   categories: chosenCategory.map { [$0] } ?? [], payments: chosenPayment.map { [$0] } ?? [])
        let snippet = ExpenseSnippetView(fields: fields, accountName: a.name, compact: false)

        if Settings.bool(SettingsKey.confirmExpenseDetails) {
            try await requestConfirmation(result: .result(dialog: "Confirm expense details:") { snippet }, confirmationActionName: .add)
        }

        let context = SharedModelContainer.shared.mainContext
        let expense = ExpenseStore.create(fields, in: a, context: context, syncNow: false)
        if a.isLinked {
            await ExpenseSyncService.shared.sync(a, context: context, quiet: true)
            if expense.syncState != .synced {
                return .result(dialog: "Saved in OpenSpend. It will reach Google Sheets on the next sync.") {
                    ExpenseSnippetView(fields: fields, accountName: a.name, compact: !showCreatedExpense)
                }
            }
        }
        let message: IntentDialog = a.isLinked ? "Added to OpenSpend and Google Sheets." : "Expense added."
        return .result(dialog: message) {
            ExpenseSnippetView(fields: fields, accountName: a.name, compact: !showCreatedExpense)
        }
    }
}

struct ExpenseSnippetView: View {
    var fields: ExpenseFields
    var accountName: String
    var compact: Bool

    var body: some View {
        if compact {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fields.title).font(.headline).lineLimit(2)
                    Spacer()
                    Text(Money.format(fields.amount, currency: fields.currency)).font(.title2.bold())
                }
                let detail = ([accountName] + fields.categories + fields.payments).joined(separator: " · ")
                Text(detail).font(.subheadline).foregroundStyle(Palette.textMuted)
                Text(fields.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.textMuted)
            }
            .foregroundStyle(Palette.primary)
            .padding()
            // The snippet renders in the system's appearance, not the app's forced dark,
            // so it paints its own dark surface to keep the light text readable.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
        }
    }
}

struct GetCategoriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Categories"
    static let description = IntentDescription("Get all categories for an account in OpenSpend.")

    @Parameter(title: "Account") var account: AccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get categories for \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[CategoryEntity]> & ProvidesDialog {
        guard let a = EntityData.account(id: account?.id) ?? EntityData.activeAccount() else { throw AddExpenseError.noAccount }
        let cats = EntityData.categories(accountId: a.id).map(CategoryEntity.init)
        let dialog: IntentDialog = cats.isEmpty ? "No categories found for \(a.name)." : "\(a.name) has \(cats.count) categories."
        return .result(value: cats, dialog: dialog)
    }
}

struct OpenSpendShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(), phrases: [
            "Add expense in \(.applicationName)",
            "Log expense in \(.applicationName)",
            "Record expense in \(.applicationName)",
            "New expense in \(.applicationName)",
            "Add spending in \(.applicationName)",
        ], shortTitle: "Add Expense", systemImageName: "plus.circle")

        AppShortcut(intent: GetCategoriesIntent(), phrases: [
            "Get categories in \(.applicationName)",
            "List categories in \(.applicationName)",
            "Show categories in \(.applicationName)",
        ], shortTitle: "Get Categories", systemImageName: "tag")
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
