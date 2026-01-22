import Foundation

// MARK: - Parsed Dispatch

/// Data extracted from a dispatch email
struct ParsedDispatch {
    // Insured info
    var insuredName: String?
    var insuredEmail: String?

    // Property info
    var propertyAddress: String?
    var propertyCity: String?
    var propertyState: String?
    var propertyZip: String?
    var latitude: Double?
    var longitude: Double?

    // Claim info
    var claimNumber: String?
    var dateOfLoss: Date?
    var typeOfLoss: LossType?
    var xaId: String?
    var dispatchType: DispatchType?

    // Insurance info
    var insuranceCompany: String?

    // Raw email for reference
    var rawEmail: String

    /// Whether minimum required fields are present
    var isValid: Bool {
        insuredName != nil && propertyAddress != nil
    }
}

// MARK: - Dispatch Email Parser

/// Parses XactAnalysis dispatch emails to extract claim information
class DispatchEmailParser {

    // MARK: - Public Methods

    /// Parse a dispatch email text into structured data
    func parse(_ emailText: String) -> ParsedDispatch {
        var result = ParsedDispatch(rawEmail: emailText)

        // Extract fields
        result.insuredName = extractField(from: emailText, pattern: "Insured Name:\\s*(.+)")
        result.insuredEmail = extractField(from: emailText, pattern: "Email Address:\\s*(.+)")
        result.claimNumber = extractField(from: emailText, pattern: "Claim Number:\\s*(.+)")
        result.xaId = extractField(from: emailText, pattern: "XA ID:\\s*(.+)")

        // Parse date of loss
        if let dateString = extractField(from: emailText, pattern: "Date of Loss:\\s*(.+)") {
            result.dateOfLoss = parseDate(dateString)
        }

        // Parse loss type
        if let lossTypeCode = extractField(from: emailText, pattern: "Type of Loss:\\s*(.+)") {
            result.typeOfLoss = LossType(fromCode: lossTypeCode.trimmingCharacters(in: .whitespaces))
        }

        // Parse dispatch type
        if let typeString = extractField(from: emailText, pattern: "Type:\\s*(Normal|Rush|Emergency)") {
            result.dispatchType = DispatchType(rawValue: typeString)
        }

        // Parse address
        if let addressLine = extractField(from: emailText, pattern: "Location of Property:\\s*(.+)") {
            let parsed = parseAddress(addressLine)
            result.propertyAddress = parsed.street
            result.propertyCity = parsed.city
            result.propertyState = parsed.state
            result.propertyZip = parsed.zip
        }

        // Parse coordinates
        if let coords = extractCoordinates(from: emailText) {
            result.latitude = coords.lat
            result.longitude = coords.lon
        }

        // Try to extract insurance company from subject line
        result.insuranceCompany = extractInsuranceCompany(from: emailText)

        return result
    }

    // MARK: - Private Methods

    /// Extract a field value using regex pattern
    private func extractField(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: text) else {
            return nil
        }

