import Foundation

enum StravaConfig {
    // Register your app at https://www.strava.com/settings/api
    // Set Authorization Callback Domain to: smartertraining
    static let clientID = "245900"
    static let clientSecret = "fb177ea743a7372eb357d17b6cec09f67d9f7b7c"

    static let callbackScheme = "smartertraining"
    static let redirectURI = "smartertraining://smartertraining"
    static let scope = "activity:write"

    static let authBaseURL = "https://www.strava.com/oauth/authorize"
    static let tokenURL = "https://www.strava.com/oauth/token"
    static let uploadURL = "https://www.strava.com/api/v3/uploads"

    static var isConfigured: Bool {
        clientID != "YOUR_CLIENT_ID" && clientSecret != "YOUR_CLIENT_SECRET"
    }
}
