import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Main Tab View

/// Root view that provides tab-based navigation between Jobs and My Work
/// This enables field staff to access their work orders while maintaining
/// the existing estimate management functionality
@available(iOS 16.0, *)
struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var authService = AuthService.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Jobs tab - existing estimate management
            ContentView()
                .tabItem {
                    Label("Jobs", systemImage: "briefcase.fill")
                }
                .tag(0)

            // My Work tab - field staff work orders
            MyWorkView()
                .tabItem {
                    Label("My Work", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(1)

            // Settings tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .tint(.accentColor)
    }
}

// MARK: - Settings View

/// Basic settings view for auth and app configuration
@available(iOS 16.0, *)
struct SettingsView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showingTokenSheet = false
    @State private var showingQRScanner = false
    @State private var tokenInput = ""
    @State private var showingSuccessAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Account") {
                    if authService.isSignedIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Signed In")
                            Spacer()
                            if let userId = authService.userId {
                                Text(String(userId.prefix(8)) + "...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button("Sign Out", role: .destructive) {
                            authService.signOut()
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not Signed In")
                        }

                        // Primary: QR Code scan
                        Button {
                            showingQRScanner = true
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Scan QR Code")
                            }
                        }

                        // Secondary: Manual token entry
                        Button("Enter Token Manually") {
                            showingTokenSheet = true
                        }
                        .foregroundColor(.secondary)
                    }
                }



                Section("Web Sync") {
                    NavigationLink {
                        WebConnectionView()
                    } label: {
                        Label("Server URL + API Token", systemImage: "link")
                    }

                    if !authService.isSignedIn {
                        Label("⚙️ Connect to Web to enable sync", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                // App Info section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2025.01")
                            .foregroundColor(.secondary)
                    }
                }

                // Developer section (debug only)
                #if DEBUG
                Section("Developer") {
                    NavigationLink("API Configuration") {
                        APIConfigView()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingTokenSheet) {
                TokenInputSheet(
                    tokenInput: $tokenInput,
                    onSave: {
                        authService.setToken(tokenInput)
                        showingTokenSheet = false
                        showingSuccessAlert = true
                    },
                    onCancel: {
                        showingTokenSheet = false
                    }
                )
            }
            .sheet(isPresented: $showingQRScanner) {
                AuthQRCodeScannerView { scannedToken in
                    authService.setToken(scannedToken)
                    showingQRScanner = false
                    showingSuccessAlert = true
                }
            }
            .alert("Connected!", isPresented: $showingSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your account is now connected. You can sync estimates with the web app.")
            }
        }
    }
}

// MARK: - Token Input Sheet

