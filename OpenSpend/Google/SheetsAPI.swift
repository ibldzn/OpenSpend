import Foundation

struct SpreadsheetFile: Identifiable, Hashable {
    var id: String
    var name: String
    var modifiedTime: Date?
}

struct SheetTab: Identifiable, Hashable {
    var id: Int // sheetId
    var title: String
}

struct SheetsAPIError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { "Google Sheets error (\(status)): \(message)" }
}

/// Thin REST client for the Sheets v4 and Drive v3 endpoints the app needs.
struct SheetsAPI {
    let email: String

    private static let sheetsBase = "https://sheets.googleapis.com/v4/spreadsheets"
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    // MARK: Drive

    func listSpreadsheets(search: String = "") async throws -> [SpreadsheetFile] {
        var q = "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false"
        if !search.isEmpty { q += " and name contains '\(search.replacingOccurrences(of: "'", with: "\\'"))'" }
        var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "orderBy", value: "modifiedTime desc"),
            .init(name: "pageSize", value: "100"),
            .init(name: "fields", value: "files(id,name,modifiedTime)"),
        ]
        let json = try await send(c.url!) as? [String: Any]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (json?["files"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return SpreadsheetFile(id: id, name: name, modifiedTime: ($0["modifiedTime"] as? String).flatMap(iso.date(from:)))
        }
    }

    // MARK: Spreadsheets

    func tabs(spreadsheetId: String) async throws -> (title: String, tabs: [SheetTab]) {
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId)?fields=properties.title,sheets.properties(sheetId,title)")!
        let json = try await send(url) as? [String: Any] ?? [:]
        let title = (json["properties"] as? [String: Any])?["title"] as? String ?? "Spreadsheet"
        let tabs = (json["sheets"] as? [[String: Any]] ?? []).compactMap { s -> SheetTab? in
            guard let p = s["properties"] as? [String: Any], let id = p["sheetId"] as? Int, let t = p["title"] as? String else { return nil }
            return SheetTab(id: id, title: t)
        }
        return (title, tabs)
    }

    /// Creates a spreadsheet with one tab and the default header row.
    func createSpreadsheet(title: String, sheetTitle: String, headers: [String]) async throws -> (id: String, tab: SheetTab) {
        let body: [String: Any] = [
            "properties": ["title": title],
            "sheets": [["properties": ["title": sheetTitle, "gridProperties": ["frozenRowCount": 1]]]],
        ]
        let json = try await send(URL(string: Self.sheetsBase)!, method: "POST", body: body) as? [String: Any] ?? [:]
        guard let id = json["spreadsheetId"] as? String,
              let p = (json["sheets"] as? [[String: Any]])?.first?["properties"] as? [String: Any],
              let sheetId = p["sheetId"] as? Int else { throw SheetsAPIError(status: 0, message: "Unexpected create response") }
        try await update(spreadsheetId: id, range: SheetCodec.a1(sheet: sheetTitle, "A1"), values: [headers])
        return (id, SheetTab(id: sheetId, title: sheetTitle))
    }

    func values(spreadsheetId: String, range: String) async throws -> [[Any]] {
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId)/values/\(encode(range))?valueRenderOption=UNFORMATTED_VALUE&dateTimeRenderOption=SERIAL_NUMBER")!
        let json = try await send(url) as? [String: Any]
        return json?["values"] as? [[Any]] ?? []
    }

    func update(spreadsheetId: String, range: String, values: [[Any]]) async throws {
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId)/values/\(encode(range))?valueInputOption=USER_ENTERED")!
        _ = try await send(url, method: "PUT", body: ["range": range, "majorDimension": "ROWS", "values": values])
    }

    func batchUpdateValues(spreadsheetId: String, data: [(range: String, values: [[Any]])]) async throws {
        guard !data.isEmpty else { return }
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId)/values:batchUpdate")!
        _ = try await send(url, method: "POST", body: [
            "valueInputOption": "USER_ENTERED",
            "data": data.map { ["range": $0.range, "majorDimension": "ROWS", "values": $0.values] },
        ])
    }

    func append(spreadsheetId: String, sheet: String, values: [[Any]]) async throws {
        guard !values.isEmpty else { return }
        let range = SheetCodec.a1(sheet: sheet, "A1")
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId)/values/\(encode(range)):append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS")!
        _ = try await send(url, method: "POST", body: ["range": range, "majorDimension": "ROWS", "values": values])
    }

    /// Deletes 1-based row numbers. Sorted descending so earlier deletes don't shift later ones.
    func deleteRows(spreadsheetId: String, sheetId: Int, rows: [Int]) async throws {
        guard !rows.isEmpty else { return }
        let requests = rows.sorted(by: >).map { row -> [String: Any] in
            ["deleteDimension": ["range": ["sheetId": sheetId, "dimension": "ROWS", "startIndex": row - 1, "endIndex": row]]]
        }
        let url = URL(string: "\(Self.sheetsBase)/\(spreadsheetId):batchUpdate")!
        _ = try await send(url, method: "POST", body: ["requests": requests])
    }

    // MARK: Transport

    private func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? s }

    private func send(_ url: URL, method: String = "GET", body: Any? = nil) async throws -> Any {
        let token = try await GoogleAuth.shared.accessToken(for: email)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? [:] : (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        guard (200..<300).contains(status) else {
            let message = ((json as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
            DebugLogger.shared.log("Sheets \(method) \(url.path) failed: \(status) \(message)")
            throw SheetsAPIError(status: status, message: message)
        }
        return json
    }
}
