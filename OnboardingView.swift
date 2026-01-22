import SwiftUI

// MARK: - Onboarding View

/// Welcome carousel for first-time users
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPage = 0
    private let totalPages = 3
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    PaulDavisTheme.Colors.primary.opacity(0.1),
                    PaulDavisTheme.Colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }
                
                // Page content
                TabView(selection: $currentPage) {
                    OnboardingPage(
                        icon: "viewfinder.circle.fill",
                        title: "Scan Rooms with LiDAR",
                        description: "Use your device's LiDAR sensor to capture accurate room dimensions in seconds. No tape measure needed.",
                        accentColor: PaulDavisTheme.Colors.primary
                    )
                    .tag(0)
                    
                    OnboardingPage(
                        icon: "exclamationmark.triangle.fill",
                        title: "Tag Damage & Materials",
                        description: "Mark damage locations, annotate severity, and tag materials for automatic scope generation.",
                        accentColor: PaulDavisTheme.Colors.secondary
                    )
                    .tag(1)
                    
                    OnboardingPage(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Sync to Web Platform",
                        description: "All your data syncs to xtmate for AI-powered scope generation and team collaboration.",
                        accentColor: PaulDavisTheme.Colors.success
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? PaulDavisTheme.Colors.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }
                .padding(.bottom, PaulDavisTheme.Spacing.lg)
                
                // Action buttons
                VStack(spacing: PaulDavisTheme.Spacing.md) {
                    if currentPage == totalPages - 1 {
                        Button(action: completeOnboarding) {
                            HStack {
                                Text("Let's Go")
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paulDavisPrimary)
                    } else {
                        Button(action: nextPage) {
                            HStack {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paulDavisPrimary)
                    }
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.xl)
                .padding(.bottom, PaulDavisTheme.Spacing.xl)
            }
        }
    }
    
    private func nextPage() {
        withAnimation {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Onboarding Page

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.xxl) {
            Spacer()
            
            // Icon with animated gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.2), accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundStyle(accentColor)
            }
            .padding(.bottom, PaulDavisTheme.Spacing.lg)
            
            // Title
            Text(title)
                .font(PaulDavisTheme.Typography.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PaulDavisTheme.Spacing.xl)
            
            // Description
            Text(description)
                .font(PaulDavisTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PaulDavisTheme.Spacing.xxl)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView()
}
