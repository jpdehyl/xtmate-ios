import SwiftUI

// MARK: - Assignment Card

/// Card displaying an assignment (E, R, C) with its status and total
struct AssignmentCard: View {
    let assignment: Assignment
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                // Header with type badge and status
                HStack {
                    // Type badge
                    Text(assignment.type.shortCode)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(assignment.type.color)

                    Spacer()

                    // Status badge
                    StatusBadge(status: assignment.status)
                }

                // Type name
                Text(assignment.type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Total
                Text(formatCurrency(assignment.total))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(AppTheme.Spacing.md)
            .frame(width: 140, height: 130)
            .background(isSelected ? assignment.type.color.opacity(0.1) : AppTheme.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? assignment.type.color : Color.clear, lineWidth: 2)
            )
            .continuousCornerRadius(AppTheme.Radius.md)
            .appShadow(AppTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Status Badge

/// Small badge showing assignment status
struct StatusBadge: View {
    let status: AssignmentStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .continuousCornerRadius(AppTheme.Radius.full)
    }
}

// MARK: - Assignments Row

/// Horizontal row of assignment cards with add button
struct AssignmentsRow: View {
    let assignments: [Assignment]
    @Binding var selectedAssignment: Assignment?
    var onAddAssignment: (() -> Void)?
    var onTapAssignment: ((Assignment) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header
            HStack {
                Label("Assignments", systemImage: AppTheme.Icons.scope)
                    .font(.headline)

                Spacer()

                if let onAdd = onAddAssignment {
                    Button(action: onAdd) {
                        Label("Add", systemImage: AppTheme.Icons.add)
                            .font(.subheadline)
                    }
                }
            }

            // Cards scroll view
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.md) {
                    ForEach(assignments.sorted { $0.order < $1.order }) { assignment in
                        AssignmentCard(
                            assignment: assignment,
                            isSelected: selectedAssignment?.id == assignment.id,
                            onTap: {
                                selectedAssignment = assignment
                                onTapAssignment?(assignment)
                            }
                        )
                    }

                    // Empty state or add button
                    if assignments.isEmpty {
                        AddAssignmentCard(onTap: onAddAssignment)
                    }
                }
                .padding(.horizontal, 1) // For shadow visibility
            }

            // Sequential flow indicator
            if assignments.count > 1 {
                SequentialFlowIndicator(assignments: assignments)
            }
        }
    }
}

// MARK: - Add Assignment Card

/// Placeholder card for adding new assignment
struct AddAssignmentCard: View {
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: AppTheme.Icons.add)
                    .font(.title)
                    .foregroundStyle(.secondary)

                Text("Add Assignment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, height: 130)
            .background(Color(uiColor: .systemGray6))
            .continuousCornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sequential Flow Indicator

/// Shows the workflow order: E → R → C
struct SequentialFlowIndicator: View {
    let assignments: [Assignment]

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(Array(assignments.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { index, assignment in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(assignment.type.shortCode)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(assignment.status == .completed ? .green : .secondary)
            }

            Spacer()

            Text("Sequential workflow")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
    }
}

// MARK: - Assignment Type Picker

/// Sheet for selecting assignment type when adding
struct AssignmentTypePicker: View {
    let jobType: JobType
    var existingTypes: Set<AssignmentType> = []
    var onSelect: (AssignmentType) -> Void

    private var availableTypes: [AssignmentType] {
        let types = jobType == .insurance ? AssignmentType.insuranceTypes : AssignmentType.privateTypes
        return types.filter { !existingTypes.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List(availableTypes) { type in
                Button(action: { onSelect(type) }) {
                    HStack {
                        Image(systemName: type.icon)
                            .foregroundStyle(type.color)
                            .frame(width: 32)

                        VStack(alignment: .leading) {
                            Text(type.fullDisplayName)
                                .font(.headline)
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add Assignment")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func typeDescription(_ type: AssignmentType) -> String {
        switch type {
        case .emergency, .emergencyPrivate:
            return "Water extraction, demolition, drying equipment"
        case .repairs, .repairsPrivate:
            return "Rebuild, restoration, construction work"
        case .contents:
            return "Personal property restoration and replacement"
        case .fullService:
            return "Complete job with emergency, repairs, and contents"
        }
    }
}

// MARK: - Preview

#Preview("Assignment Card") {
    HStack {
        AssignmentCard(
            assignment: Assignment(
                estimateId: UUID(),
                type: .emergency,
                status: .inProgress,
                total: 2500
            ),
            isSelected: false
        )

        AssignmentCard(
            assignment: Assignment(
                estimateId: UUID(),
                type: .repairs,
                status: .pending,
                total: 15000
            ),
            isSelected: true
        )

        AssignmentCard(
            assignment: Assignment(
                estimateId: UUID(),
                type: .contents,
                status: .approved,
                total: 3200
            ),
            isSelected: false
        )
    }
    .padding()
}

#Preview("Assignments Row") {
    AssignmentsRow(
        assignments: [
            Assignment(estimateId: UUID(), type: .emergency, status: .inProgress, total: 2500, order: 0),
            Assignment(estimateId: UUID(), type: .repairs, status: .pending, total: 15000, order: 1),
            Assignment(estimateId: UUID(), type: .contents, status: .pending, total: 3200, order: 2)
        ],
        selectedAssignment: .constant(nil)
    )
    .padding()
}
