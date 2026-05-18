import Foundation
import AuthenticationServices

@Observable
final class BackendAuthService {

    private(set) var isSignedIn = false
    private(set) var userId: String?

    private static let keychainService = "com.timforan.SmarterTraining.backend"
    private enum Keys {
        static let jwt = "backend_jwt"
        static let userId = "backend_user_id"
        static let expiresAt = "backend_jwt_expires"
    }

    var jwt: String? {
        KeychainHelper.read(forKey: Keys.jwt, service: Self.keychainService)
    }

    init() {
        let token = KeychainHelper.read(forKey: Keys.jwt, service: Self.keychainService)
        isSignedIn = token != nil
        userId = KeychainHelper.read(forKey: Keys.userId, service: Self.keychainService)
    }

    func handleSignIn(authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.missingToken
        }

        let authorizationCode: String? = credential.authorizationCode.flatMap {
            String(data: $0, encoding: .utf8)
        }

        AnalyticsService.shared.track(.siwaStarted)
        do {
            try await exchangeToken(
                identityToken: tokenString,
                fullName: credential.fullName,
                authorizationCode: authorizationCode
            )
            AnalyticsService.shared.track(.siwaSucceeded)
            if let userId {
                AnalyticsService.shared.identify(userId: userId)
                SentryService.setUser(id: userId)
            }
        } catch {
            AnalyticsService.shared.track(.siwaFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            throw error
        }
    }

    func deleteAccount() async throws {
        guard let jwt else {
            throw AuthError.serverError("Please sign in to delete your account")
        }

        let url = URL(string: "\(Self.baseURL)/v1/account")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw AuthError.serverError("Account deletion failed (\(httpResponse.statusCode))")
        }

        signOut()
    }

    func signOut() {
        KeychainHelper.delete(forKey: Keys.jwt, service: Self.keychainService)
        KeychainHelper.delete(forKey: Keys.userId, service: Self.keychainService)
        KeychainHelper.delete(forKey: Keys.expiresAt, service: Self.keychainService)
        isSignedIn = false
        userId = nil
        AnalyticsService.shared.reset()
        SentryService.clearUser()
    }

    private func exchangeToken(identityToken: String, fullName: PersonNameComponents?, authorizationCode: String? = nil) async throws {
        var body: [String: Any] = ["identity_token": identityToken]
        if let name = fullName {
            var nameParts: [String] = []
            if let given = name.givenName { nameParts.append(given) }
            if let family = name.familyName { nameParts.append(family) }
            if !nameParts.isEmpty {
                body["full_name"] = nameParts.joined(separator: " ")
            }
        }
        if let authorizationCode {
            body["authorization_code"] = authorizationCode
        }

        let url = URL(string: "\(Self.baseURL)/v1/auth/apple")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            var detail = "Server authentication failed"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverDetail = json["detail"] as? String {
                detail = serverDetail
            }
            throw AuthError.serverError(detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let uid = json["user_id"] as? String else {
            throw AuthError.invalidResponse
        }

        let expiresAt = json["expires_at"] as? String

        KeychainHelper.save(token, forKey: Keys.jwt, service: Self.keychainService)
        KeychainHelper.save(uid, forKey: Keys.userId, service: Self.keychainService)
        if let exp = expiresAt {
            KeychainHelper.save(exp, forKey: Keys.expiresAt, service: Self.keychainService)
        }

        isSignedIn = true
        userId = uid
    }

    enum AuthError: Error, LocalizedError {
        case missingToken
        case serverError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingToken: "Missing identity token from Apple"
            case .serverError(let detail): detail
            case .invalidResponse: "Invalid server response"
            }
        }
    }

    #if DEBUG
    static var baseURL = "https://smartertraining.onrender.com"
    #else
    static let baseURL = "https://smartertraining.onrender.com"
    #endif
}