struct TokenInputSheet: View {
    @Binding var tokenInput: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.lg) {
                Text("Enter your authentication token from the web app.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Auth Token", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, AppTheme.Spacing.xl)
            .navigationTitle("Auth Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: onSave)
                        .disabled(tokenInput.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}



@available(iOS 16.0, *)
struct WebConnectionView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService = SyncService.shared
    @State private var token = ""
    @State private var serverURL = ""

    var body: some View {
        Form {
            Section("Server") {
                TextField("https://xtmate-v3.vercel.app/api", text: $serverURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Use Production") {
                    serverURL = "https://xtmate-v3.vercel.app/api"
                }
            }

            Section("API Token") {
                SecureField("Clerk session token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Paste the session token from the web app. It will be stored in Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Save Connection") {
                    syncService.customServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    authService.setToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if authService.isSignedIn {
                    Button("Disconnect", role: .destructive) {
                        authService.signOut()
                    }
                }
            }
        }
        .navigationTitle("Connect to Web")
        .onAppear {
            token = authService.sessionToken ?? ""
            serverURL = syncService.currentServerURL
        }
    }
}

// MARK: - API Config View (Debug)

#if DEBUG
@available(iOS 16.0, *)
struct APIConfigView: View {
    @StateObject private var syncService = SyncService.shared
    @State private var serverURLInput = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var showingResetConfirmation = false

    enum ConnectionStatus {
        case unknown, testing, success, failed(String)

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .testing: return .orange
            case .success: return .green
            case .failed: return .red
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "circle.dashed"
            case .testing: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        List {
            // Current Configuration
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Server URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(syncService.currentServerURL)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Connection Status")
                    Spacer()
                    Image(systemName: connectionStatus.icon)
                        .foregroundColor(connectionStatus.color)
                    if case .failed(let error) = connectionStatus {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Current Configuration")
            } footer: {
                if SyncService.isPhysicalDevice {
                    Text("Running on physical device. localhost won't work - enter your Mac's local IP address.")
                        .foregroundColor(.orange)
                }
            }

            // Set Custom URL
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("http://192.168.1.XXX:3000/api", text: $serverURLInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text("Enter your Mac's local IP address. Find it with: ifconfig | grep 'inet 192'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    saveAndTestConnection()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Save & Test Connection")
                    }
                }
                .disabled(serverURLInput.isEmpty || isTestingConnection)

                if syncService.customServerURL != nil {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default")
                        }
                    }
                }
            } header: {
                Text("Custom Server URL")
            }

            // Quick Actions
            Section("Quick Actions") {
                Button {
                    testCurrentConnection()
                } label: {
                    HStack {
                        Image(systemName: "network")
                        Text("Test Current Connection")
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTestingConnection)
            }

            // Help
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("To find your Mac's IP address:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Open Terminal on your Mac")
                        Text("2. Run: ipconfig getifaddr en0")
                        Text("3. Copy the IP (e.g., 192.168.1.42)")
                        Text("4. Enter: http://[IP]:3000/api")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text("Make sure your Mac and iPhone are on the same WiFi network.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle("API Configuration")
        .onAppear {
            serverURLInput = syncService.customServerURL ?? ""
        }
        .confirmationDialog("Reset to Default?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                syncService.customServerURL = nil
                serverURLInput = ""
                connectionStatus = .unknown
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset the server URL to the default value.")
        }
    }

    private func saveAndTestConnection() {
        guard !serverURLInput.isEmpty else { return }

        // Ensure the URL ends properly
        var url = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.lowercased().hasPrefix("http") {
            url = "http://" + url
        }
        if !url.hasSuffix("/api") && !url.hasSuffix("/api/") {
            if url.hasSuffix("/") {
                url += "api"
            } else {
                url += "/api"
            }
        }

        syncService.customServerURL = url
        serverURLInput = url
        testCurrentConnection()
    }

    private func testCurrentConnection() {
        isTestingConnection = true
        connectionStatus = .testing

        Task {
            do {
                // Try to fetch the estimates list as a connection test
                _ = try await syncService.fetchServerEstimatesList()
                await MainActor.run {
                    connectionStatus = .success
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }
}
#endif

// MARK: - Auth Token QR Scanner View

struct AuthQRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> AuthQRScannerViewController {
        let controller = AuthQRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: AuthQRScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, dismiss: dismiss)
    }

    class Coordinator: NSObject, AuthQRScannerDelegate {
        let onCodeScanned: (String) -> Void
        let dismiss: DismissAction

        init(onCodeScanned: @escaping (String) -> Void, dismiss: DismissAction) {
            self.onCodeScanned = onCodeScanned
            self.dismiss = dismiss
        }

        func didScanCode(_ code: String) {
            onCodeScanned(code)
        }

        func didCancel() {
            dismiss()
        }
    }
}

// MARK: - Auth QR Scanner View Controller

protocol AuthQRScannerDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didCancel()
}

class AuthQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: AuthQRScannerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showCameraUnavailableAlert()
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            showCameraUnavailableAlert()
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        self.previewLayer = previewLayer
        self.captureSession = session
    }

    private func setupUI() {
        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Instructions label
        let instructionsLabel = UILabel()
        instructionsLabel.text = "Point camera at QR code\nfrom XtMate web app Settings"
        instructionsLabel.textColor = .white
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 2
        instructionsLabel.font = .systemFont(ofSize: 16)
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionsLabel)

        // Scan frame overlay
        let scanFrame = UIView()
        scanFrame.layer.borderColor = UIColor.white.cgColor
        scanFrame.layer.borderWidth = 2
        scanFrame.layer.cornerRadius = 12
        scanFrame.backgroundColor = .clear
        scanFrame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanFrame)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            instructionsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            instructionsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scanFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanFrame.widthAnchor.constraint(equalToConstant: 250),
            scanFrame.heightAnchor.constraint(equalToConstant: 250)
        ])
    }

    @objc private func cancelTapped() {
        delegate?.didCancel()
    }

    private func showCameraUnavailableAlert() {
        let alert = UIAlertController(
            title: "Camera Unavailable",
            message: "Camera access is required to scan QR codes. Please enable camera access in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.delegate?.didCancel()
        })
        present(alert, animated: true)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned else { return }

        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {

            // Check if it looks like a JWT token (starts with ey)
            if stringValue.hasPrefix("ey") && stringValue.contains(".") {
                hasScanned = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                delegate?.didScanCode(stringValue)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    MainTabView()
}
#endif
