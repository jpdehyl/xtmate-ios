import SwiftUI

// MARK: - Claim Info Card

/// Compact card displaying claim/insured/adjuster information
struct ClaimInfoCard: View {
    let claimNumber: String?
    let dateOfLoss: Date?
    let lossType: LossType?
    let insuredName: String?
    let insuredPhone: String?
    let insuredEmail: String?
    let adjusterName: String?
    let adjusterPhone: String?
    let propertyAddress: String?
    let propertyCity: String?
    let propertyState: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    // Claim badge
                    if let claimNumber = claimNumber {
                        Text("#\(claimNumber)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PaulDavisTheme.Colors.primary)
                            .continuousCornerRadius(PaulDavisTheme.Radius.xs)
                    }

                    // Loss type badge
                    if let lossType = lossType {
                        HStack(spacing: 4) {
                            Image(systemName: lossType.icon)
                            Text(lossType.shortName)
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(lossType.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(lossType.color.opacity(0.15))
                        .continuousCornerRadius(PaulDavisTheme.Radius.xs)
                    }

                    Spacer()

                    // Date of loss
                    if let dateOfLoss = dateOfLoss {
                        Text("DOL: \(formatDate(dateOfLoss))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(PaulDavisTheme.Spacing.md)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, PaulDavisTheme.Spacing.md)

                VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                    // Insured section
                    if insuredName != nil || insuredPhone != nil {
                        ContactSection(
                            title: "Insured",
                            name: insuredName,
                            phone: insuredPhone,
                            email: insuredEmail
                        )
                    }

                    // Adjuster section
                    if adjusterName != nil || adjusterPhone != nil {
                        ContactSection(
                            title: "Adjuster",
                            name: adjusterName,
                            phone: adjusterPhone,
                            email: nil
                        )
                    }

                    // Property address
                    if let address = formattedAddress {
                        AddressSection(address: address)
                    }
                }
                .padding(PaulDavisTheme.Spacing.md)
            }
        }
        .background(PaulDavisTheme.Colors.cardBackground)
        .continuousCornerRadius(PaulDavisTheme.Radius.md)
        .appShadow(PaulDavisTheme.Shadow.sm)
    }

    private var formattedAddress: String? {
        var parts: [String] = []
        if let address = propertyAddress { parts.append(address) }
        if let city = propertyCity { parts.append(city) }
        if let state = propertyState { parts.append(state) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Contact Section

private struct ContactSection: View {
    let title: String
    let name: String?
    let phone: String?
    let email: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.xs) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                if let name = name {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                if let phone = phone {
                    Button(action: { callPhone(phone) }) {
                        Label(phone, systemImage: PaulDavisTheme.Icons.call)
                            .font(.caption)
                            .foregroundStyle(PaulDavisTheme.Colors.primary)
                    }
                }

                if let email = email {
                    Button(action: { sendEmail(email) }) {
                        Image(systemName: PaulDavisTheme.Icons.email)
                            .font(.caption)
                            .foregroundStyle(PaulDavisTheme.Colors.primary)
                    }
                }
            }
        }
    }

    private func callPhone(_ number: String) {
        let cleaned = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func sendEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Address Section

private struct AddressSection: View {
    let address: String

    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.xs) {
            Text("PROPERTY")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Button(action: { openMaps() }) {
                HStack {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: PaulDavisTheme.Icons.map)
                        .foregroundStyle(PaulDavisTheme.Colors.primary)
                }
            }
        }
    }

    private func openMaps() {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Compact Claim Header

/// Ultra-compact header for claim info when space is limited
struct CompactClaimHeader: View {
    let claimNumber: String?
    let insuredName: String?
    let lossType: LossType?
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                // Loss type icon
                if let lossType = lossType {
                    Image(systemName: lossType.icon)
                        .foregroundStyle(lossType.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let name = insuredName {
                        Text(name)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if let claim = claimNumber {
                        Text("#\(claim)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(PaulDavisTheme.Spacing.md)
            .background(PaulDavisTheme.Colors.cardBackground)
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Claim Info Card") {
    VStack(spacing: 20) {
        ClaimInfoCard(
            claimNumber: "202511242869",
            dateOfLoss: Date().addingTimeInterval(-86400 * 30),
            lossType: .water,
            insuredName: "Jesse Daniel Mayor",
            insuredPhone: "(604) 555-1234",
            insuredEmail: "jesse@example.com",
            adjusterName: "Sarah Smith",
            adjusterPhone: "(604) 555-5678",
            propertyAddress: "2250 W 3rd Ave - Unit 105",
            propertyCity: "Vancouver",
            propertyState: "BC"
        )

        CompactClaimHeader(
            claimNumber: "202511242869",
            insuredName: "Jesse Daniel Mayor",
            lossType: .water
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
