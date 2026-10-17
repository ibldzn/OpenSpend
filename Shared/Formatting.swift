import Foundation

enum AmountParser {
    /// Parses user-typed amounts. Accepts "12.5", "12,5", "1,234.56", "1.234,56", "$ 9".
    static func parse(_ input: String) -> Double? {
        var s = input.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !s.isEmpty else { return nil }
        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")
        switch (lastDot, lastComma) {
        case let (d?, c?):
            // Whichever comes last is the decimal separator.
            if d > c { s.removeAll { $0 == "," } } else { s.removeAll { $0 == "." }; s = s.replacingOccurrences(of: ",", with: ".") }
        case (nil, _?):
            // One comma = decimal separator; several = thousands separators.
            s = s.filter { $0 == "," }.count == 1 ? s.replacingOccurrences(of: ",", with: ".") : s.replacingOccurrences(of: ",", with: "")
        case (_?, nil):
            if s.filter({ $0 == "." }).count > 1 { s.removeAll { $0 == "." } }
        default: break
        }
        return Double(s)
    }
}

enum Money {
    static func format(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency).presentation(.narrow))
    }

    static func symbol(for currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.currencySymbol ?? currency
    }
}
