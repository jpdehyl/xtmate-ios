import SwiftUI

// MARK: - Material Tagging View

/// Quick material tagging with smart defaults
struct MaterialTaggingView: View {
    let roomCategory: String
    var onComplete: (MaterialSelection) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFloor: String?
    @State private var selectedWall: String?
    @State private var selectedCeiling: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xxl) {
                    // Header
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                        
                        Text("Tag Materials")
                            .font(.title2.weight(.bold))
                        
                        Text("Select materials for each surface")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, AppTheme.Spacing.lg)
                    
                    // Floor Material
                    MaterialTaggingSection(
                        title: "Floor Material",
                        icon: "square.fill",
                        selectedMaterial: $selectedFloor,
                        materials: floorMaterials,
                        suggestedMaterials: suggestedFloorMaterials
                    )
                    
                    // Wall Finish
                    MaterialTaggingSection(
                        title: "Wall Finish",
                        icon: "rectangle.portrait.fill",
                        selectedMaterial: $selectedWall,
                        materials: wallMaterials,
                        suggestedMaterials: suggestedWallMaterials
                    )
                    
                    // Ceiling Material
                    MaterialTaggingSection(
                        title: "Ceiling Finish",
                        icon: "rectangle.fill",
                        selectedMaterial: $selectedCeiling,
                        materials: ceilingMaterials,
                        suggestedMaterials: suggestedCeilingMaterials
                    )
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("Materials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMaterials()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Material Lists
    
    private var floorMaterials: [String] {
        ["Tile", "LVP", "Hardwood", "Carpet", "Laminate", "Vinyl Sheet", "Concrete", "Other"]
    }
    
    private var wallMaterials: [String] {
        ["Painted Drywall", "Tile", "Wallpaper", "Wood Paneling", "Stone", "Brick", "Other"]
    }
    
    private var ceilingMaterials: [String] {
        ["Smooth", "Popcorn", "Orange Peel", "Knockdown", "Textured", "Drop Ceiling", "Other"]
    }
    
    // MARK: - Smart Suggestions
    
    private var suggestedFloorMaterials: [String] {
        switch roomCategory.lowercased() {
        case "kitchen":
            return ["Tile", "LVP", "Hardwood"]
        case "bathroom":
            return ["Tile", "LVP", "Vinyl Sheet"]
        case "bedroom", "living", "livingroom", "dining", "diningroom":
            return ["Carpet", "Hardwood", "Laminate"]
        case "basement":
            return ["Concrete", "Carpet", "LVP"]
        case "garage":
            return ["Concrete"]
        default:
            return ["LVP", "Carpet", "Tile"]
        }
    }
    
    private var suggestedWallMaterials: [String] {
        switch roomCategory.lowercased() {
        case "kitchen":
            return ["Painted Drywall", "Tile"]
        case "bathroom":
            return ["Tile", "Painted Drywall"]
        case "basement":
            return ["Painted Drywall", "Concrete"]
        default:
            return ["Painted Drywall"]
        }
    }
    
    private var suggestedCeilingMaterials: [String] {
        switch roomCategory.lowercased() {
        case "basement":
            return ["Drop Ceiling", "Smooth"]
        default:
            return ["Smooth", "Popcorn", "Orange Peel"]
        }
    }
    
    // MARK: - Actions
    
    private func saveMaterials() {
        let selection = MaterialSelection(
            floor: selectedFloor,
            wall: selectedWall,
            ceiling: selectedCeiling
        )
        onComplete(selection)
        dismiss()
    }
}

// MARK: - Material Tagging Section

private struct MaterialTaggingSection: View {
    let title: String
    let icon: String
    @Binding var selectedMaterial: String?
    let materials: [String]
    let suggestedMaterials: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Section header
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
            }
            
            // Suggested materials (if any)
            if !suggestedMaterials.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Suggested")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(suggestedMaterials, id: \.self) { material in
                                MaterialChip(
                                    material: material,
                                    isSelected: selectedMaterial == material,
                                    isSuggested: true,
                                    onTap: { selectedMaterial = material }
                                )
                            }
                        }
                    }
                }
            }
            
            // All materials grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppTheme.Spacing.sm
            ) {
                ForEach(materials, id: \.self) { material in
                    MaterialCard(
                        material: material,
                        isSelected: selectedMaterial == material,
                        onTap: { selectedMaterial = material }
                    )
                }
            }
        }
    }
}

// MARK: - Material Chip (Suggested)

private struct MaterialChip: View {
    let material: String
    let isSelected: Bool
    let isSuggested: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isSuggested {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
                Text(material)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? Color.purple : Color.purple.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .purple)
            .continuousCornerRadius(AppTheme.Radius.full)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Material Card

private struct MaterialCard: View {
    let material: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(material)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(height: 56)
            .background(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.cardBackground)
            .continuousCornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.Colors.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Material Selection

struct MaterialSelection {
    let floor: String?
    let wall: String?
    let ceiling: String?
}

// MARK: - Preview

#Preview("Material Tagging - Kitchen") {
    MaterialTaggingView(
        roomCategory: "Kitchen",
        onComplete: { _ in }
    )
}

#Preview("Material Tagging - Bathroom") {
    MaterialTaggingView(
        roomCategory: "Bathroom",
        onComplete: { _ in }
    )
}
