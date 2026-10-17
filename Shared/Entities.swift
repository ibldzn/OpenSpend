import AppIntents
import Foundation
import SwiftData

/// Sentinel id for the "Go Back" option shown during shortcut disambiguation.
let goBackEntityId = "__go_back__"

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountEntityQuery()

    var id: String
    @Property(title: "Account Name") var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ a: ExpenseAccount) { self.init(id: a.id.uuidString, name: a.name) }

    static let goBack = AccountEntity(id: goBackEntityId, name: "‹ Go Back")

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AccountEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        EntityData.accounts().filter { identifiers.contains($0.id.uuidString) }.map(AccountEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        EntityData.accounts().map(AccountEntity.init)
    }
}

/// Category or payment option. `accountId` scopes it; names are what expenses store.
struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    var id: String
    var accountId: String
    @Property(title: "Option Name") var name: String
    var iconName: String

    init(id: String, accountId: String, name: String, iconName: String) {
        self.id = id
        self.accountId = accountId
        self.iconName = iconName
        self.name = name // @Property setter needs every stored property set first
    }

    init(_ c: ExpenseCategory) {
        self.init(id: c.id.uuidString, accountId: c.accountId.uuidString, name: c.name, iconName: c.iconName)
    }

    static let goBack = CategoryEntity(id: goBackEntityId, accountId: "", name: "‹ Go Back", iconName: "chevron.left")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: iconName))
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        EntityData.categories(accountId: nil).filter { identifiers.contains($0.id.uuidString) }.map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        EntityData.categories(accountId: EntityData.activeAccount()?.id).map(CategoryEntity.init)
    }
}

struct PaymentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Payment Method"
    static let defaultQuery = PaymentEntityQuery()

    var id: String
    var accountId: String
    @Property(title: "Option Name") var name: String
    var iconName: String

    init(id: String, accountId: String, name: String, iconName: String) {
        self.id = id
        self.accountId = accountId
        self.iconName = iconName
        self.name = name // @Property setter needs every stored property set first
    }

    init(_ p: ExpensePayment) {
        self.init(id: p.id.uuidString, accountId: p.accountId.uuidString, name: p.name, iconName: p.iconName)
    }

    static let goBack = PaymentEntity(id: goBackEntityId, accountId: "", name: "‹ Go Back", iconName: "chevron.left")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: iconName))
    }
}

struct PaymentEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PaymentEntity] {
        EntityData.payments(accountId: nil).filter { identifiers.contains($0.id.uuidString) }.map(PaymentEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PaymentEntity] {
        EntityData.payments(accountId: EntityData.activeAccount()?.id).map(PaymentEntity.init)
    }
}

/// Small fetch helpers shared by intents and the widget.
@MainActor
enum EntityData {
    static var context: ModelContext { SharedModelContainer.shared.mainContext }

    static func accounts() -> [ExpenseAccount] {
        (try? context.fetch(FetchDescriptor<ExpenseAccount>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    static func account(id: String?) -> ExpenseAccount? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return accounts().first { $0.id == uuid }
    }

    static func activeAccount() -> ExpenseAccount? {
        let all = accounts()
        return all.first { $0.id == Settings.activeAccountId } ?? all.first
    }

    static func categories(accountId: UUID?) -> [ExpenseCategory] {
        let all = (try? context.fetch(FetchDescriptor<ExpenseCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard let accountId else { return all }
        return all.filter { $0.accountId == accountId }
    }

    static func payments(accountId: UUID?) -> [ExpensePayment] {
        let all = (try? context.fetch(FetchDescriptor<ExpensePayment>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard let accountId else { return all }
        return all.filter { $0.accountId == accountId }
    }

    static func expenses(accountId: UUID) -> [Expense] {
        let d = FetchDescriptor<Expense>(predicate: #Predicate { $0.accountId == accountId && !$0.isTrashed },
                                         sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }
}
