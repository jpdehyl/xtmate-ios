import SwiftUI
import Combine

// MARK: - Enhanced Claim Detail View

/// Comprehensive claim detail view with collapsible sections
struct ClaimDetailView: View {
    let claimId: UUID
    
    @StateObject private var viewModel = ClaimDetailViewModel()
    @State private var selectedRoomId: UUID?
    @State private var showingRoomCapture = false
    @State private var showingAddDamage = false
    @State private var showingPreliminaryReport = false
    @State private var showingVideoWalkthrough = false
    @State private var isClaimInfoExpanded = false
    @State private var viewMode: PropertyHeroView.ViewMode = .isometric
    @State private var preliminaryReport: PreliminaryReport?
    @State private var walkthroughResult: WalkthroughResult?
    @State private var isGeneratingReport = false

    @ObservedObject private var reportService = PreliminaryReportService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Property Hero Section
                if !viewModel.rooms.isEmpty {
                    PropertyHeroView(
                        rooms: viewModel.rooms.map { $0.toRoomListItem() },
                        selectedRoomId: $selectedRoomId,
                        viewMode: viewMode,
                        onToggleViewMode: {
                            withAnimation {
                                viewMode = viewMode == .isometric ? .floorPlan : .isometric
                            }
                        },
                        onCaptureRoom: { showingRoomCapture = true },
                        onSelectRoom: { room in
                            // Navigate to room detail
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                }
                
                // Main content
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Claim Info Card (Collapsible)
                    ClaimInfoCard(
                        claimNumber: viewModel.claim?.claimNumber,
                        dateOfLoss: viewModel.claim?.dateOfLoss,
                        lossType: viewModel.claim?.lossType,
                        insuredName: viewModel.claim?.insuredName,
                        insuredPhone: viewModel.claim?.insuredPhone,
                        insuredEmail: viewModel.claim?.insuredEmail,
                        adjusterName: viewModel.claim?.adjusterName,
                        adjusterPhone: viewModel.claim?.adjusterPhone,
                        propertyAddress: viewModel.claim?.propertyAddress,
                        propertyCity: viewModel.claim?.propertyCity,
                        propertyState: viewModel.claim?.propertyState
                    )
                    
                    // Rooms Section
                    roomsSection
                    
                    // Assignments Section
                    if !viewModel.assignments.isEmpty {
                        AssignmentsRow(
                            assignments: viewModel.assignments,
                            selectedAssignment: $viewModel.selectedAssignment,
                            onAddAssignment: {
                                // TODO: Add assignment
                            },
                            onTapAssignment: { assignment in
                                // TODO: Navigate to assignment detail
                            }
                        )
                    }
                    
                    // Quick Actions Section
                    quickActionsSection
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
        .background(AppTheme.Colors.background)
        .navigationTitle(viewModel.claim?.displayName ?? "Claim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { viewModel.syncClaim() }) {
                        Label("Sync to Web", systemImage: AppTheme.Icons.sync)
                    }
                    
                    Button(action: {}) {
                        Label("Export PDF", systemImage: AppTheme.Icons.export)
                    }
                    
                    Divider()
                    
                    Button(action: {}) {
                        Label("Edit Claim Info", systemImage: AppTheme.Icons.edit)
                    }
                    
                    Button(role: .destructive, action: {}) {
                        Label("Delete Claim", systemImage: AppTheme.Icons.delete)
                    }
                } label: {
                    Image(systemName: AppTheme.Icons.more)
                }
            }
        }
        .sheet(isPresented: $showingRoomCapture) {
            Text("Room Capture View")
            // TODO: Integrate RoomCaptureView
        }
        .sheet(isPresented: $showingAddDamage) {
            QuickDamageEntryView(roomId: selectedRoomId)
        }
        .sheet(isPresented: $showingPreliminaryReport) {
            if #available(iOS 16.0, *) {
                if var report = preliminaryReport {
                    PreliminaryReportView(report: Binding(
                        get: { report },
                        set: { report = $0; preliminaryReport = $0 }
                    ))
                }
            }
        }
        .fullScreenCover(isPresented: $showingVideoWalkthrough) {
            if #available(iOS 16.0, *) {
                VideoWalkthroughView(
                    onComplete: { result in
                        walkthroughResult = result
                        showingVideoWalkthrough = false
                        // Auto-generate preliminary report from walkthrough
                        if let result = result {
                            generatePreliminaryReport(from: result)
                        }
                    },
                    onCancel: {
                        showingVideoWalkthrough = false
                    }
                )
            }
        }
        .overlay {
            if isGeneratingReport {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Generating Report...")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Analyzing video frames")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
            }
        }
        .onAppear {
            viewModel.loadClaim(claimId)
        }
        // Floating Action Button
        .overlay(alignment: .bottomTrailing) {
            if viewModel.rooms.isEmpty {
                FloatingActionButton(
                    icon: AppTheme.Icons.scan,
                    label: "Scan Room",
                    action: { showingRoomCapture = true }
                )
                .padding(AppTheme.Spacing.xl)
            }
        }
    }
    
    // MARK: - Rooms Section
    
    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Section header
            HStack {
                Label("Rooms", systemImage: AppTheme.Icons.room)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingRoomCapture = true }) {
                    Label("Scan", systemImage: AppTheme.Icons.scan)
                        .font(.subheadline)
                }
            }
            
            // Rooms list
            if viewModel.rooms.isEmpty {
                EmptyRoomsView(onScanRoom: { showingRoomCapture = true })
            } else {
                LazyVStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(viewModel.rooms) { room in
                        NavigationLink(value: room.id) {
                            RoomListCard(
                                room: room,
                                isSelected: selectedRoomId == room.id,
                                onTap: { selectedRoomId = room.id },
                                onAddDamage: {
                                    selectedRoomId = room.id
                                    showingAddDamage = true
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { roomId in
            Text("Room Detail: \(roomId)")
            // TODO: Navigate to RoomDetailView
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Quick Actions")
                .font(.headline)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppTheme.Spacing.md
            ) {
                QuickActionCard(
                    icon: AppTheme.Icons.photo,
                    label: "Take Photos",
                    color: .blue,
                    action: {}
                )
                
                QuickActionCard(
                    icon: "exclamationmark.triangle.fill",
                    label: "Add Damage",
                    color: .orange,
                    action: { showingAddDamage = true }
                )
                
                QuickActionCard(
                    icon: "wand.and.stars",
                    label: "Generate Scope",
                    color: .purple,
                    action: {}
                )
                
                QuickActionCard(
                    icon: "video.fill",
                    label: "Video Walkthrough",
                    color: .indigo,
                    action: { showingVideoWalkthrough = true }
                )

                QuickActionCard(
                    icon: "doc.text.fill",
                    label: "Prelim Report",
                    color: .green,
                    action: {
                        if preliminaryReport == nil {
                            preliminaryReport = PreliminaryReport(estimateId: claimId)
                        }
                        showingPreliminaryReport = true
                    }
                )
            }
        }
    }

    // MARK: - Helper Methods

    @available(iOS 16.0, *)
    private func generatePreliminaryReport(from walkthrough: WalkthroughResult) {
        isGeneratingReport = true

        Task {
            do {
                let report = try await reportService.generateFromWalkthrough(
                    walkthrough,
                    estimateId: claimId,
                    existingReport: preliminaryReport
                )

                await MainActor.run {
                    preliminaryReport = report
                    isGeneratingReport = false
                    showingPreliminaryReport = true
                }
            } catch {
                await MainActor.run {
                    isGeneratingReport = false
                    // TODO: Show error alert
                    print("Error generating report: \(error)")
                }
            }
        }
    }
}

// MARK: - Empty Rooms View

private struct EmptyRoomsView: View {
    let onScanRoom: () -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "viewfinder.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("No Rooms Scanned")
                    .font(.subheadline.weight(.medium))
                
                Text("Scan your first room to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button(action: onScanRoom) {
                Label("Scan Room", systemImage: AppTheme.Icons.scan)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(AppTheme.Colors.primary)
                    .foregroundStyle(.white)
                    .continuousCornerRadius(AppTheme.Radius.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xxl)
        .background(AppTheme.Colors.cardBackground)
        .continuousCornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - Room List Card

private struct RoomListCard: View {
    let room: ClaimRoomListItem
    let isSelected: Bool
    let onTap: () -> Void
    let onAddDamage: () -> Void
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Room icon
            Image(systemName: room.icon)
                .font(.title2)
                .foregroundStyle(room.damageCount > 0 ? .orange : .blue)
                .frame(width: 44, height: 44)
                .background((room.damageCount > 0 ? Color.orange : Color.blue).opacity(0.15))
                .continuousCornerRadius(AppTheme.Radius.sm)
            
            // Room info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.name)
                        .font(.subheadline.weight(.medium))
                    
                    if room.hasScope {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text("\(Int(room.squareFeet)) SF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if room.damageCount > 0 {
                        Label("\(room.damageCount) damage\(room.damageCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            Button(action: onAddDamage) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.Colors.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.md)
        .background(isSelected ? AppTheme.Colors.primary.opacity(0.1) : AppTheme.Colors.cardBackground)
        .continuousCornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.Colors.primary : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Quick Action Card

private struct QuickActionCard: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)
                    .frame(width: 56, height: 56)
                    .background(color.opacity(0.15))
                    .continuousCornerRadius(AppTheme.Radius.md)
                
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.cardBackground)
            .continuousCornerRadius(AppTheme.Radius.md)
            .appShadow(AppTheme.Shadow.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Action Button

private struct FloatingActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.primary)
            .foregroundStyle(.white)
            .continuousCornerRadius(AppTheme.Radius.full)
            .appShadow(AppTheme.Shadow.lg)
        }
    }
}

// MARK: - Room List Item

/// Room list item for ClaimDetailView
struct ClaimRoomListItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var floor: String
    var squareFeet: Double
    var hasScope: Bool
    var damageCount: Int
    
    var icon: String {
        switch category.lowercased() {
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower.fill"
        case "bedroom": return "bed.double.fill"
        case "living", "livingroom": return "sofa.fill"
        case "dining", "diningroom": return "fork.knife.circle"
        case "office": return "desktopcomputer"
        case "laundry": return "washer.fill"
        case "garage": return "car.fill"
        case "basement": return "stairs"
        default: return "square.split.bottomrightquarter"
        }
    }
    
    /// Convert to RoomListItem for use with RoomsListCard
    func toRoomListItem() -> RoomListItem {
        RoomListItem(
            id: id,
            name: name,
            category: category,
            floor: floor,
            hasScope: hasScope,
            damageCount: damageCount
        )
    }
}

// MARK: - Claim Detail View Model

@MainActor
class ClaimDetailViewModel: ObservableObject {
    @Published var claim: ClaimListItem?
    @Published var rooms: [ClaimRoomListItem] = []
    @Published var assignments: [Assignment] = []
    @Published var selectedAssignment: Assignment?
    @Published var isLoading = false
    @Published var isSyncing = false
    
    func loadClaim(_ id: UUID) {
        isLoading = true
        
        // TODO: Load from persistence
        // Mock data for now
        claim = ClaimListItem(
            id: id,
            displayName: "2250 W 3rd Ave",
            claimNumber: "202511242869",
            jobType: .insurance,
            lossType: .water,
            insuredName: "Jesse Daniel Mayor",
            insuredPhone: "(604) 555-1234",
            propertyAddress: "2250 W 3rd Ave - Unit 105",
            dateOfLoss: Date().addingTimeInterval(-86400 * 30),
            status: .inProgress,
            syncStatus: .synced,
            roomCount: 4,
            damageCount: 2,
            totalSquareFeet: 1850,
            createdAt: Date().addingTimeInterval(-86400 * 30)
        )
        
        // Mock rooms
        rooms = [
            ClaimRoomListItem(id: UUID(), name: "Kitchen", category: "kitchen", floor: "1", squareFeet: 144, hasScope: true, damageCount: 2),
            ClaimRoomListItem(id: UUID(), name: "Living Room", category: "living", floor: "1", squareFeet: 256, hasScope: true, damageCount: 0),
            ClaimRoomListItem(id: UUID(), name: "Master Bedroom", category: "bedroom", floor: "2", squareFeet: 180, hasScope: false, damageCount: 0),
            ClaimRoomListItem(id: UUID(), name: "Bathroom", category: "bathroom", floor: "2", squareFeet: 64, hasScope: false, damageCount: 1)
        ]
        
        // Mock assignments
        assignments = [
            Assignment(estimateId: id, type: .emergency, status: .inProgress, total: 2500, order: 0),
            Assignment(estimateId: id, type: .repairs, status: .pending, total: 15000, order: 1),
            Assignment(estimateId: id, type: .contents, status: .pending, total: 3200, order: 2)
        ]
        
        isLoading = false
    }
    
    func syncClaim() {
        isSyncing = true
        
        Task {
            // Simulate sync
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                isSyncing = false
                claim?.syncStatus = .synced
            }
        }
    }
}

// MARK: - Preview

#Preview("Claim Detail") {
    NavigationStack {
        ClaimDetailView(claimId: UUID())
    }
}
