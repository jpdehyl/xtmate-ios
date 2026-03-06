import SwiftUI

// MARK: - Quick Damage Entry View

/// Fast damage annotation with large touch targets
struct QuickDamageEntryView: View {
    let roomId: UUID?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedType: DamageType = .water
    @State private var selectedSeverity: DamageSeverity = .moderate
    @State private var selectedSurfaces: Set<SurfaceType> = []
    @State private var notes: String = ""
    @State private var isRecordingVoice = false
    @State private var photos: [UIImage] = []
    
    // Large touch target size (72pt for field use)
    private let buttonSize: CGFloat = 72
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaulDavisTheme.Spacing.xl) {
                    // Damage Type Selection
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                        Text("Damage Type")
                            .font(.headline)
                        
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: PaulDavisTheme.Spacing.md
                        ) {
                            ForEach(DamageType.allCases.filter { $0 != .other }, id: \.self) { type in
                                DamageTypeButton(
                                    type: type,
                                    isSelected: selectedType == type,
                                    size: buttonSize,
                                    onTap: { selectedType = type }
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Severity Selection
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                        Text("Severity")
                            .font(.headline)
                        
                        HStack(spacing: PaulDavisTheme.Spacing.md) {
                            ForEach(DamageSeverity.allCases, id: \.self) { severity in
                                SeverityButton(
                                    severity: severity,
                                    isSelected: selectedSeverity == severity,
                                    onTap: { selectedSeverity = severity }
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Affected Surfaces
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                        Text("Affected Surfaces")
                            .font(.headline)
                        
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: PaulDavisTheme.Spacing.md
                        ) {
                            ForEach([SurfaceType.floor, .wall, .ceiling], id: \.self) { surface in
                                SurfaceButton(
                                    surface: surface,
                                    isSelected: selectedSurfaces.contains(surface),
                                    size: buttonSize,
                                    onTap: {
                                        if selectedSurfaces.contains(surface) {
                                            selectedSurfaces.remove(surface)
                                        } else {
                                            selectedSurfaces.insert(surface)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Photos & Voice Note
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                        Text("Documentation")
                            .font(.headline)
                        
                        HStack(spacing: PaulDavisTheme.Spacing.md) {
                            // Photo button
                            DocumentationButton(
                                icon: PaulDavisTheme.Icons.photo,
                                label: "Add Photos",
                                badge: photos.isEmpty ? nil : "\(photos.count)",
                                color: .blue,
                                onTap: {
                                    // TODO: Show photo picker
                                }
                            )
                            
                            // Voice note button
                            DocumentationButton(
                                icon: "mic.fill",
                                label: isRecordingVoice ? "Recording..." : "Voice Note",
                                badge: nil,
                                color: isRecordingVoice ? .red : .green,
                                onTap: {
                                    isRecordingVoice.toggle()
                                    // TODO: Start/stop voice recording
                                }
                            )
                        }
                    }
                    
                    // Optional text notes
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.sm) {
                        Text("Additional Notes (Optional)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .padding(PaulDavisTheme.Spacing.sm)
                            .background(PaulDavisTheme.Colors.surface)
                            .continuousCornerRadius(PaulDavisTheme.Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(PaulDavisTheme.Spacing.lg)
            }
            .background(PaulDavisTheme.Colors.background)
            .navigationTitle("Add Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDamage()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !selectedSurfaces.isEmpty
    }
    
    private func saveDamage() {
        // TODO: Save damage annotation
        dismiss()
    }
}

// MARK: - Damage Type Button

private struct DamageTypeButton: View {
    let type: DamageType
    let isSelected: Bool
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: PaulDavisTheme.Spacing.sm) {
                Image(systemName: type.icon)
                    .font(.title)
                    .foregroundStyle(isSelected ? .white : type.color)
                
                Text(type.shortName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: size, height: size)
            .background(isSelected ? type.color : type.color.opacity(0.15))
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? type.color : Color.clear, lineWidth: 2)
            )
            .appShadow(PaulDavisTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Severity Button

private struct SeverityButton: View {
    let severity: DamageSeverity
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: PaulDavisTheme.Spacing.xs) {
                Circle()
                    .fill(isSelected ? severity.color : severity.color.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(severity.color, lineWidth: isSelected ? 3 : 1)
                    )
                
                Text(severity.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .background(isSelected ? severity.color.opacity(0.1) : PaulDavisTheme.Colors.cardBackground)
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? severity.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Surface Button

private struct SurfaceButton: View {
    let surface: SurfaceType
    let isSelected: Bool
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: PaulDavisTheme.Spacing.sm) {
                Image(systemName: surface.icon)
                    .font(.title)
                    .foregroundStyle(isSelected ? .white : PaulDavisTheme.Colors.primary)
                
                Text(surface.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: size, height: size)
            .background(isSelected ? PaulDavisTheme.Colors.primary : PaulDavisTheme.Colors.primary.opacity(0.15))
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? PaulDavisTheme.Colors.primary : Color.clear, lineWidth: 2)
            )
            .appShadow(PaulDavisTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Documentation Button

private struct DocumentationButton: View {
    let icon: String
    let label: String
    let badge: String?
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title2)
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .continuousCornerRadius(PaulDavisTheme.Radius.full)
                            .offset(x: 8, y: -8)
                    }
                }
                
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .foregroundStyle(.white)
            .background(color)
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
            .appShadow(PaulDavisTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
// Note: DamageSeverity is defined in ContentView.swift

#Preview("Quick Damage Entry") {
    QuickDamageEntryView(roomId: UUID())
}
