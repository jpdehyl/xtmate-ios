import SwiftUI

// MARK: - My Work View

/// Main view for field staff to see their assigned work orders
/// Per UX requirements: 56pt touch targets, large text, high contrast
@available(iOS 16.0, *)
struct MyWorkView: View {
    @StateObject private var service = WorkOrderService.shared
    @StateObject private var offlineQueue = OfflineQueueManager.shared
    @State private var selectedOrder: WorkOrder?
    @State private var showingCompletedOrders = false

    var body: some View {
        NavigationStack {
            ZStack {
                if service.isLoading && service.workOrders.isEmpty {
                    ProgressView("Loading work orders...")
                        .font(.title3)
                } else if service.workOrders.isEmpty {
                    EmptyWorkOrdersView()
                } else {
                    workOrdersList
                }
            }
            .navigationTitle("My Work")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    OfflineIndicator()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCompletedOrders.toggle() }) {
                        Image(systemName: showingCompletedOrders ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel(showingCompletedOrders ? "Hide completed" : "Show completed")
                }
            }
            .safeAreaInset(edge: .top) {
                // Show offline/sync banner when needed
                if !offlineQueue.pendingItems.isEmpty || !NetworkMonitor.shared.isConnected {
                    NetworkStatusBanner()
                        .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                        .padding(.top, PaulDavisTheme.Spacing.sm)
                }
            }
            .refreshable {
                await service.fetchMyWorkOrders()
            }
            .task {
                await service.fetchMyWorkOrders()
            }
            .navigationDestination(item: $selectedOrder) { order in
                WorkOrderDetailView(workOrder: order)
            }
        }
    }

    // MARK: - Work Orders List

    private var workOrdersList: some View {
        ScrollView {
            LazyVStack(spacing: PaulDavisTheme.Spacing.lg) {
                // Today section
                if !service.todayOrders.isEmpty {
                    WorkOrderSection(
                        title: "Today",
                        icon: "sun.max.fill",
                        iconColor: .orange,
                        orders: service.todayOrders,
                        onSelect: { selectedOrder = $0 }
                    )
                }

                // Upcoming section
                if !service.upcomingOrders.isEmpty {
                    WorkOrderSection(
                        title: "Upcoming",
                        icon: "calendar",
                        iconColor: .blue,
                        orders: service.upcomingOrders,
                        onSelect: { selectedOrder = $0 }
                    )
                }

                // Completed section (toggleable)
                if showingCompletedOrders && !service.completedOrders.isEmpty {
                    WorkOrderSection(
                        title: "Completed",
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        orders: service.completedOrders,
                        onSelect: { selectedOrder = $0 }
                    )
                }
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.lg)
            .padding(.vertical, PaulDavisTheme.Spacing.md)
        }
    }
}

// MARK: - Work Order Section

@available(iOS 16.0, *)
struct WorkOrderSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let orders: [WorkOrder]
    let onSelect: (WorkOrder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            // Section header
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("(\(orders.count))")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.xs)

            // Work order cards
            ForEach(orders) { order in
                WorkOrderRow(order: order)
                    .onTapGesture {
                        // Haptic feedback for field staff
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        onSelect(order)
                    }
            }
        }
    }
}

// MARK: - Work Order Row

@available(iOS 16.0, *)
struct WorkOrderRow: View {
    let order: WorkOrder

    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            // Property address
            Text(order.propertyAddress)
                .font(.title3) // Larger text for outdoor visibility
                .fontWeight(.semibold)
                .lineLimit(2)

            // Status and time
            HStack(spacing: PaulDavisTheme.Spacing.lg) {
                // Scheduled time
                if let time = order.scheduledTime {
                    HStack(spacing: PaulDavisTheme.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.body)
                        Text(time, style: .time)
                            .font(.body)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Status badge
                WorkOrderStatusBadge(status: order.status)

                // Progress indicator
                HStack(spacing: PaulDavisTheme.Spacing.xs) {
                    Image(systemName: "checklist")
                        .font(.body)
                    Text("\(order.completedItems)/\(order.totalItems)")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .foregroundColor(order.completedItems == order.totalItems ? .green : .secondary)
            }

            // Priority indicator for high/urgent
            if order.priority == .high || order.priority == .urgent {
                HStack(spacing: PaulDavisTheme.Spacing.xs) {
                    Image(systemName: order.priority.icon)
                        .font(.caption)
                    Text(order.priority.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(priorityColor)
                .padding(.horizontal, PaulDavisTheme.Spacing.sm)
                .padding(.vertical, PaulDavisTheme.Spacing.xs)
                .background(priorityColor.opacity(0.15))
                .clipShape(Capsule())
            }

            // Clocked in indicator
            if order.isClockedIn {
                HStack(spacing: PaulDavisTheme.Spacing.xs) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.body)
                    Text("Clocked In")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
            }
        }
        .padding(PaulDavisTheme.Spacing.lg)
        .frame(minHeight: 100) // 56pt minimum touch target guideline (with some extra)
        .background(PaulDavisTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(Rectangle()) // Makes entire card tappable
    }

    private var priorityColor: Color {
        switch order.priority {
        case .urgent: return .red
        case .high: return .orange
        default: return .blue
        }
    }
}

// MARK: - Status Badge

struct WorkOrderStatusBadge: View {
    let status: WorkOrderStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption)
            Text(status.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, PaulDavisTheme.Spacing.sm)
        .padding(.vertical, PaulDavisTheme.Spacing.xs)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .assigned: return .gray
        case .enRoute: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}

// MARK: - Empty State

struct EmptyWorkOrdersView: View {
    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.xl) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Work Orders")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You don't have any work orders assigned.\nPull down to refresh.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(PaulDavisTheme.Spacing.xxxl)
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    MyWorkView()
}
#endif
