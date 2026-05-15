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

        try await exchangeToken(identityToken: tokenString, fullName: credential.fullName)
    }

    func signOut() {
        KeychainHelper.delete(forKey: Keys.jwt, service: Self.keychainService)
        KeychainHelper.delete(forKey: Keys.userId, service: Self.keychainService)
        KeychainHelper.delete(forKey: Keys.expiresAt, service: Self.keychainService)
        isSignedIn = false
        userId = nil
    }

    private func exchangeToken(identityToken: String, fullName: PersonNameComponents?) async throws {
        var body: [String: Any] = ["identity_token": identityToken]
        if let name = fullName {
            var nameParts: [String] = []
            if let given = name.givenName { nameParts.append(given) }
            if let family = name.familyName { nameParts.append(family) }
            if !nameParts.isEmpty {
                body["full_name"] = nameParts.joined(separator: " ")
            }
        }

        let url = URL(string: "\(Self.baseURL)/v1/auth/apple")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.serverError
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
        case serverError
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingToken: "Missing identity token from Apple"
            case .serverError: "Server authentication failed"
            case .invalidResponse: "Invalid server response"
            }
        }
    }

    #if DEBUG
    static var baseURL = "https://smartertraining-api.onrender.com"
    #else
    static let baseURL = "https://smartertraining-api.onrender.com"
    #endif
}
