import SwiftUI

// MARK: - Paul Davis Restoration Theme

/// XtMate theme inspired by Paul Davis Restoration branding
/// Colors, spacing, and design tokens aligned with pauldavis.ca
enum PaulDavisTheme {
    
    // MARK: - Brand Colors
    
    enum Colors {
        // Primary brand colors (from Paul Davis identity)
        static let paulDavisRed = Color(hex: "#E31C23")      // #E31C23 - Paul Davis red
        static let darkNavy = Color(hex: "#1C1C1E")          // #1C1C1E - Paul Davis dark
        static let lightGray = Color(hex: "#F5F1E8")         // #F5F1E8 - Paul Davis cream
        static let charcoal = Color(red: 0.20, green: 0.24, blue: 0.29)          // #333C4A - Dark text
        
        // Primary/Accent
        static let primary = paulDavisRed
        static let primaryDark = Color(red: 0.70, green: 0.10, blue: 0.11)       // Darker red for pressed states
        static let primaryLight = Color(red: 0.95, green: 0.70, blue: 0.70)      // Light red for backgrounds
        
        // Secondary palette
        static let secondary = darkNavy
        static let secondaryLight = Color(red: 0.25, green: 0.35, blue: 0.45)    // Lighter navy
        
        // Semantic colors (system-aware)
        static let background = lightGray
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let cardBackground = Color.white
        
        // Text colors
        static let text = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        static let textOnPrimary = Color.white                                    // Text on red
        static let textOnNavy = Color.white                                       // Text on navy
        
        // Status colors (restoration context)
        static let emergency = Color.orange                                       // Emergency/mitigation
        static let active = Color.blue                                            // Active work
        static let complete = Color.green                                         // Completed
        static let pending = Color.gray                                           // Pending
        
        // Damage type colors
        static let water = Color.blue
        static let fire = paulDavisRed                                           // Use brand red for fire
        static let smoke = Color.gray
        static let mold = Color.green
        static let storm = Color.purple
        static let wind = Color.cyan
        
        // Feedback colors
        static let success = Color(red: 0.13, green: 0.58, blue: 0.30)          // #22954D
        static let warning = Color.orange
        static let error = paulDavisRed
        static let info = Color.blue
        
        // Glass/Material effects (modern iOS design)
        static let glassTint = darkNavy.opacity(0.1)
        static let glassBackground = Color.white.opacity(0.7)
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Heading styles
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title, design: .rounded, weight: .bold)
        static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)
        
        // Body styles
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .default, weight: .regular)
        static let bodyBold = Font.system(.body, design: .default, weight: .semibold)
        static let callout = Font.system(.callout, design: .default, weight: .regular)
        static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)
        static let footnote = Font.system(.footnote, design: .default, weight: .regular)
        static let caption = Font.system(.caption, design: .default, weight: .regular)
        static let caption2 = Font.system(.caption2, design: .default, weight: .regular)
        
        // Specialized styles
        static let button = Font.system(.body, design: .rounded, weight: .semibold)
        static let buttonLarge = Font.system(.title3, design: .rounded, weight: .bold)
        static let badge = Font.system(.caption, design: .rounded, weight: .bold)
        static let stat = Font.system(.title, design: .rounded, weight: .bold)
    }
    
    // MARK: - Spacing (Field-Optimized)
    
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
        
        // Field-specific spacing (extra large touch targets)
        static let touchTarget: CGFloat = 72      // Minimum for gloved hands
        static let touchTargetMin: CGFloat = 56   // Absolute minimum (Apple HIG)
        static let cardPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
    }
    
    // MARK: - Corner Radius
    
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = 9999
        
        // Professional/modern radius
        static let card: CGFloat = 16
        static let button: CGFloat = 12
        static let buttonLarge: CGFloat = 16
    }
    
    // MARK: - Shadows
    
    enum Shadow {
        static let sm = ShadowStyle(
            color: Colors.charcoal.opacity(0.08),
            radius: 2,
            x: 0,
            y: 1
        )
        
        static let md = ShadowStyle(
            color: Colors.charcoal.opacity(0.12),
            radius: 4,
            x: 0,
            y: 2
        )
        
        static let lg = ShadowStyle(
            color: Colors.charcoal.opacity(0.16),
            radius: 8,
            x: 0,
            y: 4
        )
        
        static let xl = ShadowStyle(
            color: Colors.charcoal.opacity(0.20),
            radius: 16,
            x: 0,
            y: 8
        )
        
        // Professional card shadow
        static let card = ShadowStyle(
            color: Colors.charcoal.opacity(0.10),
            radius: 6,
            x: 0,
            y: 3
        )
    }
    
    // MARK: - Icons (SF Symbols)
    
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
        
        // Claims & Properties
        static let claim = "doc.text.fill"
        static let room = "square.split.bottomrightquarter"
        static let scope = "list.bullet.clipboard.fill"
        static let photo = "camera.fill"
        static let scan = "viewfinder"
        static let ai = "sparkles"
        
        // Emergency/Restoration specific
        static let emergency = "bolt.fill"                    // Emergency services
        static let mitigation = "drop.triangle.fill"          // Water mitigation
        static let drying = "wind"                            // Drying equipment
        static let demolition = "hammer.fill"                 // Demo work
        static let reconstruction = "building.2.fill"         // Rebuild
        static let contents = "shippingbox.fill"              // Contents/pack-out
        
        // Damage types
        static let water = "drop.fill"
        static let fire = "flame.fill"
        static let smoke = "smoke.fill"
        static let mold = "allergens"
        static let storm = "cloud.bolt.rain.fill"
        static let wind = "wind"
        
        // Status
        static let pending = "clock"
        static let inProgress = "arrow.triangle.2.circlepath"
        static let submitted = "paperplane.fill"
        static let approved = "checkmark.seal.fill"
        static let completed = "checkmark.circle.fill"
        
        // Actions
        static let call = "phone.fill"
        static let email = "envelope.fill"
        static let map = "map.fill"
        static let sync = "arrow.triangle.2.circlepath"
        static let export = "square.and.arrow.up"
        
        // Paul Davis specific
        static let paulDavisLogo = "p.square.fill"            // Placeholder until custom logo
        static let restoration = "wrench.and.screwdriver.fill"
        static let inspection = "magnifyingglass"
    }
    
    // MARK: - Animations
    
    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let smooth = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let bounce = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply Paul Davis card styling
    func paulDavisCard() -> some View {
        self
            .background(PaulDavisTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.card, style: .continuous))
            .shadow(
                color: PaulDavisTheme.Shadow.card.color,
                radius: PaulDavisTheme.Shadow.card.radius,
                x: PaulDavisTheme.Shadow.card.x,
                y: PaulDavisTheme.Shadow.card.y
            )
    }
    
    /// Apply Paul Davis shadow
    func paulDavisShadow(_ style: ShadowStyle = PaulDavisTheme.Shadow.md) -> some View {
        self.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
    
    /// Apply Paul Davis primary button style
    func paulDavisPrimaryButton() -> some View {
        self
            .font(PaulDavisTheme.Typography.button)
            .foregroundStyle(PaulDavisTheme.Colors.textOnPrimary)
            .padding(.horizontal, PaulDavisTheme.Spacing.xl)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .background(PaulDavisTheme.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous))
            .paulDavisShadow(PaulDavisTheme.Shadow.sm)
    }
    
    /// Apply Paul Davis secondary button style
    func paulDavisSecondaryButton() -> some View {
        self
            .font(PaulDavisTheme.Typography.button)
            .foregroundStyle(PaulDavisTheme.Colors.primary)
            .padding(.horizontal, PaulDavisTheme.Spacing.xl)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .background(PaulDavisTheme.Colors.primaryLight.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous)
                    .strokeBorder(PaulDavisTheme.Colors.primary, lineWidth: 2)
            )
    }
    
    /// Apply glass effect with Paul Davis tint
    /// Note: glassEffect requires iOS 26.0 or later
    @available(iOS 26.0, *)
    func paulDavisGlass() -> some View {
        self.glassEffect(.regular.tint(PaulDavisTheme.Colors.darkNavy))
    }
}

