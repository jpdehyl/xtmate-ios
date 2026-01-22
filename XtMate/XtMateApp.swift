//
//  XtMateApp.swift
//  XtMate
//
//  Created by Juan Dominguez on 2026-01-13.
//

import SwiftUI

// MARK: - Clerk SDK Integration
// To fully enable Clerk authentication:
// 1. Add the Swift Package: https://github.com/clerk/clerk-ios
// 2. Uncomment the ClerkSDK import below
// 3. Uncomment the Clerk.configure line in init()
// 4. Replace "pk_test_..." with your Clerk publishable key

// import ClerkSDK

@available(iOS 16.0, *)
@main
struct XtMateApp: App {
    init() {
        // Configure Clerk with your publishable key from clerk.com dashboard
        // Clerk.configure(publishableKey: "pk_test_...")
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
