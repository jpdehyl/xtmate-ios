import SwiftUI
import RoomPlan
import simd
import Combine
import UIKit


// MARK: - CGPoint already conforms to Codable in CoreGraphics

// MARK: - Identifiable Wrapper for CapturedRoom
@available(iOS 16.0, *)
struct IdentifiableCapturedRoom: Identifiable {
    let id = UUID()
    let room: CapturedRoom
}

// MARK: - Main App View
@available(iOS 16.0, *)
struct ContentView: View {
    @StateObject private var store = EstimateStore()
    @StateObject private var syncService = SyncService.shared
    @State private var isCapturing = false
    @State private var showingNewEstimate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var capturedRoomForReview: IdentifiableCapturedRoom?
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""

    // ESX Export states
    @State private var showingESXShareSheet = false
    @State private var esxFileURL: URL?
    @State private var isExportingESX = false
    @State private var esxExportError: String?
    @State private var showingESXError = false

    // P3-RC-002: Room boundary detection states
    @State private var analysisResult: RoomBoundaryAnalysisResult?
    @State private var showingProposedRooms = false
    @State private var isAnalyzingRooms = false
    @State private var capturedRoomForAnalysis: CapturedRoom?

    // Room boundary analyzer instance
    private let roomBoundaryAnalyzer = RoomBoundaryAnalyzer()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - P3B-4: Job Queue with grouping
            JobQueueView(store: store, showingNewEstimate: $showingNewEstimate)
                .navigationTitle("XtMate")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        SyncButton(store: store, syncService: syncService, showingSyncAlert: $showingSyncAlert, syncAlertMessage: $syncAlertMessage)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingNewEstimate = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
        } detail: {
            // Detail - Estimate or Empty State
            if let estimate = store.currentEstimate {
                EstimateDetailView(estimate: estimate, store: store, isCapturing: $isCapturing)
                    .navigationTitle(estimate.name)
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { isCapturing = true }) {
                                Label("Capture Room", systemImage: "plus.viewfinder")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                // ESX Export
                                Button(action: { exportToESX(estimate) }) {
                                    Label("Export to Xactimate (ESX)", systemImage: "square.and.arrow.up")
                                }
                                .disabled(estimate.rooms.isEmpty || isExportingESX)

                                Divider()

                                Button(role: .destructive, action: {
                                    store.showingDeleteConfirmation = true
                                }) {
                                    Label("Delete Claim", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
            } else {
                EmptyDetailView()
            }
        }
        .sheet(isPresented: $showingNewEstimate) {
            NewEstimateSheet(store: store, isPresented: $showingNewEstimate)
        }
        .fullScreenCover(isPresented: $isCapturing) {
            RoomCaptureViewRepresentable(
                isPresented: $isCapturing,
                onRoomCaptured: { room in
                    print("📍 Room captured, starting boundary analysis...")
                    capturedRoomForAnalysis = room
                    isAnalyzingRooms = true

                    // Run boundary analysis in background
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = roomBoundaryAnalyzer.analyze(room)

                        DispatchQueue.main.async {
                            isAnalyzingRooms = false
                            analysisResult = result

                            // If multiple rooms detected with good confidence, show proposed rooms view
                            if result.wasSuccessful && result.proposedRooms.count > 1 && result.overallConfidence >= 0.5 {
                                print("📍 Multiple rooms detected (\(result.proposedRooms.count)), showing review...")
                                showingProposedRooms = true
                            } else {
                                // Single room or low confidence - use traditional review
                                print("📍 Single room detected or low confidence, showing standard review...")
                                capturedRoomForReview = IdentifiableCapturedRoom(room: room)
                            }
                        }
                    }
                }
            )
            .ignoresSafeArea()
        }
        // P3-RC-002: Show proposed rooms review when multiple rooms detected
        .fullScreenCover(isPresented: $showingProposedRooms) {
            if let result = analysisResult, let capturedRoom = capturedRoomForAnalysis {
                ProposedRoomsReviewView(
                    capturedRoom: capturedRoom,
                    analysisResult: result,
                    onSaveRooms: { rooms in
                        // Save multiple rooms
                        for room in rooms {
                            store.addRoomDirect(room)
                        }
                        showingProposedRooms = false
                        analysisResult = nil
                        capturedRoomForAnalysis = nil
                    },
                    onSaveSingleRoom: { room in
                        store.addRoomDirect(room)
                        showingProposedRooms = false
                        analysisResult = nil
                        capturedRoomForAnalysis = nil
                    },
                    onCancel: {
                        showingProposedRooms = false
                        analysisResult = nil
                        capturedRoomForAnalysis = nil
                    }
                )
            }
        }
        // Standard single room review
        .fullScreenCover(item: $capturedRoomForReview) { wrapper in
            RoomReviewView(
                capturedRoom: wrapper.room,
                onSave: { savedRoom in
                    store.addRoomDirect(savedRoom)
                    capturedRoomForReview = nil
                    capturedRoomForAnalysis = nil
                },
                onCancel: {
                    capturedRoomForReview = nil
                    capturedRoomForAnalysis = nil
                }
            )
        }
        // Show loading overlay during analysis
        .overlay {
            if isAnalyzingRooms {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Detecting Rooms...")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Analyzing boundaries and objects")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(Color(.systemGray5).opacity(0.9))
                    .cornerRadius(16)
                }
            }
        }
        .alert("Delete Claim", isPresented: $store.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deleteCurrentEstimate()
            }
        } message: {
            Text("Are you sure you want to delete this claim? This action cannot be undone.")
        }
        .onAppear {
            // Load mock data in simulator for testing
            #if targetEnvironment(simulator)
            store.loadMockData()
            #endif
        }
        .alert("Sync", isPresented: $showingSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
        }
        // ESX Export share sheet
        .sheet(isPresented: $showingESXShareSheet) {
            if let url = esxFileURL {
                ESXShareSheet(url: url)
            }
        }
        .alert("Export Error", isPresented: $showingESXError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(esxExportError ?? "Unknown error occurred during export.")
        }
        // ESX Export overlay
        .overlay {
            if isExportingESX {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Exporting to ESX...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(.systemGray5).opacity(0.9))
                    .cornerRadius(16)
                }
            }
        }
    }

    // MARK: - ESX Export

    private func exportToESX(_ estimate: Estimate) {
        guard !estimate.rooms.isEmpty else { return }

        isExportingESX = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try ESXExportService.shared.exportToESX(estimate: estimate)

                DispatchQueue.main.async {
                    isExportingESX = false
                    esxFileURL = url
                    showingESXShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    isExportingESX = false
                    esxExportError = error.localizedDescription
                    showingESXError = true
                }
            }
        }
    }
}

// MARK: - ESX Share Sheet

struct ESXShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sync Button
struct SyncButton: View {
    @ObservedObject var store: EstimateStore
    @ObservedObject var syncService: SyncService
    @Binding var showingSyncAlert: Bool
    @Binding var syncAlertMessage: String
    @State private var showingPullFromWeb = false

    var body: some View {
        Menu {
            // Primary action: Smart bidirectional sync
            Button(action: {
                Task { await performSmartSync() }
            }) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud")
            }

            Divider()

            // Link specific estimate from web using job number
            Button(action: {
                showingPullFromWeb = true
            }) {
                Label("Link from Web", systemImage: "link")
            }

            // Force actions
            Button(action: {
                Task { await performDownload() }
            }) {
                Label("Download All", systemImage: "icloud.and.arrow.down")
            }

            Button(action: {
                Task { await performUpload() }
            }) {
                Label("Upload All", systemImage: "icloud.and.arrow.up")
            }

            Divider()

            if let lastSync = syncService.lastSyncDate {
                Text("Last sync: \(lastSync, formatter: timeFormatter)")
                    .font(.caption)
            }
        } label: {
            HStack(spacing: 6) {
                if syncService.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: syncStatusIcon)
                        .foregroundColor(syncStatusColor)
                }

