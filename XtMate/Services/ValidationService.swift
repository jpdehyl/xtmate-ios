import Foundation
import Combine

// MARK: - Validation Service

/// Service for validating line item selectors against the web API
class ValidationService: ObservableObject {
    static let shared = ValidationService()

    @Published var isValidating = false
    @Published var lastError: String?

    private let baseURL: String

    init() {
        // For local development, use localhost
        // When you deploy, change this to your production URL
        self.baseURL = "http://localhost:3000/api"
    }

    // MARK: - Single Selector Validation

    /// Validate a single selector against the active price list
    /// - Parameter selector: The selector code to validate (e.g., "WTR DRY")
    /// - Returns: ValidationResponse with isValid, priceInfo, and suggestions
    func validateSelector(_ selector: String) async throws -> ValidationResponse {
        guard let url = URL(string: "\(baseURL)/price-lists/validate") else {
            throw ValidationError.networkError
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token
        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["selector": selector]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw ValidationError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw ValidationError.serverError(errorResponse.error)
            }
            throw ValidationError.serverError("Unknown error")
        }

        return try JSONDecoder().decode(ValidationResponse.self, from: data)
    }

    // MARK: - Bulk Validation

    /// Validate multiple selectors at once (max 100)
    /// - Parameter selectors: Array of selector codes to validate
    /// - Returns: BulkValidationResponse with results and stats
    func validateSelectors(_ selectors: [String]) async throws -> BulkValidationResponse {
        guard selectors.count <= 100 else {
            throw ValidationError.tooManySelectors
        }

        guard !selectors.isEmpty else {
            return BulkValidationResponse(
                results: [],
                stats: nil
            )
        }

        guard let url = URL(string: "\(baseURL)/price-lists/validate") else {
            throw ValidationError.networkError
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["selectors": selectors]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw ValidationError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw ValidationError.serverError(errorResponse.error)
            }
            throw ValidationError.serverError("Unknown error")
        }

        return try JSONDecoder().decode(BulkValidationResponse.self, from: data)
    }

    // MARK: - Search

    /// Search for price list items by query
    /// - Parameters:
    ///   - query: Search term (searches selector and description)
    ///   - limit: Maximum results to return (default 20)
    /// - Returns: Array of matching items
    func search(query: String, limit: Int = 20) async throws -> [SuggestionInfo] {
        guard !query.isEmpty else {
            return []
        }

        guard let url = URL(string: "\(baseURL)/price-lists/validate") else {
            throw ValidationError.networkError
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await AuthService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw ValidationError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw ValidationError.serverError(errorResponse.error)
            }
            throw ValidationError.serverError("Unknown error")
        }

        let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
        return searchResponse.results
    }
}

// MARK: - Response Types

struct ValidationResponse: Codable {
    let isValid: Bool
    let priceInfo: PriceInfo?
    let suggestions: [SuggestionInfo]
}

struct PriceInfo: Codable {
    let selector: String
    let category: String
    let description: String
    let unit: String
    let laborRate: Double
    let materialRate: Double
    let equipmentRate: Double
    let totalRate: Double
}

struct SuggestionInfo: Codable, Identifiable {
    var id: String { selector }
    let selector: String
    let category: String
    let description: String
    let unit: String
    let totalRate: Double
    let similarity: Double?
}

struct BulkValidationResponse: Codable {
    let results: [BulkValidationResult]
    let stats: ValidationStats?
}

struct ValidationStats: Codable {
    let total: Int
    let valid: Int
    let invalid: Int
    let withSuggestions: Int
}

struct BulkValidationResult: Codable {
    let selector: String
    let isValid: Bool
    let priceInfo: PriceInfo?
    let suggestions: [SuggestionInfo]
}

struct SearchResponse: Codable {
    let results: [SuggestionInfo]
}

struct APIErrorResponse: Codable {
    let error: String
}

// MARK: - Validation Errors

enum ValidationError: Error, LocalizedError {
    case serverError(String)
    case unauthorized
    case tooManySelectors
    case networkError
    case noPriceList

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .unauthorized:
            return "Please sign in to validate items."
        case .tooManySelectors:
            return "Maximum 100 selectors per request."
        case .networkError:
            return "Network error. Check your connection."
        case .noPriceList:
            return "No active price list. Import one in Settings."
        }
    }
}
