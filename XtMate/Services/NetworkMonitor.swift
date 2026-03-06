import Foundation
import Network
import Combine

// MARK: - Network Monitor

/// Monitors network connectivity status using NWPathMonitor
/// Publishes connectivity changes for reactive UI updates
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    // Allow objectWillChange to be accessed from any context
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: - Published State

    @Published var isConnected = true {
        willSet { objectWillChange.send() }
    }
    @Published var connectionType: ConnectionType = .unknown {
        willSet { objectWillChange.send() }
    }

    // MARK: - Private Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    // MARK: - Init

    private init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }
        monitor.start(queue: queue)
    }

    private func stopMonitoring() {
        monitor.cancel()
    }

    private func updateConnectionStatus(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = isConnected ? .unknown : .none
        }

        // Log status changes
        if wasConnected != isConnected {
            print("Network status changed: \(isConnected ? "Connected" : "Disconnected") via \(connectionType.displayName)")

            // Post notification for components that don't use Combine
            NotificationCenter.default.post(
                name: .networkStatusChanged,
                object: nil,
                userInfo: ["isConnected": isConnected, "type": connectionType]
            )
        }
    }

    // MARK: - Convenience Methods

    /// Check if we have a good connection for uploads (WiFi or strong cellular)
    var isGoodForUpload: Bool {
        guard isConnected else { return false }
        return connectionType == .wifi || connectionType == .ethernet
    }

    /// Human-readable status
    var statusDescription: String {
        guard isConnected else { return "Offline" }
        return "Online (\(connectionType.displayName))"
    }
}

// MARK: - Connection Type

enum ConnectionType: String, CaseIterable {
    case wifi
    case cellular
    case ethernet
    case unknown
    case none

    var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .ethernet: return "Ethernet"
        case .unknown: return "Unknown"
        case .none: return "None"
        }
    }

    var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .unknown: return "questionmark.circle"
        case .none: return "wifi.slash"
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("networkStatusChanged")
}

// MARK: - Network Status View Component

import SwiftUI

/// A small status indicator showing current network status
/// Shows offline banner when disconnected
@available(iOS 16.0, *)
struct NetworkStatusBanner: View {
    @StateObject private var monitor = NetworkMonitor.shared
    @StateObject private var offlineQueue = OfflineQueueManager.shared

    var body: some View {
        if !monitor.isConnected || !offlineQueue.pendingItems.isEmpty {
            HStack(spacing: PaulDavisTheme.Spacing.sm) {
                Image(systemName: monitor.isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    .font(.caption)

                if !monitor.isConnected {
                    Text("Offline")
                        .font(.caption)
                        .fontWeight(.medium)
                } else if !offlineQueue.pendingItems.isEmpty {
                    Text("\(offlineQueue.pendingItems.count) pending")
                        .font(.caption)
                        .fontWeight(.medium)

                    if offlineQueue.isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .padding(.horizontal, PaulDavisTheme.Spacing.md)
            .padding(.vertical, PaulDavisTheme.Spacing.sm)
            .background(monitor.isConnected ? Color.orange : Color.red)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
    }
}

/// Offline indicator badge for use in navigation bars
@available(iOS 16.0, *)
struct OfflineIndicator: View {
    @StateObject private var monitor = NetworkMonitor.shared

    var body: some View {
        if !monitor.isConnected {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundColor(.red)
                .padding(6)
                .background(Color.red.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview("Network Status Banner") {
    VStack(spacing: 20) {
        NetworkStatusBanner()

        Text("Content goes here")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
    }
}
#endif