                if !syncService.syncProgress.isEmpty {
                    Text(syncService.syncProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(syncService.isSyncing)
        .sheet(isPresented: $showingPullFromWeb) {
            LinkEstimateSheet(onLinked: { estimate in
                showingPullFromWeb = false
                syncAlertMessage = "Linked: \(estimate.name)"
                showingSyncAlert = true
            })
            .environmentObject(store)
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    private var syncStatusIcon: String {
        if syncService.lastSyncError != nil {
            return "exclamationmark.icloud"
        } else if syncService.lastSyncDate != nil {
            return "checkmark.icloud"
        } else {
            return "icloud"
        }
    }

    private var syncStatusColor: Color {
        if syncService.lastSyncError != nil {
            return .orange
        } else if syncService.lastSyncDate != nil {
            return .green
        } else {
            return .blue
        }
    }

    private func performSmartSync() async {
        await syncService.smartSync(store: store)

        if let error = syncService.lastSyncError {
            syncAlertMessage = error
            showingSyncAlert = true
        } else {
            syncAlertMessage = "Sync complete! Data is now up to date."
            showingSyncAlert = true
        }
    }

    private func performDownload() async {
        await syncService.downloadAllFromServer(store: store)

        if let error = syncService.lastSyncError {
            syncAlertMessage = error
            showingSyncAlert = true
        } else {
            syncAlertMessage = "Downloaded \(store.estimates.count) estimates from server"
            showingSyncAlert = true
        }
    }

    private func performUpload() async {
        await syncService.syncAll(store: store)

        if let error = syncService.lastSyncError {
            syncAlertMessage = error
            showingSyncAlert = true
        } else {
            syncAlertMessage = "Uploaded \(store.estimates.count) estimates to server"
            showingSyncAlert = true
        }
    }
}

// MARK: - Empty Detail View
struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.left")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Select a Claim")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Choose a claim from the sidebar to view rooms and details")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - P3B-4: Job Queue View (replaces EstimateListView)
/// Groups estimates by urgency: Today, This Week, Later
/// Shows SLA countdown based on dateOfLoss
struct JobQueueView: View {
    @ObservedObject var store: EstimateStore
    @Binding var showingNewEstimate: Bool

    // Computed groupings based on dateOfLoss or createdAt
    var todayJobs: [Estimate] {
        store.estimates.filter { estimate in
            let referenceDate = estimate.dateOfLoss ?? estimate.createdAt
            return Calendar.current.isDateInToday(referenceDate)
        }.sorted { ($0.dateOfLoss ?? $0.createdAt) > ($1.dateOfLoss ?? $1.createdAt) }
    }

    var thisWeekJobs: [Estimate] {
        store.estimates.filter { estimate in
            let referenceDate = estimate.dateOfLoss ?? estimate.createdAt
            if Calendar.current.isDateInToday(referenceDate) { return false }

            let now = Date()
            let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            return referenceDate >= now && referenceDate <= weekFromNow
        }.sorted { ($0.dateOfLoss ?? $0.createdAt) > ($1.dateOfLoss ?? $1.createdAt) }
    }

    var laterJobs: [Estimate] {
        store.estimates.filter { estimate in
            let referenceDate = estimate.dateOfLoss ?? estimate.createdAt
            let now = Date()
            let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

            // Jobs older than today or beyond a week
            return referenceDate < Calendar.current.startOfDay(for: now) || referenceDate > weekFromNow
        }.sorted { ($0.dateOfLoss ?? $0.createdAt) > ($1.dateOfLoss ?? $1.createdAt) }
    }

    var body: some View {
        if store.estimates.isEmpty {
            ContentUnavailableView(
                "No Claims Yet",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Tap the + button to create your first claim")
            )
        } else {
            List(selection: $store.currentEstimate) {
                // Today section
                if !todayJobs.isEmpty {
                    Section {
                        ForEach(todayJobs) { estimate in
                            JobQueueRow(estimate: estimate)
                                .tag(estimate)
                        }
                        .onDelete { indexSet in
                            deleteFromSection(indexSet, from: todayJobs)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.orange)
                            Text("Today")
                                .fontWeight(.semibold)
                        }
                    }
                }

                // This Week section
                if !thisWeekJobs.isEmpty {
                    Section {
                        ForEach(thisWeekJobs) { estimate in
                            JobQueueRow(estimate: estimate)
                                .tag(estimate)
                        }
                        .onDelete { indexSet in
                            deleteFromSection(indexSet, from: thisWeekJobs)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("This Week")
                                .fontWeight(.semibold)
                        }
                    }
                }

                // Later section
                if !laterJobs.isEmpty {
                    Section {
                        ForEach(laterJobs) { estimate in
                            JobQueueRow(estimate: estimate)
                                .tag(estimate)
                        }
                        .onDelete { indexSet in
                            deleteFromSection(indexSet, from: laterJobs)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.gray)
                            Text("Later")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func deleteFromSection(_ indexSet: IndexSet, from section: [Estimate]) {
        for index in indexSet {
            if let estimateIndex = store.estimates.firstIndex(where: { $0.id == section[index].id }) {
                store.deleteEstimates(at: IndexSet(integer: estimateIndex))
            }
        }
    }
}

// MARK: - Job Queue Row with SLA Countdown
struct JobQueueRow: View {
    let estimate: Estimate

    // SLA calculation: hours since dateOfLoss
    var slaHours: Int? {
        guard let dol = estimate.dateOfLoss else { return nil }
        let hours = Int(Date().timeIntervalSince(dol) / 3600)
        return hours
    }

    var slaColor: Color {
        guard let hours = slaHours else { return .clear }
        if hours < 24 { return .green }
        if hours < 48 { return .yellow }
        if hours < 72 { return .orange }
        return .red
    }

    var slaText: String {
        guard let hours = slaHours else { return "" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Primary: Property address or display name
            Text(estimate.propertyAddress ?? estimate.displayName)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 6) {
                // Insured name if available
                if let insured = estimate.insuredName {
                    Text(insured)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Assignment badges
                ForEach(estimate.assignments.prefix(2).sorted { $0.order < $1.order }) { assignment in
                    Text(assignment.type.shortCode)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(assignment.type.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(assignment.type.color.opacity(0.15))
                        .cornerRadius(4)
                }

                // Status badge
                Text(estimate.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(estimate.status.color.opacity(0.2))
                    .foregroundColor(estimate.status.color)
                    .cornerRadius(4)

                // SLA countdown (if dateOfLoss exists)
                if slaHours != nil {
                    HStack(spacing: 2) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text(slaText)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(slaColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(slaColor.opacity(0.15))
                    .cornerRadius(4)
                }
            }

            // Bottom row: claim number + room count
            HStack {
                if let claim = estimate.claimNumber {
                    Text("#\(claim)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(estimate.rooms.count) room\(estimate.rooms.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Legacy EstimateRow (kept for compatibility)
struct EstimateRow: View {
    let estimate: Estimate

    var body: some View {
        JobQueueRow(estimate: estimate)
    }
}

// MARK: - New Estimate Sheet
struct NewEstimateSheet: View {
    @ObservedObject var store: EstimateStore
    @Binding var isPresented: Bool

    var body: some View {
        NewClaimSheet { claimData in
            store.createFromDispatch(claimData)
            isPresented = false
        }
    }
}

// MARK: - Estimate Detail View
struct EstimateDetailView: View {
    let estimate: Estimate
    @ObservedObject var store: EstimateStore
    @Binding var isCapturing: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Card
                EstimateHeaderCard(estimate: estimate)
                
                // Rooms Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Rooms")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Text("\(estimate.rooms.count)")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    
                    if estimate.rooms.isEmpty {
                        EmptyRoomsCard(onCapture: { isCapturing = true })
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 16)
                        ], spacing: 16) {
                            ForEach(estimate.rooms) { room in
                                RoomCard(room: room, store: store, estimateId: estimate.id)
                            }
                        }
                    }
                }
                
                // Scope Section
                ScopeCard(estimate: estimate, store: store)

                // Totals Section
                if !estimate.rooms.isEmpty {
                    TotalsCard(estimate: estimate)
                }

                // Actions
                ActionButtonsCard(estimate: estimate, store: store)
            }
            .padding(24)
            .frame(maxWidth: 1200) // Max width for ultra-wide displays
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct EstimateHeaderCard: View {
    let estimate: Estimate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let claim = estimate.claimNumber {
                Label(claim, systemImage: "number")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let address = estimate.propertyAddress {
                Label(address, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let insured = estimate.insuredName {
                Label(insured, systemImage: "person")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label(estimate.causeOfLoss, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                
                Spacer()
                
                Text(estimate.status.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(estimate.status.color.opacity(0.2))
                    .foregroundColor(estimate.status.color)
                    .cornerRadius(6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct EmptyRoomsCard: View {
    let onCapture: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("No rooms captured yet")
                .font(.headline)
            
            Text("Use LiDAR to capture room dimensions")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: onCapture) {
                Label("Capture Room", systemImage: "viewfinder")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Clean, Compact Room Card
struct RoomCard: View {
    let room: Room
    @ObservedObject var store: EstimateStore
    let estimateId: UUID

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedCategory: RoomCategory = .other
    @State private var editedFloor: FloorLevel = .first
    @State private var editedFloorMaterial: FloorMaterial = .other
    @State private var editedWallMaterial: WallMaterial = .smooth
    @State private var editedCeilingMaterial: CeilingMaterial = .smoothDrywall
    @State private var showingFloorPicker = false
    @State private var showingMaterialPicker = false
    @State private var showingDamageAnnotation = false
    @State private var showingRoomDetail = false  // NEW: View room floor plan/3D
    @State private var showingPhotoCapture = false  // P3B-3: Photo capture
    @StateObject private var photoService = PhotoService.shared  // P3B photo count

    // Photo count for badge display
    var photoCount: Int {
        photoService.photosForRoom(room.id).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content - tappable
            Button(action: { showingRoomDetail = true }) {
                VStack(alignment: .leading, spacing: 12) {
                    // Header row
                    HStack(spacing: 12) {
                        // Room icon
                        Image(systemName: room.category.icon)
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)

                        // Room name and badges
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.name)
                                .font(.headline)
                                .foregroundColor(.primary)

                            // Compact badge row
                            HStack(spacing: 6) {
                                // Floor badge
                                CompactBadge(text: room.floor.shortName, color: .blue)

                                // Materials (only show if set, condensed)
                                if room.floorMaterial != nil || room.wallMaterial != nil {
                                    CompactBadge(
                                        text: [room.floorMaterial?.displayName, room.wallMaterial?.displayName]
                                            .compactMap { $0 }
                                            .joined(separator: " / "),
                                        color: .secondary
                                    )
                                }

                                // Damage count
                                if !room.annotations.isEmpty {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 9))
                                        Text("\(room.annotations.count)")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.red)
                                }

                                // Photo count
                                if photoCount > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 9))
                                        Text("\(photoCount)")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }

                        Spacer()

                        // Square footage (prominent)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(room.squareFeet))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("SF")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Dimensions row (compact)
                    HStack(spacing: 16) {
                        CompactDimension(label: "L", value: room.lengthFtIn)
                        CompactDimension(label: "W", value: room.widthFtIn)
                        CompactDimension(label: "H", value: room.heightFtIn)

                        Spacer()

                        // Features count
                        HStack(spacing: 12) {
                            FeatureCount(icon: "rectangle.split.3x1", count: room.wallCount)
                            FeatureCount(icon: "door.left.hand.closed", count: room.doorCount)
                            FeatureCount(icon: "window.horizontal", count: room.windowCount)
                        }

                        Text("\(Int(room.wallSf)) SF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Damage summary (if any, compact)
                    if !room.annotations.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(room.annotations.prefix(3)) { annotation in
                                HStack(spacing: 4) {
                                    Image(systemName: annotation.damageType.icon)
                                        .font(.caption2)
                                        .foregroundColor(annotation.damageType.color)
                                    Text(annotation.severity.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(annotation.damageType.color.opacity(0.1))
                                .cornerRadius(4)
                            }
                            if room.annotations.count > 3 {
                                Text("+\(room.annotations.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Action menu (separate from tappable area)
            HStack {
                Spacer()
                Menu {
                    Button(action: { showingRoomDetail = true }) {
                        Label("View Floor Plan", systemImage: "map")
                    }
                    Button(action: {
                        editedName = room.name
                        editedCategory = room.category
                        editedFloor = room.floor
                        editedFloorMaterial = room.floorMaterial ?? .other
                        editedWallMaterial = room.wallMaterial ?? .smooth
                        editedCeilingMaterial = room.ceilingMaterial ?? .smoothDrywall
                        isEditing = true
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: { showingMaterialPicker = true }) {
                        Label("Tag Materials", systemImage: "tag")
                    }
                    Button(action: { showingDamageAnnotation = true }) {
                        Label("Add Damage", systemImage: "exclamationmark.triangle")
                    }
                    Button(action: { showingPhotoCapture = true }) {
                        Label("Add Photos", systemImage: "camera")
                    }
                    Divider()
                    Button(role: .destructive, action: {
                        store.deleteRoom(room.id, from: estimateId)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .contentShape(Rectangle())
                }
            }
            .padding(.trailing, 4)
            .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        // Edit sheet
        .sheet(isPresented: $isEditing) {
            RoomEditSheet(
                room: room,
                editedName: $editedName,
                editedCategory: $editedCategory,
                editedFloor: $editedFloor,
                editedFloorMaterial: $editedFloorMaterial,
                editedWallMaterial: $editedWallMaterial,
                editedCeilingMaterial: $editedCeilingMaterial,
                onSave: {
                    store.updateRoom(
                        room.id,
                        in: estimateId,
                        name: editedName,
                        category: editedCategory,
                        floor: editedFloor,
                        floorMaterial: editedFloorMaterial,
                        wallMaterial: editedWallMaterial,
                        ceilingMaterial: editedCeilingMaterial
                    )
                    isEditing = false
                },
                onCancel: { isEditing = false }
            )
        }
        // Floor picker sheet
        .sheet(isPresented: $showingFloorPicker) {
            FloorPickerSheet(
                currentFloor: room.floor,
                onSelect: { newFloor in
                    store.updateRoomFloor(room.id, in: estimateId, floor: newFloor)
                    showingFloorPicker = false
                },
                onCancel: { showingFloorPicker = false }
            )
            .presentationDetents([.height(300)])
        }
        // Material picker sheet
        .sheet(isPresented: $showingMaterialPicker) {
            MaterialPickerSheet(
                room: room,
                onSave: { floorMat, wallMat, ceilingMat in
                    store.updateRoomMaterials(room.id, in: estimateId, floorMaterial: floorMat, wallMaterial: wallMat, ceilingMaterial: ceilingMat)
                    showingMaterialPicker = false
                },
                onCancel: { showingMaterialPicker = false }
            )
        }
        // Damage annotation sheet
        .sheet(isPresented: $showingDamageAnnotation) {
            DamageAnnotationSheet(
                onSave: { annotation in
                    store.addAnnotation(annotation, to: room.id, in: estimateId)
                    showingDamageAnnotation = false
                },
                onCancel: { showingDamageAnnotation = false }
            )
        }
        // Room detail sheet (Floor Plan / 3D View / Stats)
        .sheet(isPresented: $showingRoomDetail) {
            SavedRoomDetailView(room: room, store: store, estimateId: estimateId)
        }
        // P3B-3: Photo capture sheet
        .fullScreenCover(isPresented: $showingPhotoCapture) {
            PhotoCaptureView(
                estimateId: estimateId,
                roomId: room.id,
                annotationId: nil,
                onPhotosCaptured: { photos in
                    print("📸 RoomCard: Captured \(photos.count) photos for room \(room.name)")
                    showingPhotoCapture = false
                }
            )
        }
    }
}

// MARK: - Compact UI Components
struct CompactBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct CompactDimension: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }
}

struct FeatureCount: View {
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Room Edit Sheet (moved from inline editing)
struct RoomEditSheet: View {
    let room: Room
    @Binding var editedName: String
    @Binding var editedCategory: RoomCategory
    @Binding var editedFloor: FloorLevel
    @Binding var editedFloorMaterial: FloorMaterial
    @Binding var editedWallMaterial: WallMaterial
    @Binding var editedCeilingMaterial: CeilingMaterial
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Name", text: $editedName)
                    Picker("Category", selection: $editedCategory) {
                        ForEach(RoomCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    Picker("Floor", selection: $editedFloor) {
                        ForEach(FloorLevel.allCases, id: \.self) { floor in
                            Label(floor.displayName, systemImage: floor.icon).tag(floor)
                        }
                    }
                }

                Section("Materials") {
                    Picker("Floor Material", selection: $editedFloorMaterial) {
                        ForEach(FloorMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }
                    Picker("Wall Finish", selection: $editedWallMaterial) {
                        ForEach(WallMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }
                    Picker("Ceiling Type", selection: $editedCeilingMaterial) {
                        ForEach(CeilingMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }
                }
            }
            .navigationTitle("Edit Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}

// MARK: - Saved Room Detail View (Floor Plan / 3D / Stats)
@available(iOS 16.0, *)
struct SavedRoomDetailView: View {
    let room: Room
    @ObservedObject var store: EstimateStore
    let estimateId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var viewMode: ViewMode = .floorPlan
    @StateObject private var photoService = PhotoService.shared

    enum ViewMode: String, CaseIterable {
        case floorPlan = "Floor Plan"
        case isometric = "3D View"
        case photos = "Photos"
        case stats = "Stats"
    }

    // Photo count for this room
    var photoCount: Int {
        photoService.photosForRoom(room.id).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Main content
                ZStack {
                    switch viewMode {
                    case .floorPlan:
                        SavedRoomFloorPlanView(room: room)
                    case .isometric:
                        SavedRoom3DView(room: room, annotations: room.annotations)
                    case .photos:
                        PhotoGalleryView(
                            estimateId: estimateId,
                            roomId: room.id,
                            title: "\(room.name) Photos"
                        )
                    case .stats:
                        SavedRoomStatsView(room: room)
                    }
                }

                // Bottom info bar
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        QuickStat(icon: "cube", label: "Walls", value: "\(room.wallCount)")
                        QuickStat(icon: "door.left.hand.closed", label: "Doors", value: "\(room.doorCount)")
                        QuickStat(icon: "window.horizontal", label: "Windows", value: "\(room.windowCount)")
                        QuickStat(icon: "exclamationmark.triangle", label: "Damage", value: "\(room.annotations.count)")
                        QuickStat(icon: "camera.fill", label: "Photos", value: "\(photoCount)")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
            }
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Floor plan view for saved room (synthetic from dimensions)
@available(iOS 16.0, *)
struct SavedRoomFloorPlanView: View {
    let room: Room

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                (geometry.size.width - 100) / CGFloat(room.lengthIn),
                (geometry.size.height - 100) / CGFloat(room.widthIn)
            ) * 0.8

            let roomWidth = CGFloat(room.lengthIn) * scale
            let roomHeight = CGFloat(room.widthIn) * scale

            ZStack {
                // Background
                Color(red: 0.97, green: 0.98, blue: 1.0)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    // Room rectangle
                    ZStack {
                        // Floor fill
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: roomWidth, height: roomHeight)
                            .shadow(color: .black.opacity(0.1), radius: 8)

                        // Walls
                        Rectangle()
                            .stroke(Color(red: 0.15, green: 0.15, blue: 0.2), lineWidth: 6)
                            .frame(width: roomWidth, height: roomHeight)
                    }

                    Spacer()

                    // Dimension labels
                    HStack {
                        Text(room.lengthFtIn)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(4)
                    }
                    .padding(.bottom, 20)
                }

                // Right dimension
                HStack {
                    Spacer()
                    Text(room.widthFtIn)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(4)
                        .rotationEffect(.degrees(-90))
                        .padding(.trailing, 20)
                }
            }
        }
    }
}

// 3D view for saved room
@available(iOS 16.0, *)
struct SavedRoom3DView: View {
    let room: Room
    let annotations: [DamageAnnotation]

    var body: some View {
        // Use a simplified isometric view based on room dimensions
        SavedRoomIsometricView(room: room, annotations: annotations)
    }
}

// Simplified isometric view for saved rooms
@available(iOS 16.0, *)
struct SavedRoomIsometricView: View {
    let room: Room
    let annotations: [DamageAnnotation]

    @StateObject private var geminiService = GeminiService.shared
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.14)
                .ignoresSafeArea()

            if let image = generatedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .padding()
            } else if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Generating AI Render...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Button("Retry") {
                        Task { await generateRender() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))

                    Text("Generate AI Render")
                        .font(.headline)
                        .foregroundColor(.white)

                    Button("Generate") {
                        Task { await generateRender() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            if generatedImage == nil && !isGenerating {
                Task { await generateRender() }
            }
        }
    }

    private func generateRender() async {
        await MainActor.run {
            isGenerating = true
            errorMessage = nil
        }

        do {
            let geometry = buildGeometryFromRoom()
            let annotationData = annotations.map { ann in
                DamageAnnotationData(
                    damageType: ann.damageType.rawValue,
                    severity: ann.severity.rawValue,
                    affectedSurfaces: ann.affectedSurfaces.map { $0.rawValue },
                    waterLineHeight: ann.affectedHeightIn,
                    highlightColor: ann.damageType.rawValue.lowercased()
                )
            }

            let image = try await geminiService.generateIsometricRender(
                roomGeometry: geometry,
                annotations: annotationData,
                style: .clean
            )

            await MainActor.run {
                self.generatedImage = image
                self.isGenerating = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }

    private func buildGeometryFromRoom() -> RoomGeometryData {
        // Build walls based on room shape (assume rectangular for now)
        let walls = [
            RoomGeometryData.WallData(lengthFt: room.lengthIn / 12, heightFt: room.heightIn / 12, positionDescription: "North wall"),
            RoomGeometryData.WallData(lengthFt: room.widthIn / 12, heightFt: room.heightIn / 12, positionDescription: "East wall"),
            RoomGeometryData.WallData(lengthFt: room.lengthIn / 12, heightFt: room.heightIn / 12, positionDescription: "South wall"),
            RoomGeometryData.WallData(lengthFt: room.widthIn / 12, heightFt: room.heightIn / 12, positionDescription: "West wall")
        ]

        return RoomGeometryData(
            category: room.category.rawValue,
            lengthFt: room.lengthIn / 12,
            widthFt: room.widthIn / 12,
            heightFt: room.heightIn / 12,
            squareFeet: room.squareFeet,
            isRectangular: true,
            walls: walls,
            doors: [],
            windows: [],
            objects: [],
            floorMaterial: room.floorMaterial?.displayName,
            wallMaterial: room.wallMaterial?.displayName,
            ceilingMaterial: room.ceilingMaterial?.displayName
        )
    }
}

// Stats view for saved room
struct SavedRoomStatsView: View {
    let room: Room

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Dimensions
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        DimensionCard(label: "Length", value: room.lengthFtIn)
                        DimensionCard(label: "Width", value: room.widthFtIn)
                        DimensionCard(label: "Height", value: room.heightFtIn)
                    }

                    VStack(spacing: 8) {
                        Text("\(Int(room.squareFeet))")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Square Feet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
                .padding()

                // Materials
                VStack(alignment: .leading, spacing: 12) {
                    Text("Materials")
                        .font(.title2)
                        .fontWeight(.bold)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MaterialInfoCard(
                            icon: room.floorMaterial?.icon ?? "square.fill",
                            label: "Floor",
                            value: room.floorMaterial?.displayName ?? "Not set"
                        )
                        MaterialInfoCard(
                            icon: room.wallMaterial?.icon ?? "rectangle",
                            label: "Walls",
                            value: room.wallMaterial?.displayName ?? "Not set"
                        )
                        MaterialInfoCard(
                            icon: room.ceilingMaterial?.icon ?? "rectangle",
                            label: "Ceiling",
                            value: room.ceilingMaterial?.displayName ?? "Not set"
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.title2)
                        .fontWeight(.bold)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        FeatureCard(icon: "rectangle.split.3x1", label: "Walls", value: "\(room.wallCount)")
                        FeatureCard(icon: "door.left.hand.closed", label: "Doors", value: "\(room.doorCount)")
                        FeatureCard(icon: "window.horizontal", label: "Windows", value: "\(room.windowCount)")
                        FeatureCard(icon: "square.stack.3d.up", label: "Wall SF", value: "\(Int(room.wallSf))")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct MaterialInfoCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// P3-002/003/004: Small material badge for room card header
struct MaterialBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

// P3-002/003/004: Enhanced Material Picker with PM Favorites and Visual Cards
struct MaterialPickerSheet: View {
    let room: Room
    let onSave: (FloorMaterial, WallMaterial, CeilingMaterial) -> Void
    let onCancel: () -> Void

    @StateObject private var prefs = MaterialPreferences.shared
    @State private var floorMaterial: FloorMaterial
    @State private var wallMaterial: WallMaterial
    @State private var ceilingMaterial: CeilingMaterial
    @State private var showingAllFloors = false
    @State private var showingAllWalls = false
    @State private var showingAllCeilings = false

    init(room: Room, onSave: @escaping (FloorMaterial, WallMaterial, CeilingMaterial) -> Void, onCancel: @escaping () -> Void) {
        self.room = room
        self.onSave = onSave
        self.onCancel = onCancel
        _floorMaterial = State(initialValue: room.floorMaterial ?? MaterialPreferences.shared.defaultFloorMaterial)
        _wallMaterial = State(initialValue: room.wallMaterial ?? MaterialPreferences.shared.defaultWallMaterial)
        _ceilingMaterial = State(initialValue: room.ceilingMaterial ?? MaterialPreferences.shared.defaultCeilingMaterial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Floor Section
                    MaterialSection(
                        title: "Floor",
                        icon: "square.split.diagonal",
                        selectedMaterial: floorMaterial,
                        favorites: prefs.favoriteFloorMaterials,
                        allMaterials: FloorMaterial.allCases,
                        showingAll: $showingAllFloors,
                        onSelect: { floorMaterial = $0 },
                        onToggleFavorite: { prefs.toggleFavorite($0) },
                        materialCard: { mat, isSelected, isFavorite, onSelect, onToggleFav in
                            FloorMaterialCard(
                                material: mat,
                                isSelected: isSelected,
                                isFavorite: isFavorite,
                                onSelect: onSelect,
                                onToggleFavorite: onToggleFav
                            )
                        }
                    )

                    // Wall Section
                    MaterialSection(
                        title: "Walls",
                        icon: "rectangle.portrait",
                        selectedMaterial: wallMaterial,
                        favorites: prefs.favoriteWallMaterials,
                        allMaterials: WallMaterial.allCases,
                        showingAll: $showingAllWalls,
                        onSelect: { wallMaterial = $0 },
                        onToggleFavorite: { prefs.toggleFavorite($0) },
                        materialCard: { mat, isSelected, isFavorite, onSelect, onToggleFav in
                            WallMaterialCard(
                                material: mat,
                                isSelected: isSelected,
                                isFavorite: isFavorite,
                                onSelect: onSelect,
                                onToggleFavorite: onToggleFav
                            )
                        }
                    )

                    // Ceiling Section
                    MaterialSection(
                        title: "Ceiling",
                        icon: "rectangle.topthird.inset.filled",
                        selectedMaterial: ceilingMaterial,
                        favorites: prefs.favoriteCeilingMaterials,
                        allMaterials: CeilingMaterial.allCases,
                        showingAll: $showingAllCeilings,
                        onSelect: { ceilingMaterial = $0 },
                        onToggleFavorite: { prefs.toggleFavorite($0) },
                        materialCard: { mat, isSelected, isFavorite, onSelect, onToggleFav in
                            CeilingMaterialCard(
                                material: mat,
                                isSelected: isSelected,
                                isFavorite: isFavorite,
                                onSelect: onSelect,
                                onToggleFavorite: onToggleFav
                            )
                        }
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tag Materials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(floorMaterial, wallMaterial, ceilingMaterial)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Material Section (Generic)
struct MaterialSection<Material: Hashable, CardView: View>: View {
    let title: String
    let icon: String
    let selectedMaterial: Material
    let favorites: [Material]
    let allMaterials: [Material]
    @Binding var showingAll: Bool
    let onSelect: (Material) -> Void
    let onToggleFavorite: (Material) -> Void
    let materialCard: (Material, Bool, Bool, @escaping () -> Void, @escaping () -> Void) -> CardView

    private var displayedMaterials: [Material] {
        if showingAll {
            return allMaterials
        }
        // Show favorites first, then add selected if not in favorites
        var displayed = favorites
        if !displayed.contains(selectedMaterial) {
            displayed.append(selectedMaterial)
        }
        return displayed
    }

    private var hiddenCount: Int {
        allMaterials.count - displayedMaterials.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
                if hiddenCount > 0 && !showingAll {
                    Button(action: { showingAll = true }) {
                        Text("+\(hiddenCount) more")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else if showingAll && favorites.count < allMaterials.count {
                    Button(action: { showingAll = false }) {
                        Text("Show less")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            // Material Cards Grid - large touch targets
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(displayedMaterials, id: \.self) { material in
                    materialCard(
                        material,
                        material == selectedMaterial,
                        favorites.contains(material),
                        { onSelect(material) },
                        { onToggleFavorite(material) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Floor Material Card
struct FloorMaterialCard: View {
    let material: FloorMaterial
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Color swatch with texture pattern
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(material.swatchColor)
                        .frame(height: 50)

                    // Texture overlay based on material
                    materialTextureOverlay

                    // Selection checkmark
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                            .shadow(radius: 2)
                    }
                }

                // Name
                Text(material.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Xact code hint
                Text(material.xactCodes.first ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }

    @ViewBuilder
    private var materialTextureOverlay: some View {
        switch material {
        case .carpet:
            // Carpet texture dots
            Image(systemName: "circle.grid.3x3.fill")
                .foregroundColor(.white.opacity(0.2))
        case .tile:
            // Tile grid
            Image(systemName: "square.grid.2x2")
                .foregroundColor(.gray.opacity(0.3))
        case .hardwood, .lvp, .laminate:
            // Wood grain lines
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.black.opacity(0.15))
        default:
            EmptyView()
        }
    }
}

// MARK: - Wall Material Card
struct WallMaterialCard: View {
    let material: WallMaterial
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Color swatch with texture
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(material.swatchColor)
                        .frame(height: 50)

                    // Texture overlay
                    wallTextureOverlay

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                            .shadow(color: .white, radius: 2)
                    }
                }

                Text(material.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(material.xactCodes.first ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }

    @ViewBuilder
    private var wallTextureOverlay: some View {
        switch material {
        case .orangePeel:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray.opacity(0.3))
        case .knockdown:
            Image(systemName: "waveform")
                .foregroundColor(.gray.opacity(0.2))
        case .heavyTexture:
            Image(systemName: "waveform.path")
                .foregroundColor(.gray.opacity(0.25))
        case .wallpaper:
            Image(systemName: "doc.richtext")
                .foregroundColor(.gray.opacity(0.2))
        default:
            EmptyView()
        }
    }
}

// MARK: - Ceiling Material Card
struct CeilingMaterialCard: View {
    let material: CeilingMaterial
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Color swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(material.swatchColor)
                        .frame(height: 50)

                    // Texture overlay
                    ceilingTextureOverlay

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                            .shadow(color: .white, radius: 2)
                    }
                }

                Text(material.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(material.xactCodes.first ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }

    @ViewBuilder
    private var ceilingTextureOverlay: some View {
        switch material {
        case .popcorn:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray.opacity(0.4))
        case .tBar:
            Image(systemName: "square.grid.3x3")
                .foregroundColor(.gray.opacity(0.3))
        case .textured:
            Image(systemName: "waveform")
                .foregroundColor(.gray.opacity(0.2))
        case .exposed:
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
        default:
            EmptyView()
        }
    }
}

// P3-007: Damage annotation sheet
struct DamageAnnotationSheet: View {
    let onSave: (DamageAnnotation) -> Void
    let onCancel: () -> Void

    @State private var damageType: DamageType = .water
    @State private var severity: DamageSeverity = .moderate
    @State private var affectedSurfaces: Set<AffectedSurface> = [.floor]
    @State private var affectedHeightIn: Double = 24
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Damage Type") {
                    Picker("Type", selection: $damageType) {
                        ForEach(DamageType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(DamageSeverity.allCases, id: \.self) { sev in
                            HStack {
                                Circle()
                                    .fill(sev.color)
                                    .frame(width: 12, height: 12)
                                Text(sev.rawValue)
                            }
                            .tag(sev)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Affected Surfaces") {
                    ForEach(AffectedSurface.allCases, id: \.self) { surface in
                        Toggle(isOn: Binding(
                            get: { affectedSurfaces.contains(surface) },
                            set: { isOn in
                                if isOn {
                                    affectedSurfaces.insert(surface)
                                } else {
                                    affectedSurfaces.remove(surface)
                                }
                            }
                        )) {
                            Label(surface.rawValue, systemImage: surface.icon)
                        }
                    }
                }

                // Show height picker for water damage with wall affected
                if damageType == .water && affectedSurfaces.contains(.wall) {
                    Section("Water Line Height") {
                        HStack {
                            Text("\(Int(affectedHeightIn / 12))' \(Int(affectedHeightIn) % 12)\"")
                                .font(.headline)
                            Spacer()
                            Stepper("", value: $affectedHeightIn, in: 1...96, step: 6)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Add Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let annotation = DamageAnnotation(
                            position: CGPoint(x: 0.5, y: 0.5),
                            damageType: damageType,
                            severity: severity,
                            affectedSurfaces: affectedSurfaces,
                            affectedHeightIn: affectedSurfaces.contains(.wall) ? affectedHeightIn : nil,
                            notes: notes
                        )
                        onSave(annotation)
                    }
                    .disabled(affectedSurfaces.isEmpty)
                }
            }
        }
    }
}

// P3-008: Display damage annotations list on room card
struct DamageAnnotationsList: View {
    let annotations: [DamageAnnotation]
    @ObservedObject var store: EstimateStore
    let roomId: UUID
    let estimateId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Damage")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(annotations) { annotation in
                HStack(spacing: 8) {
                    Image(systemName: annotation.damageType.icon)
                        .foregroundColor(annotation.damageType.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(annotation.damageType.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: 4) {
                            Text(annotation.severity.rawValue)
                                .font(.caption2)
                                .foregroundColor(annotation.severity.color)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(annotation.affectedSurfaces.map { $0.rawValue }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if let height = annotation.affectedHeightIn {
                                Text("• \(Int(height / 12))'\(Int(height) % 12)\"")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(action: {
                        store.deleteAnnotation(annotation.id, from: roomId, in: estimateId)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(annotation.severity.color.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// P3-001: Floor picker sheet for quick floor selection
struct FloorPickerSheet: View {
    let currentFloor: FloorLevel
    let onSelect: (FloorLevel) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(FloorLevel.allCases, id: \.self) { floor in
                    Button(action: { onSelect(floor) }) {
                        HStack {
                            Image(systemName: floor.icon)
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40)

                            Text(floor.displayName)
                                .font(.headline)

                            Spacer()

                            if floor == currentFloor {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Floor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

struct DimensionBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Scope Card

struct ScopeCard: View {
    let estimate: Estimate
    @ObservedObject var store: EstimateStore

    var lineItemCount: Int { estimate.lineItems.count }
    var validCount: Int { estimate.lineItems.filter { $0.validationState == .valid }.count }
    var invalidCount: Int { estimate.lineItems.filter { $0.validationState == .invalid }.count }
    var scopeTotal: Double { estimate.lineItems.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scope")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(lineItemCount) items")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            if lineItemCount == 0 {
                // Empty state with navigation link
                NavigationLink(destination: ScopeListView(store: store, estimate: estimate)) {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Line Items")
                                .font(.headline)
                            Text("Tap to add scope items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                // Summary with stats
                NavigationLink(destination: ScopeListView(store: store, estimate: estimate)) {
                    VStack(spacing: 12) {
                        // Stats row
                        HStack(spacing: 24) {
                            ScopeStatItem(
                                icon: "checkmark.circle.fill",
                                value: "\(validCount)",
                                label: "Valid",
                                color: .green
                            )

                            ScopeStatItem(
                                icon: "exclamationmark.triangle.fill",
                                value: "\(invalidCount)",
                                label: "Invalid",
                                color: .orange
                            )

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Total")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("$\(scopeTotal, specifier: "%.2f")")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                        }

                        // Action hint
                        HStack {
                            Text("View & Edit Scope")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ScopeStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(value)
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Totals Card

struct TotalsCard: View {
    let estimate: Estimate

    var totalSF: Double {
        estimate.rooms.reduce(0) { $0 + $1.squareFeet }
    }

    var totalWallSF: Double {
        estimate.rooms.reduce(0) { $0 + $1.wallSf }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Totals")
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                TotalItem(label: "Total Floor SF", value: String(format: "%.0f", totalSF))
                Spacer()
                TotalItem(label: "Total Wall SF", value: String(format: "%.0f", totalWallSF))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct TotalItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

struct ActionButtonsCard: View {
    let estimate: Estimate
    @ObservedObject var store: EstimateStore
    @State private var isSyncing = false
    @State private var showingSyncSuccess = false
    @State private var isExportingESX = false
    @State private var showingESXShareSheet = false
    @State private var esxFileURL: URL?
    @State private var showingESXError = false
    @State private var esxExportError: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Sync Button
                Button(action: syncToWeb) {
                    HStack(spacing: 12) {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3)
                        }
                        Text(isSyncing ? "Syncing..." : "Sync to Web")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isSyncing || estimate.rooms.isEmpty)

                // Generate Scope Button (Future)
                Button(action: {}) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                        Text("Generate AI Scope")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(estimate.rooms.isEmpty)
            }

            // ESX Export Button
            Button(action: exportToESX) {
                HStack(spacing: 12) {
                    if isExportingESX {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                    Text(isExportingESX ? "Exporting..." : "Export to Xactimate (ESX)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isExportingESX || estimate.rooms.isEmpty)
        }
        .alert("Sync Complete", isPresented: $showingSyncSuccess) {
            Button("OK") {}
        } message: {
            Text("Estimate synced to web successfully!")
        }
        .alert("Export Error", isPresented: $showingESXError) {
            Button("OK") {}
        } message: {
            Text(esxExportError ?? "Unknown error during export.")
        }
        .sheet(isPresented: $showingESXShareSheet) {
            if let url = esxFileURL {
                ESXShareSheet(url: url)
            }
        }
    }

    private func exportToESX() {
        guard !estimate.rooms.isEmpty else { return }

        isExportingESX = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try ESXExportService.shared.exportToESX(estimate: estimate)

                DispatchQueue.main.async {
                    isExportingESX = false
                    esxFileURL = url
                    showingESXShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    isExportingESX = false
                    esxExportError = error.localizedDescription
                    showingESXError = true
                }
            }
        }
    }
    
    func syncToWeb() {
        isSyncing = true

        Task {
            do {
                try await SyncService.shared.uploadEstimate(estimate)
                await MainActor.run {
                    isSyncing = false
                    showingSyncSuccess = true
                    store.markSynced(estimate.id)
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    // Show error to user
                    print("❌ Sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Data Models
struct Estimate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var claimNumber: String?
    var policyNumber: String?
    var insuredName: String?
    var insuredPhone: String?
    var insuredEmail: String?
    var propertyAddress: String?
    var propertyCity: String?
    var propertyState: String?
    var propertyZip: String?
    var causeOfLoss: String
    var status: EstimateStatus
    var rooms: [Room]
    var assignments: [Assignment]  // NEW: Assignments (E, R, C)
    var lineItems: [ScopeLineItem]  // Scope line items with validation
    var createdAt: Date
    var updatedAt: Date  // Track local modifications for sync
    var syncedAt: Date?

    // NEW: Job type and dispatch info
    var jobType: JobType
    var xaId: String?
    var dispatchType: DispatchType?
    var dateOfLoss: Date?

    // NEW: Adjuster info
    var adjusterName: String?
    var adjusterPhone: String?
    var adjusterEmail: String?
    var insuranceCompany: String?

    // NEW: Coordinates
    var latitude: Double?
    var longitude: Double?

    init(
        id: UUID = UUID(),
        name: String,
        claimNumber: String? = nil,
        policyNumber: String? = nil,
        insuredName: String? = nil,
        insuredPhone: String? = nil,
        insuredEmail: String? = nil,
        propertyAddress: String? = nil,
        propertyCity: String? = nil,
        propertyState: String? = nil,
        propertyZip: String? = nil,
        causeOfLoss: String = "Water",
        status: EstimateStatus = .draft,
        rooms: [Room] = [],
        assignments: [Assignment] = [],
        lineItems: [ScopeLineItem] = [],
        jobType: JobType = .insurance,
        xaId: String? = nil,
        dispatchType: DispatchType? = nil,
        dateOfLoss: Date? = nil,
        adjusterName: String? = nil,
        adjusterPhone: String? = nil,
        adjusterEmail: String? = nil,
        insuranceCompany: String? = nil
    ) {
        self.id = id
        self.name = name
        self.claimNumber = claimNumber
        self.policyNumber = policyNumber
        self.insuredName = insuredName
        self.insuredPhone = insuredPhone
        self.insuredEmail = insuredEmail
        self.propertyAddress = propertyAddress
        self.propertyCity = propertyCity
        self.propertyState = propertyState
        self.propertyZip = propertyZip
        self.causeOfLoss = causeOfLoss
        self.status = status
        self.rooms = rooms
        self.assignments = assignments
        self.lineItems = lineItems
        self.jobType = jobType
        self.xaId = xaId
        self.dispatchType = dispatchType
        self.dateOfLoss = dateOfLoss
        self.adjusterName = adjusterName
        self.adjusterPhone = adjusterPhone
        self.adjusterEmail = adjusterEmail
        self.insuranceCompany = insuranceCompany
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Display name for UI
    var displayName: String {
        if !propertyAddress.isNilOrEmpty {
            return propertyAddress!
        } else if !insuredName.isNilOrEmpty {
            return insuredName!
        } else if let claim = claimNumber {
            return "Claim #\(claim)"
        }
        return name
    }
}

// Helper extension for optional strings
extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

enum EstimateStatus: String, Codable {
    case draft = "Draft"
    case inProgress = "In Progress"
    case pendingSync = "Pending Sync"
    case synced = "Synced"
    case complete = "Complete"

    var color: Color {
        switch self {
        case .draft: return .gray
        case .inProgress: return .orange
        case .pendingSync: return .yellow
        case .synced: return .green
        case .complete: return .blue
        }
    }
}

// MARK: - Damage Types (from CoreModels)

/// Types of damage that can be annotated
enum DamageType: String, Codable, CaseIterable, Identifiable {
    case water = "Water"
    case fire = "Fire"
    case smoke = "Smoke"
    case mold = "Mold"
    case impact = "Impact"
    case wind = "Wind"
    case other = "Other"

    var id: String { rawValue }
    var shortName: String { rawValue }
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .fire: return "flame.fill"
        case .smoke: return "smoke.fill"
        case .mold: return "allergens"
        case .impact: return "burst.fill"
        case .wind: return "wind"
        case .other: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .water: return .blue
        case .fire: return .red
        case .smoke: return .gray
        case .mold: return .green
        case .impact: return .orange
        case .wind: return .cyan
        case .other: return .purple
        }
    }
    // Note: uiColor is defined as extension in IsometricRoomView.swift
}

/// Severity levels for damage
enum DamageSeverity: String, Codable, CaseIterable, Hashable {
    case light = "Light"
    case moderate = "Moderate"
    case heavy = "Heavy"
    case destroyed = "Destroyed"

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .light: return .yellow
        case .moderate: return .orange
        case .heavy: return .red
        case .destroyed: return .purple
        }
    }
}

/// Surfaces that can be affected by damage
enum AffectedSurface: String, Codable, CaseIterable, Hashable {
    case floor = "Floor"
    case wall = "Wall"
    case ceiling = "Ceiling"
    case trim = "Trim"
    case cabinetry = "Cabinetry"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .floor: return "square.fill"
        case .wall: return "rectangle.portrait.fill"
        case .ceiling: return "rectangle.fill"
        case .trim: return "line.horizontal.3"
        case .cabinetry: return "cabinet.fill"
        }
    }
}

/// Represents a damage annotation in a room
/// P3-017: Full damage annotation data model with 3D positioning
struct DamageAnnotation: Identifiable, Codable, Hashable {
    let id: UUID
    var roomId: UUID?
    var damageType: DamageType
    var severity: DamageSeverity
    var affectedSurfaces: Set<AffectedSurface>

    // Position in room (normalized 0-1 coordinates)
    var position: CGPoint  // x, y position on floor plan
    var positionZ: Double?  // P3-017: z position (height from floor in inches, nil = floor level)

    var affectedHeightIn: Double?  // Water line height for water damage
    var affectedAreaSf: Double?  // P3-017: Estimated affected area in square feet
    var notes: String
    var photos: [String]  // Local file paths to photos
    var audioPath: String?  // Local file path to voice memo
    var createdAt: Date
    var updatedAt: Date

    // P3-017: Computed properties for API compatibility
    var photoUrls: [String] {
        get { photos }
        set { photos = newValue }
    }

    var voiceMemoUrl: String? {
        get { audioPath }
        set { audioPath = newValue }
    }

    // P3-017: 3D position tuple for easy access
    var position3D: (x: Double, y: Double, z: Double) {
        (x: position.x, y: position.y, z: positionZ ?? 0)
    }

    init(
        id: UUID = UUID(),
        roomId: UUID? = nil,
        position: CGPoint = .zero,
        positionZ: Double? = nil,
        damageType: DamageType = .water,
        severity: DamageSeverity = .moderate,
        affectedSurfaces: Set<AffectedSurface> = [],
        affectedHeightIn: Double? = nil,
        affectedAreaSf: Double? = nil,
        notes: String = "",
        photos: [String] = [],
        audioPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.roomId = roomId
        self.position = position
        self.positionZ = positionZ
        self.damageType = damageType
        self.severity = severity
        self.affectedSurfaces = affectedSurfaces
        self.affectedHeightIn = affectedHeightIn
        self.affectedAreaSf = affectedAreaSf
        self.notes = notes
        self.photos = photos
        self.audioPath = audioPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct Room: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: RoomCategory
    var floor: FloorLevel  // P3-001: Floor level for organizing rooms

    // P3-002, P3-003, P3-004: Material tagging
    var floorMaterial: FloorMaterial?
    var wallMaterial: WallMaterial?
    var ceilingMaterial: CeilingMaterial?

    // Dimensions in inches
    let lengthIn: Double
    let widthIn: Double
    let heightIn: Double

    // Counts
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int

    // P3-013: Room subdivision support
    var divisionLines: [DivisionLine]?
    var subRooms: [SubRoom]?
    var isDivided: Bool { subRooms != nil && !(subRooms?.isEmpty ?? true) }

    // Damage annotations
    var annotations: [DamageAnnotation]
    
    // Calculated
    var squareFeet: Double { (lengthIn * widthIn) / 144 }
    var perimeterLf: Double { (lengthIn + widthIn) * 2 / 12 }
    var wallSf: Double { perimeterLf * (heightIn / 12) }
    var ceilingSf: Double { squareFeet }
    
    // Formatted
    var lengthFtIn: String { formatFeetInches(lengthIn) }
    var widthFtIn: String { formatFeetInches(widthIn) }
    var heightFtIn: String { formatFeetInches(heightIn) }
    
    var createdAt: Date
    
    @available(iOS 16.0, *)
    init(from capturedRoom: CapturedRoom) {
        self.id = UUID()
        self.name = "Room"
        self.category = Room.detectCategory(from: capturedRoom)
        self.floor = .first  // P3-001: Default to 1st floor

        // P3-002, P3-003, P3-004: Materials default to nil (unset)
        self.floorMaterial = nil
        self.wallMaterial = nil
        self.ceilingMaterial = nil

        let bounds = Room.calculateBounds(from: capturedRoom)
        self.lengthIn = bounds.length
        self.widthIn = bounds.width
        self.heightIn = bounds.height

        self.wallCount = capturedRoom.walls.count
        self.doorCount = capturedRoom.doors.count
        self.windowCount = capturedRoom.windows.count
        self.createdAt = Date()

        // P3-013: Initialize subdivision properties
        self.divisionLines = nil
        self.subRooms = nil
        self.annotations = []

        // Auto-name based on category
        self.name = self.category.rawValue
    }

    // P3-RC-002: Simple initializer for creating rooms from ProposedRoom or manual entry
    init(
        id: UUID = UUID(),
        name: String,
        category: RoomCategory,
        floor: FloorLevel = .first,
        floorMaterial: FloorMaterial? = nil,
        wallMaterial: WallMaterial? = nil,
        ceilingMaterial: CeilingMaterial? = nil,
        lengthIn: Double,
        widthIn: Double,
        heightIn: Double,
        wallCount: Int = 4,
        doorCount: Int = 1,
        windowCount: Int = 0,
        divisionLines: [DivisionLine]? = nil,
        subRooms: [SubRoom]? = nil,
        annotations: [DamageAnnotation] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.floor = floor
        self.floorMaterial = floorMaterial
        self.wallMaterial = wallMaterial
        self.ceilingMaterial = ceilingMaterial
        self.lengthIn = lengthIn
        self.widthIn = widthIn
        self.heightIn = heightIn
        self.wallCount = wallCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.divisionLines = divisionLines
        self.subRooms = subRooms
        self.annotations = annotations
        self.createdAt = createdAt
    }

    // P3-013: Calculate sub-room dimensions from division lines
    /// Creates SubRoom objects from division lines by calculating approximate areas
    mutating func calculateSubRoomsFromDivisionLines() {
        guard let lines = divisionLines, !lines.isEmpty else {
            subRooms = nil
            return
        }

        // Simple implementation: for each division line, create two sub-rooms
        // dividing the space based on the line's position
        var generatedSubRooms: [SubRoom] = []

        // For a single horizontal or vertical line, calculate two regions
        if lines.count == 1 {
            let line = lines[0]

            // Determine if line is more horizontal or vertical
            let isHorizontal = abs(line.endPoint.y - line.startPoint.y) < abs(line.endPoint.x - line.startPoint.x)

            if isHorizontal {
                // Line divides room top/bottom
                let splitRatio = (line.startPoint.y + line.endPoint.y) / 2

                let topHeight = lengthIn * splitRatio
                let bottomHeight = lengthIn * (1 - splitRatio)

                generatedSubRooms.append(SubRoom(
                    name: "Area A",
                    category: .other,
                    lengthIn: topHeight,
                    widthIn: widthIn,
                    heightIn: heightIn
                ))
                generatedSubRooms.append(SubRoom(
                    name: "Area B",
                    category: .other,
                    lengthIn: bottomHeight,
                    widthIn: widthIn,
                    heightIn: heightIn
                ))
            } else {
                // Line divides room left/right
                let splitRatio = (line.startPoint.x + line.endPoint.x) / 2

                let leftWidth = widthIn * splitRatio
                let rightWidth = widthIn * (1 - splitRatio)

                generatedSubRooms.append(SubRoom(
                    name: "Area A",
                    category: .other,
                    lengthIn: lengthIn,
                    widthIn: leftWidth,
                    heightIn: heightIn
                ))
                generatedSubRooms.append(SubRoom(
                    name: "Area B",
                    category: .other,
                    lengthIn: lengthIn,
                    widthIn: rightWidth,
                    heightIn: heightIn
                ))
            }
        } else {
            // Multiple lines: create approximate regions based on number of lines
            // This is a simplified calculation - real implementation would use polygon intersection
            let numRegions = lines.count + 1
            let avgLength = lengthIn / Double(numRegions)

            for i in 0..<numRegions {
                generatedSubRooms.append(SubRoom(
                    name: "Area \(Character(UnicodeScalar(65 + i)!))",  // A, B, C, etc.
                    category: .other,
                    lengthIn: avgLength,
                    widthIn: widthIn,
                    heightIn: heightIn
                ))
            }
        }

        subRooms = generatedSubRooms
    }

    // P3-013: Get total area of all sub-rooms (should match parent room area)
    var totalSubRoomSquareFeet: Double {
        subRooms?.reduce(0) { $0 + $1.squareFeet } ?? 0
    }
    
    private func formatFeetInches(_ inches: Double) -> String {
        let feet = Int(inches) / 12
        let remaining = Int(inches) % 12
        return remaining == 0 ? "\(feet)'" : "\(feet)'\(remaining)\""
    }
    
    @available(iOS 16.0, *)
    static func calculateBounds(from room: CapturedRoom) -> (length: Double, width: Double, height: Double) {
        guard !room.walls.isEmpty else {
            return (120, 120, 96)
        }
        
        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        var totalHeight: Double = 0
        
        for wall in room.walls {
            let position = wall.transform.columns.3
            let dimensions = wall.dimensions
            
            let x = Double(position.x)
            let z = Double(position.z)
            let halfLength = Double(dimensions.x) / 2
            
            minX = min(minX, x - halfLength)
            maxX = max(maxX, x + halfLength)
            minZ = min(minZ, z - halfLength)
            maxZ = max(maxZ, z + halfLength)
            
            totalHeight += Double(dimensions.y)
        }
        
        let avgHeight = totalHeight / Double(room.walls.count)
        
        return (
            length: max((maxX - minX) * 39.3701, 36),
            width: max((maxZ - minZ) * 39.3701, 36),
            height: max(avgHeight * 39.3701, 72)
        )
    }
    
    @available(iOS 16.0, *)
    static func detectCategory(from room: CapturedRoom) -> RoomCategory {
        for object in room.objects {
            switch object.category {
            case .toilet, .bathtub, .sink:
                return .bathroom
            case .oven, .refrigerator, .dishwasher:
                return .kitchen
            case .bed:
                return .bedroom
            case .sofa:
                return .livingRoom
            case .washerDryer:
                return .laundry
            default:
                break
            }
        }
        return .other
    }
}

enum RoomCategory: String, Codable, CaseIterable {
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case bedroom = "Bedroom"
    case livingRoom = "Living Room"
    case diningRoom = "Dining Room"
    case office = "Office"
    case laundry = "Laundry"
    case garage = "Garage"
    case basement = "Basement"
    case hallway = "Hallway"
    case closet = "Closet"
    case other = "Other"

    var icon: String {
        switch self {
        case .kitchen: return "refrigerator"
        case .bathroom: return "shower"
        case .bedroom: return "bed.double"
        case .livingRoom: return "sofa"
        case .diningRoom: return "fork.knife"
        case .office: return "desktopcomputer"
        case .laundry: return "washer"
        case .garage: return "car"
        case .basement: return "stairs"
        case .hallway: return "arrow.left.and.right"
        case .closet: return "door.sliding.left.hand.closed"
        case .other: return "square.dashed"
        }
    }
}

// P3-001: Floor level enum for organizing rooms by building level
enum FloorLevel: String, Codable, CaseIterable {
    case basement = "Basement"
    case first = "1"
    case second = "2"
    case third = "3"
    case attic = "Attic"

    var displayName: String {
        switch self {
        case .basement: return "Basement"
        case .first: return "1st Floor"
        case .second: return "2nd Floor"
        case .third: return "3rd Floor"
        case .attic: return "Attic"
        }
    }

    var shortName: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .basement: return "arrow.down.to.line"
        case .first: return "1.circle"
        case .second: return "2.circle"
        case .third: return "3.circle"
        case .attic: return "arrow.up.to.line"
        }
    }
}

// P3-002: Floor material enum for tagging floor surface types
enum FloorMaterial: String, Codable, CaseIterable {
    case lvp = "LVP"
    case carpet = "Carpet"
    case tile = "Tile"
    case hardwood = "Hardwood"
    case laminate = "Laminate"
    case concrete = "Concrete"
    case vinyl = "Vinyl"
    case other = "Other"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .lvp: return "square.grid.3x3"
        case .carpet: return "rectangle.fill"
        case .tile: return "square.grid.2x2"
        case .hardwood: return "line.3.horizontal"
        case .laminate: return "rectangle.split.3x1"
        case .concrete: return "square.fill"
        case .vinyl: return "square"
        case .other: return "questionmark.square"
        }
    }

    /// Xactimate selector codes for scope generation
    var xactCodes: [String] {
        switch self {
        case .lvp: return ["FLRLVP", "FLRLVPREM"]
        case .carpet: return ["FLRCPT", "FLRCPTREM", "FLRCPTPAD"]
        case .tile: return ["FLRTILE", "FLRTILEREM"]
        case .hardwood: return ["FLRHDWD", "FLRHDWDREF", "FLRHDWDREM"]
        case .laminate: return ["FLRLAM", "FLRLAMREM"]
        case .concrete: return ["FLRCONC"]
        case .vinyl: return ["FLRVNYL", "FLRVNYLREM"]
        case .other: return ["FLR"]
        }
    }

    /// Description for PM reference
    var description: String {
        switch self {
        case .lvp: return "Luxury Vinyl Plank - click-lock floating floor"
        case .carpet: return "Wall-to-wall carpet with pad"
        case .tile: return "Ceramic or porcelain tile"
        case .hardwood: return "Solid or engineered hardwood"
        case .laminate: return "Laminate floating floor"
        case .concrete: return "Exposed or sealed concrete"
        case .vinyl: return "Sheet vinyl or vinyl tile"
        case .other: return "Other flooring type"
        }
    }

    /// Color swatch for visual identification
    var swatchColor: Color {
        switch self {
        case .lvp: return Color(red: 0.6, green: 0.5, blue: 0.4)
        case .carpet: return Color(red: 0.5, green: 0.5, blue: 0.55)
        case .tile: return Color(red: 0.85, green: 0.82, blue: 0.78)
        case .hardwood: return Color(red: 0.55, green: 0.35, blue: 0.2)
        case .laminate: return Color(red: 0.7, green: 0.55, blue: 0.4)
        case .concrete: return Color(red: 0.6, green: 0.6, blue: 0.6)
        case .vinyl: return Color(red: 0.75, green: 0.7, blue: 0.65)
        case .other: return Color.gray
        }
    }
}

// P3-003: Wall material enum for tagging wall finish types
enum WallMaterial: String, Codable, CaseIterable {
    case smooth = "Smooth"
    case orangePeel = "Orange Peel"
    case knockdown = "Knockdown"
    case heavyTexture = "Heavy Texture"
    case paneling = "Paneling"
    case wallpaper = "Wallpaper"
    case other = "Other"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .smooth: return "rectangle"
        case .orangePeel: return "circle.dotted"
        case .knockdown: return "waveform"
        case .heavyTexture: return "waveform.path"
        case .paneling: return "rectangle.split.3x1"
        case .wallpaper: return "photo"
        case .other: return "questionmark.square"
        }
    }

    /// Xactimate selector codes for scope generation
    var xactCodes: [String] {
        switch self {
        case .smooth: return ["DRYWSM", "PNTSM"]
        case .orangePeel: return ["DRYWOP", "PNTOP"]
        case .knockdown: return ["DRYWKD", "PNTKD"]
        case .heavyTexture: return ["DRYWHVY", "PNTHVY"]
        case .paneling: return ["PANL", "PANLREM"]
        case .wallpaper: return ["WLPR", "WLPRREM"]
        case .other: return ["DRYW"]
        }
    }

    /// Description for PM reference
    var description: String {
        switch self {
        case .smooth: return "Level 5 smooth finish drywall"
        case .orangePeel: return "Light spray texture (most common in BC)"
        case .knockdown: return "Sprayed and knocked down texture"
        case .heavyTexture: return "Heavy hand or spray texture"
        case .paneling: return "Wood or composite paneling"
        case .wallpaper: return "Wallpaper or wall covering"
        case .other: return "Other wall finish"
        }
    }

    /// Color swatch for visual identification
    var swatchColor: Color {
        switch self {
        case .smooth: return Color(red: 0.95, green: 0.95, blue: 0.93)
        case .orangePeel: return Color(red: 0.92, green: 0.9, blue: 0.87)
        case .knockdown: return Color(red: 0.88, green: 0.86, blue: 0.83)
        case .heavyTexture: return Color(red: 0.85, green: 0.82, blue: 0.78)
        case .paneling: return Color(red: 0.5, green: 0.35, blue: 0.25)
        case .wallpaper: return Color(red: 0.7, green: 0.75, blue: 0.8)
        case .other: return Color.gray
        }
    }
}

// P3-004: Ceiling material enum for tagging ceiling types
enum CeilingMaterial: String, Codable, CaseIterable {
    case smoothDrywall = "Smooth Drywall"
    case popcorn = "Popcorn"
    case tBar = "T-bar/Drop"
    case textured = "Textured"
    case exposed = "Exposed"
    case other = "Other"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .smoothDrywall: return "rectangle"
        case .popcorn: return "circle.dotted"
        case .tBar: return "square.grid.3x1.below.line.grid.1x2"
        case .textured: return "waveform"
        case .exposed: return "lines.measurement.horizontal"
        case .other: return "questionmark.square"
        }
    }

    /// Xactimate selector codes for scope generation
    var xactCodes: [String] {
        switch self {
        case .smoothDrywall: return ["CLGSM", "PNTCLGSM"]
        case .popcorn: return ["CLGPOP", "CLGPOPREM", "PNTCLGPOP"]
        case .tBar: return ["CLGTBAR", "CLGTBARREM"]
        case .textured: return ["CLGTEX", "PNTCLGTEX"]
        case .exposed: return ["CLG"]
        case .other: return ["CLG"]
        }
    }

    /// Description for PM reference
    var description: String {
        switch self {
        case .smoothDrywall: return "Flat painted drywall ceiling"
        case .popcorn: return "Acoustic popcorn/cottage cheese texture"
        case .tBar: return "Suspended grid with drop-in tiles"
        case .textured: return "Spray or hand-applied texture"
        case .exposed: return "Exposed joists or rafters"
        case .other: return "Other ceiling type"
        }
    }

    /// Color swatch for visual identification
    var swatchColor: Color {
        switch self {
        case .smoothDrywall: return Color(red: 0.98, green: 0.98, blue: 0.96)
        case .popcorn: return Color(red: 0.92, green: 0.92, blue: 0.88)
        case .tBar: return Color(red: 0.85, green: 0.85, blue: 0.85)
        case .textured: return Color(red: 0.94, green: 0.92, blue: 0.88)
        case .exposed: return Color(red: 0.45, green: 0.35, blue: 0.25)
        case .other: return Color.gray
        }
    }
}

// MARK: - PM Material Preferences

/// Stores PM's favorite/default materials for quick selection
class MaterialPreferences: ObservableObject {
    static let shared = MaterialPreferences()

    @Published var favoriteFloorMaterials: [FloorMaterial] {
        didSet { save() }
    }
    @Published var favoriteWallMaterials: [WallMaterial] {
        didSet { save() }
    }
    @Published var favoriteCeilingMaterials: [CeilingMaterial] {
        didSet { save() }
    }

    /// Default materials for new rooms (BC common defaults)
    @Published var defaultFloorMaterial: FloorMaterial {
        didSet { save() }
    }
    @Published var defaultWallMaterial: WallMaterial {
        didSet { save() }
    }
    @Published var defaultCeilingMaterial: CeilingMaterial {
        didSet { save() }
    }

    private let userDefaults = UserDefaults.standard
    private let favFloorKey = "favFloorMaterials"
    private let favWallKey = "favWallMaterials"
    private let favCeilingKey = "favCeilingMaterials"
    private let defFloorKey = "defaultFloorMaterial"
    private let defWallKey = "defaultWallMaterial"
    private let defCeilingKey = "defaultCeilingMaterial"

    private init() {
        // BC common defaults - most homes have these
        let bcDefaultFloor: [FloorMaterial] = [.lvp, .carpet, .laminate, .tile]
        let bcDefaultWall: [WallMaterial] = [.orangePeel, .knockdown, .smooth]
        let bcDefaultCeiling: [CeilingMaterial] = [.smoothDrywall, .textured, .popcorn]

        // Load favorites or use BC defaults
        if let floorRaws = userDefaults.array(forKey: favFloorKey) as? [String] {
            self.favoriteFloorMaterials = floorRaws.compactMap { FloorMaterial(rawValue: $0) }
        } else {
            self.favoriteFloorMaterials = bcDefaultFloor
        }

        if let wallRaws = userDefaults.array(forKey: favWallKey) as? [String] {
            self.favoriteWallMaterials = wallRaws.compactMap { WallMaterial(rawValue: $0) }
        } else {
            self.favoriteWallMaterials = bcDefaultWall
        }

        if let ceilingRaws = userDefaults.array(forKey: favCeilingKey) as? [String] {
            self.favoriteCeilingMaterials = ceilingRaws.compactMap { CeilingMaterial(rawValue: $0) }
        } else {
            self.favoriteCeilingMaterials = bcDefaultCeiling
        }

        // Load defaults
        if let floorRaw = userDefaults.string(forKey: defFloorKey),
           let floor = FloorMaterial(rawValue: floorRaw) {
            self.defaultFloorMaterial = floor
        } else {
            self.defaultFloorMaterial = .lvp  // Most common in BC new builds
        }

        if let wallRaw = userDefaults.string(forKey: defWallKey),
           let wall = WallMaterial(rawValue: wallRaw) {
            self.defaultWallMaterial = wall
        } else {
            self.defaultWallMaterial = .orangePeel  // Most common in BC
        }

        if let ceilingRaw = userDefaults.string(forKey: defCeilingKey),
           let ceiling = CeilingMaterial(rawValue: ceilingRaw) {
            self.defaultCeilingMaterial = ceiling
        } else {
            self.defaultCeilingMaterial = .smoothDrywall
        }
    }

    private func save() {
        userDefaults.set(favoriteFloorMaterials.map { $0.rawValue }, forKey: favFloorKey)
        userDefaults.set(favoriteWallMaterials.map { $0.rawValue }, forKey: favWallKey)
        userDefaults.set(favoriteCeilingMaterials.map { $0.rawValue }, forKey: favCeilingKey)
        userDefaults.set(defaultFloorMaterial.rawValue, forKey: defFloorKey)
        userDefaults.set(defaultWallMaterial.rawValue, forKey: defWallKey)
        userDefaults.set(defaultCeilingMaterial.rawValue, forKey: defCeilingKey)
    }

    /// Toggle a floor material as favorite
    func toggleFavorite(_ material: FloorMaterial) {
        if favoriteFloorMaterials.contains(material) {
            favoriteFloorMaterials.removeAll { $0 == material }
        } else {
            favoriteFloorMaterials.append(material)
        }
    }

    /// Toggle a wall material as favorite
    func toggleFavorite(_ material: WallMaterial) {
        if favoriteWallMaterials.contains(material) {
            favoriteWallMaterials.removeAll { $0 == material }
        } else {
            favoriteWallMaterials.append(material)
        }
    }

    /// Toggle a ceiling material as favorite
    func toggleFavorite(_ material: CeilingMaterial) {
        if favoriteCeilingMaterials.contains(material) {
            favoriteCeilingMaterials.removeAll { $0 == material }
        } else {
            favoriteCeilingMaterials.append(material)
        }
    }

    /// Reset to BC defaults
    func resetToDefaults() {
        favoriteFloorMaterials = [.lvp, .carpet, .laminate, .tile]
        favoriteWallMaterials = [.orangePeel, .knockdown, .smooth]
        favoriteCeilingMaterials = [.smoothDrywall, .textured, .popcorn]
        defaultFloorMaterial = .lvp
        defaultWallMaterial = .orangePeel
        defaultCeilingMaterial = .smoothDrywall
    }
}

// MARK: - Estimate Store
class EstimateStore: ObservableObject {
    @Published var estimates: [Estimate] = []
    @Published var currentEstimate: Estimate?
    @Published var showingDeleteConfirmation = false

    private let saveKey = "savedEstimates"
    
    init() {
        loadEstimates()
    }
    
    func addEstimate(_ estimate: Estimate) {
        // Prevent duplicates - check if estimate with same ID already exists
        if let existingIndex = estimates.firstIndex(where: { $0.id == estimate.id }) {
            // Update existing instead of adding duplicate
            estimates[existingIndex] = estimate
        } else {
            estimates.insert(estimate, at: 0)
        }
        saveEstimates()
    }
    
    func deleteEstimates(at offsets: IndexSet) {
        estimates.remove(atOffsets: offsets)
        saveEstimates()
    }

    func deleteCurrentEstimate() {
        guard let current = currentEstimate,
              let index = estimates.firstIndex(where: { $0.id == current.id }) else { return }
        estimates.remove(at: index)
        currentEstimate = nil
        saveEstimates()
    }

    @available(iOS 16.0, *)
    func addRoom(_ capturedRoom: CapturedRoom) {
        guard var estimate = currentEstimate,
              let index = estimates.firstIndex(where: { $0.id == estimate.id }) else { return }
        
        let room = Room(from: capturedRoom)
        estimate.rooms.append(room)
        estimate.status = .inProgress
        
        estimates[index] = estimate
        currentEstimate = estimate
        saveEstimates()
    }
    
    func addRoomDirect(_ room: Room) {
        guard var estimate = currentEstimate,
              let index = estimates.firstIndex(where: { $0.id == estimate.id }) else { return }

        estimate.rooms.append(room)
        estimate.status = .inProgress
        estimate.updatedAt = Date()

        estimates[index] = estimate
        currentEstimate = estimate
        saveEstimates()
    }

    func deleteRoom(_ roomId: UUID, from estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        estimates[index].rooms.removeAll { $0.id == roomId }
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }
    
    func updateRoom(_ roomId: UUID, in estimateId: UUID, name: String, category: RoomCategory, floor: FloorLevel? = nil, floorMaterial: FloorMaterial? = nil, wallMaterial: WallMaterial? = nil, ceilingMaterial: CeilingMaterial? = nil) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let roomIndex = estimates[estIndex].rooms.firstIndex(where: { $0.id == roomId }) else { return }

        estimates[estIndex].rooms[roomIndex].name = name
        estimates[estIndex].rooms[roomIndex].category = category
        if let floor = floor {
            estimates[estIndex].rooms[roomIndex].floor = floor
        }
        // P3-002/003/004: Update materials
        if let floorMat = floorMaterial {
            estimates[estIndex].rooms[roomIndex].floorMaterial = floorMat
        }
        if let wallMat = wallMaterial {
            estimates[estIndex].rooms[roomIndex].wallMaterial = wallMat
        }
        if let ceilingMat = ceilingMaterial {
            estimates[estIndex].rooms[roomIndex].ceilingMaterial = ceilingMat
        }

        markModified(estimateId)
        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    // P3-001: Update room floor level
    func updateRoomFloor(_ roomId: UUID, in estimateId: UUID, floor: FloorLevel) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let roomIndex = estimates[estIndex].rooms.firstIndex(where: { $0.id == roomId }) else { return }

        estimates[estIndex].rooms[roomIndex].floor = floor
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    // P3-002/003/004: Update room materials
    func updateRoomMaterials(_ roomId: UUID, in estimateId: UUID, floorMaterial: FloorMaterial, wallMaterial: WallMaterial, ceilingMaterial: CeilingMaterial) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let roomIndex = estimates[estIndex].rooms.firstIndex(where: { $0.id == roomId }) else { return }

        estimates[estIndex].rooms[roomIndex].floorMaterial = floorMaterial
        estimates[estIndex].rooms[roomIndex].wallMaterial = wallMaterial
        estimates[estIndex].rooms[roomIndex].ceilingMaterial = ceilingMaterial
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    // P3-007: Add damage annotation to room
    func addAnnotation(_ annotation: DamageAnnotation, to roomId: UUID, in estimateId: UUID) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let roomIndex = estimates[estIndex].rooms.firstIndex(where: { $0.id == roomId }) else { return }

        estimates[estIndex].rooms[roomIndex].annotations.append(annotation)
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    // P3-008: Delete damage annotation from room
    func deleteAnnotation(_ annotationId: UUID, from roomId: UUID, in estimateId: UUID) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let roomIndex = estimates[estIndex].rooms.firstIndex(where: { $0.id == roomId }) else { return }

        estimates[estIndex].rooms[roomIndex].annotations.removeAll { $0.id == annotationId }
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    // MARK: - Line Item Management

    /// Add a line item to an estimate
    func addLineItem(_ item: ScopeLineItem, to estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        estimates[index].lineItems.append(item)
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }

    /// Delete a line item from an estimate
    func deleteLineItem(_ itemId: UUID, from estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        estimates[index].lineItems.removeAll { $0.id == itemId }
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }

    /// Set line item to validating state
    func setLineItemValidating(_ itemId: UUID, in estimateId: UUID) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let itemIndex = estimates[estIndex].lineItems.firstIndex(where: { $0.id == itemId }) else { return }

        estimates[estIndex].lineItems[itemIndex].validationState = .validating

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        // Don't save for intermediate state
    }

    /// Set line item to pending state
    func setLineItemPending(_ itemId: UUID, in estimateId: UUID) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let itemIndex = estimates[estIndex].lineItems.firstIndex(where: { $0.id == itemId }) else { return }

        estimates[estIndex].lineItems[itemIndex].validationState = .pending

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    /// Update line item validation state with results from API
    func updateLineItemValidation(
        selector: String,
        in estimateId: UUID,
        isValid: Bool,
        priceInfo: PriceInfo?,
        suggestions: [SuggestionInfo]
    ) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let itemIndex = estimates[estIndex].lineItems.firstIndex(where: { $0.selector == selector }) else { return }

        estimates[estIndex].lineItems[itemIndex].validationState = isValid ? .valid : .invalid

        if let price = priceInfo {
            estimates[estIndex].lineItems[itemIndex].unitPrice = price.totalRate
        }

        estimates[estIndex].lineItems[itemIndex].suggestions = suggestions.map { info in
            SelectorSuggestion(from: info)
        }

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    /// Replace a line item's selector with a suggested replacement
    func replaceLineItemSelector(
        _ itemId: UUID,
        in estimateId: UUID,
        newSelector: String,
        newCategory: String,
        newDescription: String,
        newUnit: String,
        newUnitPrice: Double
    ) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let itemIndex = estimates[estIndex].lineItems.firstIndex(where: { $0.id == itemId }) else { return }

        estimates[estIndex].lineItems[itemIndex].selector = newSelector
        estimates[estIndex].lineItems[itemIndex].category = newCategory
        estimates[estIndex].lineItems[itemIndex].description = newDescription
        estimates[estIndex].lineItems[itemIndex].unit = newUnit
        estimates[estIndex].lineItems[itemIndex].unitPrice = newUnitPrice
        estimates[estIndex].lineItems[itemIndex].validationState = .valid
        estimates[estIndex].lineItems[itemIndex].suggestions = []
        estimates[estIndex].lineItems[itemIndex].updatedAt = Date()

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    func markSynced(_ estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        estimates[index].status = .synced
        estimates[index].syncedAt = Date()

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }

    /// Update estimate from server data (full replacement)
    func updateEstimateFromServer(_ estimate: Estimate) {
        if let index = estimates.firstIndex(where: { $0.id == estimate.id }) {
            estimates[index] = estimate
            estimates[index].syncedAt = Date()
            if currentEstimate?.id == estimate.id {
                currentEstimate = estimates[index]
            }
        }
        saveEstimates()
    }

    // MARK: - Assignment Management

    /// Add an assignment to an estimate
    func addAssignment(type: AssignmentType, to estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        let assignment = Assignment(
            estimateId: estimateId,
            type: type,
            order: type.defaultOrder
        )

        estimates[index].assignments.append(assignment)
        estimates[index].assignments.sort { $0.order < $1.order }
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }

    /// Update assignment status
    func updateAssignmentStatus(_ assignmentId: UUID, in estimateId: UUID, status: AssignmentStatus) {
        guard let estIndex = estimates.firstIndex(where: { $0.id == estimateId }),
              let assIndex = estimates[estIndex].assignments.firstIndex(where: { $0.id == assignmentId }) else { return }

        estimates[estIndex].assignments[assIndex].status = status
        estimates[estIndex].assignments[assIndex].updatedAt = Date()
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[estIndex]
        }
        saveEstimates()
    }

    /// Delete assignment from estimate
    func deleteAssignment(_ assignmentId: UUID, from estimateId: UUID) {
        guard let index = estimates.firstIndex(where: { $0.id == estimateId }) else { return }

        estimates[index].assignments.removeAll { $0.id == assignmentId }
        markModified(estimateId)

        if currentEstimate?.id == estimateId {
            currentEstimate = estimates[index]
        }
        saveEstimates()
    }

    /// Create estimate from dispatch email data
    func createFromDispatch(_ claimData: ClaimData) {
        // Create assignments based on selected types
        var assignments: [Assignment] = []
        let estimateId = UUID()

        for (index, type) in claimData.assignmentTypes.enumerated() {
            let assignment = Assignment(
                estimateId: estimateId,
                type: type,
                order: index
            )
            assignments.append(assignment)
        }

        let estimate = Estimate(
            id: estimateId,
            name: claimData.displayName,
            claimNumber: claimData.claimNumber,
            insuredName: claimData.insuredName,
            insuredPhone: claimData.insuredPhone,
            insuredEmail: claimData.insuredEmail,
            propertyAddress: claimData.propertyAddress,
            propertyCity: claimData.propertyCity,
            propertyState: claimData.propertyState,
            propertyZip: claimData.propertyZip,
            causeOfLoss: claimData.lossType.shortName,
            assignments: assignments,
            jobType: claimData.jobType,
            xaId: claimData.xaId,
            dateOfLoss: claimData.dateOfLoss,
            adjusterName: claimData.adjusterName,
            adjusterPhone: claimData.adjusterPhone,
            adjusterEmail: claimData.adjusterEmail,
            insuranceCompany: claimData.insuranceCompany
        )

        addEstimate(estimate)
        currentEstimate = estimate
    }

    private func saveEstimates() {
        if let encoded = try? JSONEncoder().encode(estimates) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    /// Mark an estimate as modified (updates updatedAt timestamp)
    private func markModified(_ estimateId: UUID) {
        if let index = estimates.firstIndex(where: { $0.id == estimateId }) {
            estimates[index].updatedAt = Date()
        }
    }

    private func loadEstimates() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Estimate].self, from: data) {
            estimates = decoded
        }
    }
}

// MARK: - Room Capture
@available(iOS 16.0, *)
struct RoomCaptureViewRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onRoomCaptured: (CapturedRoom) -> Void
    
    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onRoomCaptured: onRoomCaptured)
    }
    
    class Coordinator: NSObject, RoomCaptureViewControllerDelegate {
        @Binding var isPresented: Bool
        let onRoomCaptured: (CapturedRoom) -> Void
        
        init(isPresented: Binding<Bool>, onRoomCaptured: @escaping (CapturedRoom) -> Void) {
            _isPresented = isPresented
            self.onRoomCaptured = onRoomCaptured
        }
        
        func roomCaptureViewController(_ controller: RoomCaptureViewController, didFinishWith room: CapturedRoom) {
            onRoomCaptured(room)
            isPresented = false
        }
        
        func roomCaptureViewControllerDidCancel(_ controller: RoomCaptureViewController) {
            isPresented = false
        }
    }
}

@available(iOS 16.0, *)
class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    var delegate: RoomCaptureViewControllerDelegate?
    private var roomCaptureView: RoomCaptureView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.delegate = self
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(roomCaptureView)
        
        setupButtons()
        
        let config = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: config)
    }
    
    private func setupButtons() {
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        let cancelButton = UIButton(type: .system)
        var cancelConfig = UIButton.Configuration.filled()
        cancelConfig.title = "Cancel"
        cancelConfig.baseBackgroundColor = UIColor.systemGray5
        cancelConfig.baseForegroundColor = UIColor.label
        cancelConfig.cornerStyle = .medium
        cancelConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        let doneButton = UIButton(type: .system)
        var doneConfig = UIButton.Configuration.filled()
        doneConfig.title = "Done"
        doneConfig.baseBackgroundColor = .systemBlue
        doneConfig.baseForegroundColor = .white
        doneConfig.cornerStyle = .medium
        doneConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        doneButton.configuration = doneConfig
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(doneButton)
        view.addSubview(buttonStack)
        
        NSLayoutConstraint.activate([
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    @objc func cancelTapped() {
        roomCaptureView.captureSession.stop()
        delegate?.roomCaptureViewControllerDidCancel(self)
    }
    
    @objc func doneTapped() {
        roomCaptureView.captureSession.stop()
    }
    
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        delegate?.roomCaptureViewController(self, didFinishWith: processedResult)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        roomCaptureView.captureSession.stop()
    }
}

@available(iOS 16.0, *)
protocol RoomCaptureViewControllerDelegate: AnyObject {
    func roomCaptureViewController(_ controller: RoomCaptureViewController, didFinishWith room: CapturedRoom)
    func roomCaptureViewControllerDidCancel(_ controller: RoomCaptureViewController)
}

// MARK: - 3D Room Review View
@available(iOS 16.0, *)
struct RoomReviewView: View {
    let capturedRoom: CapturedRoom
    let onSave: (Room) -> Void
    let onCancel: () -> Void

    @State private var roomName: String = ""
    @State private var roomCategory: RoomCategory = .other
    @State private var showingSaveSheet = false
    @State private var viewMode: ViewMode = .floorPlan
    @State private var annotations: [DamageAnnotation] = []
    @State private var showingDamageAssistant = false
    @State private var generatedLineItems: [GeneratedLineItem] = []
    @State private var showingWalkthroughCapture = false
    @State private var walkthroughResult: WalkthroughResult?

    enum ViewMode: String, CaseIterable {
        case floorPlan = "Floor Plan"
        case isometric = "3D View"
        case stats = "Stats"
    }

    init(capturedRoom: CapturedRoom, onSave: @escaping (Room) -> Void, onCancel: @escaping () -> Void) {
        self.capturedRoom = capturedRoom
        self.onSave = onSave
        self.onCancel = onCancel
        print("🔍 RoomReviewView initialized with room:")
        print("   - Walls: \(capturedRoom.walls.count)")
        print("   - Doors: \(capturedRoom.doors.count)")
        print("   - Windows: \(capturedRoom.windows.count)")
        print("   - Objects: \(capturedRoom.objects.count)")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Main content area
                ZStack {
                    switch viewMode {
                    case .floorPlan:
                        FloorPlanView(capturedRoom: capturedRoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .isometric:
                        IsometricRoomView(
                            capturedRoom: capturedRoom,
                            annotations: annotations,
                            onSurfaceTapped: { hit in
                                // Could show annotation options
                                print("Tapped: \(hit.surfaceType.rawValue) at \(hit.normalizedPosition)")
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .stats:
                        RoomStatsView(capturedRoom: capturedRoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Bottom Info Panel
                VStack(spacing: 16) {
                    // Quick Stats
                    HStack(spacing: 20) {
                        QuickStat(
                            icon: "cube",
                            label: "Walls",
                            value: "\(capturedRoom.walls.count)"
                        )
                        QuickStat(
                            icon: "door.left.hand.closed",
                            label: "Doors",
                            value: "\(capturedRoom.doors.count)"
                        )
                        QuickStat(
                            icon: "window.horizontal",
                            label: "Windows",
                            value: "\(capturedRoom.windows.count)"
                        )
                        QuickStat(
                            icon: "exclamationmark.triangle",
                            label: "Damage",
                            value: "\(annotations.count)"
                        )
                    }
                    .padding(.horizontal)

                    Divider()

                    // Damage Assistant Button (new)
                    Button(action: { showingDamageAssistant = true }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Document Damage with AI Assistant")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Video Walkthrough Button (US-RC-006)
                    Button(action: { showingWalkthroughCapture = true }) {
                        HStack {
                            Image(systemName: "video.badge.waveform")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Video Walkthrough")
                                if let result = walkthroughResult {
                                    Text("\(result.transitions.count) transitions detected")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Optional - helps identify room boundaries")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if walkthroughResult != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .padding()
                        .background(walkthroughResult != nil ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .foregroundColor(walkthroughResult != nil ? .green : .orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Detected Objects List
                    if !capturedRoom.objects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(capturedRoom.objects.enumerated()), id: \.offset) { index, object in
                                    DetectedObjectBadge(object: object)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: onCancel) {
                            Text("Discard")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }

                        Button(action: { showingSaveSheet = true }) {
                            Text("Save Room")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
            }
            .navigationTitle("Review Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveRoomSheet(
                capturedRoom: capturedRoom,
                annotations: annotations,
                generatedLineItems: generatedLineItems,
                walkthroughResult: walkthroughResult,
                onSave: { room in
                    onSave(room)
                    showingSaveSheet = false
                },
                onCancel: { showingSaveSheet = false }
            )
        }
        .fullScreenCover(isPresented: $showingDamageAssistant) {
            NavigationStack {
                DamageAnnotationAssistant(
                    capturedRoom: capturedRoom,
                    roomGeometry: buildRoomGeometry(),
                    annotations: $annotations,
                    onLineItemsGenerated: { items in
                        generatedLineItems = items.map { suggested in
                            GeneratedLineItem(
                                category: suggested.selector.prefix(3).uppercased(),
                                selector: suggested.selector,
                                description: suggested.description,
                                quantity: suggested.quantity,
                                unit: suggested.unit,
                                notes: "",
                                confidence: suggested.confidence,
                                source: .aiGenerated
                            )
                        }
                    }
                )
                .navigationTitle("Damage Documentation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDamageAssistant = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingWalkthroughCapture) {
            VideoWalkthroughView(
                onComplete: { result in
                    walkthroughResult = result
                    showingWalkthroughCapture = false
                },
                onCancel: {
                    showingWalkthroughCapture = false
                }
            )
        }
    }

    private func buildRoomGeometry() -> RoomGeometryData {
        let bounds = Room.calculateBounds(from: capturedRoom)

        var walls: [RoomGeometryData.WallData] = []
        for (index, wall) in capturedRoom.walls.enumerated() {
            walls.append(RoomGeometryData.WallData(
                lengthFt: Double(wall.dimensions.x) * 3.28084,
                heightFt: Double(wall.dimensions.y) * 3.28084,
                positionDescription: "Wall \(index + 1)"
            ))
        }

        var doors: [RoomGeometryData.DoorData] = []
        for door in capturedRoom.doors {
            doors.append(RoomGeometryData.DoorData(
                widthFt: Double(door.dimensions.x) * 3.28084,
                heightFt: Double(door.dimensions.y) * 3.28084,
                wallPosition: "interior"
            ))
        }

        var windows: [RoomGeometryData.WindowData] = []
        for window in capturedRoom.windows {
            windows.append(RoomGeometryData.WindowData(
                widthFt: Double(window.dimensions.x) * 3.28084,
                heightFt: Double(window.dimensions.y) * 3.28084,
                wallPosition: "exterior"
            ))
        }

        return RoomGeometryData(
            category: Room.detectCategory(from: capturedRoom).rawValue,
            lengthFt: bounds.length / 12,
            widthFt: bounds.width / 12,
            heightFt: bounds.height / 12,
            squareFeet: (bounds.length * bounds.width) / 144,
            isRectangular: capturedRoom.walls.count == 4,
            walls: walls,
            doors: doors,
            windows: windows,
            objects: [],
            floorMaterial: nil,
            wallMaterial: nil,
            ceilingMaterial: nil
        )
    }
}

struct QuickStat: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetectedObjectBadge: View {
    let object: CapturedRoom.Object
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: objectIcon)
                .foregroundColor(.blue)
            Text(objectName)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    var objectIcon: String {
        switch object.category {
        case .storage: return "cabinet"
        case .refrigerator: return "refrigerator"
        case .stove: return "flame"
        case .bed: return "bed.double"
        case .sink: return "sink"
        case .washerDryer: return "washer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table.furniture"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "tv"
        case .stairs: return "stairs"
        @unknown default: return "cube.box"
        }
    }
    
    var objectName: String {
        switch object.category {
        case .storage: return "Cabinet"
        case .refrigerator: return "Refrigerator"
        case .stove: return "Stove"
        case .bed: return "Bed"
        case .sink: return "Sink"
        case .washerDryer: return "Washer/Dryer"
        case .toilet: return "Toilet"
        case .bathtub: return "Bathtub"
        case .oven: return "Oven"
        case .dishwasher: return "Dishwasher"
        case .table: return "Table"
        case .sofa: return "Sofa"
        case .chair: return "Chair"
        case .fireplace: return "Fireplace"
        case .television: return "TV"
        case .stairs: return "Stairs"
        @unknown default: return "Object"
        }
    }
}

struct SaveRoomSheet: View {
    let capturedRoom: CapturedRoom
    var annotations: [DamageAnnotation] = []
    var generatedLineItems: [GeneratedLineItem] = []
    var walkthroughResult: WalkthroughResult? = nil
    let onSave: (Room) -> Void
    let onCancel: () -> Void

    @State private var roomName: String = ""
    @State private var roomCategory: RoomCategory = .other
    @State private var roomFloor: FloorLevel = .first  // P3-001
    @State private var floorMaterial: FloorMaterial = .other  // P3-002
    @State private var wallMaterial: WallMaterial = .smooth  // P3-003
    @State private var ceilingMaterial: CeilingMaterial = .smoothDrywall  // P3-004

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room Name", text: $roomName)

                    Picker("Category", selection: $roomCategory) {
                        ForEach(RoomCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }

                    // P3-001: Floor picker
                    Picker("Floor", selection: $roomFloor) {
                        ForEach(FloorLevel.allCases, id: \.self) { floor in
                            Label(floor.displayName, systemImage: floor.icon)
                                .tag(floor)
                        }
                    }
                }

                // P3-002/003/004: Material tagging section
                Section("Materials") {
                    Picker("Floor Material", selection: $floorMaterial) {
                        ForEach(FloorMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }

                    Picker("Wall Finish", selection: $wallMaterial) {
                        ForEach(WallMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }

                    Picker("Ceiling Type", selection: $ceilingMaterial) {
                        ForEach(CeilingMaterial.allCases, id: \.self) { mat in
                            Label(mat.displayName, systemImage: mat.icon).tag(mat)
                        }
                    }
                }

                Section("Dimensions") {
                    let bounds = Room.calculateBounds(from: capturedRoom)
                    let lengthFt = Int(bounds.length / 12)
                    let widthFt = Int(bounds.width / 12)
                    let heightFt = Int(bounds.height / 12)
                    let sf = Int((bounds.length * bounds.width) / 144)

                    LabeledContent("Length", value: "\(lengthFt)'")
                    LabeledContent("Width", value: "\(widthFt)'")
                    LabeledContent("Height", value: "\(heightFt)'")
                    LabeledContent("Square Feet", value: "\(sf) SF")
                }

                Section("Detected Features") {
                    LabeledContent("Walls", value: "\(capturedRoom.walls.count)")
                    LabeledContent("Doors", value: "\(capturedRoom.doors.count)")
                    LabeledContent("Windows", value: "\(capturedRoom.windows.count)")
                    LabeledContent("Objects", value: "\(capturedRoom.objects.count)")
                }

                // Show walkthrough data if captured
                if let walkthrough = walkthroughResult {
                    Section("Video Walkthrough") {
                        LabeledContent("Duration", value: VideoWalkthroughService.formatDuration(walkthrough.duration))
                        LabeledContent("Transitions", value: "\(walkthrough.transitions.count)")
                        LabeledContent("Est. Rooms", value: "\(walkthrough.potentialRoomCount)")
                        if !walkthrough.transitions.isEmpty {
                            ForEach(walkthrough.transitions.prefix(3)) { transition in
                                HStack {
                                    Circle()
                                        .fill(colorForTransitionType(transition.transitionType))
                                        .frame(width: 8, height: 8)
                                    Text(transition.transitionType.rawValue.capitalized)
                                        .font(.caption)
                                    Spacer()
                                    Text(String(format: "%.1fs", transition.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if walkthrough.transitions.count > 3 {
                                Text("+ \(walkthrough.transitions.count - 3) more transitions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Show damage annotations if any
                if !annotations.isEmpty {
                    Section("Damage Annotations (\(annotations.count))") {
                        ForEach(annotations) { annotation in
                            HStack {
                                Image(systemName: annotation.damageType.icon)
                                    .foregroundColor(annotation.damageType.color)
                                VStack(alignment: .leading) {
                                    Text(annotation.damageType.rawValue)
                                        .fontWeight(.medium)
                                    Text(annotation.affectedSurfaces.map { $0.rawValue }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(annotation.severity.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(annotation.severity.color.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Show generated line items if any
                if !generatedLineItems.isEmpty {
                    Section("AI-Generated Scope (\(generatedLineItems.count) items)") {
                        ForEach(generatedLineItems.prefix(5)) { item in
                            HStack {
                                Text(item.selector)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                VStack(alignment: .leading) {
                                    Text(item.description)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(Int(item.quantity)) \(item.unit)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if generatedLineItems.count > 5 {
                            Text("+ \(generatedLineItems.count - 5) more items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var room = Room(from: capturedRoom)
                        if !roomName.isEmpty {
                            room.name = roomName
                        }
                        room.category = roomCategory
                        room.floor = roomFloor  // P3-001
                        room.floorMaterial = floorMaterial  // P3-002
                        room.wallMaterial = wallMaterial  // P3-003
                        room.ceilingMaterial = ceilingMaterial  // P3-004
                        room.annotations = annotations  // Add annotations
                        onSave(room)
                    }
                }
            }
            .onAppear {
                // Auto-detect category and set default name
                roomCategory = Room.detectCategory(from: capturedRoom)
                roomName = roomCategory.rawValue
            }
        }
    }

    private func colorForTransitionType(_ type: WalkthroughTransition.TransitionType) -> Color {
        switch type {
        case .doorway: return .green
        case .opening: return .blue
        case .threshold: return .orange
        case .turnaround: return .purple
        case .unknown: return .gray
        }
    }
}

// MARK: - 2D Fallback Stats View
@available(iOS 16.0, *)
struct RoomStatsView: View {
    let capturedRoom: CapturedRoom
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                Text("Room Captured Successfully")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Dimensions
                let bounds = Room.calculateBounds(from: capturedRoom)
                let lengthFt = Int(bounds.length / 12)
                let widthFt = Int(bounds.width / 12)
                let heightFt = Int(bounds.height / 12)
                let sf = Int((bounds.length * bounds.width) / 144)
                
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        DimensionCard(label: "Length", value: "\(lengthFt)'")
                        DimensionCard(label: "Width", value: "\(widthFt)'")
                        DimensionCard(label: "Height", value: "\(heightFt)'")
                    }
                    
                    VStack(spacing: 8) {
                        Text("\(sf)")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Square Feet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
                .padding()
                
                // Features Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    FeatureCard(icon: "rectangle.split.3x1", 
                               label: "Walls", 
                               value: "\(capturedRoom.walls.count)")
                    FeatureCard(icon: "door.left.hand.closed", 
                               label: "Doors", 
                               value: "\(capturedRoom.doors.count)")
                    FeatureCard(icon: "window.horizontal", 
                               label: "Windows", 
                               value: "\(capturedRoom.windows.count)")
                    FeatureCard(icon: "cube.box", 
                               label: "Objects", 
                               value: "\(capturedRoom.objects.count)")
                }
                .padding(.horizontal)
                
                // Detected Objects
                if !capturedRoom.objects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detected Objects")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        ForEach(Array(capturedRoom.objects.enumerated()), id: \.offset) { index, object in
                            DetectedObjectRow(object: object)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct DimensionCard: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 36, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct FeatureCard: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.blue)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct DetectedObjectRow: View {
    let object: CapturedRoom.Object
    
    var body: some View {
        HStack {
            Image(systemName: objectIcon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            Text(objectName)
                .font(.headline)
            
            Spacer()
            
            let dims = object.dimensions
            Text(String(format: "%.1f\" × %.1f\" × %.1f\"", 
                       dims.x * 39.37, dims.y * 39.37, dims.z * 39.37))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    var objectIcon: String {
        switch object.category {
        case .storage: return "cabinet"
        case .refrigerator: return "refrigerator"
        case .stove: return "flame"
        case .bed: return "bed.double"
        case .sink: return "sink"
        case .washerDryer: return "washer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table.furniture"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "tv"
        case .stairs: return "stairs"
        @unknown default: return "cube.box"
        }
    }
    
    var objectName: String {
        switch object.category {
        case .storage: return "Cabinet"
        case .refrigerator: return "Refrigerator"
        case .stove: return "Stove"
        case .bed: return "Bed"
        case .sink: return "Sink"
        case .washerDryer: return "Washer/Dryer"
        case .toilet: return "Toilet"
        case .bathtub: return "Bathtub"
        case .oven: return "Oven"
        case .dishwasher: return "Dishwasher"
        case .table: return "Table"
        case .sofa: return "Sofa"
        case .chair: return "Chair"
        case .fireplace: return "Fireplace"
        case .television: return "TV"
        case .stairs: return "Stairs"
        @unknown default: return "Object"
        }
    }
}

// MARK: - Professional Architectural Floor Plan View
@available(iOS 16.0, *)
struct FloorPlanView: View {
    let capturedRoom: CapturedRoom
    let onTapLocation: ((CGPoint) -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var gestureStartScale: CGFloat = 1.0 // Track gesture baseline
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cachedFloorPlan: FloorPlanGeometry? // Cache expensive geometry

    // Architectural drawing colors
    private let blueprintBackground = Color(red: 0.97, green: 0.98, blue: 1.0)
    private let wallColor = Color(red: 0.15, green: 0.15, blue: 0.2)
    private let dimensionColor = Color(red: 0.2, green: 0.4, blue: 0.7)
    private let windowColor = Color(red: 0.3, green: 0.6, blue: 0.8)
    private let doorColor = Color(red: 0.4, green: 0.3, blue: 0.25)
    private let gridColor = Color(red: 0.85, green: 0.88, blue: 0.92)

    init(capturedRoom: CapturedRoom, onTapLocation: ((CGPoint) -> Void)? = nil) {
        self.capturedRoom = capturedRoom
        self.onTapLocation = onTapLocation
    }

    var body: some View {
        GeometryReader { geometry in
            // Use cached geometry to avoid expensive O(n²) recalculation on every render
            let floorPlan = cachedFloorPlan ?? FloorPlanGeometry(capturedRoom: capturedRoom, viewSize: geometry.size)

            ZStack {
                // Blueprint-style background
                blueprintBackground
                    .ignoresSafeArea()

                // Floor plan content
                Canvas { context, size in
                    // Apply transforms
                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
                    transform = transform.scaledBy(x: scale, y: scale)
                    transform = transform.translatedBy(x: -floorPlan.center.x, y: -floorPlan.center.y)

                    context.concatenate(transform)

                    // Draw architectural grid
                    drawArchitecturalGrid(context: context, floorPlan: floorPlan)

                    // Draw floor fill with subtle pattern
                    drawFloorFill(context: context, floorPlan: floorPlan)

                    // Draw walls with proper architectural weight
                    drawArchitecturalWalls(context: context, floorPlan: floorPlan)

                    // Draw windows with standard architectural symbol
                    drawArchitecturalWindows(context: context, floorPlan: floorPlan)

                    // Draw doors with standard architectural symbol
                    drawArchitecturalDoors(context: context, floorPlan: floorPlan)

                    // Draw objects with architectural symbols
                    drawArchitecturalObjects(context: context, floorPlan: floorPlan)

                    // Draw dimension lines with proper architectural style
                    drawArchitecturalDimensions(context: context, floorPlan: floorPlan)

                    // Draw room label in center
                    drawRoomLabel(context: context, floorPlan: floorPlan)
                }

                // Dimension labels overlay
                architecturalDimensionLabels(floorPlan: floorPlan, viewSize: geometry.size)

                // Scale indicator
                VStack {
                    HStack {
                        scaleIndicator(floorPlan: floorPlan)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        // Fix: Use baseline scale to properly track pinch gesture
                        scale = max(0.5, min(3.0, gestureStartScale * value))
                    }
                    .onEnded { _ in
                        gestureStartScale = scale
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onAppear {
                // Cache the expensive geometry computation on first appear
                if cachedFloorPlan == nil {
                    cachedFloorPlan = FloorPlanGeometry(capturedRoom: capturedRoom, viewSize: geometry.size)
                }
                scale = floorPlan.fitScale
                gestureStartScale = floorPlan.fitScale
            }
        }
    }

    // MARK: - Scale Indicator
    @ViewBuilder
    private func scaleIndicator(floorPlan: FloorPlanGeometry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Scale bar
            HStack(spacing: 0) {
                Rectangle()
                    .fill(wallColor)
                    .frame(width: 40, height: 4)
                Rectangle()
                    .fill(blueprintBackground)
                    .frame(width: 40, height: 4)
                    .overlay(
                        Rectangle()
                            .stroke(wallColor, lineWidth: 1)
                    )
            }
            Text("1' = 1'")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(wallColor.opacity(0.7))
        }
        .padding(8)
        .background(blueprintBackground.opacity(0.95))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(gridColor, lineWidth: 1)
        )
    }

    // MARK: - Architectural Grid
    private func drawArchitecturalGrid(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        // Use adaptive grid spacing based on room size
        let spacing = floorPlan.gridSpacing
        let bounds = floorPlan.bounds.insetBy(dx: -80, dy: -80)

        // Cap iterations to prevent runaway loops with degenerate spacing
        let maxIterations = 500

        // Minor grid (lighter)
        var minorGridPath = Path()
        var iterations = 0
        var x = bounds.minX - bounds.minX.truncatingRemainder(dividingBy: spacing.minor)
        while x <= bounds.maxX && iterations < maxIterations {
            minorGridPath.move(to: CGPoint(x: x, y: bounds.minY))
            minorGridPath.addLine(to: CGPoint(x: x, y: bounds.maxY))
            x += spacing.minor
            iterations += 1
        }

        iterations = 0
        var y = bounds.minY - bounds.minY.truncatingRemainder(dividingBy: spacing.minor)
        while y <= bounds.maxY && iterations < maxIterations {
            minorGridPath.move(to: CGPoint(x: bounds.minX, y: y))
            minorGridPath.addLine(to: CGPoint(x: bounds.maxX, y: y))
            y += spacing.minor
            iterations += 1
        }

        context.stroke(minorGridPath, with: .color(Color(red: 0.88, green: 0.90, blue: 0.94)), lineWidth: 0.5)

        // Major grid (darker)
        var majorGridPath = Path()

        iterations = 0
        x = bounds.minX - bounds.minX.truncatingRemainder(dividingBy: spacing.major)
        while x <= bounds.maxX && iterations < maxIterations {
            majorGridPath.move(to: CGPoint(x: x, y: bounds.minY))
            majorGridPath.addLine(to: CGPoint(x: x, y: bounds.maxY))
            x += spacing.major
            iterations += 1
        }

        iterations = 0
        y = bounds.minY - bounds.minY.truncatingRemainder(dividingBy: spacing.major)
        while y <= bounds.maxY && iterations < maxIterations {
            majorGridPath.move(to: CGPoint(x: bounds.minX, y: y))
            majorGridPath.addLine(to: CGPoint(x: bounds.maxX, y: y))
            y += spacing.major
            iterations += 1
        }

        context.stroke(majorGridPath, with: .color(Color(red: 0.82, green: 0.85, blue: 0.90)), lineWidth: 0.75)
    }

    private func drawFloorFill(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        guard !floorPlan.wallSegments.isEmpty else { return }

        var floorPath = Path()
        let points = floorPlan.wallSegments.flatMap { [$0.start, $0.end] }

        if let convexHull = convexHull(points: points), !convexHull.isEmpty {
            floorPath.move(to: convexHull[0])
            for point in convexHull.dropFirst() {
                floorPath.addLine(to: point)
            }
            floorPath.closeSubpath()

            // Clean white fill with subtle shadow
            context.fill(floorPath, with: .color(.white))
        }
    }

    // MARK: - Architectural Walls
    private func drawArchitecturalWalls(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        // Wall parameters - standard architectural representation
        // Interior wall thickness is ~4 inches (2x4 studs + drywall)
        // 4 inches * 3 px/inch = 12 pixels
        let wallThicknessInches: CGFloat = 4.0
        let outerWallThickness: CGFloat = wallThicknessInches * floorPlan.pixelsPerInch
        let innerLineThickness: CGFloat = 1

        for segment in floorPlan.wallSegments {
            // Calculate perpendicular direction
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }

            let perpX = -dy / length * (outerWallThickness / 2)
            let perpY = dx / length * (outerWallThickness / 2)

            // Create wall shape (filled rectangle)
            var wallPath = Path()
            wallPath.move(to: CGPoint(x: segment.start.x + perpX, y: segment.start.y + perpY))
            wallPath.addLine(to: CGPoint(x: segment.end.x + perpX, y: segment.end.y + perpY))
            wallPath.addLine(to: CGPoint(x: segment.end.x - perpX, y: segment.end.y - perpY))
            wallPath.addLine(to: CGPoint(x: segment.start.x - perpX, y: segment.start.y - perpY))
            wallPath.closeSubpath()

            // Fill wall
            context.fill(wallPath, with: .color(wallColor))

            // Add inner detail line (architectural convention for walls)
            var innerPath = Path()
            innerPath.move(to: segment.start)
            innerPath.addLine(to: segment.end)
            context.stroke(innerPath, with: .color(.white.opacity(0.3)), lineWidth: innerLineThickness)
        }
    }

    // MARK: - Architectural Doors
    private func drawArchitecturalDoors(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        // Use consistent wall thickness for clearing door openings
        let wallThicknessInches: CGFloat = 4.0
        let clearThickness: CGFloat = (wallThicknessInches * floorPlan.pixelsPerInch) / 2 + 2

        for door in floorPlan.doors {
            let doorWidth = hypot(door.end.x - door.start.x, door.end.y - door.start.y)

            // Clear the wall where door is
            var clearPath = Path()
            let dx = door.end.x - door.start.x
            let dy = door.end.y - door.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }

            let perpX = -dy / length * clearThickness
            let perpY = dx / length * clearThickness

            clearPath.move(to: CGPoint(x: door.start.x + perpX, y: door.start.y + perpY))
            clearPath.addLine(to: CGPoint(x: door.end.x + perpX, y: door.end.y + perpY))
            clearPath.addLine(to: CGPoint(x: door.end.x - perpX, y: door.end.y - perpY))
            clearPath.addLine(to: CGPoint(x: door.start.x - perpX, y: door.start.y - perpY))
            clearPath.closeSubpath()
            context.fill(clearPath, with: .color(.white))

            // Door opening line (threshold)
            var thresholdPath = Path()
            thresholdPath.move(to: door.start)
            thresholdPath.addLine(to: door.end)
            context.stroke(thresholdPath, with: .color(doorColor), style: StrokeStyle(lineWidth: 1.5))

            // Door swing arc (standard 90° arc)
            var arcPath = Path()
            arcPath.addArc(
                center: door.start,
                radius: doorWidth,
                startAngle: .degrees(door.swingStartAngle),
                endAngle: .degrees(door.swingEndAngle),
                clockwise: false
            )
            context.stroke(arcPath, with: .color(doorColor.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            // Door panel (solid line showing door position)
            var panelPath = Path()
            panelPath.move(to: door.start)
            let panelEnd = CGPoint(
                x: door.start.x + doorWidth * cos(CGFloat(door.swingEndAngle) * .pi / 180),
                y: door.start.y + doorWidth * sin(CGFloat(door.swingEndAngle) * .pi / 180)
            )
            panelPath.addLine(to: panelEnd)
            context.stroke(panelPath, with: .color(doorColor), lineWidth: 2)

            // Door hinge indicator (small circle)
            var hingePath = Path()
            hingePath.addEllipse(in: CGRect(x: door.start.x - 3, y: door.start.y - 3, width: 6, height: 6))
            context.fill(hingePath, with: .color(doorColor))
        }
    }

    // MARK: - Architectural Windows
    private func drawArchitecturalWindows(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        // Use consistent wall thickness for window proportions
        let wallThicknessInches: CGFloat = 4.0
        let wallThickness = wallThicknessInches * floorPlan.pixelsPerInch
        let clearWidth: CGFloat = wallThickness / 2 + 2
        let windowFrameWidth: CGFloat = wallThickness / 4

        for window in floorPlan.windows {
            let dx = window.end.x - window.start.x
            let dy = window.end.y - window.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }

            let perpX = -dy / length
            let perpY = dx / length

            // Clear wall area for window
            var clearPath = Path()
            clearPath.move(to: CGPoint(x: window.start.x + perpX * clearWidth, y: window.start.y + perpY * clearWidth))
            clearPath.addLine(to: CGPoint(x: window.end.x + perpX * clearWidth, y: window.end.y + perpY * clearWidth))
            clearPath.addLine(to: CGPoint(x: window.end.x - perpX * clearWidth, y: window.end.y - perpY * clearWidth))
            clearPath.addLine(to: CGPoint(x: window.start.x - perpX * clearWidth, y: window.start.y - perpY * clearWidth))
            clearPath.closeSubpath()
            context.fill(clearPath, with: .color(.white))

            // Standard architectural window symbol: two parallel lines with center line
            // Outer frame lines
            var framePath = Path()
            framePath.move(to: CGPoint(x: window.start.x + perpX * windowFrameWidth, y: window.start.y + perpY * windowFrameWidth))
            framePath.addLine(to: CGPoint(x: window.end.x + perpX * windowFrameWidth, y: window.end.y + perpY * windowFrameWidth))
            framePath.move(to: CGPoint(x: window.start.x - perpX * windowFrameWidth, y: window.start.y - perpY * windowFrameWidth))
            framePath.addLine(to: CGPoint(x: window.end.x - perpX * windowFrameWidth, y: window.end.y - perpY * windowFrameWidth))
            context.stroke(framePath, with: .color(windowColor), lineWidth: 2)

            // Center glass line
            var glassPath = Path()
            glassPath.move(to: window.start)
            glassPath.addLine(to: window.end)
            context.stroke(glassPath, with: .color(windowColor.opacity(0.5)), lineWidth: 1)

            // End caps connecting the parallel lines
            var capPath = Path()
            capPath.move(to: CGPoint(x: window.start.x + perpX * windowFrameWidth, y: window.start.y + perpY * windowFrameWidth))
            capPath.addLine(to: CGPoint(x: window.start.x - perpX * windowFrameWidth, y: window.start.y - perpY * windowFrameWidth))
            capPath.move(to: CGPoint(x: window.end.x + perpX * windowFrameWidth, y: window.end.y + perpY * windowFrameWidth))
            capPath.addLine(to: CGPoint(x: window.end.x - perpX * windowFrameWidth, y: window.end.y - perpY * windowFrameWidth))
            context.stroke(capPath, with: .color(windowColor), lineWidth: 1.5)
        }
    }

    // MARK: - Architectural Objects
    private func drawArchitecturalObjects(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        for object in floorPlan.objects {
            let rect = CGRect(
                x: object.position.x - object.size.width / 2,
                y: object.position.y - object.size.height / 2,
                width: object.size.width,
                height: object.size.height
            )

            // Draw with architectural symbol style
            switch object.category {
            case .toilet:
                drawToiletSymbol(context: context, rect: rect)
            case .bathtub:
                drawBathtubSymbol(context: context, rect: rect)
            case .sink:
                drawSinkSymbol(context: context, rect: rect)
            case .refrigerator:
                drawApplianceSymbol(context: context, rect: rect, label: "REF")
            case .stove, .oven:
                drawStoveSymbol(context: context, rect: rect)
            case .dishwasher:
                drawApplianceSymbol(context: context, rect: rect, label: "DW")
            case .washerDryer:
                drawApplianceSymbol(context: context, rect: rect, label: "W/D")
            default:
                drawGenericObjectSymbol(context: context, rect: rect, color: object.color)
            }
        }
    }

    private func drawToiletSymbol(context: GraphicsContext, rect: CGRect) {
        // Tank (rectangle)
        let tankRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.35)
        let tankPath = Path(roundedRect: tankRect, cornerRadius: 2)
        context.fill(tankPath, with: .color(.white))
        context.stroke(tankPath, with: .color(wallColor), lineWidth: 1.5)

        // Bowl (oval)
        let bowlRect = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.3, width: rect.width, height: rect.height * 0.7)
        let bowlPath = Path(ellipseIn: bowlRect)
        context.fill(bowlPath, with: .color(.white))
        context.stroke(bowlPath, with: .color(wallColor), lineWidth: 1.5)

        // Inner bowl
        let innerBowl = bowlRect.insetBy(dx: 6, dy: 8)
        let innerPath = Path(ellipseIn: innerBowl)
        context.stroke(innerPath, with: .color(wallColor.opacity(0.5)), lineWidth: 1)
    }

    private func drawBathtubSymbol(context: GraphicsContext, rect: CGRect) {
        let tubPath = Path(roundedRect: rect, cornerRadius: 8)
        context.fill(tubPath, with: .color(.white))
        context.stroke(tubPath, with: .color(wallColor), lineWidth: 2)

        // Inner edge
        let innerRect = rect.insetBy(dx: 4, dy: 4)
        let tubInnerPath = Path(roundedRect: innerRect, cornerRadius: 6)
        context.stroke(tubInnerPath, with: .color(wallColor.opacity(0.5)), lineWidth: 1)

        // Drain
        let drainSize: CGFloat = 8
        let drainRect = CGRect(
            x: rect.maxX - 20,
            y: rect.midY - drainSize / 2,
            width: drainSize,
            height: drainSize
        )
        let tubDrainPath = Path(ellipseIn: drainRect)
        context.fill(tubDrainPath, with: .color(wallColor.opacity(0.3)))
        context.stroke(tubDrainPath, with: .color(wallColor), lineWidth: 1)
    }

    private func drawSinkSymbol(context: GraphicsContext, rect: CGRect) {
        // Counter/vanity
        let counterPath = Path(roundedRect: rect, cornerRadius: 2)
        context.fill(counterPath, with: .color(.white))
        context.stroke(counterPath, with: .color(wallColor), lineWidth: 1.5)

        // Basin (oval)
        let basinRect = rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.2)
        let basinPath = Path(ellipseIn: basinRect)
        context.stroke(basinPath, with: .color(wallColor), lineWidth: 1.5)

        // Drain
        let drainSize: CGFloat = 4
        let drainRect = CGRect(
            x: rect.midX - drainSize / 2,
            y: rect.midY - drainSize / 2,
            width: drainSize,
            height: drainSize
        )
        let sinkDrainPath = Path(ellipseIn: drainRect)
        context.fill(sinkDrainPath, with: .color(wallColor))
    }

    private func drawStoveSymbol(context: GraphicsContext, rect: CGRect) {
        let stovePath = Path(roundedRect: rect, cornerRadius: 2)
        context.fill(stovePath, with: .color(.white))
        context.stroke(stovePath, with: .color(wallColor), lineWidth: 1.5)

        // Burners (4 circles in a grid)
        let burnerSize = min(rect.width, rect.height) * 0.25
        let positions = [
            CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.3),
            CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.3),
            CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.7),
            CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.7)
        ]

        for pos in positions {
            let burnerRect = CGRect(x: pos.x - burnerSize/2, y: pos.y - burnerSize/2, width: burnerSize, height: burnerSize)
            let burnerPath = Path(ellipseIn: burnerRect)
            context.stroke(burnerPath, with: .color(wallColor), lineWidth: 1.5)
        }
    }

    private func drawApplianceSymbol(context: GraphicsContext, rect: CGRect, label: String) {
        let appliancePath = Path(roundedRect: rect, cornerRadius: 2)
        context.fill(appliancePath, with: .color(.white))
        context.stroke(appliancePath, with: .color(wallColor), lineWidth: 1.5)

        // Diagonal line (standard appliance indicator)
        var diagPath = Path()
        diagPath.move(to: CGPoint(x: rect.minX, y: rect.minY))
        diagPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.stroke(diagPath, with: .color(wallColor.opacity(0.4)), lineWidth: 0.75)
    }

    private func drawGenericObjectSymbol(context: GraphicsContext, rect: CGRect, color: Color) {
        let objectPath = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(objectPath, with: .color(color.opacity(0.15)))
        context.stroke(objectPath, with: .color(color.opacity(0.6)), lineWidth: 1)
    }

    // MARK: - Architectural Dimensions
    private func drawArchitecturalDimensions(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        let bounds = floorPlan.bounds
        let dimOffset: CGFloat = 40
        let tickLength: CGFloat = 8
        let lineWeight: CGFloat = 0.75

        // Dimension line color
        let dimColor = Color(red: 0.2, green: 0.4, blue: 0.7)

        // Width dimension (bottom)
        var widthPath = Path()
        // Main line
        widthPath.move(to: CGPoint(x: bounds.minX, y: bounds.maxY + dimOffset))
        widthPath.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY + dimOffset))
        // Extension lines
        widthPath.move(to: CGPoint(x: bounds.minX, y: bounds.maxY + 10))
        widthPath.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY + dimOffset + tickLength))
        widthPath.move(to: CGPoint(x: bounds.maxX, y: bounds.maxY + 10))
        widthPath.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY + dimOffset + tickLength))
        // Tick marks (architectural slash style)
        widthPath.move(to: CGPoint(x: bounds.minX - 4, y: bounds.maxY + dimOffset + 4))
        widthPath.addLine(to: CGPoint(x: bounds.minX + 4, y: bounds.maxY + dimOffset - 4))
        widthPath.move(to: CGPoint(x: bounds.maxX - 4, y: bounds.maxY + dimOffset + 4))
        widthPath.addLine(to: CGPoint(x: bounds.maxX + 4, y: bounds.maxY + dimOffset - 4))

        context.stroke(widthPath, with: .color(dimColor), lineWidth: lineWeight)

        // Length dimension (right side)
        var lengthPath = Path()
        // Main line
        lengthPath.move(to: CGPoint(x: bounds.maxX + dimOffset, y: bounds.minY))
        lengthPath.addLine(to: CGPoint(x: bounds.maxX + dimOffset, y: bounds.maxY))
        // Extension lines
        lengthPath.move(to: CGPoint(x: bounds.maxX + 10, y: bounds.minY))
        lengthPath.addLine(to: CGPoint(x: bounds.maxX + dimOffset + tickLength, y: bounds.minY))
        lengthPath.move(to: CGPoint(x: bounds.maxX + 10, y: bounds.maxY))
        lengthPath.addLine(to: CGPoint(x: bounds.maxX + dimOffset + tickLength, y: bounds.maxY))
        // Tick marks
        lengthPath.move(to: CGPoint(x: bounds.maxX + dimOffset - 4, y: bounds.minY - 4))
        lengthPath.addLine(to: CGPoint(x: bounds.maxX + dimOffset + 4, y: bounds.minY + 4))
        lengthPath.move(to: CGPoint(x: bounds.maxX + dimOffset - 4, y: bounds.maxY - 4))
        lengthPath.addLine(to: CGPoint(x: bounds.maxX + dimOffset + 4, y: bounds.maxY + 4))

        context.stroke(lengthPath, with: .color(dimColor), lineWidth: lineWeight)
    }

    // MARK: - Room Label
    private func drawRoomLabel(context: GraphicsContext, floorPlan: FloorPlanGeometry) {
        let center = floorPlan.center
        let areaText = String(format: "%.0f SF", floorPlan.roomAreaSF)

        // Draw room name label (centered in room)
        let nameFont = Font.system(size: 14, weight: .semibold, design: .default)
        let areaFont = Font.system(size: 11, weight: .regular, design: .monospaced)
        let labelColor = Color(red: 0.3, green: 0.3, blue: 0.35)

        // Room name
        context.draw(
            Text(floorPlan.roomName)
                .font(nameFont)
                .foregroundColor(labelColor),
            at: CGPoint(x: center.x, y: center.y - 8),
            anchor: .center
        )

        // Square footage below name
        context.draw(
            Text(areaText)
                .font(areaFont)
                .foregroundColor(labelColor.opacity(0.8)),
            at: CGPoint(x: center.x, y: center.y + 8),
            anchor: .center
        )
    }

    @ViewBuilder
    private func architecturalDimensionLabels(floorPlan: FloorPlanGeometry, viewSize: CGSize) -> some View {
        let roomBounds = Room.calculateBounds(from: capturedRoom)

        let widthFeet = Int(roomBounds.width / 12)
        let widthInches = Int(roomBounds.width) % 12
        let lengthFeet = Int(roomBounds.length / 12)
        let lengthInches = Int(roomBounds.length) % 12

        let dimColor = Color(red: 0.2, green: 0.4, blue: 0.7)

        VStack {
            Spacer()

            // Bottom dimension label (width)
            Text(formatArchitecturalDimension(feet: widthFeet, inches: widthInches))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(dimColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(blueprintBackground.opacity(0.95))
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(dimColor.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.bottom, 12)
        }

        HStack {
            Spacer()

            // Right dimension label (length)
            Text(formatArchitecturalDimension(feet: lengthFeet, inches: lengthInches))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(dimColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(blueprintBackground.opacity(0.95))
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(dimColor.opacity(0.3), lineWidth: 0.5)
                )
                .rotationEffect(.degrees(-90))
                .padding(.trailing, 12)
        }
    }

    private func formatArchitecturalDimension(feet: Int, inches: Int) -> String {
        if inches == 0 {
            return "\(feet)'-0\""
        } else {
            return "\(feet)'-\(inches)\""
        }
    }

    // Simple convex hull algorithm for floor fill
    private func convexHull(points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 3 else { return points }

        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        // Guard against empty collections (can happen with collinear/degenerate geometry)
        if !lower.isEmpty { lower.removeLast() }
        if !upper.isEmpty { upper.removeLast() }

        let result = lower + upper
        return result.isEmpty ? nil : result
    }

    private func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
}

// MARK: - Floor Plan Geometry Calculator
struct FloorPlanGeometry {
    let wallSegments: [WallSegment]
    let doors: [DoorElement]
    let windows: [WindowElement]
    let objects: [ObjectElement]
    let bounds: CGRect
    let center: CGPoint
    let fitScale: CGFloat
    let pixelsPerInch: CGFloat = 3.0 // Scale factor for drawing
    let roomAreaSF: Double // Square footage for adaptive grid
    let roomName: String // Room name for label

    // Snapping tolerance: 6 inches = 18 pixels at 3px/inch
    static let snapTolerancePixels: CGFloat = 6 * 3.0

    struct WallSegment {
        let start: CGPoint
        let end: CGPoint
        let thickness: CGFloat
        let lengthInches: Double // Length in inches for dimension display
    }

    struct DoorElement {
        let start: CGPoint
        let end: CGPoint
        let swingStartAngle: Double
        let swingEndAngle: Double
        let widthInches: Double // Door width for display
    }

    struct WindowElement {
        let start: CGPoint
        let end: CGPoint
        let widthInches: Double // Window width for display
    }

    struct ObjectElement {
        let position: CGPoint
        let size: CGSize
        let category: CapturedRoom.Object.Category
        let color: Color
        let icon: String
    }

    /// Adaptive grid spacing based on room size
    /// Small rooms (<100 SF): 6" grid (minor), 2' grid (major)
    /// Medium rooms (100-400 SF): 1' grid (minor), 5' grid (major)
    /// Large rooms (>400 SF): 2' grid (minor), 10' grid (major)
    var gridSpacing: (minor: CGFloat, major: CGFloat) {
        if roomAreaSF < 100 {
            return (minor: 6 * pixelsPerInch, major: 24 * pixelsPerInch) // 6" / 2'
        } else if roomAreaSF < 400 {
            return (minor: 12 * pixelsPerInch, major: 60 * pixelsPerInch) // 1' / 5'
        } else {
            return (minor: 24 * pixelsPerInch, major: 120 * pixelsPerInch) // 2' / 10'
        }
    }

    init(capturedRoom: CapturedRoom, viewSize: CGSize, roomName: String = "Room") {
        var rawEndpoints: [(start: CGPoint, end: CGPoint, lengthInches: Double)] = []
        var doorElements: [DoorElement] = []
        var windowElements: [WindowElement] = []
        var objectElements: [ObjectElement] = []

        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity

        // Process walls - extract wall positions from transform matrices
        for wall in capturedRoom.walls {
            let position = wall.transform.columns.3
            let dimensions = wall.dimensions

            // Get wall orientation from transform
            let xAxis = wall.transform.columns.0
            let angle = atan2(Double(xAxis.z), Double(xAxis.x))

            // Calculate wall endpoints in 2D (top-down view, X-Z plane)
            let halfLength = CGFloat(dimensions.x) / 2
            let centerX = CGFloat(position.x) * pixelsPerInch * 39.3701 // meters to inches to pixels
            let centerY = CGFloat(position.z) * pixelsPerInch * 39.3701

            let dx = halfLength * CGFloat(cos(angle)) * pixelsPerInch * 39.3701
            let dy = halfLength * CGFloat(sin(angle)) * pixelsPerInch * 39.3701

            let start = CGPoint(x: centerX - dx, y: centerY - dy)
            let end = CGPoint(x: centerX + dx, y: centerY + dy)

            // Store length in inches for dimension labels
            let lengthInches = Double(dimensions.x) * 39.3701

            rawEndpoints.append((start: start, end: end, lengthInches: lengthInches))

            // Update bounds
            minX = min(minX, start.x, end.x)
            maxX = max(maxX, start.x, end.x)
            minY = min(minY, start.y, end.y)
            maxY = max(maxY, start.y, end.y)
        }

        // === WALL ENDPOINT SNAPPING ===
        // Snap endpoints that are within 6" tolerance to connect walls properly
        var allEndpoints: [CGPoint] = []
        for segment in rawEndpoints {
            allEndpoints.append(segment.start)
            allEndpoints.append(segment.end)
        }

        // Helper to create a hashable key from CGPoint (for iOS <18 compatibility)
        func pointKey(_ p: CGPoint) -> String {
            "\(Int(p.x * 100)),\(Int(p.y * 100))"
        }

        // Find clusters of nearby points and snap them to their centroid
        var snappedPoints: [String: CGPoint] = [:] // Point key -> Snapped point
        var used: Set<Int> = []

        for i in 0..<allEndpoints.count {
            guard !used.contains(i) else { continue }

            var cluster: [Int] = [i]
            for j in (i + 1)..<allEndpoints.count {
                guard !used.contains(j) else { continue }
                let dist = hypot(allEndpoints[i].x - allEndpoints[j].x,
                                allEndpoints[i].y - allEndpoints[j].y)
                if dist <= FloorPlanGeometry.snapTolerancePixels {
                    cluster.append(j)
                }
            }

            // Calculate centroid of cluster
            let centroid = CGPoint(
                x: cluster.reduce(0.0) { $0 + allEndpoints[$1].x } / CGFloat(cluster.count),
                y: cluster.reduce(0.0) { $0 + allEndpoints[$1].y } / CGFloat(cluster.count)
            )

            // Map all points in cluster to centroid
            for idx in cluster {
                snappedPoints[pointKey(allEndpoints[idx])] = centroid
                used.insert(idx)
            }
        }

        // Helper function to snap a point
        func snap(_ point: CGPoint) -> CGPoint {
            snappedPoints[pointKey(point)] ?? point
        }

        // Create wall segments with snapped endpoints
        var segments: [WallSegment] = []
        for raw in rawEndpoints {
            let snappedStart = snap(raw.start)
            let snappedEnd = snap(raw.end)
            segments.append(WallSegment(
                start: snappedStart,
                end: snappedEnd,
                thickness: 6,
                lengthInches: raw.lengthInches
            ))
        }

        // Process doors
        for door in capturedRoom.doors {
            let position = door.transform.columns.3
            let dimensions = door.dimensions
            let xAxis = door.transform.columns.0
            let angle = atan2(Double(xAxis.z), Double(xAxis.x))

            let halfWidth = CGFloat(dimensions.x) / 2
            let centerX = CGFloat(position.x) * pixelsPerInch * 39.3701
            let centerY = CGFloat(position.z) * pixelsPerInch * 39.3701

            let dx = halfWidth * CGFloat(cos(angle)) * pixelsPerInch * 39.3701
            let dy = halfWidth * CGFloat(sin(angle)) * pixelsPerInch * 39.3701

            let start = CGPoint(x: centerX - dx, y: centerY - dy)
            let end = CGPoint(x: centerX + dx, y: centerY + dy)

            // Door swing angles (90 degree swing)
            let swingStart = angle * 180 / .pi
            let swingEnd = swingStart + 90

            doorElements.append(DoorElement(
                start: start,
                end: end,
                swingStartAngle: swingStart,
                swingEndAngle: swingEnd,
                widthInches: Double(dimensions.x) * 39.3701
            ))
        }

        // Process windows
        for window in capturedRoom.windows {
            let position = window.transform.columns.3
            let dimensions = window.dimensions
            let xAxis = window.transform.columns.0
            let angle = atan2(Double(xAxis.z), Double(xAxis.x))

            let halfWidth = CGFloat(dimensions.x) / 2
            let centerX = CGFloat(position.x) * pixelsPerInch * 39.3701
            let centerY = CGFloat(position.z) * pixelsPerInch * 39.3701

            let dx = halfWidth * CGFloat(cos(angle)) * pixelsPerInch * 39.3701
            let dy = halfWidth * CGFloat(sin(angle)) * pixelsPerInch * 39.3701

            windowElements.append(WindowElement(
                start: CGPoint(x: centerX - dx, y: centerY - dy),
                end: CGPoint(x: centerX + dx, y: centerY + dy),
                widthInches: Double(dimensions.x) * 39.3701
            ))
        }

        // Process objects
        for object in capturedRoom.objects {
            let position = object.transform.columns.3
            let dimensions = object.dimensions

            let x = CGFloat(position.x) * pixelsPerInch * 39.3701
            let y = CGFloat(position.z) * pixelsPerInch * 39.3701
            let width = CGFloat(dimensions.x) * pixelsPerInch * 39.3701
            let depth = CGFloat(dimensions.z) * pixelsPerInch * 39.3701

            let color: Color
            let icon: String

            switch object.category {
            case .refrigerator:
                color = .blue
                icon = "refrigerator"
            case .stove, .oven:
                color = .orange
                icon = "flame"
            case .sink:
                color = .cyan
                icon = "drop"
            case .toilet:
                color = .gray
                icon = "toilet"
            case .bathtub:
                color = .teal
                icon = "bathtub"
            case .bed:
                color = .purple
                icon = "bed.double"
            case .sofa:
                color = .brown
                icon = "sofa"
            case .table:
                color = .brown
                icon = "table.furniture"
            case .chair:
                color = .brown
                icon = "chair"
            case .washerDryer:
                color = .gray
                icon = "washer"
            case .dishwasher:
                color = .gray
                icon = "dishwasher"
            case .storage:
                color = .brown
                icon = "cabinet"
            default:
                color = .gray
                icon = "cube"
            }

            objectElements.append(ObjectElement(
                position: CGPoint(x: x, y: y),
                size: CGSize(width: max(width, 20), height: max(depth, 20)),
                category: object.category,
                color: color,
                icon: icon
            ))

            // Update bounds
            minX = min(minX, x - width/2)
            maxX = max(maxX, x + width/2)
            minY = min(minY, y - depth/2)
            maxY = max(maxY, y + depth/2)
        }

        // Calculate room area for adaptive grid
        let roomBounds = Room.calculateBounds(from: capturedRoom)
        let calculatedAreaSF = (roomBounds.length * roomBounds.width) / 144.0 // inches to SF

        // Handle empty room case
        if segments.isEmpty {
            let width = roomBounds.width * pixelsPerInch
            let length = roomBounds.length * pixelsPerInch
            minX = -width / 2
            maxX = width / 2
            minY = -length / 2
            maxY = length / 2

            // Create rectangular walls as fallback
            segments = [
                WallSegment(start: CGPoint(x: minX, y: minY), end: CGPoint(x: maxX, y: minY), thickness: 6, lengthInches: roomBounds.width),
                WallSegment(start: CGPoint(x: maxX, y: minY), end: CGPoint(x: maxX, y: maxY), thickness: 6, lengthInches: roomBounds.length),
                WallSegment(start: CGPoint(x: maxX, y: maxY), end: CGPoint(x: minX, y: maxY), thickness: 6, lengthInches: roomBounds.width),
                WallSegment(start: CGPoint(x: minX, y: maxY), end: CGPoint(x: minX, y: minY), thickness: 6, lengthInches: roomBounds.length)
            ]
        }

        // Add padding to bounds
        let padding: CGFloat = 60
        let boundsRect = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )

        self.wallSegments = segments
        self.doors = doorElements
        self.windows = windowElements
        self.objects = objectElements
        self.bounds = boundsRect
        self.center = CGPoint(x: boundsRect.midX, y: boundsRect.midY)
        self.roomAreaSF = calculatedAreaSF
        self.roomName = roomName

        // Calculate scale to fit view
        let scaleX = (viewSize.width - 80) / boundsRect.width
        let scaleY = (viewSize.height - 80) / boundsRect.height
        self.fitScale = min(scaleX, scaleY, 2.0)
    }
}

// MARK: - Room Subdivision Models

/// Represents a line drawn to divide a room into sub-rooms
struct DivisionLine: Identifiable, Codable, Hashable {
    let id: UUID
    var startPoint: CGPoint  // Normalized coordinates (0-1)
    var endPoint: CGPoint    // Normalized coordinates (0-1)
    
    init(id: UUID = UUID(), startPoint: CGPoint, endPoint: CGPoint) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

/// Represents a sub-room created by dividing a larger captured space
struct SubRoom: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: RoomCategory
    
    // Calculated dimensions based on parent room and division lines
    let lengthIn: Double
    let widthIn: Double
    let heightIn: Double  // Inherits from parent room
    
    var squareFeet: Double { (lengthIn * widthIn) / 144 }
    
    init(id: UUID = UUID(), name: String, category: RoomCategory, lengthIn: Double, widthIn: Double, heightIn: Double) {
        self.id = id
        self.name = name
        self.category = category
        self.lengthIn = lengthIn
        self.widthIn = widthIn
        self.heightIn = heightIn
    }
}

// MARK: - Note: Core models are defined in CoreModels.swift
// DamageAnnotation, DamageType, DamageSeverity, AffectedSurface, Room, RoomCategory, etc.

#Preview {
    ContentView()
}
