import SwiftUI

@available(iOS 16.0, *)
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.xl) {
            Spacer()

            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(hex: "E31C23"))

            Text("Welcome to XtMate")
                .font(.largeTitle.bold())

            Text("Capture claims in the field and keep everything synced with the web dashboard.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            Button {
                hasSeenOnboarding = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "E31C23"))
                    .foregroundColor(.white)
                    .continuousCornerRadius(PaulDavisTheme.Radius.md)
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.lg)
            .padding(.bottom, PaulDavisTheme.Spacing.xl)
        }
        .background(Color(hex: "F5F1E8").ignoresSafeArea())
    }
}

@available(iOS 16.0, *)
struct HomeDashboardView: View {
    @StateObject private var authService = AuthService.shared

    var body: some View {
        MainTabView()
            .overlay(alignment: .top) {
                if !authService.isSignedIn {
                    NavigationLink(destination: WebConnectionView()) {
                        Label("⚙️ Connect to Web", systemImage: "link.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, PaulDavisTheme.Spacing.md)
                            .padding(.vertical, PaulDavisTheme.Spacing.sm)
                            .background(Color(hex: "E31C23"))
                            .foregroundColor(.white)
                            .continuousCornerRadius(PaulDavisTheme.Radius.md)
                            .padding(.top, PaulDavisTheme.Spacing.sm)
                    }
                }
            }
    }
}

@available(iOS 16.0, *)
struct AppRootView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        NavigationStack {
            if hasSeenOnboarding {
                HomeDashboardView()
            } else {
                OnboardingView()
            }
        }
    }
}
