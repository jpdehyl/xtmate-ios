import SwiftUI

// MARK: - Add Line Item Sheet

/// Sheet for adding a new line item to an estimate
struct AddLineItemSheet: View {
    let rooms: [Room]
    let onSave: (ScopeLineItem) -> Void
    let onCancel: () -> Void

    @State private var category = ""
    @State private var selector = ""
    @State private var description = ""
    @State private var quantity: Double = 1.0
    @State private var unit = "SF"
    @State private var unitPrice: Double = 0.0
    @State private var selectedRoomId: UUID?
    @State private var notes = ""

    @State private var searchText = ""
    @State private var searchResults: [SuggestionInfo] = []
    @State private var isSearching = false
    @State private var showingSearch = false

    var body: some View {
        NavigationStack {
            Form {
                // Price list search section
                Section {
                    Button(action: { showingSearch = true }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(selector.isEmpty ? "Search Price List..." : selector)
                                .foregroundColor(selector.isEmpty ? .secondary : .primary)
                            Spacer()
                            if !selector.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    Text("Item Selection")
                } footer: {
                    Text("Search the price list to auto-fill item details")
                }

                // Manual entry section
                Section("Item Details") {
                    HStack {
                        Text("Category")
                        Spacer()
                        TextField("WTR", text: $category)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Selector")
                        Spacer()
                        TextField("WTR EXTRT", text: $selector)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading) {
                        Text("Description")
                        TextField("Enter description...", text: $description, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                // Quantity section
                Section("Quantity & Pricing") {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("0", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    Picker("Unit", selection: $unit) {
                        ForEach(LineItemUnit.allCases, id: \.rawValue) { u in
                            Text(u.rawValue).tag(u.rawValue)
                        }
                    }

                    HStack {
                        Text("Unit Price")
                        Spacer()
                        Text("$")
                        TextField("0.00", value: $unitPrice, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("$\(quantity * unitPrice, specifier: "%.2f")")
                            .fontWeight(.semibold)
                    }
                }

                // Room assignment
                if !rooms.isEmpty {
                    Section("Room") {
                        Picker("Assign to Room", selection: $selectedRoomId) {
                            Text("None (General)").tag(nil as UUID?)
                            ForEach(rooms) { room in
                                Text(room.name).tag(room.id as UUID?)
                            }
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveItem()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingSearch) {
                PriceListSearchSheet(
                    onSelect: { info in
                        fillFromSearch(info)
                        showingSearch = false
                    },
                    onCancel: { showingSearch = false }
                )
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !selector.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        quantity > 0
    }

    // MARK: - Actions

    private func fillFromSearch(_ info: SuggestionInfo) {
        category = info.category
        selector = info.selector
        description = info.description
        unit = info.unit
        unitPrice = info.totalRate
    }

    private func saveItem() {
        let item = ScopeLineItem(
            category: category.uppercased().trimmingCharacters(in: .whitespaces),
            selector: selector.uppercased().trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            unit: unit,
            unitPrice: unitPrice,
            roomId: selectedRoomId,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        onSave(item)
    }
}

// MARK: - Price List Search Sheet

/// Sheet for searching the price list
struct PriceListSearchSheet: View {
    let onSelect: (SuggestionInfo) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var results: [SuggestionInfo] = []
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search items...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit { performSearch() }

                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                // Error
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }

                // Results
                if results.isEmpty && !isSearching {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("Search the Price List")
                            .font(.headline)
                        Text("Enter a code or description to find items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, id: \.selector) { item in
                        Button(action: { onSelect(item) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.selector)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text(item.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)

                                    Spacer()

                                    Text("$\(item.totalRate, specifier: "%.2f")/\(item.unit)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search Price List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true
        error = nil

        Task {
            do {
                let searchResults = try await ValidationService.shared.search(query: searchText)
                await MainActor.run {
                    results = searchResults
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AddLineItemSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddLineItemSheet(
            rooms: [],
            onSave: { _ in },
            onCancel: { }
        )
    }
}
#endif
