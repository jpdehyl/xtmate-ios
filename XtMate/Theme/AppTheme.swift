import SwiftUI

// MARK: - App Theme

/// Central design system for XtMate
/// Following Apple Human Interface Guidelines
enum AppTheme {
    // MARK: - Colors

    enum Colors {
        // Semantic colors - automatically adapt to light/dark mode
        static let primary = Color.accentColor
        static let secondary = Color.secondary
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let cardBackground = Color(uiColor: .systemBackground)

        // Text colors
        static let text = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(uiColor: .tertiaryLabel)

        // Assignment type colors
        static let emergency = Color.orange
        static let repairs = Color.blue
        static let contents = Color.purple
        static let fullService = Color.green

        // Status colors
        static let statusPending = Color.gray
        static let statusActive = Color.orange
        static let statusSubmitted = Color.blue
        static let statusApproved = Color.green
        static let statusCompleted = Color.green

        // Feedback colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Damage type colors
        static let water = Color.blue
        static let fire = Color.red
        static let storm = Color.purple
        static let wind = Color.teal
        static let mold = Color.green
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 9999
    }

    // MARK: - Shadows

    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        static let md = ShadowStyle(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        static let lg = ShadowStyle(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Icons

    enum Icons {
        // Navigation
        static let back = "chevron.left"
        static let forward = "chevron.right"
        static let close = "xmark"
        static let menu = "line.3.horizontal"
        static let add = "plus"
        static let edit = "pencil"
        static let delete = "trash"
        static let more = "ellipsis"

        // Claims
        static let claim = "doc.text.fill"
        static let room = "square.split.bottomrightquarter"
        static let scope = "list.bullet.clipboard"
        static let photo = "camera.fill"

        // Assignment types
        static let emergency = "bolt.fill"
        static let repairs = "hammer.fill"
        static let contents = "shippingbox.fill"
        static let fullService = "square.stack.3d.up.fill"

        // Status
        static let pending = "clock"
        static let inProgress = "arrow.triangle.2.circlepath"
        static let submitted = "paperplane.fill"
        static let approved = "checkmark.seal.fill"
        static let completed = "checkmark.circle.fill"

        // Damage types
        static let water = "drop.fill"
        static let fire = "flame.fill"
        static let storm = "cloud.bolt.rain.fill"
        static let wind = "wind"
        static let mold = "allergens"

        // Actions
        static let call = "phone.fill"
        static let email = "envelope.fill"
        static let map = "map.fill"
        static let sync = "arrow.triangle.2.circlepath"
        static let export = "square.and.arrow.up"
        static let scan = "viewfinder"
        static let ai = "sparkles"
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    /// Apply app card styling
    func appCard() -> some View {
        self
            .background(AppTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    /// Apply app shadow
    func appShadow(_ style: ShadowStyle = AppTheme.Shadow.sm) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Continuous corner radius (iOS style)
    func continuousCornerRadius(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Color Extensions

extension Color {
    /// Create color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
