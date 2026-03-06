import SwiftUI

struct ConnectToWebSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService = SyncService.shared

    @State private var serverURL: String = ""
    @State private var apiToken: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    SecureField("Clerk Session Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Save Connection") {
                        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

                        syncService.customServerURL = trimmedURL.isEmpty ? nil : trimmedURL
                        if !trimmedToken.isEmpty {
                            authService.setToken(trimmedToken)
                        }
                        dismiss()
                    }
                    .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Current") {
                    LabeledContent("Server") {
                        Text(syncService.currentServerURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Token") {
                        Text(authService.isSignedIn ? "Configured" : "Not Set")
                            .foregroundStyle(authService.isSignedIn ? .green : .red)
                    }
                }
            }
            .navigationTitle("Connect to Web")
            .onAppear {
                serverURL = syncService.customServerURL ?? ""
                apiToken = authService.sessionToken ?? ""
            }
        }
    }
}
