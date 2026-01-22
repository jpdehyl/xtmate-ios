//
//  XtMateWidget.swift
//  XtMateWidget
//
//  Home screen widgets for XtMate
//  2026-01-16
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - SLA Status
enum SLAStatus: String, Codable {
    case onTrack
    case warning
    case overdue

    var color: Color {
        switch self {
        case .onTrack: return .green
        case .warning: return .orange
        case .overdue: return .red
        }
    }
}

// MARK: - Estimate Progress Model
struct EstimateProgress: Identifiable, Codable {
    let id: UUID
    let name: String
    let displayAddress: String
    let progressPercent: Int
    let slaStatus: SLAStatus

    var progressColor: Color {
        if progressPercent >= 75 { return .green }
        if progressPercent >= 50 { return .orange }
        return .blue
    }

    static let preview = EstimateProgress(
        id: UUID(),
        name: "Smith Residence",
        displayAddress: "123 Main St, Austin TX",
        progressPercent: 65,
        slaStatus: .onTrack
    )
}

// MARK: - Work Order Model
struct WorkOrderProgress: Identifiable, Codable {
    let id: UUID
    let address: String
    let scheduledTime: Date
    let taskCount: Int
    let completedCount: Int

    var isToday: Bool {
        Calendar.current.isDateInToday(scheduledTime)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: scheduledTime)
    }

    static let preview = WorkOrderProgress(
        id: UUID(),
        address: "456 Oak Ave",
        scheduledTime: Date(),
        taskCount: 5,
        completedCount: 2
    )
}

// MARK: - Progress Data Model
struct ProgressData: Codable {
    let estimates: [EstimateProgress]
    let workOrders: [WorkOrderProgress]
    let lastUpdated: Date

    var activeEstimatesCount: Int {
        estimates.count
    }

    static func loadForWidget() -> ProgressData? {
        // Load from App Group shared container
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.dehyl.xtmate"
        ) else { return nil }

        let fileURL = containerURL.appendingPathComponent("widget_data.json")

        guard let data = try? Data(contentsOf: fileURL),
              let progressData = try? JSONDecoder().decode(ProgressData.self, from: data) else {
            return nil
        }

        return progressData
    }

    static let preview = ProgressData(
        estimates: [
            EstimateProgress(id: UUID(), name: "Smith Residence", displayAddress: "123 Main St", progressPercent: 75, slaStatus: .onTrack),
            EstimateProgress(id: UUID(), name: "Johnson Water Damage", displayAddress: "456 Oak Ave", progressPercent: 45, slaStatus: .warning),
            EstimateProgress(id: UUID(), name: "Williams Fire Claim", displayAddress: "789 Pine Rd", progressPercent: 20, slaStatus: .overdue)
        ],
        workOrders: [
            WorkOrderProgress(id: UUID(), address: "456 Oak Ave", scheduledTime: Date(), taskCount: 5, completedCount: 2)
        ],
        lastUpdated: Date()
    )
}

// MARK: - Widget Entry
struct XtMateWidgetEntry: TimelineEntry {
    let date: Date
    let progressData: ProgressData?
    let configuration: ConfigurationAppIntent
}

