import SwiftUI

// MARK: - Work Order Detail View

/// Detail view for a work order with time tracking and task checklist
/// Per UX requirements: 56pt touch targets, large text (17pt+), high contrast, haptic feedback
@available(iOS 16.0, *)
struct WorkOrderDetailView: View {
    let workOrder: WorkOrder

    @StateObject private var service = WorkOrderService.shared
    @State private var localOrder: WorkOrder
    @State private var showingSignature = false
    @State private var showingBreakEntry = false
    @State private var breakMinutes: Int = 0
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    // Photo capture state
    @State private var selectedItemForPhoto: WorkOrderItem?
    @State private var taskPhotos: [UUID: [UIImage]] = [:]
    @State private var showingPhotoCapture = false

    init(workOrder: WorkOrder) {
        self.workOrder = workOrder
        _localOrder = State(initialValue: workOrder)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: PaulDavisTheme.Spacing.xl) {
                // Property header
                PropertyHeaderCard(order: localOrder)
                
                // Time tracking card
                TimeTrackingCard(
                    order: localOrder,
                    elapsedSeconds: elapsedSeconds,
                    isProcessing: isProcessing,
                    onClockIn: clockIn,
                    onClockOut: { showingBreakEntry = true }
                )
                
                // Task checklist
                TaskChecklistCard(
                    items: localOrder.items,
                    taskPhotos: taskPhotos,
                    onToggle: toggleItem,
                    onAddPhoto: { item in
                        selectedItemForPhoto = item
                        showingPhotoCapture = true
                    },
                    isProcessing: isProcessing
                )
                
                // Complete button (when all items done)
                if localOrder.allItemsComplete && localOrder.status != .completed {
                    Button(action: { showingSignature = true }) {
                        HStack(spacing: PaulDavisTheme.Spacing.md) {
                            Image(systemName: "signature")
                                .font(.title2)
                            Text("Complete & Get Signature")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56) // 56pt touch target
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                    }
                    .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                }
                
                // Notes section
                if let notes = localOrder.notes, !notes.isEmpty {
                    NotesCard(title: "Work Order Notes", notes: notes)
                }
            }
            .padding(.vertical, PaulDavisTheme.Spacing.lg)
        }
        .navigationTitle("Work Order")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSignature) {
            SignatureCaptureView(
                onComplete: { signatureData, signedName in
                    Task {
                        await completeWithSignature(signatureData: signatureData, signedName: signedName)
                    }
                    showingSignature = false
                },
                onCancel: {
                    showingSignature = false
                }
            )
        }
        .sheet(isPresented: $showingBreakEntry) {
            BreakEntrySheet(
                breakMinutes: $breakMinutes,
                onConfirm: {
                    showingBreakEntry = false
                    Task { await clockOut() }
                },
                onCancel: {
                    showingBreakEntry = false
                }
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingPhotoCapture) {
            if let item = selectedItemForPhoto {
                TaskPhotoSheet(
                    item: item,
                    photos: Binding(
                        get: { taskPhotos[item.id] ?? [] },
                        set: { taskPhotos[item.id] = $0 }
                    ),
                    onSave: { photos in
                        taskPhotos[item.id] = photos
                        // Upload photos to server
                        Task {
                            await uploadTaskPhotos(itemId: item.id, photos: photos)
                        }
                        showingPhotoCapture = false
                    },
                    onCancel: {
                        showingPhotoCapture = false
                    }
                )
            }
        }
        .onAppear {
            startTimerIfNeeded()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: localOrder.isClockedIn) { _, isClockedIn in
            if isClockedIn {
                startTimerIfNeeded()
            } else {
                stopTimer()
            }
        }
    }
    
    // MARK: - Timer Management
    
    private func startTimerIfNeeded() {
        guard localOrder.isClockedIn, timer == nil else { return }
        updateElapsedTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsedTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateElapsedTime() {
        guard let clockIn = localOrder.clockIn else {
            elapsedSeconds = 0
            return
        }
        let breakSeconds = localOrder.breakMinutes * 60
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(clockIn)) - breakSeconds)
    }
    
    // MARK: - Actions
    
    private func clockIn() {
        Task {
            isProcessing = true
            
            // Haptic feedback
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            
            do {
                let updated = try await service.clockIn(workOrderId: localOrder.id)
                localOrder = updated
                
                // Success haptic
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                
                // Error haptic
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
            }
            
            isProcessing = false
        }
    }
    
    private func clockOut() async {
        isProcessing = true
        
        // Haptic feedback
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        do {
            let updated = try await service.clockOut(workOrderId: localOrder.id, breakMinutes: breakMinutes)
            localOrder = updated
            
            // Success haptic
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            
            // Error haptic
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
        }
        
        isProcessing = false
    }
    
    private func toggleItem(_ item: WorkOrderItem) {
        Task {
            isProcessing = true
            
            // Haptic feedback
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
            
            let newStatus: WorkOrderItemStatus = item.status == .completed ? .pending : .completed
            
            do {
                let updated = try await service.updateItemStatus(
                    workOrderId: localOrder.id,
                    itemId: item.id,
                    status: newStatus
                )
                localOrder = updated
                
                // Success haptic
                if newStatus == .completed {
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            
            isProcessing = false
        }
    }
    
    private func completeWithSignature(signatureData: Data, signedName: String) async {
        isProcessing = true

        do {
            let updated = try await service.completeWithSignature(
                workOrderId: localOrder.id,
                signatureData: signatureData,
                signedName: signedName
            )
            localOrder = updated

            // Success haptic
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }

        isProcessing = false
    }

    private func uploadTaskPhotos(itemId: UUID, photos: [UIImage]) async {
        guard !photos.isEmpty else { return }

        do {
            for photo in photos {
                _ = try await service.uploadTaskPhoto(
                    workOrderId: localOrder.id,
                    itemId: itemId,
                    image: photo
                )
            }

            // Success haptic
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // Queue for offline sync if upload fails
            await OfflineQueueManager.shared.queuePhotoUpload(
                workOrderId: localOrder.id,
                itemId: itemId,
                photos: photos
            )

            // Show subtle error (photo queued for later)
            print("Photo upload queued for later: \(error.localizedDescription)")
        }
    }
}

// MARK: - Property Header Card

@available(iOS 16.0, *)
struct PropertyHeaderCard: View {
    let order: WorkOrder
    
    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            // Address
            Text(order.propertyAddress)
                .font(.title2)
                .fontWeight(.bold)
            
            // Estimate info
            if let estimate = order.estimate {
                if let insuredName = estimate.insuredName, !insuredName.isEmpty {
                    HStack(spacing: PaulDavisTheme.Spacing.sm) {
                        Image(systemName: "person.fill")
                            .font(.body)
                        Text(insuredName)
                            .font(.body)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let claimNumber = estimate.claimNumber, !claimNumber.isEmpty {
                    HStack(spacing: PaulDavisTheme.Spacing.sm) {
                        Image(systemName: "doc.text")
                            .font(.body)
                        Text("Claim: \(claimNumber)")
                            .font(.body)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            // Status badge
            HStack {
                WorkOrderStatusBadge(status: order.status)
                
                Spacer()
                
                // Priority
                if order.priority == .high || order.priority == .urgent {
                    HStack(spacing: 4) {
                        Image(systemName: order.priority.icon)
                            .font(.caption)
                        Text(order.priority.displayName)
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, PaulDavisTheme.Spacing.sm)
                    .padding(.vertical, PaulDavisTheme.Spacing.xs)
                    .background(order.priority == .urgent ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(order.priority == .urgent ? .red : .orange)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(PaulDavisTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaulDavisTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .padding(.horizontal, PaulDavisTheme.Spacing.lg)
    }
}

// MARK: - Time Tracking Card

@available(iOS 16.0, *)
struct TimeTrackingCard: View {
    let order: WorkOrder
    let elapsedSeconds: Int
    let isProcessing: Bool
    let onClockIn: () -> Void
    let onClockOut: () -> Void
    
    private var formattedElapsedTime: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: PaulDavisTheme.Spacing.lg) {
            // Title
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Time Tracking")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Elapsed time display
            if order.isClockedIn {
                VStack(spacing: PaulDavisTheme.Spacing.sm) {
                    Text(formattedElapsedTime)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    
                    Text("Time Elapsed")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if order.breakMinutes > 0 {
                        Text("(\(order.breakMinutes) min break)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, PaulDavisTheme.Spacing.md)
            } else if let totalHours = order.totalHours {
                // Show completed time
                VStack(spacing: PaulDavisTheme.Spacing.sm) {
                    Text(String(format: "%.2f hrs", totalHours))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.green)
                    
                    Text("Total Time Worked")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, PaulDavisTheme.Spacing.md)
            }
            
            // Clock in/out button
            if order.status != .completed && order.status != .cancelled {
                Button(action: {
                    if order.isClockedIn {
                        onClockOut()
                    } else {
                        onClockIn()
                    }
                }) {
                    HStack(spacing: PaulDavisTheme.Spacing.md) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: order.isClockedIn ? "clock.badge.xmark" : "clock.badge.checkmark")
                                .font(.title2)
                        }
                        Text(order.isClockedIn ? "Clock Out" : "Clock In")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56) // 56pt touch target
                    .background(order.isClockedIn ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                }
                .disabled(isProcessing)
            }
        }
        .padding(PaulDavisTheme.Spacing.lg)
        .background(PaulDavisTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .padding(.horizontal, PaulDavisTheme.Spacing.lg)
    }
}

// MARK: - Task Checklist Card

@available(iOS 16.0, *)
struct TaskChecklistCard: View {
    let items: [WorkOrderItem]
    let taskPhotos: [UUID: [UIImage]]
    let onToggle: (WorkOrderItem) -> Void
    let onAddPhoto: (WorkOrderItem) -> Void
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.lg) {
            // Title with progress
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Tasks")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.filter { $0.status == .completed }.count)/\(items.count)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .clipShape(Capsule())

                    let progress = items.isEmpty ? 0 : CGFloat(items.filter { $0.status == .completed }.count) / CGFloat(items.count)
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .clipShape(Capsule())
                        .animation(.easeInOut, value: progress)
                }
            }
            .frame(height: 8)

            // Task list
            VStack(spacing: PaulDavisTheme.Spacing.sm) {
                ForEach(items.sorted(by: { $0.order < $1.order })) { item in
                    TaskItemRow(
                        item: item,
                        photoCount: taskPhotos[item.id]?.count ?? 0,
                        onToggle: onToggle,
                        onAddPhoto: onAddPhoto,
                        isProcessing: isProcessing
                    )
                }
            }
        }
        .padding(PaulDavisTheme.Spacing.lg)
        .background(PaulDavisTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .padding(.horizontal, PaulDavisTheme.Spacing.lg)
    }
}

// MARK: - Task Item Row

@available(iOS 16.0, *)
struct TaskItemRow: View {
    let item: WorkOrderItem
    let photoCount: Int
    let onToggle: (WorkOrderItem) -> Void
    let onAddPhoto: (WorkOrderItem) -> Void
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: PaulDavisTheme.Spacing.md) {
            // Checkbox button
            Button(action: { onToggle(item) }) {
                ZStack {
                    Circle()
                        .stroke(item.status == .completed ? Color.green : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    if item.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)

            // Description (tappable area)
            Button(action: { onToggle(item) }) {
                Text(item.description)
                    .font(.body) // 17pt minimum
                    .strikethrough(item.status == .completed)
                    .foregroundColor(item.status == .completed ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)

            // Photo button
            Button(action: { onAddPhoto(item) }) {
                HStack(spacing: 4) {
                    Image(systemName: photoCount > 0 ? "photo.fill" : "camera")
                        .font(.system(size: 14))
                    if photoCount > 0 {
                        Text("\(photoCount)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(photoCount > 0 ? .green : .blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(photoCount > 0 ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())

            // Category badge
            if let category = item.lineItem?.category {
                Text(category)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(PaulDavisTheme.Spacing.md)
        .frame(minHeight: 56) // 56pt touch target
        .background(item.status == .completed ? Color.green.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.sm))
    }
}

// MARK: - Notes Card

struct NotesCard: View {
    let title: String
    let notes: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
            HStack {
                Image(systemName: "note.text")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Text(notes)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(PaulDavisTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaulDavisTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .padding(.horizontal, PaulDavisTheme.Spacing.lg)
    }
}

// MARK: - Break Entry Sheet

@available(iOS 16.0, *)
struct BreakEntrySheet: View {
    @Binding var breakMinutes: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    private let breakOptions = [0, 15, 30, 45, 60, 90]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: PaulDavisTheme.Spacing.xl) {
                Text("How long was your break?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, PaulDavisTheme.Spacing.xl)
                
                // Break options
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PaulDavisTheme.Spacing.md) {
                    ForEach(breakOptions, id: \.self) { minutes in
                        Button(action: {
                            breakMinutes = minutes
                            let feedback = UIImpactFeedbackGenerator(style: .light)
                            feedback.impactOccurred()
                        }) {
                            Text(minutes == 0 ? "No Break" : "\(minutes) min")
                                .font(.title3)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56) // 56pt touch target
                                .background(breakMinutes == minutes ? Color.blue : Color.gray.opacity(0.1))
                                .foregroundColor(breakMinutes == minutes ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                        }
                    }
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                
                Spacer()
                
                // Confirm button
                Button(action: onConfirm) {
                    Text("Confirm Clock Out")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.xl)
            }
            .navigationTitle("Break Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Task Photo Sheet

@available(iOS 16.0, *)
struct TaskPhotoSheet: View {
    let item: WorkOrderItem
    @Binding var photos: [UIImage]
    let onSave: ([UIImage]) -> Void
    let onCancel: () -> Void

    @State private var localPhotos: [UIImage] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.lg) {
                    // Task info
                    VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.sm) {
                        Text("Task")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(item.description)
                            .font(.body)
                            .fontWeight(.medium)

                        if let category = item.lineItem?.category {
                            Text(category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(PaulDavisTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PaulDavisTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))

                    // Photo capture
                    TaskPhotoCapture(
                        selectedPhotos: $localPhotos,
                        maxPhotos: 5
                    )
                    .padding(PaulDavisTheme.Spacing.lg)
                    .background(PaulDavisTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))

                    // Hint text
                    Text("Take photos to document task completion. Photos help verify work quality and support insurance claims.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, PaulDavisTheme.Spacing.md)
                }
                .padding(PaulDavisTheme.Spacing.lg)
            }
            .navigationTitle("Completion Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(localPhotos)
                    }
                    .fontWeight(.semibold)
                    .disabled(localPhotos.isEmpty)
                }
            }
        }
        .onAppear {
            localPhotos = photos
        }
        .presentationDetents([.large])
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    NavigationStack {
        WorkOrderDetailView(workOrder: WorkOrder(
            id: UUID(),
            estimateId: UUID(),
            assignedTo: "user123",
            status: .inProgress,
            scheduledDate: Date(),
            scheduledStartTime: "09:00",
            scheduledEndTime: "17:00",
            clockIn: Date().addingTimeInterval(-3600),
            breakMinutes: 0,
            priority: .normal,
            items: [
                WorkOrderItem(
                    id: UUID(),
                    workOrderId: UUID(),
                    lineItemId: nil,
                    status: .completed,
                    order: 0,
                    createdAt: Date(),
                    lineItem: LineItemSummary(
                        id: UUID(),
                        description: "Remove water damaged drywall",
                        category: "DEM",
                        selector: nil,
                        quantity: 50,
                        unit: "SF"
                    )
                ),
                WorkOrderItem(
                    id: UUID(),
                    workOrderId: UUID(),
                    lineItemId: nil,
                    status: .pending,
                    order: 1,
                    createdAt: Date(),
                    lineItem: LineItemSummary(
                        id: UUID(),
                        description: "Install new drywall",
                        category: "DRW",
                        selector: nil,
                        quantity: 50,
                        unit: "SF"
                    )
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            estimate: EstimateSummary(
                id: UUID(),
                name: "Smith Water Damage",
                propertyAddress: "123 Main Street",
                propertyCity: "Austin",
                propertyState: "TX",
                insuredName: "John Smith",
                claimNumber: "CLM-2025-001234"
            )
        ))
    }
}
#endif
