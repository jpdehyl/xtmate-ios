import SwiftUI

// MARK: - Post Scan Quick Actions

/// Appears immediately after room capture to guide next steps
struct PostScanQuickActionsView: View {
    let room: PostScanRoom
    var onTakePhotos: () -> Void
    var onAddDamage: () -> Void
    var onTagMaterials: () -> Void
    var onVoiceNote: () -> Void
    var onSkip: () -> Void
    var onContinue: () -> Void
    
    @State private var selectedActions: Set<QuickAction> = []
    
    enum QuickAction: String, CaseIterable, Identifiable {
        case photos = "Take Photos"
        case damage = "Add Damage"
        case materials = "Tag Materials"
        case voiceNote = "Voice Note"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .photos: return "camera.fill"
            case .damage: return "exclamationmark.triangle.fill"
            case .materials: return "paintpalette.fill"
            case .voiceNote: return "mic.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .photos: return .blue
            case .damage: return .orange
            case .materials: return .purple
            case .voiceNote: return .green
            }
        }
        
        var description: String {
            switch self {
            case .photos: return "Capture room conditions"
            case .damage: return "Mark visible damage"
            case .materials: return "Identify surfaces"
            case .voiceNote: return "Add verbal notes"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Success header
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Success animation
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                    }
                    .padding(.top, AppTheme.Spacing.xxl)
                    
                    // Room info
                    VStack(spacing: AppTheme.Spacing.xs) {
                        Text(room.name)
                            .font(.title.weight(.bold))
                        
                        HStack(spacing: AppTheme.Spacing.md) {
                            Label("\(Int(room.squareFeet)) SF", systemImage: "ruler")
                            Label(room.category, systemImage: categoryIcon(room.category))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppTheme.Spacing.xl)
                .background(AppTheme.Colors.cardBackground)
                
                // Quick Actions Grid
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Next Steps")
                                .font(.headline)
                            
                            Text("Select actions to complete for this room")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.lg)
                        
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: AppTheme.Spacing.md
                        ) {
                            ForEach(QuickAction.allCases) { action in
                                QuickActionButton(
                                    action: action,
                                    isSelected: selectedActions.contains(action),
                                    onTap: {
                                        if selectedActions.contains(action) {
                                            selectedActions.remove(action)
                                        } else {
                                            selectedActions.insert(action)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                    }
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                
                // Bottom actions
                VStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: {
                        executeSelectedActions()
                    }) {
                        HStack {
                            Text(selectedActions.isEmpty ? "Done" : "Continue with \(selectedActions.count) action\(selectedActions.count == 1 ? "" : "s")")
                                .fontWeight(.semibold)
                            if !selectedActions.isEmpty {
                                Image(systemName: "arrow.right")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppTheme.Colors.primary)
                        .foregroundStyle(.white)
                        .continuousCornerRadius(AppTheme.Radius.md)
                    }
                    
                    if !selectedActions.isEmpty {
                        Button(action: onSkip) {
                            Text("Skip for Now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .background(.ultraThinMaterial)
            }
            .background(AppTheme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip All", action: onSkip)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func executeSelectedActions() {
        // Execute actions in logical order
        let orderedActions = [
            QuickAction.photos,
            QuickAction.damage,
            QuickAction.materials,
            QuickAction.voiceNote
        ]
        
        for action in orderedActions {
            if selectedActions.contains(action) {
                switch action {
                case .photos:
                    onTakePhotos()
                case .damage:
                    onAddDamage()
                case .materials:
                    onTagMaterials()
                case .voiceNote:
                    onVoiceNote()
                }
                return // Execute first action and return
            }
        }
        
        // If no actions selected, just continue
        onContinue()
    }
    
    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower.fill"
        case "bedroom": return "bed.double.fill"
        case "living": return "sofa.fill"
        default: return "square.split.bottomrightquarter"
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let action: PostScanQuickActionsView.QuickAction
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Image(systemName: action.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? .white : action.color)
                        .frame(width: 48, height: 48)
                        .background((isSelected ? action.color : action.color.opacity(0.15)))
                        .continuousCornerRadius(AppTheme.Radius.sm)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(action.color)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(action.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
            .background(isSelected ? action.color.opacity(0.1) : AppTheme.Colors.cardBackground)
            .continuousCornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? action.color : Color.clear, lineWidth: 2)
            )
            .appShadow(AppTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post Scan Room

struct PostScanRoom {
    let id: UUID
    let name: String
    let category: String
    let squareFeet: Double
    let lengthFt: Double
    let widthFt: Double
    let heightFt: Double
}

// MARK: - Preview

#Preview("Post Scan Actions") {
    PostScanQuickActionsView(
        room: PostScanRoom(
            id: UUID(),
            name: "Kitchen",
            category: "Kitchen",
            squareFeet: 144,
            lengthFt: 12,
            widthFt: 12,
            heightFt: 8
        ),
        onTakePhotos: {},
        onAddDamage: {},
        onTagMaterials: {},
        onVoiceNote: {},
        onSkip: {},
        onContinue: {}
    )
}
