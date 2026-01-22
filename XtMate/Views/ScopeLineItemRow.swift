import SwiftUI

// MARK: - Scope Line Item Row

/// Row displaying a single line item with validation state
struct ScopeLineItemRow: View {
    let lineItem: ScopeLineItem
    let onTapSuggestion: (SelectorSuggestion) -> Void

    @State private var showingSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row content
            HStack(spacing: 12) {
                // Validation indicator
                Image(systemName: lineItem.validationState.icon)
                    .font(.title3)
                    .foregroundColor(lineItem.validationState.color)
                    .frame(width: 24)

                // Item details
                VStack(alignment: .leading, spacing: 4) {
                    // Selector code
                    HStack(spacing: 6) {
                        Text(lineItem.selector)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(lineItem.validationState == .invalid ? .orange : .primary)

                        // Category badge
                        Text(lineItem.category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    // Description
                    Text(lineItem.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Quantity and price
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(lineItem.quantity, specifier: "%.1f") \(lineItem.unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("$\(lineItem.total, specifier: "%.2f")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            // Invalid state - show suggestions button
            if lineItem.validationState == .invalid && !lineItem.suggestions.isEmpty {
                Button(action: { showingSuggestions = true }) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        Text("\(lineItem.suggestions.count) suggestion\(lineItem.suggestions.count == 1 ? "" : "s") available")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Validating state - show progress
            if lineItem.validationState == .validating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingSuggestions) {
            SuggestionsSheet(
                invalidSelector: lineItem.selector,
                suggestions: lineItem.suggestions,
                onSelect: { suggestion in
                    onTapSuggestion(suggestion)
                    showingSuggestions = false
                },
                onCancel: { showingSuggestions = false }
            )
        }
    }
}

// MARK: - Suggestions Sheet

struct SuggestionsSheet: View {
    let invalidSelector: String
    let suggestions: [SelectorSuggestion]
    let onSelect: (SelectorSuggestion) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("The selector \"\(invalidSelector)\" was not found in your price list.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Similar Items") {
                    ForEach(suggestions) { suggestion in
                        Button(action: { onSelect(suggestion) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(suggestion.selector)
                                        .font(.headline)
                                    Spacer()
                                    Text("$\(suggestion.totalRate, specifier: "%.2f")/\(suggestion.unit)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text(suggestion.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ScopeLineItemRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            // Valid item
            ScopeLineItemRow(
                lineItem: ScopeLineItem(
                    category: "WTR",
                    selector: "WTR EXTRT",
                    description: "Extract water from floor - includes setup and takedown",
                    quantity: 125,
                    unit: "SF",
                    unitPrice: 0.85
                ),
                onTapSuggestion: { _ in }
            )

            // Invalid item with suggestions
            ScopeLineItemRow(
                lineItem: {
                    var item = ScopeLineItem(
                        category: "WTR",
                        selector: "WTR BADCODE",
                        description: "Invalid line item",
                        quantity: 50,
                        unit: "SF",
                        unitPrice: 1.00
                    )
                    item.validationState = .invalid
                    item.suggestions = [
                        SelectorSuggestion(
                            selector: "WTR DRY",
                            category: "WTR",
                            description: "Water drying services",
                            unit: "SF",
                            totalRate: 0.95,
                            similarity: 0.8
                        )
                    ]
                    return item
                }(),
                onTapSuggestion: { _ in }
            )

            // Validating item
            ScopeLineItemRow(
                lineItem: {
                    var item = ScopeLineItem(
                        category: "DEM",
                        selector: "DEM FLR",
                        description: "Remove flooring",
                        quantity: 100,
                        unit: "SF",
                        unitPrice: 2.50
                    )
                    item.validationState = .validating
                    return item
                }(),
                onTapSuggestion: { _ in }
            )
        }
    }
}
#endif
