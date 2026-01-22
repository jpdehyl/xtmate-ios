import SwiftUI

// MARK: - Scope List View

/// View showing all line items for an estimate with validation states
struct ScopeListView: View {
    @ObservedObject var store: EstimateStore
    let estimate: Estimate

    @State private var showingAddLineItem = false
    @State private var isValidating = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            ScopeHeaderView(
                lineItems: estimate.lineItems,
                isValidating: isValidating
            )

            // Error banner
            if let error = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button(action: { validationError = nil }) {
                        Image(systemName: "xmark")
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }

            // Line items list
            if estimate.lineItems.isEmpty {
                EmptyScopeView(onAddItem: { showingAddLineItem = true })
            } else {
                List {
                    ForEach(groupedLineItems.keys.sorted(), id: \.self) { roomName in
                        Section(header: Text(roomName)) {
                            ForEach(groupedLineItems[roomName] ?? []) { item in
                                ScopeLineItemRow(
                                    lineItem: item,
                                    onTapSuggestion: { suggestion in
                                        replaceLineItem(item, with: suggestion)
                                    }
                                )
                            }
                            .onDelete { indexSet in
                                deleteItems(in: roomName, at: indexSet)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Scope")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddLineItem = true }) {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if isValidating {
                    ProgressView()
                } else {
                    Button(action: validateAllItems) {
                        Image(systemName: "checkmark.shield")
                    }
                    .disabled(estimate.lineItems.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingAddLineItem) {
            AddLineItemSheet(
                rooms: estimate.rooms,
                onSave: { item in
                    store.addLineItem(item, to: estimate.id)
                    showingAddLineItem = false
                },
                onCancel: { showingAddLineItem = false }
            )
        }
    }

    // MARK: - Grouped Line Items

    /// Group line items by room name
    private var groupedLineItems: [String: [ScopeLineItem]] {
        Dictionary(grouping: estimate.lineItems) { item in
            if let roomId = item.roomId,
               let room = estimate.rooms.first(where: { $0.id == roomId }) {
                return room.name
            }
            return "General"
        }
    }

    // MARK: - Validation

    /// Validate all line items against the price list
    private func validateAllItems() {
        guard !estimate.lineItems.isEmpty else { return }

        isValidating = true
        validationError = nil

        // Mark all items as validating
        for item in estimate.lineItems {
            store.setLineItemValidating(item.id, in: estimate.id)
        }

        Task {
            let selectors = estimate.lineItems.map { $0.selector }

            do {
                let response = try await ValidationService.shared.validateSelectors(selectors)

                await MainActor.run {
                    // Update line items with validation results
                    for result in response.results {
                        store.updateLineItemValidation(
                            selector: result.selector,
                            in: estimate.id,
                            isValid: result.isValid,
                            priceInfo: result.priceInfo,
                            suggestions: result.suggestions
                        )
                    }
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    isValidating = false

                    // Reset validation state to pending
                    for item in estimate.lineItems {
                        store.setLineItemPending(item.id, in: estimate.id)
                    }
                }
            }
        }
    }

    // MARK: - Item Actions

    private func replaceLineItem(_ item: ScopeLineItem, with suggestion: SelectorSuggestion) {
        store.replaceLineItemSelector(
            item.id,
            in: estimate.id,
            newSelector: suggestion.selector,
            newCategory: suggestion.category,
            newDescription: suggestion.description,
            newUnit: suggestion.unit,
            newUnitPrice: suggestion.totalRate
        )
    }

    private func deleteItems(in roomName: String, at indexSet: IndexSet) {
        let items = groupedLineItems[roomName] ?? []
        for index in indexSet {
            store.deleteLineItem(items[index].id, from: estimate.id)
        }
    }
}

// MARK: - Scope Header View

/// Header showing validation statistics and total
struct ScopeHeaderView: View {
    let lineItems: [ScopeLineItem]
    let isValidating: Bool

    var validCount: Int {
        lineItems.filter { $0.validationState == .valid }.count
    }

    var invalidCount: Int {
        lineItems.filter { $0.validationState == .invalid }.count
    }

    var pendingCount: Int {
        lineItems.filter { $0.validationState == .pending || $0.validationState == .validating }.count
    }

    var totalAmount: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Stats
            HStack(spacing: 16) {
                StatBadge(
                    icon: "checkmark.circle.fill",
                    value: "\(validCount)",
                    label: "Valid",
                    color: .green
                )

                StatBadge(
                    icon: "exclamationmark.triangle.fill",
                    value: "\(invalidCount)",
                    label: "Invalid",
                    color: .orange
                )

                StatBadge(
                    icon: "questionmark.circle",
                    value: "\(pendingCount)",
                    label: "Pending",
                    color: .gray
                )
            }

            Spacer()

            // Total
            VStack(alignment: .trailing, spacing: 2) {
                Text("Total")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("$\(totalAmount, specifier: "%.2f")")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            // Validating indicator
            if isValidating {
                ProgressView()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Stat Badge

/// Small stat display with icon and value
struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Empty Scope View

/// Placeholder view when no line items exist
struct EmptyScopeView: View {
    let onAddItem: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Line Items")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add scope items to this estimate")
                .foregroundColor(.secondary)

            Button(action: onAddItem) {
                Label("Add Line Item", systemImage: "plus")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview

#if DEBUG
struct ScopeListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            // Preview would need a mock store and estimate
            EmptyScopeView(onAddItem: { })
        }
    }
}
#endif
