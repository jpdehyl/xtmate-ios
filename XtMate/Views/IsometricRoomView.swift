import SwiftUI
import SceneKit
import RoomPlan

// MARK: - Isometric Room View with Gemini AI Rendering

@available(iOS 16.0, *)
struct IsometricRoomView: View {
    let capturedRoom: CapturedRoom
    let annotations: [DamageAnnotation]
    let onSurfaceTapped: ((SurfaceHit) -> Void)?

    @StateObject private var geminiService = GeminiService.shared
    @State private var generatedImage: UIImage?
    @State private var isGeneratingImage = false
    @State private var sceneKitScene: SCNScene?
    @State private var selectedSurface: SurfaceHit?
    @State private var useGeminiRender = true // Default to Gemini (Nano Banana) rendering
    @State private var errorMessage: String?
    @State private var hasAttemptedGeneration = false

    // Visual styling
    private let accentColor = Color(red: 0.2, green: 0.5, blue: 0.9)

    init(
        capturedRoom: CapturedRoom,
        annotations: [DamageAnnotation] = [],
        onSurfaceTapped: ((SurfaceHit) -> Void)? = nil
    ) {
        self.capturedRoom = capturedRoom
        self.annotations = annotations
        self.onSurfaceTapped = onSurfaceTapped
    }

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.12, green: 0.12, blue: 0.14)
                .ignoresSafeArea()

            if useGeminiRender {
                // Gemini AI-generated isometric render
                geminiRenderView
            } else {
                // Fallback SceneKit view
                SceneKitIsometricView(
                    scene: buildScene(),
                    annotations: annotations,
                    onTap: { hit in
                        selectedSurface = hit
                        onSurfaceTapped?(hit)
                    }
                )
            }

            // Overlay controls
            VStack {
                // Top bar with controls
                HStack {
                    // View mode indicator
                    HStack(spacing: 6) {
                        Image(systemName: useGeminiRender ? "wand.and.stars" : "cube")
                            .font(.caption)
                        Text(useGeminiRender ? "AI Render" : "3D Model")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)

                    Spacer()

                    // Toggle button
                    Button(action: {
                        useGeminiRender.toggle()
                        if useGeminiRender && generatedImage == nil && !hasAttemptedGeneration {
                            Task {
                                await generateIsometricImage()
                            }
                        }
                    }) {
                        Image(systemName: useGeminiRender ? "cube" : "wand.and.stars")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(accentColor)
                            .clipShape(Circle())
                    }

                    // Refresh button (only for Gemini mode)
                    if useGeminiRender {
                        Button(action: {
                            Task {
                                await generateIsometricImage()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .disabled(isGeneratingImage)
                    }
                }
                .padding()

                Spacer()

                // Selected surface indicator
                if let surface = selectedSurface {
                    HStack {
                        Image(systemName: surface.surfaceType.icon)
                        Text(surface.surfaceType.rawValue)
                            .fontWeight(.medium)
                        Text("selected")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            // Auto-generate Gemini render when view appears
            if useGeminiRender && generatedImage == nil && !hasAttemptedGeneration {
                Task {
                    await generateIsometricImage()
                }
            }
        }
    }

    // MARK: - Gemini Render View
    @ViewBuilder
    private var geminiRenderView: some View {
        if let image = generatedImage {
            // Successfully generated image
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .padding()
                    .shadow(color: .black.opacity(0.3), radius: 20)

                // Overlay damage annotations on the image
                if !annotations.isEmpty {
                    GeometryReader { geometry in
                        ForEach(annotations) { annotation in
                            annotationMarker(for: annotation, in: geometry.size)
                        }
                    }
                    .padding()
                }
            }
        } else if isGeneratingImage {
            // Loading state
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isGeneratingImage)
                }

                VStack(spacing: 8) {
                    Text("Generating AI Render")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Using Gemini to create isometric view...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            // Error state
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                VStack(spacing: 8) {
                    Text("Render Failed")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack(spacing: 16) {
                    Button(action: {
                        errorMessage = nil
                        Task {
                            await generateIsometricImage()
                        }
                    }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        errorMessage = nil
                        useGeminiRender = false
                    }) {
                        Label("Use 3D Model", systemImage: "cube")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Initial state - prompt to generate
            VStack(spacing: 24) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 56))
                    .foregroundColor(accentColor)

                VStack(spacing: 8) {
                    Text("AI Isometric Render")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Generate a professional isometric view using Gemini AI")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Button(action: {
                    Task {
                        await generateIsometricImage()
                    }
                }) {
                    Label("Generate Render", systemImage: "sparkles")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Annotation Marker on Generated Image
    @ViewBuilder
    private func annotationMarker(for annotation: DamageAnnotation, in size: CGSize) -> some View {
        let x = annotation.position.x * size.width
        let y = annotation.position.y * size.height

        VStack(spacing: 4) {
            Image(systemName: annotation.damageType.icon)
                .font(.title3)
                .foregroundColor(.white)
                .padding(8)
                .background(annotation.damageType.color)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4)

            Text(annotation.severity.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(annotation.severity.color)
                .cornerRadius(4)
        }
        .position(x: x, y: y)
    }

    // MARK: - Build SceneKit Scene

    private func buildScene() -> SCNScene {
        if let existing = sceneKitScene {
            return existing
        }

        let scene = SCNScene()
        scene.background.contents = UIColor.systemGray6

        // Calculate room bounds
        let bounds = Room.calculateBounds(from: capturedRoom)
        let lengthM = bounds.length / 39.3701
        let widthM = bounds.width / 39.3701
        let heightM = bounds.height / 39.3701

        // Create floor
        let floorGeometry = SCNBox(width: CGFloat(lengthM), height: 0.02, length: CGFloat(widthM), chamferRadius: 0)
        floorGeometry.firstMaterial?.diffuse.contents = UIColor.white
        floorGeometry.firstMaterial?.lightingModel = .physicallyBased
        let floorNode = SCNNode(geometry: floorGeometry)
        floorNode.name = "floor"
        floorNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(floorNode)

        // Create walls from captured data
        for (index, wall) in capturedRoom.walls.enumerated() {
            let wallNode = createWallNode(wallTransform: wall.transform, wallDimensions: wall.dimensions, index: index, roomHeight: heightM)
            scene.rootNode.addChildNode(wallNode)
        }

        // Create doors
        for (index, door) in capturedRoom.doors.enumerated() {
            let doorNode = createDoorNode(doorTransform: door.transform, doorDimensions: door.dimensions, index: index)
            scene.rootNode.addChildNode(doorNode)
        }

        // Create windows
        for (index, window) in capturedRoom.windows.enumerated() {
            let windowNode = createWindowNode(windowTransform: window.transform, windowDimensions: window.dimensions, index: index)
            scene.rootNode.addChildNode(windowNode)
        }

        // Add damage annotation markers
        for annotation in annotations {
            let markerNode = createAnnotationMarker(annotation: annotation, roomBounds: (lengthM, widthM, heightM))
            scene.rootNode.addChildNode(markerNode)
        }

        // Setup camera for isometric view
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = Double(max(lengthM, widthM)) * 0.8

        // Isometric angle: 45° rotation, 35.264° elevation (true isometric)
        let distance = Float(max(lengthM, widthM)) * 2
        cameraNode.position = SCNVector3(distance, distance * 0.8, distance)
        cameraNode.look(at: SCNVector3(0, Float(heightM) / 2, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Add directional light for shadows
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.castsShadow = true
        directionalLight.position = SCNVector3(5, 10, 5)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)

        return scene
    }

    private func createWallNode(wallTransform: simd_float4x4, wallDimensions: simd_float3, index: Int, roomHeight: Double) -> SCNNode {
        let wallLength = Double(wallDimensions.x)
        let wallHeight = Double(wallDimensions.y)
        let wallThickness = 0.1

        let geometry = SCNBox(
            width: CGFloat(wallLength),
            height: CGFloat(wallHeight),
            length: CGFloat(wallThickness),
            chamferRadius: 0
        )

        // Light gray wall material
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 0.95, alpha: 1.0)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.8
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "wall_\(index)"

        // Position from transform
        let position = wallTransform.columns.3
        node.position = SCNVector3(position.x, position.y + Float(wallHeight) / 2, position.z)

        // Rotation from transform
        node.simdTransform = wallTransform
        node.position.y = Float(wallHeight) / 2

        return node
    }

    private func createDoorNode(doorTransform: simd_float4x4, doorDimensions: simd_float3, index: Int) -> SCNNode {
        let doorWidth = Double(doorDimensions.x)
        let doorHeight = Double(doorDimensions.y)
        let doorDepth = 0.05

        let geometry = SCNBox(
            width: CGFloat(doorWidth),
            height: CGFloat(doorHeight),
            length: CGFloat(doorDepth),
            chamferRadius: 0.01
        )

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.brown
        material.lightingModel = .physicallyBased
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "door_\(index)"

        let position = doorTransform.columns.3
        node.position = SCNVector3(position.x, Float(doorHeight) / 2, position.z)

        return node
    }

    private func createWindowNode(windowTransform: simd_float4x4, windowDimensions: simd_float3, index: Int) -> SCNNode {
        let windowWidth = Double(windowDimensions.x)
        let windowHeight = Double(windowDimensions.y)
        let windowDepth = 0.02

        let geometry = SCNBox(
            width: CGFloat(windowWidth),
            height: CGFloat(windowHeight),
            length: CGFloat(windowDepth),
            chamferRadius: 0
        )

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
        material.lightingModel = .physicallyBased
        material.transparency = 0.5
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "window_\(index)"

        let position = windowTransform.columns.3
        node.position = SCNVector3(position.x, position.y, position.z)

        return node
    }

    private func createAnnotationMarker(annotation: DamageAnnotation, roomBounds: (Double, Double, Double)) -> SCNNode {
        let (lengthM, widthM, heightM) = roomBounds

        // Convert normalized position to world coordinates
        let worldX = Float(annotation.position.x - 0.5) * Float(lengthM)
        let worldZ = Float(annotation.position.y - 0.5) * Float(widthM)
        let worldY: Float

        if annotation.affectedSurfaces.contains(.ceiling) {
            worldY = Float(heightM)
        } else if annotation.affectedSurfaces.contains(.wall) {
            worldY = Float(annotation.affectedHeightIn ?? heightM * 39.3701 / 2) / 39.3701
        } else {
            worldY = 0.1
        }

        // Create marker sphere
        let markerGeometry = SCNSphere(radius: 0.15)
        let material = SCNMaterial()
        material.diffuse.contents = annotation.damageType.uiColor
        material.emission.contents = annotation.damageType.uiColor.withAlphaComponent(0.5)
        markerGeometry.materials = [material]

        let markerNode = SCNNode(geometry: markerGeometry)
        markerNode.name = "annotation_\(annotation.id.uuidString)"
        markerNode.position = SCNVector3(worldX, worldY, worldZ)

        // Add pulsing animation
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.2, duration: 0.5),
            SCNAction.scale(to: 1.0, duration: 0.5)
        ])
        markerNode.runAction(SCNAction.repeatForever(pulse))

        // Add damage type icon as billboard
        let iconNode = createDamageIcon(type: annotation.damageType)
        iconNode.position = SCNVector3(0, 0.3, 0)
        markerNode.addChildNode(iconNode)

        return markerNode
    }

    private func createDamageIcon(type: DamageType) -> SCNNode {
        let plane = SCNPlane(width: 0.2, height: 0.2)

        // Create icon image
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        if let iconImage = UIImage(systemName: type.icon, withConfiguration: config)?.withTintColor(type.uiColor) {
            plane.firstMaterial?.diffuse.contents = iconImage
        }
        plane.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()]

        return node
    }

    // MARK: - Generate Gemini Image (Nano Banana)

    private func generateIsometricImage() async {
        await MainActor.run {
            isGeneratingImage = true
            errorMessage = nil
            hasAttemptedGeneration = true
        }

        do {
            let geometry = buildGeometryData()
            let annotationData = annotations.map { ann in
                DamageAnnotationData(
                    damageType: ann.damageType.rawValue,
                    severity: ann.severity.rawValue,
                    affectedSurfaces: ann.affectedSurfaces.map { $0.rawValue },
                    waterLineHeight: ann.affectedHeightIn,
                    highlightColor: ann.damageType.rawValue.lowercased()
                )
            }

            print("🎨 Requesting Gemini isometric render...")
            print("   Room: \(geometry.category), \(geometry.squareFeet) SF")
            print("   Walls: \(geometry.walls.count), Doors: \(geometry.doors.count), Windows: \(geometry.windows.count)")
            print("   Damage annotations: \(annotationData.count)")

            let image = try await geminiService.generateIsometricRender(
                roomGeometry: geometry,
                annotations: annotationData,
                style: .clean
            )

            print("✅ Gemini render successful!")

            await MainActor.run {
                self.generatedImage = image
                self.isGeneratingImage = false
            }
        } catch {
            print("❌ Gemini render failed: \(error)")

            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGeneratingImage = false
            }
        }
    }

    private func buildGeometryData() -> RoomGeometryData {
        let bounds = Room.calculateBounds(from: capturedRoom)

        var walls: [RoomGeometryData.WallData] = []
        for (index, wall) in capturedRoom.walls.enumerated() {
            let position = wall.transform.columns.3
            walls.append(RoomGeometryData.WallData(
                lengthFt: Double(wall.dimensions.x) * 3.28084,
                heightFt: Double(wall.dimensions.y) * 3.28084,
                positionDescription: "Wall \(index + 1) at (\(String(format: "%.1f", position.x)), \(String(format: "%.1f", position.z)))"
            ))
        }

        var doors: [RoomGeometryData.DoorData] = []
        for door in capturedRoom.doors {
            let position = door.transform.columns.3
            doors.append(RoomGeometryData.DoorData(
                widthFt: Double(door.dimensions.x) * 3.28084,
                heightFt: Double(door.dimensions.y) * 3.28084,
                wallPosition: "x:\(String(format: "%.1f", position.x)), z:\(String(format: "%.1f", position.z))"
            ))
        }

        var windows: [RoomGeometryData.WindowData] = []
        for window in capturedRoom.windows {
            let position = window.transform.columns.3
            windows.append(RoomGeometryData.WindowData(
                widthFt: Double(window.dimensions.x) * 3.28084,
                heightFt: Double(window.dimensions.y) * 3.28084,
                wallPosition: "x:\(String(format: "%.1f", position.x)), z:\(String(format: "%.1f", position.z))"
            ))
        }

        var objects: [RoomGeometryData.ObjectData] = []
        for obj in capturedRoom.objects {
            let position = obj.transform.columns.3
            objects.append(RoomGeometryData.ObjectData(
                name: objectName(for: obj.category),
                positionDescription: "(\(String(format: "%.1f", position.x)), \(String(format: "%.1f", position.z)))"
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
            objects: objects,
            floorMaterial: nil,
            wallMaterial: nil,
            ceilingMaterial: nil
        )
    }

    private func objectName(for category: CapturedRoom.Object.Category) -> String {
        switch category {
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

// MARK: - SceneKit View Wrapper

@available(iOS 16.0, *)
struct SceneKitIsometricView: UIViewRepresentable {
    let scene: SCNScene
    let annotations: [DamageAnnotation]
    let onTap: (SurfaceHit) -> Void

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.backgroundColor = .systemGray6
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true // Enable orbit, pan, zoom

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: (SurfaceHit) -> Void

        init(onTap: @escaping (SurfaceHit) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)

            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            if let hit = hitResults.first, let nodeName = hit.node.name {
                let surfaceType: SurfaceType
                if nodeName == "floor" {
                    surfaceType = .floor
                } else if nodeName.starts(with: "wall") {
                    surfaceType = .wall
                } else if nodeName.starts(with: "door") {
                    surfaceType = .door
                } else if nodeName.starts(with: "window") {
                    surfaceType = .window
                } else if nodeName.starts(with: "annotation") {
                    surfaceType = .annotation
                } else {
                    surfaceType = .object
                }

                let surfaceHit = SurfaceHit(
                    surfaceType: surfaceType,
                    nodeName: nodeName,
                    worldPosition: hit.worldCoordinates,
                    normalizedPosition: CGPoint(
                        x: CGFloat(hit.worldCoordinates.x),
                        y: CGFloat(hit.worldCoordinates.z)
                    )
                )

                onTap(surfaceHit)
            }
        }
    }
}

// MARK: - Supporting Types

struct SurfaceHit {
    let surfaceType: SurfaceType
    let nodeName: String
    let worldPosition: SCNVector3
    let normalizedPosition: CGPoint
}

enum SurfaceType: String {
    case floor = "Floor"
    case wall = "Wall"
    case ceiling = "Ceiling"
    case door = "Door"
    case window = "Window"
    case object = "Object"
    case annotation = "Annotation"

    var icon: String {
        switch self {
        case .floor: return "square.fill"
        case .wall: return "rectangle.portrait.fill"
        case .ceiling: return "rectangle.fill"
        case .door: return "door.left.hand.closed"
        case .window: return "window.horizontal"
        case .object: return "cube.fill"
        case .annotation: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - DamageType Extension

extension DamageType {
    var uiColor: UIColor {
        switch self {
        case .water: return .systemBlue
        case .fire: return .systemRed
        case .smoke: return .systemGray
        case .mold: return .systemGreen
        case .impact: return .systemOrange
        case .wind: return .systemCyan
        case .other: return .systemPurple
        }
    }
}
