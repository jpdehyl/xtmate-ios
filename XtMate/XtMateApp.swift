//
//  XtMateApp.swift
//  XtMate
//
//  Created by Juan Dominguez on 2026-01-13.
//

import SwiftUI

@available(iOS 16.0, *)
@main
struct XtMateApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

@available(iOS 16.0, *)
private struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            HomeDashboardView()
        } else {
            OnboardingView()
        }
    }
}
