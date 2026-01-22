import Foundation

// MARK: - API Keys Configuration
// DO NOT hardcode API keys in source files
// Keys should be loaded from Info.plist (for development) or fetched from server (for production)

enum APIKeys {
    /// Gemini API key for AI features
    /// In development: Set GEMINI_API_KEY in Info.plist or environment
    /// In production: Fetch from secure server endpoint
    static var gemini: String {
        // Try to get from Info.plist first
        if let key = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String,
           !key.isEmpty,
           !key.starts(with: "$(") { // Not a placeholder
            return key
        }

        // Try environment variable (useful for CI/local development)
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           !key.isEmpty {
            return key
        }

        // Fallback warning - should not reach production
        #if DEBUG
        print("⚠️ WARNING: GEMINI_API_KEY not configured. Add to Info.plist or environment.")
        #endif

        return ""
    }

    /// Anthropic API key (future use for scope generation)
    static var anthropic: String {
        if let key = Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String,
           !key.isEmpty,
           !key.starts(with: "$(") {
            return key
        }

        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !key.isEmpty {
            return key
        }

        return ""
    }

    /// Web API base URL
    static var apiBaseURL: String {
        #if DEBUG
        // Local development - try both common ports (3000 primary, 3001 fallback)
        // If 3000 is in use, Next.js automatically uses 3001
        return "http://localhost:3001/api"
        #else
        // Production
        return "https://xtmate.vercel.app/api"
        #endif
    }
}
