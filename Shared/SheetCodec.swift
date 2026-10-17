import Foundation

/// App fields that can be mapped to spreadsheet columns.
enum SheetField: String, Codable, CaseIterable, Identifiable {
    case title, amount, date, currency, category, payment, notes, tags

    var id: String { rawValue }

    static let required: [SheetField] = [.title, .amount, .date]
    static let optional: [SheetField] = [.currency, .category, .payment, .notes, .tags]

    var isRequired: Bool { SheetField.required.contains(self) }

    var label: String {
        switch self {
        case .title: "Title"
        case .amount: "Amount"
        case .date: "Date"
        case .currency: "Currency"
        case .category: "Category"
        case .payment: "Payment Method"
        case .notes: "Notes"
        case .tags: "Tags"
        }
    }

    var defaultHeader: String { label }
}

/// Plain value type for an expense, used by the codec, forms and intents.
struct ExpenseFields: Equatable {
    var title: String
    var amount: Double
    var currency: String
    var date: Date
    var categories: [String] = []
    var payments: [String] = []
    var notes: String = ""
    var tags: [String] = []
}

/// Which header (column name) each field is stored under.
struct ColumnMap: Codable, Equatable {
    var headers: [String: String] = [:] // SheetField.rawValue -> header text

    subscript(field: SheetField) -> String? {
        get { headers[field.rawValue] }
        set { headers[field.rawValue] = newValue }
    }

    var isComplete: Bool { SheetField.required.allSatisfy { self[$0] != nil } }
}

struct DecodedRow {
    var rowNumber: Int          // 1-based sheet row
    var id: String?
    var fields: ExpenseFields
    var raw: [Any]
}

enum SheetCodecError: LocalizedError, Equatable {
    case missingColumn(String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let h): "Column \"\(h)\" was not found in the sheet. Remap your columns in Account Settings."
        }
    }
}

enum SheetCodec {
    static let idHeader = "OpenSpend ID"
    static let listSeparator = ", "

    /// Resolve column indexes from the header row. Throws if a mapped column vanished.
    static func indexes(header: [String], map: ColumnMap) throws -> [SheetField: Int] {
        let normalized = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var result: [SheetField: Int] = [:]
        for field in SheetField.allCases {
            guard let h = map[field] else { continue }
            guard let i = normalized.firstIndex(of: h.trimmingCharacters(in: .whitespaces).lowercased()) else {
                throw SheetCodecError.missingColumn(h)
            }
            result[field] = i
        }
        return result
    }

    static func idIndex(header: [String]) -> Int? {
        header.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(idHeader) == .orderedSame }
    }

    static func decode(row: [Any], rowNumber: Int, indexes: [SheetField: Int], idIndex: Int?, defaultCurrency: String) -> DecodedRow? {
        func cell(_ f: SheetField) -> Any? {
            guard let i = indexes[f], i < row.count else { return nil }
            return row[i]
        }
        let title = string(cell(.title))
        let amount = cell(.amount).flatMap(parseAmount)
        // Skip blank rows.
        if title.isEmpty && amount == nil { return nil }
        let id = idIndex.flatMap { $0 < row.count ? string(row[$0]) : nil }.flatMap { $0.isEmpty ? nil : $0 }
        let currency = string(cell(.currency))
        let fields = ExpenseFields(
            title: title,
            amount: amount ?? 0,
            currency: currency.isEmpty ? defaultCurrency : currency.uppercased(),
            date: cell(.date).flatMap(parseDate) ?? Date(),
            categories: list(cell(.category)),
            payments: list(cell(.payment)),
            notes: string(cell(.notes)),
            tags: list(cell(.tags))
        )
        return DecodedRow(rowNumber: rowNumber, id: id, fields: fields, raw: row)
    }

    /// Writes mapped fields into `base` (an existing row, to keep unmapped cells), returning a full-width row.
    static func encode(_ f: ExpenseFields, id: String, indexes: [SheetField: Int], idIndex: Int, base: [Any] = []) -> [Any] {
        let width = max(base.count, (indexes.values.max() ?? 0) + 1, idIndex + 1)
        var row: [Any] = base + Array(repeating: "", count: width - base.count)
        for (field, i) in indexes {
            switch field {
            case .title: row[i] = f.title
            case .amount: row[i] = f.amount
            case .date: row[i] = sheetDateString(f.date)
            case .currency: row[i] = f.currency
            case .category: row[i] = f.categories.joined(separator: listSeparator)
            case .payment: row[i] = f.payments.joined(separator: listSeparator)
            case .notes: row[i] = f.notes
            case .tags: row[i] = f.tags.joined(separator: listSeparator)
            }
        }
        row[idIndex] = id
        return row
    }

    // MARK: Cell parsing

    static func string(_ v: Any?) -> String {
        switch v {
        case let s as String: s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let n as NSNumber: n.stringValue
        default: ""
        }
    }

    static func list(_ v: Any?) -> [String] {
        string(v).split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseAmount(_ v: Any) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return AmountParser.parse(s) }
        return nil
    }

    /// Accepts Sheets serial numbers (days since 1899-12-30) and common date strings.
    static func parseDate(_ v: Any) -> Date? {
        if let n = v as? NSNumber {
            return Date(timeIntervalSince1970: (n.doubleValue - 25569) * 86400).addingTimeInterval(-Double(TimeZone.current.secondsFromGMT()))
        }
        guard let s = v as? String, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "M/d/yyyy H:mm:ss", "M/d/yyyy H:mm", "M/d/yyyy", "d/M/yyyy", "dd.MM.yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Written with valueInputOption=USER_ENTERED so Sheets stores a real date.
    static func sheetDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 0 -> A, 25 -> Z, 26 -> AA
    static func columnLetter(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func a1(sheet: String, _ range: String) -> String {
        "'\(sheet.replacingOccurrences(of: "'", with: "''"))'!\(range)"
    }
}
