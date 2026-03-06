import SwiftUI
import SwiftUI
import Combine

// MARK: - Home Dashboard View

/// Enhanced dashboard showing claims with status and quick actions
struct HomeDashboardView: View {
    @StateObject private var viewModel = ClaimsViewModel()
    @State private var showingNewClaim = false
    @State private var showingLinkEstimate = false
    @State private var showingOnboarding = false
    @State private var searchText = ""
    @State private var selectedFilter: ClaimFilter = .all
    @State private var showingConnectSheet = false

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    enum ClaimFilter: String, CaseIterable {
        case all = "All"
        case insurance = "Insurance"
        case privateJob = "Private"
        case pending = "Pending Sync"
        case active = "Active"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .insurance: return "building.columns"
            case .privateJob: return "person"
            case .pending: return "arrow.triangle.2.circlepath"
            case .active: return "clock"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaulDavisTheme.Spacing.lg) {
                    // Status Cards Section
                    statusCardsSection
                    
                    // Filter Pills
                    filterSection
                    
                    // Claims List
                    claimsSection
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.xl)
            }
            .background(PaulDavisTheme.Colors.background)
            .navigationTitle("XtMate")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingConnectSheet = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search claims...")
            .sheet(isPresented: $showingNewClaim) {
                NewClaimSheet(onSave: { claimData in
                    viewModel.createClaim(from: claimData)
                })
            }
            .sheet(isPresented: $showingLinkEstimate) {
                LinkEstimateSheet(onLinked: { estimate in
                    // Refresh the claims list after linking
                    viewModel.loadClaims()
                })
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showingConnectSheet) {
                ConnectToWebSettingsView()
            }
            .refreshable {
                await viewModel.syncAll()
            }
            .onAppear {
                if !hasCompletedOnboarding {
                    showingOnboarding = true
                }
            }
        }
    }
    
    // MARK: - Status Cards Section
    
    private var statusCardsSection: some View {
        VStack(spacing: PaulDavisTheme.Spacing.md) {
            if !AuthService.shared.isSignedIn {
                UrgentBanner(
                    icon: "gearshape.2.fill",
                    title: "⚙️ Connect to Web",
                    action: { showingConnectSheet = true }
                )
            }

            // Urgent banner if needed
            if viewModel.pendingSyncCount > 0 {
                UrgentBanner(
                    icon: "exclamationmark.triangle.fill",
                    title: "\(viewModel.pendingSyncCount) claim\(viewModel.pendingSyncCount == 1 ? "" : "s") pending sync",
                    action: {
                        Task {
                            await viewModel.syncAll()
                        }
                    }
                )
            }
            
            // Stats row
            HStack(spacing: PaulDavisTheme.Spacing.md) {
                StatCard(
                    icon: "doc.text.fill",
                    label: "Total",
                    value: "\(viewModel.totalClaims)",
                    color: .blue
                )
                
                StatCard(
                    icon: "clock.fill",
                    label: "In Progress",
                    value: "\(viewModel.activeClaims)",
                    color: .orange
                )
                
                StatCard(
                    icon: "checkmark.circle.fill",
                    label: "Completed",
                    value: "\(viewModel.completedClaims)",
                    color: .green
                )
            }
        }
        .padding(.top, PaulDavisTheme.Spacing.sm)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                ForEach(ClaimFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        filter: filter,
                        isSelected: selectedFilter == filter,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = filter
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Claims Section
    
    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            // Section header
            HStack {
                Text(selectedFilter == .all ? "Recent Claims" : selectedFilter.rawValue)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: PaulDavisTheme.Spacing.md) {
                    Button(action: { showingLinkEstimate = true }) {
                        Label("Link", systemImage: "link")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PaulDavisTheme.Colors.secondary)
                    }

                    Button(action: { showingNewClaim = true }) {
                        Label("New", systemImage: PaulDavisTheme.Icons.add)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PaulDavisTheme.Colors.primary)
                    }
                }
            }
            
            // Claims list
            if filteredClaims.isEmpty {
                EmptyClaimsView(
                    filter: selectedFilter,
                    onCreateClaim: { showingNewClaim = true }
                )
            } else {
                LazyVStack(spacing: PaulDavisTheme.Spacing.md) {
                    ForEach(filteredClaims) { claim in
                        NavigationLink(value: claim) {
                            EnhancedClaimCard(claim: claim, viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: ClaimListItem.self) { claim in
            ClaimDetailView(claimId: claim.id)
        }
    }
    
    private var filteredClaims: [ClaimListItem] {
        let claims = viewModel.claims
        
        // Apply filter
        let filtered: [ClaimListItem]
        switch selectedFilter {
        case .all:
            filtered = claims
        case .insurance:
            filtered = claims.filter { $0.jobType == .insurance }
        case .privateJob:
            filtered = claims.filter { $0.jobType == .privateJob }
        case .pending:
            filtered = claims.filter { $0.syncStatus == .pending }
        case .active:
            filtered = claims.filter { $0.status == .inProgress }
        }
        
        // Apply search
        if searchText.isEmpty {
            return filtered
        } else {
            return filtered.filter { claim in
                claim.displayName.localizedCaseInsensitiveContains(searchText) ||
                (claim.claimNumber?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (claim.insuredName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
}

// MARK: - Urgent Banner

private struct UrgentBanner: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: PaulDavisTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .padding(PaulDavisTheme.Spacing.md)
            .background(Color.orange.opacity(0.1))
            .continuousCornerRadius(PaulDavisTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaulDavisTheme.Spacing.md)
        .background(PaulDavisTheme.Colors.cardBackground)
        .continuousCornerRadius(PaulDavisTheme.Radius.md)
        .appShadow(PaulDavisTheme.Shadow.sm)
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let filter: HomeDashboardView.ClaimFilter
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                Text(filter.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.md)
            .padding(.vertical, PaulDavisTheme.Spacing.sm)
            .background(isSelected ? PaulDavisTheme.Colors.primary : PaulDavisTheme.Colors.cardBackground)
            .foregroundStyle(isSelected ? .white : .primary)
            .continuousCornerRadius(PaulDavisTheme.Radius.full)
            .appShadow(isSelected ? PaulDavisTheme.Shadow.sm : PaulDavisTheme.Shadow.sm)
        }
    }
}

// MARK: - Enhanced Claim Card

private struct EnhancedClaimCard: View {
    let claim: ClaimListItem
    let viewModel: ClaimsViewModel
    
    @State private var showingSyncAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            // Header row
            HStack {
                // Loss type icon
                Image(systemName: claim.lossType.icon)
                    .font(.title3)
                    .foregroundStyle(claim.lossType.color)
                    .frame(width: 40, height: 40)
                    .background(claim.lossType.color.opacity(0.15))
                    .continuousCornerRadius(PaulDavisTheme.Radius.sm)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(claim.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let claimNumber = claim.claimNumber {
                        Text("#\(claimNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Sync status badge
                syncStatusBadge
            }
            
            // Property info
            if let address = claim.propertyAddress {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Stats row
            HStack(spacing: PaulDavisTheme.Spacing.lg) {
                ClaimStatItem(icon: "square.split.bottomrightquarter", text: "\(claim.roomCount) rooms")
                
                if claim.damageCount > 0 {
                    ClaimStatItem(icon: "exclamationmark.triangle.fill", text: "\(claim.damageCount) damages", color: .orange)
                }
                
                if claim.totalSquareFeet > 0 {
                    ClaimStatItem(icon: "ruler", text: "\(Int(claim.totalSquareFeet)) SF")
                }
                
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                ActionButton(
                    icon: claim.syncStatus == .pending ? "arrow.triangle.2.circlepath" : "arrow.right",
                    label: claim.syncStatus == .pending ? "Sync" : "Continue",
                    isPrimary: true,
                    action: {
                        if claim.syncStatus == .pending {
                            Task {
                                await viewModel.syncClaim(claim.id)
                            }
                        }
                    }
                )
                
                if let phone = claim.insuredPhone {
                    ActionButton(
                        icon: "phone.fill",
                        label: "Call",
                        isPrimary: false,
                        action: { callPhone(phone) }
                    )
                }
                
                if let address = claim.propertyAddress {
                    ActionButton(
                        icon: "map.fill",
                        label: "Navigate",
                        isPrimary: false,
                        action: { openMaps(address) }
                    )
                }
            }
        }
        .padding(PaulDavisTheme.Spacing.md)
        .background(PaulDavisTheme.Colors.cardBackground)
        .continuousCornerRadius(PaulDavisTheme.Radius.md)
        .appShadow(PaulDavisTheme.Shadow.sm)
    }
    
    @ViewBuilder
    private var syncStatusBadge: some View {
        switch claim.syncStatus {
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .pending:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case .syncing:
            ProgressView()
                .scaleEffect(0.8)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private func callPhone(_ number: String) {
        let cleaned = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openMaps(_ address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Claim Stat Item

private struct ClaimStatItem: View {
    let icon: String
    let text: String
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let label: String
    let isPrimary: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.md)
            .padding(.vertical, PaulDavisTheme.Spacing.sm)
            .background(isPrimary ? PaulDavisTheme.Colors.primary : PaulDavisTheme.Colors.surface)
            .foregroundStyle(isPrimary ? .white : .primary)
            .continuousCornerRadius(PaulDavisTheme.Radius.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty Claims View

private struct EmptyClaimsView: View {
    let filter: HomeDashboardView.ClaimFilter
    let onCreateClaim: () -> Void
    
    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.lg) {
            Image(systemName: filter == .all ? "doc.text" : "tray")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: PaulDavisTheme.Spacing.xs) {
                Text(emptyTitle)
                    .font(.headline)
                
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if filter == .all {
                Button(action: onCreateClaim) {
                    Label("Create Your First Claim", systemImage: PaulDavisTheme.Icons.add)
                        .font(.headline)
                        .padding(.horizontal, PaulDavisTheme.Spacing.xl)
                        .padding(.vertical, PaulDavisTheme.Spacing.md)
                        .background(PaulDavisTheme.Colors.primary)
                        .foregroundStyle(.white)
                        .continuousCornerRadius(PaulDavisTheme.Radius.md)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PaulDavisTheme.Spacing.xxl)
    }
    
    private var emptyTitle: String {
        switch filter {
        case .all: return "No Claims Yet"
        case .insurance: return "No Insurance Claims"
        case .privateJob: return "No Private Jobs"
        case .pending: return "All Synced!"
        case .active: return "No Active Claims"
        }
    }
    
    private var emptyMessage: String {
        switch filter {
        case .all: return "Start by creating your first claim"
        case .insurance: return "Insurance claims will appear here"
        case .privateJob: return "Private jobs will appear here"
        case .pending: return "All claims are synced to the cloud"
        case .active: return "No claims currently in progress"
        }
    }
}

// MARK: - Claims View Model

@MainActor
class ClaimsViewModel: ObservableObject {
    @Published var claims: [ClaimListItem] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    
    var totalClaims: Int { claims.count }
    var activeClaims: Int { claims.filter { $0.status == .inProgress }.count }
    var completedClaims: Int { claims.filter { $0.status == .complete }.count }
    var pendingSyncCount: Int { claims.filter { $0.syncStatus == .pending }.count }
    
    init() {
        loadClaims()
    }
    
    func loadClaims() {
        // TODO: Load from persistence
        // For now, using mock data
        claims = []
    }
    
    func createClaim(from data: ClaimData) {
        // TODO: Create claim from data
        let claim = ClaimListItem(
            id: UUID(),
            displayName: data.displayName,
            claimNumber: data.claimNumber,
            jobType: data.jobType,
            lossType: data.lossType,
            insuredName: data.insuredName,
            insuredPhone: data.insuredPhone,
            propertyAddress: data.propertyAddress,
            dateOfLoss: data.dateOfLoss,
            status: .draft,
            syncStatus: .pending,
            roomCount: 0,
            damageCount: 0,
            totalSquareFeet: 0,
            createdAt: Date()
        )
        claims.insert(claim, at: 0)
    }
    
    func syncClaim(_ id: UUID) async {
        guard let index = claims.firstIndex(where: { $0.id == id }) else { return }
        claims[index].syncStatus = .syncing
        
        // Simulate sync
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        claims[index].syncStatus = .synced
    }
    
    func syncAll() async {
        isSyncing = true
        
        for index in claims.indices where claims[index].syncStatus == .pending {
            await syncClaim(claims[index].id)
        }
        
        isSyncing = false
    }
}

// MARK: - Claim List Item

struct ClaimListItem: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var claimNumber: String?
    var jobType: JobType
    var lossType: LossType
    var insuredName: String?
    var insuredPhone: String?
    var insuredEmail: String?
    var adjusterName: String?
    var adjusterPhone: String?
    var propertyAddress: String?
    var propertyCity: String?
    var propertyState: String?
    var dateOfLoss: Date
    var status: ClaimStatus
    var syncStatus: SyncStatus
    var roomCount: Int
    var damageCount: Int
    var totalSquareFeet: Double
    var createdAt: Date
}

enum ClaimStatus {
    case draft
    case inProgress
    case complete
}

enum SyncStatus {
    case synced
    case pending
    case syncing
    case failed
}

// MARK: - Preview

#Preview("Home Dashboard") {
    HomeDashboardView()
}