// MARK: - Custom Button Styles

struct PaulDavisPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaulDavisTheme.Typography.button)
            .foregroundStyle(PaulDavisTheme.Colors.textOnPrimary)
            .padding(.horizontal, PaulDavisTheme.Spacing.xl)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .background(configuration.isPressed ? PaulDavisTheme.Colors.primaryDark : PaulDavisTheme.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous))
            .paulDavisShadow(configuration.isPressed ? PaulDavisTheme.Shadow.sm : PaulDavisTheme.Shadow.md)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(PaulDavisTheme.Animation.quick, value: configuration.isPressed)
    }
}

struct PaulDavisSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaulDavisTheme.Typography.button)
            .foregroundStyle(PaulDavisTheme.Colors.primary)
            .padding(.horizontal, PaulDavisTheme.Spacing.xl)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
            .background(configuration.isPressed ? PaulDavisTheme.Colors.primaryLight.opacity(0.3) : PaulDavisTheme.Colors.primaryLight.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.button, style: .continuous)
                    .strokeBorder(PaulDavisTheme.Colors.primary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(PaulDavisTheme.Animation.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PaulDavisPrimaryButtonStyle {
    static var paulDavisPrimary: PaulDavisPrimaryButtonStyle {
        PaulDavisPrimaryButtonStyle()
    }
}

extension ButtonStyle where Self == PaulDavisSecondaryButtonStyle {
    static var paulDavisSecondary: PaulDavisSecondaryButtonStyle {
        PaulDavisSecondaryButtonStyle()
    }
}

// MARK: - Preview

#Preview("Paul Davis Theme Showcase") {
    ScrollView {
        VStack(spacing: PaulDavisTheme.Spacing.xxl) {
            // Brand colors
            VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                Text("Brand Colors")
                    .font(PaulDavisTheme.Typography.title2)
                
                HStack(spacing: PaulDavisTheme.Spacing.md) {
                    ColorSwatch(color: PaulDavisTheme.Colors.paulDavisRed, name: "PD Red")
                    ColorSwatch(color: PaulDavisTheme.Colors.darkNavy, name: "Navy")
                    ColorSwatch(color: PaulDavisTheme.Colors.charcoal, name: "Charcoal")
                }
            }
            
            // Buttons
            VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                Text("Buttons")
                    .font(PaulDavisTheme.Typography.title2)
                
                Button("Primary Button") {}
                    .buttonStyle(.paulDavisPrimary)
                
                Button("Secondary Button") {}
                    .buttonStyle(.paulDavisSecondary)
            }
            
            // Cards
            VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                Text("Cards")
                    .font(PaulDavisTheme.Typography.title2)
                
                VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.sm) {
                    Text("Emergency Response")
                        .font(PaulDavisTheme.Typography.headline)
                    Text("24/7 availability for all your restoration needs")
                        .font(PaulDavisTheme.Typography.body)
                        .foregroundStyle(PaulDavisTheme.Colors.textSecondary)
                }
                .padding(PaulDavisTheme.Spacing.lg)
                .paulDavisCard()
            }
        }
        .padding(PaulDavisTheme.Spacing.xxl)
    }
    .background(PaulDavisTheme.Colors.background)
}

private struct ColorSwatch: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 80, height: 80)
                .paulDavisShadow()
            
            Text(name)
                .font(PaulDavisTheme.Typography.caption)
        }
    }
}
