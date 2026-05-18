import Foundation

enum StravaConfig {
    static let clientID = "245900"

    static let callbackScheme = "smartertraining"
    static let redirectURI = "smartertraining://smartertraining"
    static let scope = "activity:write"

    static let authBaseURL = "https://www.strava.com/oauth/authorize"
    static let tokenProxyURL = "\(BackendAuthService.baseURL)/v1/strava/token"
    static let uploadURL = "https://www.strava.com/api/v3/uploads"

    static var isConfigured: Bool {
        clientID != "YOUR_CLIENT_ID"
    }
}
