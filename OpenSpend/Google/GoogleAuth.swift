import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

enum GoogleAuthError: LocalizedError {
    case missingClientID
    case invalidCallback
    case server(String)
    case notSignedIn(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: "Google client ID is not configured. Set GOOGLE_CLIENT_ID in project.yml."
        case .invalidCallback: "Google sign-in was cancelled or returned an invalid response."
        case .server(let m): m
        case .notSignedIn(let email): "\(email) is signed out. Reconnect it in Google Accounts."
        }
    }
}

enum GoogleConfig {
    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "" }
    /// "123-abc.apps.googleusercontent.com" -> "com.googleusercontent.apps.123-abc"
    static var callbackScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    static var redirectURI: String { callbackScheme + ":/oauthredirect" }
    static let scopes = [
        "openid", "email", "profile",
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.metadata.readonly",
    ]
}

/// OAuth 2.0 for installed apps with PKCE. No Google SDK needed.
@MainActor
final class GoogleAuth {
    static let shared = GoogleAuth()

    private var refreshTasks: [String: Task<GoogleTokens, Error>] = [:]

    /// Runs the browser sign-in and stores tokens. Returns the signed-in identity.
    func signIn(using session: WebAuthenticationSession) async throws -> (email: String, name: String) {
        guard !GoogleConfig.clientID.isEmpty, !GoogleConfig.clientID.hasPrefix("YOUR_") else { throw GoogleAuthError.missingClientID }

        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomURLSafe(16)

        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: GoogleConfig.clientID),
            .init(name: "redirect_uri", value: GoogleConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleConfig.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
        ]

        let callback = try await session.authenticate(using: c.url!, callbackURLScheme: GoogleConfig.callbackScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleAuthError.invalidCallback }

        let tokens = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": GoogleConfig.redirectURI,
        ], previousRefreshToken: nil)

        var req = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let email = info["email"] as? String else { throw GoogleAuthError.server("Could not read the Google account email.") }

        Keychain.save(tokens, for: email)
        DebugLogger.shared.log("Google sign-in succeeded for \(email)")
        return (email, info["name"] as? String ?? email)
    }

    /// Valid access token, refreshing when it expires within a minute.
    func accessToken(for email: String) async throws -> String {
        guard let tokens = Keychain.load(for: email) else { throw GoogleAuthError.notSignedIn(email) }
        if tokens.expiresAt > Date().addingTimeInterval(60) { return tokens.accessToken }
        guard let refresh = tokens.refreshToken else { throw GoogleAuthError.notSignedIn(email) }

        if let running = refreshTasks[email] { return try await running.value.accessToken }
        let task = Task { try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh], previousRefreshToken: refresh) }
        refreshTasks[email] = task
        defer { refreshTasks[email] = nil }
        let fresh = try await task.value
        Keychain.save(fresh, for: email)
        return fresh.accessToken
    }

    func signOut(email: String) async {
        if let t = Keychain.load(for: email) {
            var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke?token=\(t.refreshToken ?? t.accessToken)")!)
            req.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: req)
        }
        Keychain.delete(for: email)
    }

    private func tokenRequest(_ params: [String: String], previousRefreshToken: String?) async throws -> GoogleTokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params
        all["client_id"] = GoogleConfig.clientID
        var c = URLComponents()
        c.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
            throw GoogleAuthError.server(json["error_description"] as? String ?? "Google token request failed.")
        }
        let expires = (json["expires_in"] as? Double) ?? 3600
        return GoogleTokens(accessToken: access,
                            refreshToken: json["refresh_token"] as? String ?? previousRefreshToken,
                            expiresAt: Date().addingTimeInterval(expires))
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    private static let service = "OpenSpend.google"

    static func save(_ tokens: GoogleTokens, for email: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        delete(for: email)
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: email,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data,
        ] as CFDictionary, nil)
    }

    static func load(for email: String) -> GoogleTokens? {
        var out: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: email,
            kSecReturnData: true,
        ] as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    static func delete(for email: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: email] as CFDictionary)
    }
}
