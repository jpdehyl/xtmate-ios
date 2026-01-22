import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Link Estimate Sheet

/// Sheet for linking to an existing web estimate using a job number or QR scan
/// Job number format: YY-####-X (e.g., "26-1234-E")
/// Where: YY = year, #### = 4-digit claim number, X = assignment type (E/A/R/P/C/Z)
struct LinkEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var estimateStore: EstimateStore
    @StateObject private var syncService = SyncService.shared

    @State private var jobNumber: String = ""
    @State private var isLinking: Bool = false
    @State private var errorMessage: String?
    @State private var showScanner: Bool = false
    @State private var linkedEstimateName: String?

    var onLinked: ((Estimate) -> Void)?

    // Job number regex pattern: YY-####-X (exactly 4-digit claim)
    private let jobNumberPattern = #"^\d{2}-\d{4}-[EARPCZX]$"#

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Link Web Estimate")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enter the job number from the web app\nor scan the QR code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Job Number Input
                VStack(spacing: 12) {
                    TextField("26-1234-E", text: $jobNumber)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isValidJobNumber ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                        .onChange(of: jobNumber) { _, newValue in
                            // Format as user types: allow digits, hyphens, and assignment letters
                            let filtered = newValue
                                .uppercased()
                                .filter { $0.isNumber || $0 == "-" || "EARPCZX".contains($0) }
                            if filtered != newValue {
                                jobNumber = filtered
                            }
                        }

                    Text("Format: YY-Claim#-Type")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("E=Emergency, R=Repairs, P=Private, C=Contents")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Success message
                if let name = linkedEstimateName {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Linked: \(name)")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    // Link button
                    Button {
                        linkEstimate()
                    } label: {
                        HStack {
                            if isLinking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                            }
                            Text(isLinking ? "Linking..." : "Link Estimate")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canLink ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canLink || isLinking)

                    // QR Scanner button
                    Button {
                        showScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                LinkQRScannerView { code in
                    handleScannedCode(code)
                }
            }
        }
    }

    private var canLink: Bool {
        isValidJobNumber
    }

    private var isValidJobNumber: Bool {
        let trimmed = jobNumber.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: jobNumberPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private func linkEstimate() {
        guard canLink else { return }

        isLinking = true
        errorMessage = nil
        linkedEstimateName = nil

        Task {
            do {
                let downloaded = try await syncService.linkEstimateByCode(jobNumber)

                // Convert to local estimate
                if let estimate = convertToLocalEstimate(downloaded) {
                    // Check if already exists locally
                    if let existingIndex = estimateStore.estimates.firstIndex(where: { $0.id == estimate.id }) {
                        // Update existing
                        estimateStore.estimates[existingIndex] = estimate
                    } else {
                        // Add new
                        estimateStore.addEstimate(estimate)
                    }

                    await MainActor.run {
                        linkedEstimateName = estimate.name
                        onLinked?(estimate)

                        // Auto-dismiss after success
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to process estimate data"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isLinking = false
            }
        }
    }

    private func handleScannedCode(_ url: String) {
        showScanner = false

        // Extract job number from URL: xtmate://link/26-1234-E
        if let code = url.components(separatedBy: "/").last {
            let trimmedCode = code.trimmingCharacters(in: .whitespaces).uppercased()
            jobNumber = trimmedCode

            // Validate and auto-link if valid
            if isValidJobNumber {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    linkEstimate()
                }
            } else {
                errorMessage = "Invalid job number format. Expected: YY-####-X"
            }
        } else {
            errorMessage = "Invalid QR code"
        }
    }

    /// Convert downloaded DTO to local Estimate model
    private func convertToLocalEstimate(_ downloaded: DownloadedEstimate) -> Estimate? {
        guard let id = UUID(uuidString: downloaded.estimate.id) else { return nil }

        // Convert rooms
        let rooms: [Room] = downloaded.rooms.compactMap { roomDTO in
            guard let roomId = UUID(uuidString: roomDTO.id) else { return nil }

            let annotations: [DamageAnnotation] = (roomDTO.annotations ?? []).compactMap { annDTO in
                guard let annId = UUID(uuidString: annDTO.id) else { return nil }
                return DamageAnnotation(
                    id: annId,
                    position: CGPoint(x: annDTO.positionX ?? 0.5, y: annDTO.positionY ?? 0.5),
                    damageType: DamageType(rawValue: annDTO.damageType) ?? .water,
                    severity: DamageSeverity(rawValue: annDTO.severity) ?? .moderate,
                    affectedSurfaces: Set(annDTO.affectedSurfaces.compactMap { AffectedSurface(rawValue: $0) }),
                    affectedHeightIn: annDTO.affectedHeightIn,
                    notes: annDTO.notes ?? ""
                )
            }

            return Room(
                id: roomId,
                name: roomDTO.name,
                category: RoomCategory(rawValue: roomDTO.category ?? "Other") ?? .other,
                floor: FloorLevel(rawValue: roomDTO.floor ?? "1") ?? .first,
                floorMaterial: roomDTO.floorMaterial.flatMap { FloorMaterial(rawValue: $0) },
                wallMaterial: roomDTO.wallMaterial.flatMap { WallMaterial(rawValue: $0) },
                ceilingMaterial: roomDTO.ceilingMaterial.flatMap { CeilingMaterial(rawValue: $0) },
                lengthIn: roomDTO.lengthIn ?? 0,
                widthIn: roomDTO.widthIn ?? 0,
                heightIn: roomDTO.heightIn ?? 0,
                annotations: annotations
            )
        }

        // Convert line items
        let lineItems: [ScopeLineItem] = downloaded.lineItems.compactMap { itemDTO in
            guard let itemId = UUID(uuidString: itemDTO.id) else { return nil }
            return ScopeLineItem(
                id: itemId,
                category: itemDTO.category,
                selector: itemDTO.selector,
                description: itemDTO.description,
                quantity: itemDTO.quantity,
                unit: itemDTO.unit,
                unitPrice: itemDTO.unitPrice ?? 0,
                roomId: itemDTO.roomId.flatMap { UUID(uuidString: $0) },
                annotationId: itemDTO.annotationId.flatMap { UUID(uuidString: $0) },
                source: LineItemSource(rawValue: itemDTO.source ?? "manual") ?? .manual,
                notes: itemDTO.notes ?? "",
                order: itemDTO.order ?? 0
            )
        }

        return Estimate(
            id: id,
            name: downloaded.estimate.name,
            claimNumber: downloaded.estimate.claimNumber,
            policyNumber: downloaded.estimate.policyNumber,
            insuredName: downloaded.estimate.insuredName,
            propertyAddress: downloaded.estimate.propertyAddress,
            causeOfLoss: downloaded.estimate.causeOfLoss ?? "Water",
            status: EstimateStatus(rawValue: downloaded.estimate.status ?? "Draft") ?? .draft,
            rooms: rooms,
            lineItems: lineItems
        )
    }
}

// MARK: - Link QR Scanner View

struct LinkQRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> LinkQRScannerViewController {
        let controller = LinkQRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: LinkQRScannerViewController, context: Context) {}
}

class LinkQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    private var overlayView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update preview layer frame to match view bounds
        previewLayer?.frame = view.bounds

        // Remove and recreate overlay to match new bounds
        overlayView?.removeFromSuperview()
        addScanOverlay()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              let captureSession = captureSession,
              captureSession.canAddInput(videoInput) else {
            showError()
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            showError()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        // Add scan frame overlay
        addScanOverlay()
    }

    private func addScanOverlay() {
        let overlayView = UIView(frame: view.bounds)
        self.overlayView = overlayView
        overlayView.backgroundColor = .clear

        // Add semi-transparent overlay
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: view.bounds)
        let scanRect = CGRect(
            x: (view.bounds.width - 250) / 2,
            y: (view.bounds.height - 250) / 2,
            width: 250,
            height: 250
        )
        path.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 12).reversing())
        maskLayer.path = path.cgPath
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor

        overlayView.layer.addSublayer(maskLayer)

        // Add corner guides
        let cornerColor = UIColor.white
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4

        let corners: [(CGPoint, [CGFloat])] = [
            (CGPoint(x: scanRect.minX, y: scanRect.minY), [0, 1, 1, 0]),
            (CGPoint(x: scanRect.maxX, y: scanRect.minY), [-1, 0, 0, 1]),
            (CGPoint(x: scanRect.minX, y: scanRect.maxY), [0, -1, 1, 0]),
            (CGPoint(x: scanRect.maxX, y: scanRect.maxY), [-1, 0, 0, -1])
        ]

        for (point, dirs) in corners {
            let hLine = CALayer()
            hLine.backgroundColor = cornerColor.cgColor
            hLine.frame = CGRect(
                x: point.x + (dirs[0] * cornerLength),
                y: point.y - cornerWidth / 2 + (dirs[1] * cornerWidth / 2),
                width: cornerLength,
                height: cornerWidth
            )

            let vLine = CALayer()
            vLine.backgroundColor = cornerColor.cgColor
            vLine.frame = CGRect(
                x: point.x - cornerWidth / 2 + (dirs[2] * cornerWidth / 2),
                y: point.y + (dirs[3] * cornerLength),
                width: cornerWidth,
                height: cornerLength
            )

            overlayView.layer.addSublayer(hLine)
            overlayView.layer.addSublayer(vLine)
        }

        // Add instruction label
        let label = UILabel()
        label.text = "Point camera at QR code"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.frame = CGRect(x: 0, y: scanRect.maxY + 30, width: view.bounds.width, height: 30)
        overlayView.addSubview(label)

        view.addSubview(overlayView)
    }

    private func showError() {
        let label = UILabel()
        label.text = "Camera access required"
        label.textColor = .white
        label.textAlignment = .center
        label.frame = view.bounds
        view.addSubview(label)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }

        // Vibrate on successful scan
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        captureSession?.stopRunning()
        onCodeScanned?(stringValue)
        dismiss(animated: true)
    }
}

// MARK: - Preview

#Preview {
    LinkEstimateSheet()
        .environmentObject(EstimateStore())
}
