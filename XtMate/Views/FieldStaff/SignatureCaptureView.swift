import SwiftUI
import PencilKit

// MARK: - Signature Capture View

/// View for capturing customer signature using PencilKit
/// Per UX requirements: 56pt touch targets, high contrast, clear visual feedback
@available(iOS 16.0, *)
struct SignatureCaptureView: View {
    let onComplete: (Data, String) -> Void
    let onCancel: () -> Void
    
    @State private var canvasView = PKCanvasView()
    @State private var signedName: String = ""
    @State private var hasDrawn = false
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instructions
                VStack(spacing: PaulDavisTheme.Spacing.sm) {
                    Image(systemName: "signature")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    Text("Customer Signature Required")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Please sign below to confirm work completion")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, PaulDavisTheme.Spacing.xl)
                
                // Signature canvas
                VStack(spacing: PaulDavisTheme.Spacing.md) {
                    SignatureCanvasRepresentable(
                        canvasView: $canvasView,
                        hasDrawn: $hasDrawn
                    )
                    .frame(height: 200)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md)
                            .stroke(hasDrawn ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                    
                    // Signature line
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        Text("Sign above")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                    
                    // Clear button
                    Button(action: clearSignature) {
                        HStack(spacing: PaulDavisTheme.Spacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Clear")
                        }
                        .font(.body)
                        .foregroundColor(.red)
                    }
                    .opacity(hasDrawn ? 1 : 0.3)
                    .disabled(!hasDrawn)
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                
                Spacer()
                
                // Name field
                VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.sm) {
                    Text("Print Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    TextField("Customer's full name", text: $signedName)
                        .font(.title3)
                        .padding(PaulDavisTheme.Spacing.md)
                        .frame(height: 56) // 56pt touch target
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                        .focused($isNameFieldFocused)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.lg)
                
                // Done button
                Button(action: complete) {
                    HStack(spacing: PaulDavisTheme.Spacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                        Text("Complete Work Order")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56) // 56pt touch target
                    .background(isValid ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                }
                .disabled(!isValid)
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.xl)
            }
            .navigationTitle("Customer Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onTapGesture {
                isNameFieldFocused = false
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValid: Bool {
        hasDrawn && !signedName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // MARK: - Actions
    
    private func clearSignature() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        
        canvasView.drawing = PKDrawing()
        hasDrawn = false
    }
    
    private func complete() {
        guard isValid else { return }
        
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        // Capture signature as PNG image
        let image = canvasView.drawing.image(
            from: canvasView.bounds,
            scale: UIScreen.main.scale
        )
        
        guard let pngData = image.pngData() else {
            print("Failed to convert signature to PNG")
            return
        }
        
        onComplete(pngData, signedName.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Signature Canvas Representable

@available(iOS 16.0, *)
struct SignatureCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var hasDrawn: Bool
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput // Works with finger and Apple Pencil
        canvasView.delegate = context.coordinator
        
        // Use a thin black pen for signatures
        let tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.tool = tool
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hasDrawn: $hasDrawn)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var hasDrawn: Bool
        
        init(hasDrawn: Binding<Bool>) {
            _hasDrawn = hasDrawn
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            hasDrawn = !canvasView.drawing.strokes.isEmpty
        }
    }
}

// MARK: - Fallback Signature View (for older iOS)

/// Fallback signature capture using Core Graphics for devices without PencilKit support
struct FallbackSignatureView: View {
    let onComplete: (Data, String) -> Void
    let onCancel: () -> Void
    
    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var signedName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    
    private var hasDrawn: Bool {
        !lines.isEmpty || !currentLine.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instructions
                VStack(spacing: PaulDavisTheme.Spacing.sm) {
                    Image(systemName: "signature")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    Text("Customer Signature Required")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.vertical, PaulDavisTheme.Spacing.xl)
                
                // Signature canvas
                VStack(spacing: PaulDavisTheme.Spacing.md) {
                    Canvas { context, size in
                        // Draw all completed lines
                        for line in lines {
                            var path = Path()
                            if let first = line.first {
                                path.move(to: first)
                                for point in line.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                            context.stroke(path, with: .color(.black), lineWidth: 3)
                        }
                        
                        // Draw current line
                        if !currentLine.isEmpty {
                            var path = Path()
                            path.move(to: currentLine[0])
                            for point in currentLine.dropFirst() {
                                path.addLine(to: point)
                            }
                            context.stroke(path, with: .color(.black), lineWidth: 3)
                        }
                    }
                    .frame(height: 200)
                    .background(Color.white)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                currentLine.append(value.location)
                            }
                            .onEnded { _ in
                                if !currentLine.isEmpty {
                                    lines.append(currentLine)
                                    currentLine = []
                                }
                            }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md)
                            .stroke(hasDrawn ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                    
                    // Clear button
                    Button(action: {
                        lines = []
                        currentLine = []
                    }) {
                        HStack(spacing: PaulDavisTheme.Spacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Clear")
                        }
                        .font(.body)
                        .foregroundColor(.red)
                    }
                    .opacity(hasDrawn ? 1 : 0.3)
                    .disabled(!hasDrawn)
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                
                Spacer()
                
                // Name field
                VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.sm) {
                    Text("Print Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    TextField("Customer's full name", text: $signedName)
                        .font(.title3)
                        .padding(PaulDavisTheme.Spacing.md)
                        .frame(height: 56)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                        .focused($isNameFieldFocused)
                }
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.lg)
                
                // Done button
                Button(action: complete) {
                    Text("Complete Work Order")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isValid ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.md))
                }
                .disabled(!isValid)
                .padding(.horizontal, PaulDavisTheme.Spacing.lg)
                .padding(.bottom, PaulDavisTheme.Spacing.xl)
            }
            .navigationTitle("Customer Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
    
    private var isValid: Bool {
        hasDrawn && !signedName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func complete() {
        // Create image from lines
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200))
        let image = renderer.image { ctx in
            ctx.cgContext.setStrokeColor(UIColor.black.cgColor)
            ctx.cgContext.setLineWidth(3)
            ctx.cgContext.setLineCap(.round)
            
            for line in lines {
                guard let first = line.first else { continue }
                ctx.cgContext.move(to: first)
                for point in line.dropFirst() {
                    ctx.cgContext.addLine(to: point)
                }
                ctx.cgContext.strokePath()
            }
        }
        
        guard let pngData = image.pngData() else { return }
        onComplete(pngData, signedName.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview {
    SignatureCaptureView(
        onComplete: { data, name in
            print("Signature captured: \(data.count) bytes, name: \(name)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
#endif