        let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Parse a date string in various formats
    private func parseDate(_ dateString: String) -> Date? {
        let formatters: [DateFormatter] = [
            createFormatter("MM/dd/yyyy"),
            createFormatter("yyyy-MM-dd"),
            createFormatter("MM-dd-yyyy"),
            createFormatter("MMM dd, yyyy"),
            createFormatter("MMMM dd, yyyy")
        ]

        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private func createFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    /// Parse a full address line into components
    /// Example: "2250 W 3rd Ave - Unit 105, Vancouver, BC V6K 1L4, Canada"
    private func parseAddress(_ addressLine: String) -> (street: String?, city: String?, state: String?, zip: String?) {
        // Remove "Canada" or country suffix
        let cleaned = addressLine
            .replacingOccurrences(of: ", Canada", with: "")
            .replacingOccurrences(of: ", USA", with: "")
            .replacingOccurrences(of: ", United States", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split by comma
        let parts = cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 2 else {
            return (street: cleaned, city: nil, state: nil, zip: nil)
        }

        // First part is the street address
        let street = parts[0]

        // Second part is typically the city
        let city = parts[1]

        // Third part (if exists) contains state and zip
        var state: String? = nil
        var zip: String? = nil

        if parts.count >= 3 {
            let stateZip = parts[2]
            // Try to extract state and zip
            // Patterns: "BC V6K 1L4" or "TX 78701" or "California 90210"
            let stateZipParts = stateZip.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            if stateZipParts.count >= 1 {
                // First word is state/province
                state = stateZipParts[0]
            }

            if stateZipParts.count >= 2 {
                // Rest is zip code (may be multi-part like "V6K 1L4")
                zip = stateZipParts.dropFirst().joined(separator: " ")
            }
        }

        return (street: street, city: city, state: state, zip: zip)
    }

    /// Extract coordinates from text
    /// Format: "49.2688115 N, 123.1563664 W" or "49.2688115, -123.1563664"
    private func extractCoordinates(from text: String) -> (lat: Double, lon: Double)? {
        // Pattern for "XX.XXXXX N, XXX.XXXXX W" format
        let pattern1 = #"(\d+\.?\d*)[°\s]*N[,\s]+(\d+\.?\d*)[°\s]*W"#
        if let regex = try? NSRegularExpression(pattern: pattern1, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 2,
           let latRange = Range(match.range(at: 1), in: text),
           let lonRange = Range(match.range(at: 2), in: text),
           let lat = Double(text[latRange]),
           let lon = Double(text[lonRange]) {
            return (lat: lat, lon: -lon) // West longitude is negative
        }

        // Pattern for decimal coordinates
        let pattern2 = #"(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: pattern2, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 2,
           let latRange = Range(match.range(at: 1), in: text),
           let lonRange = Range(match.range(at: 2), in: text),
           let lat = Double(text[latRange]),
           let lon = Double(text[lonRange]),
           abs(lat) <= 90 && abs(lon) <= 180 {
            return (lat: lat, lon: lon)
        }

        return nil
    }

    /// Extract insurance company from subject line or body
    private func extractInsuranceCompany(from text: String) -> String? {
        // Look for pattern in subject: "Contact Name @ (Type) - Company Name (Assignment)"
        // Example: "Contact Jesse Daniel Mayor @ (WaterDmg) - Paul Davis Greater Vancouver (Normal assignment)"
        if let pattern = try? NSRegularExpression(pattern: #"\)\s*-\s*(.+?)\s*\("#, options: []),
           let match = pattern.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }

        // Look for "From: Company" pattern
        if let company = extractField(from: text, pattern: "From:\\s*(.+?)\\s*(?:To:|$)") {
            // Filter out XactAnalysis sender
            if !company.lowercased().contains("xactanalysis") {
                return company
            }
        }

        return nil
    }
}

// MARK: - Preview/Testing

#if DEBUG
extension DispatchEmailParser {
    static var sampleEmail: String {
        """
        Contact Jesse Daniel Mayor @ (WaterDmg) - Paul Davis Greater Vancouver (Normal assignment)
        XactAnalysis<XactAnalysis.support@xactware.com>
        Oncall.Vancouver
        CAUTION: This email originated from outside of Paul Davis. Do not click links or open attachments unless you recognize the sender and know the content is safe.

        From:     Max - Contractors
        To:     Paul Davis Greater Vancouver

         Google Maps  MapQuest
        Assignment Profile:
        Type:     Normal
        Date of Loss:     11/23/2025
        Claim Number:     202511242869
        Insured Name:     Jesse Daniel Mayor
        Email Address:    jessemayor91@gmail.com
        Type of Loss:     WATERDMG
        XA ID:     06PJV6Y
        Location of Property:     2250 W 3rd Ave - Unit 105, Vancouver, BC V6K 1L4, Canada
        49.2688115 N, 123.1563664 W
        49 16.12869' N, 123 9.381984' W

        Instructions:


        Dates:
        Assignment Received by XactAnalysis:     01/14/2026 07:02PM GMT
        Notification Sent:     01/14/2026 12:03PM MT

        View detailed information for this assignment in XactAnalysis.
        """
    }
}
#endif
