import Foundation
import Combine
import Security

// MARK: - Auth Service

/// Service for handling authentication with Clerk
/// Note: Full Clerk iOS SDK integration requires adding the package:
/// https://github.com/clerk/clerk-ios
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn = false
    @Published var userId: String?
    @Published var sessionToken: String?

    private init() {
        // Load any cached token
        loadCachedToken()
    }

    // MARK: - Token Management

    /// Get the current authentication token for API calls
    func getToken() async -> String? {
        // If we have a valid cached token, return it
        if let token = sessionToken, isTokenValid(token) {
            return token
        }

        // TODO: When Clerk iOS SDK is integrated, refresh token:
        // do {
        //     let token = try await Clerk.shared.session?.getToken()
        //     self.sessionToken = token?.jwt
        //     cacheToken(token?.jwt)
        //     return token?.jwt
        // } catch {
        //     print("Failed to get token: \(error)")
        //     return nil
        // }

        return sessionToken
    }

    /// Set the authentication token (for testing or manual auth)
    func setToken(_ token: String) {
        sessionToken = token
        isSignedIn = true
        cacheToken(token)
    }

    /// Clear the authentication state
    func signOut() {
        sessionToken = nil
        userId = nil
        isSignedIn = false
        clearCachedToken()
        clearCachedUserId()
    }

    // MARK: - User ID Management

    /// Get the current user ID (for filtering work orders, etc.)
    /// In production with Clerk, this would come from the Clerk session
    func getUserId() -> String? {
        // If we have a userId set, return it
        if let userId = userId {
            return userId
        }

        // Check cached userId
        if let cachedId = loadCachedUserId() {
            userId = cachedId
            return cachedId
        }

        // Try to extract from cached token (simplified JWT parsing)
        if let token = sessionToken {
            if let extractedId = extractUserIdFromToken(token) {
                userId = extractedId
                cacheUserId(extractedId)
                return extractedId
            }
        }

        // For testing/development, return a mock user ID
        #if DEBUG
        return "test_user_123"
        #else
        return nil
        #endif
    }

    /// Set the user ID (for testing or manual auth)
    func setUserId(_ id: String) {
        userId = id
        cacheUserId(id)
    }

    private func extractUserIdFromToken(_ token: String) -> String? {
        // JWT tokens are base64-encoded: header.payload.signature
        // The payload contains the user ID in the 'sub' claim
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        // Decode the payload
        var payloadString = String(parts[1])
        // Add padding if needed for base64
        while payloadString.count % 4 != 0 {
            payloadString += "="
        }

        guard let payloadData = Data(base64Encoded: payloadString),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }

        return sub
    }

    private let userIdKey = "xtmate_user_id"

    private func cacheUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: userIdKey)
    }

    private func loadCachedUserId() -> String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    private func clearCachedUserId() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
    }

    // MARK: - Token Caching

    private let tokenKey = "xtmate_auth_token"

    private func cacheToken(_ token: String?) {
        guard let token = token else { return }

        let tokenData = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKey,
            kSecAttrAccount as String: tokenKey
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = tokenData
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func loadCachedToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKey,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            sessionToken = token
            isSignedIn = true
        }
    }

    private func clearCachedToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenKey,
            kSecAttrAccount as String: tokenKey
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func isTokenValid(_ token: String) -> Bool {
        // Basic JWT expiration check
        // In production, decode JWT and check exp claim
        return !token.isEmpty
    }
}

// MARK: - Clerk SDK Integration (Future)

/*
 To fully integrate Clerk iOS SDK:

 1. Add Swift Package:
    - URL: https://github.com/clerk/clerk-ios
    - Branch: main

 2. Update XtMateApp.swift:
    import ClerkSDK

    @main
    struct XtMateApp: App {
        init() {
            Clerk.configure(publishableKey: "pk_test_...")
        }
        var body: some Scene {
            WindowGroup { ContentView() }
        }
    }

 3. Update AuthService to use Clerk:
    func getToken() async -> String? {
        guard let session = Clerk.shared.session else {
            return nil
        }
        do {
            let token = try await session.getToken()
            return token.jwt
        } catch {
            print("Failed to get token: \(error)")
            return nil
        }
    }

    func signIn() async throws {
        try await Clerk.shared.signIn()
        await checkAuthStatus()
    }

    func signOut() async throws {
        try await Clerk.shared.signOut()
        await checkAuthStatus()
    }
*/