// MARK: - Timeline Provider
struct XtMateTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = XtMateWidgetEntry
    typealias Intent = ConfigurationAppIntent
    
    func placeholder(in context: Context) -> XtMateWidgetEntry {
        XtMateWidgetEntry(
            date: Date(),
            progressData: ProgressData.preview,
            configuration: ConfigurationAppIntent()
        )
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> XtMateWidgetEntry {
        let data = ProgressData.loadForWidget() ?? ProgressData.preview
        return XtMateWidgetEntry(
            date: Date(),
            progressData: data,
            configuration: configuration
        )
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<XtMateWidgetEntry> {
        let data = ProgressData.loadForWidget()
        let entry = XtMateWidgetEntry(
            date: Date(),
            progressData: data,
            configuration: configuration
        )
        
        // Refresh every 15 minutes (WidgetKit minimum)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Configuration Intent
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "XtMate Widget"
    static var description: IntentDescription = IntentDescription("Shows your active claims and work orders")
    
    @Parameter(title: "Show Work Orders", default: true)
    var showWorkOrders: Bool?
}

// MARK: - Small Widget View
struct SmallWidgetView: View {
    let entry: XtMateWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("XtMate")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Active claims count
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.progressData?.activeEstimatesCount ?? 0)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Active Claims")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // SLA status indicators (dots)
            if let data = entry.progressData {
                HStack(spacing: 4) {
                    let onTrack = data.estimates.filter { $0.slaStatus == .onTrack }.count
                    let warning = data.estimates.filter { $0.slaStatus == .warning }.count
                    let overdue = data.estimates.filter { $0.slaStatus == .overdue }.count
                    
                    if onTrack > 0 {
                        HStack(spacing: 2) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("\(onTrack)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if warning > 0 {
                        HStack(spacing: 2) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                            Text("\(warning)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if overdue > 0 {
                        HStack(spacing: 2) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text("\(overdue)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "xtmate://claims"))
    }
}

// MARK: - Medium Widget View
struct MediumWidgetView: View {
    let entry: XtMateWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side: Claims summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                    Text("Claims")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                Text("\(entry.progressData?.activeEstimatesCount ?? 0)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                // SLA breakdown
                if let data = entry.progressData {
                    HStack(spacing: 8) {
                        SLADot(color: .green, count: data.estimates.filter { $0.slaStatus == .onTrack }.count)
                        SLADot(color: .orange, count: data.estimates.filter { $0.slaStatus == .warning }.count)
                        SLADot(color: .red, count: data.estimates.filter { $0.slaStatus == .overdue }.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Right side: Next work order
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wrench.fill")
                        .foregroundColor(.orange)
                    Text("Next Up")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                if let nextOrder = entry.progressData?.workOrders.first(where: { $0.isToday }) {
                    Text(nextOrder.address)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(nextOrder.formattedTime)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    
                    Text("\(nextOrder.completedCount)/\(nextOrder.taskCount) tasks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No work scheduled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("for today")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "xtmate://claims"))
    }
}

// MARK: - Large Widget View
struct LargeWidgetView: View {
    let entry: XtMateWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("XtMate - Active Claims")
                    .font(.headline)
                Spacer()
                Text("\(entry.progressData?.activeEstimatesCount ?? 0)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            // Claims list (up to 4)
            if let estimates = entry.progressData?.estimates.prefix(4) {
                ForEach(Array(estimates), id: \.id) { estimate in
                    Link(destination: URL(string: "xtmate://estimates/\(estimate.id.uuidString)")!) {
                        EstimateWidgetRow(estimate: estimate)
                    }
                }
                
                if (entry.progressData?.estimates.count ?? 0) > 4 {
                    HStack {
                        Spacer()
                        Text("View all \(entry.progressData?.activeEstimatesCount ?? 0) claims")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("No active claims")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            Spacer(minLength: 0)
            
            // Last updated
            if let lastUpdated = entry.progressData?.lastUpdated {
                HStack {
                    Spacer()
                    Text("Updated \(lastUpdated, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "xtmate://claims"))
    }
}

// MARK: - Helper Views
struct SLADot: View {
    let color: Color
    let count: Int
    
    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EstimateWidgetRow: View {
    let estimate: EstimateProgress
    
    var body: some View {
        HStack(spacing: 12) {
            // SLA indicator
            Circle()
                .fill(estimate.slaStatus.color)
                .frame(width: 10, height: 10)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(estimate.displayAddress)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Progress
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(estimate.progressPercent)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(estimate.progressColor)
                
                ProgressView(value: Double(estimate.progressPercent), total: 100)
                    .frame(width: 40)
                    .tint(estimate.progressColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Widget Definition
struct XtMateWidget: Widget {
    let kind: String = "XtMateWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: XtMateTimelineProvider()
        ) { entry in
            XtMateWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("XtMate")
        .description("Track your active claims and work orders")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct XtMateWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: XtMateWidgetEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle
// Note: This widget bundle should be used in a separate Widget Extension target.
// When adding as a Widget Extension, add @main attribute back to this struct.
struct XtMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        XtMateWidget()
    }
}

// MARK: - Previews
#Preview("Small", as: .systemSmall) {
    XtMateWidget()
} timeline: {
    XtMateWidgetEntry(date: Date(), progressData: ProgressData.preview, configuration: ConfigurationAppIntent())
}

#Preview("Medium", as: .systemMedium) {
    XtMateWidget()
} timeline: {
    XtMateWidgetEntry(date: Date(), progressData: ProgressData.preview, configuration: ConfigurationAppIntent())
}

#Preview("Large", as: .systemLarge) {
    XtMateWidget()
} timeline: {
    XtMateWidgetEntry(date: Date(), progressData: ProgressData.preview, configuration: ConfigurationAppIntent())
}
