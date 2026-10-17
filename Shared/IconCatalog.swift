import Foundation

enum IconCatalog {
    static let category = [
        "cart", "basket", "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass", "birthday.cake",
        "car", "fuelpump", "bus", "tram", "airplane", "bicycle", "parkingsign",
        "house", "bolt", "drop", "flame", "wifi", "phone", "tv",
        "bag", "tshirt", "shoe", "gift", "sparkles", "scissors", "paintbrush",
        "heart", "cross.case", "pills", "dumbbell", "figure.run", "leaf", "pawprint",
        "book", "graduationcap", "gamecontroller", "music.note", "film", "ticket", "camera",
        "briefcase", "building.2", "hammer", "wrench.and.screwdriver", "doc.text", "percent",
        "creditcard", "banknote", "dollarsign.circle", "chart.line.uptrend.xyaxis", "arrow.triangle.2.circlepath", "tag",
    ]

    static let payment = [
        "creditcard", "creditcard.fill", "banknote", "dollarsign.circle", "wallet.bifold", "building.columns",
        "iphone", "applelogo", "qrcode", "arrow.left.arrow.right", "giftcard", "person.2", "bitcoinsign.circle", "tag",
    ]

    static let account = [
        "wallet.bifold", "person", "person.2", "house", "briefcase", "airplane", "cart", "heart", "star", "leaf", "building.2", "graduationcap",
    ]

    static func guessCategoryIcon(_ name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("food", "fork.knife"), ("dining", "fork.knife"), ("restaurant", "fork.knife"), ("coffee", "cup.and.saucer"),
            ("grocer", "cart"), ("transport", "car"), ("car", "car"), ("fuel", "fuelpump"), ("gas", "fuelpump"), ("travel", "airplane"),
            ("rent", "house"), ("home", "house"), ("util", "bolt"), ("bill", "doc.text"), ("shop", "bag"), ("cloth", "tshirt"),
            ("health", "heart"), ("medic", "cross.case"), ("gym", "dumbbell"), ("fitness", "dumbbell"), ("pet", "pawprint"),
            ("educat", "graduationcap"), ("book", "book"), ("game", "gamecontroller"), ("entertain", "film"), ("movie", "film"),
            ("music", "music.note"), ("gift", "gift"), ("subscri", "arrow.triangle.2.circlepath"), ("work", "briefcase"),
        ]
        return table.first { n.contains($0.0) }?.1 ?? "tag"
    }

    static func guessPaymentIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cash") { return "banknote" }
        if n.contains("apple") { return "applelogo" }
        if n.contains("bank") || n.contains("transfer") { return "building.columns" }
        if n.contains("qr") { return "qrcode" }
        if n.contains("card") || n.contains("visa") || n.contains("master") || n.contains("amex") { return "creditcard" }
        return "creditcard"
    }
}
