import AuthenticationServices
import Foundation
import Observation

enum StravaError: LocalizedError {
    case notConfigured
    case noCallback
    case noAuthCode
    case tokenExchangeFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Strava API credentials not configured."
        case .noCallback: "No response from Strava."
        case .noAuthCode: "Authorization code missing."
        case .tokenExchangeFailed(let msg): "Token exchange failed: \(msg)"
        case .notConnected: "Not connected to Strava."
        }
    }
}

@Observable
final class StravaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    var isConnected: Bool = false
    var athleteName: String?

    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        loadFromKeychain()
    }

    // MARK: - OAuth Flow

    func authorize() async throws {
        guard StravaConfig.isConfigured else { throw StravaError.notConfigured }

        var components = URLComponents(string: StravaConfig.authBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: StravaConfig.scope),
            URLQueryItem(name: "approval_prompt", value: "auto")
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: StravaConfig.callbackScheme
            ) { [weak self] url, error in
                self?.authSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: StravaError.noCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.noAuthCode
        }

        try await exchangeToken(code: code)
    }

    func disconnect() {
        KeychainHelper.deleteAll()
        isConnected = false
        athleteName = nil
    }

    // MARK: - Token Management

    func validAccessToken() async throws -> String {
        guard isConnected else { throw StravaError.notConnected }

        if let expiresString = KeychainHelper.read(forKey: "expires_at"),
           let expiresAt = TimeInterval(expiresString),
           Date().timeIntervalSince1970 < expiresAt - 60,
           let token = KeychainHelper.read(forKey: "access_token") {
            return token
        }

        return try await refreshToken()
    }

    // MARK: - Presentation Context

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: - Private

    private func exchangeToken(code: String) async throws {
        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        try await performTokenRequest(body: body)
    }

    private func refreshToken() async throws -> String {
        guard let refreshToken = KeychainHelper.read(forKey: "refresh_token") else {
            disconnect()
            throw StravaError.notConnected
        }
        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        try await performTokenRequest(body: body)
        guard let token = KeychainHelper.read(forKey: "access_token") else {
            throw StravaError.notConnected
        }
        return token
    }

    private func performTokenRequest(body: [String: String]) async throws {
        var request = URLRequest(url: URL(string: StravaConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw StravaError.tokenExchangeFailed(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaError.tokenExchangeFailed("Invalid response")
        }

        if let accessToken = json["access_token"] as? String {
            KeychainHelper.save(accessToken, forKey: "access_token")
        }
        if let refreshToken = json["refresh_token"] as? String {
            KeychainHelper.save(refreshToken, forKey: "refresh_token")
        }
        if let expiresAt = json["expires_at"] as? Double {
            KeychainHelper.save(String(expiresAt), forKey: "expires_at")
        }
        if let athlete = json["athlete"] as? [String: Any],
           let firstName = athlete["firstname"] as? String {
            let name = [firstName, athlete["lastname"] as? String].compactMap { $0 }.joined(separator: " ")
            KeychainHelper.save(name, forKey: "athlete_name")
            athleteName = name
        }

        isConnected = true
    }

    private func loadFromKeychain() {
        guard KeychainHelper.read(forKey: "access_token") != nil,
              KeychainHelper.read(forKey: "refresh_token") != nil else {
            return
        }
        isConnected = true
        athleteName = KeychainHelper.read(forKey: "athlete_name")
    }
}
