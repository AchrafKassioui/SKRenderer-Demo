/**
 
 ## SpriteKit Offline Rendering
 
 Exploring SKRenderer and how to render to texture and store on disc.
 
 Achraf Kassioui
 Created 20 Nov 2025
 Updated 30 Dec 2025
 
 */
import SpriteKit
import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: View

struct SKOfflineRenderingView: View {
    @State private var liveScene: SKRenderScene?
    @State private var controller = SKRenderController()
    
    @State private var renderDuration: TimeInterval = 1
    @State private var renderFPS: CGFloat = 60
    @State private var scaleFactor: CGFloat = 1
    @State private var selectedResolution: Resolution = .viewSize
    @State private var selectedFilter: CoreImageFilter = .none
    
    enum Resolution: String, CaseIterable, Identifiable {
        case viewSize = "View Size"
        case fullHD = "Full HD"
        case hd = "HD"
        
        /// Conform to Identifiable
        var id: String {
            self.rawValue
        }
        
        func size(viewSize: CGSize) -> CGSize {
            switch self {
            case .viewSize: return viewSize
            case .fullHD: return CGSize(width: 1920, height: 1080)
            case .hd: return CGSize(width: 1280, height: 720)
            }
        }
    }
    
    // MARK: Filters
    
    enum CoreImageFilter: String, CaseIterable, Identifiable {
        case none = "No Filter"
        case gaussianBlur = "Gaussian Blur"
        case pixellate = "Pixellate"
        case sepiaTone = "Sepia Tone"
        case bloom = "Bloom"
        case vignette = "Vignette"
        
        var id: String {
            self.rawValue
        }
        
        func makeFilter() -> CIFilter? {
            switch self {
            case .none: return nil
            case .gaussianBlur:
                let filter = CIFilter.gaussianBlur()
                filter.radius = 10
                return filter
            case .pixellate:
                let filter = CIFilter.pixellate()
                filter.scale = 10
                return filter
            case .sepiaTone:
                return CIFilter.sepiaTone()
            case .bloom:
                let filter = CIFilter.bloom()
                filter.intensity = 0.5
                filter.radius = 10
                return filter
            case .vignette:
                let filter = CIFilter.vignette()
                filter.intensity = 1.0
                filter.radius = 1.0
                return filter
            }
        }
    }
    
    // MARK: SpriteView
    
    var body: some View {
        GeometryReader { fullGeo in
            ZStack(alignment: .bottom) {
                if !controller.isRendering {
                    /// Live preview
                    if let scene = liveScene {
                        SpriteView(
                            scene: scene,
                            debugOptions: [.showsFPS, .showsNodeCount]
                        )
                    }
                }
                
                // MARK: UI
                
                VStack() {
                    Spacer()
                    
                    if controller.isRendering {
                        VStack(spacing: 8) {
                            ProgressView(value: controller.progress)
                                .frame(width: 200)
                            Text("Frame \(controller.currentFrame) / \(controller.totalFrames)")
                                .foregroundStyle(.white)
                        }
                        .padding()
                        .background(.black.opacity(0.7), in: .rect(cornerRadius: 20))
                    } else {
                        VStack(alignment: .leading) {
                            
                            /// # Duration
                            
                            HStack {
                                Text("Duration")
                                    .foregroundStyle(.white)
                                    .frame(width: 80, alignment: .leading)
                                Text("\(Int(renderDuration))s")
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 40, alignment: .leading)
                                Slider(value: $renderDuration, in: 1...10)
                            }
                            
                            /// # Resolution
                            
                            HStack {
                                Text("Resolution")
                                    .foregroundStyle(.white)
                                    .frame(width: 80, alignment: .leading)
                                let currentSize = selectedResolution.size(viewSize: fullGeo.size)
                                Text("\(Int(currentSize.width))×\(Int(currentSize.height))")
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 100, alignment: .leading)
                                Spacer()
                                Picker("", selection: $selectedResolution) {
                                    ForEach(Resolution.allCases) { res in
                                        Text(res.rawValue).tag(res)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)
                            }
                            
                            /// # Scale
                            
                            HStack {
                                Text("Scale")
                                    .foregroundStyle(.white)
                                    .frame(width: 80, alignment: .leading)
                                Picker("", selection: $scaleFactor) {
                                    Text("@1x").tag(CGFloat(1.0))
                                    Text("@2x").tag(CGFloat(2.0))
                                    Text("@3x").tag(CGFloat(3.0))
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            /// # Filter
                            
                            HStack {
                                Text("Filter")
                                    .foregroundStyle(.white)
                                    .frame(width: 80, alignment: .leading)
                                Picker("", selection: $selectedFilter) {
                                    ForEach(CoreImageFilter.allCases) { filter in
                                        Text(filter.rawValue).tag(filter)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)
                            }
                            
                            Divider()
                                .background(.white.opacity(0.3))
                            
                            /// # Render button
                            
                            Button {
                                Task {
                                    await controller.renderSequence(
                                        duration: renderDuration,
                                        size: selectedResolution.size(viewSize: fullGeo.size),
                                        renderScale: scaleFactor,
                                        fps: renderFPS,
                                        filter: selectedFilter.makeFilter()
                                    )
                                }
                            } label: {
                                Text("Render")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding(16)
                        .background(.black.opacity(0.5), in: .rect(cornerRadius: 26))
                        
                        /// # Message
                        
                        .overlay(alignment: .top) {
                            if let message = controller.message {
                                Text(message)
                                    .foregroundStyle(.white)
                                    .font(.caption)
                                    .padding(8)
                                    .background(.black.opacity(0.9), in: .rect(cornerRadius: 12))
                                    .offset(y: -40)
                            }
                        }
                    }
                }
                .frame(maxWidth: 360)
                .padding(.bottom, max(fullGeo.safeAreaInsets.bottom, 20))
            }
            .onAppear {
                liveScene = SKRenderScene(size: fullGeo.size, scaleFactor: scaleFactor, filter: selectedFilter.makeFilter())
            }
        }
        .ignoresSafeArea()
        .background(.black)
    }
}

#Preview {
    SKOfflineRenderingView()
}

// MARK: Scene

class SKRenderScene: SKScene, SKPhysicsContactDelegate {
    
    var deltaTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    let scaleFactor: CGFloat
    var feedback = UIImpactFeedbackGenerator()
    
    struct BitMasks: OptionSet {
        let rawValue: UInt32
        
        static let cat1 = BitMasks(rawValue: 1 << 0)
        static let cat2 = BitMasks(rawValue: 1 << 1)
        static let cat3 = BitMasks(rawValue: 1 << 2)
        static let cat4 = BitMasks(rawValue: 1 << 3)
        static let cat5 = BitMasks(rawValue: 1 << 4)
        
        static let none = BitMasks([])
        static let all = BitMasks(rawValue: UInt32.max)
    }
    
    // MARK: Init
    
    /// Setup must be done in `init` or `sceneDidLoad` since SKRenderer doesn't call `didMove(to view)`
    init(size: CGSize, scaleFactor: CGFloat, filter: CIFilter?) {
        self.scaleFactor = scaleFactor
        
        super.init(size: size)
        
        self.scaleMode = .aspectFit
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.backgroundColor = .darkGray
        self.physicsWorld.contactDelegate = self
        
        /// Apply CoreImage filter if provided
        if let filter = filter {
            self.shouldEnableEffects = true
            self.filter = filter
        }
        
        createContent()
        
        /// Control when bouncing balls are created, for physics determinism tests
        let sequence1 = SKAction.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                self?.createBouncingBalls()
            }
        ])
        
        run(sequence1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: didMove
    
    override func didMove(to view: SKView) {
        /// Better looking during device orientation change
        view.contentMode = .center
        /// When presented by SKView, we want the scene to fill the screen
        scaleMode = .resizeFill
        
        feedback = UIImpactFeedbackGenerator(view: view)
        feedback.prepare()
    }
    
    // MARK: Content
    
    private func createBouncingBalls() {
        /// Bouncing balls
        /// Test physics determinsim. Collisions and friction stress test physics predictability run after run
        let circleCount = 5
        let spacing: CGFloat = 60
        let totalWidth = CGFloat(circleCount - 1) * spacing
        let startX = -totalWidth / 2
        
        for i in 0..<circleCount {
            let circle = SKShapeNode(circleOfRadius: 18 * scaleFactor)
            circle.fillColor = .orange
            circle.lineWidth = 2 * scaleFactor
            circle.strokeColor = .black
            circle.setScale(1/scaleFactor)
            
            circle.physicsBody = SKPhysicsBody(circleOfRadius: 18)
            circle.physicsBody?.collisionBitMask = BitMasks.cat1.rawValue
            circle.physicsBody?.contactTestBitMask = BitMasks.cat1.rawValue
            circle.physicsBody?.fieldBitMask = BitMasks.cat1.rawValue
            /// Toggle these lines to test determinism
            //circle.physicsBody?.restitution = 1
            //circle.physicsBody?.linearDamping = 0
            let x = startX + CGFloat(i) * spacing
            circle.position = CGPoint(x: x, y: 150)
            addChild(circle)
        }
    }
    
    private func createContent() {
        /// SKShapeNodes with antialiasing render blurry when output resolution is more than @1x (but render sharp in SKView)
        /// Solution: supersampling. Create shapes at @x size, then scale down by @x
        let roundedRectangle = SKShapeNode(rectOf: CGSize(width: 150 * scaleFactor, height: 75 * scaleFactor), cornerRadius: 12 * scaleFactor)
        roundedRectangle.fillColor = .systemRed
        roundedRectangle.strokeColor = .black
        roundedRectangle.lineWidth = 3 * scaleFactor
        roundedRectangle.setScale(1/scaleFactor) /// Scale back to intended size
        
        /// Physics body must match the final scaled size, not the supersampled size
        roundedRectangle.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 150, height: 75))
        roundedRectangle.physicsBody?.isDynamic = false
        roundedRectangle.physicsBody?.categoryBitMask = 0x1 << 1
        roundedRectangle.physicsBody?.collisionBitMask = 0x1 << 1
        addChild(roundedRectangle)
        
        let action = SKAction.rotate(byAngle: .pi, duration: 1)
        roundedRectangle.run(.repeatForever(action))
        
        /// Ground sprite
        let ground = SKSpriteNode(color: .black, size: CGSize(width: 350, height: 10))
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size)
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.restitution = 1
        ground.physicsBody?.categoryBitMask = BitMasks.cat1.rawValue
        ground.physicsBody?.collisionBitMask = BitMasks.cat1.rawValue
        ground.position = CGPoint(x: 0, y: -100)
        addChild(ground)
        
        /// Text node
        let label = SKLabelNode(text: "SKRenderer")
        label.fontName = "Menlo-Bold"
        label.fontColor = .systemYellow
        label.position = CGPoint(x: 0, y: 300)
        label.verticalAlignmentMode = .center
        addChild(label)
        
        /// Programmatic textures should be scaled by scaleFactor for more than @1x rendering
        let textureSize = CGSize(width: 2 * scaleFactor, height: 2 * scaleFactor)
        let cgRenderer = UIGraphicsImageRenderer(size: textureSize)
        let particleTexture = SKTexture(image: cgRenderer.image { context in
            SKColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: textureSize))
        })
        
        /// Particle emitter with programmatic texture
        let emitter = SKEmitterNode()
        emitter.particleTexture = particleTexture
        emitter.particleScale = 1 / scaleFactor
        emitter.particlePositionRange = CGVector(dx: label.calculateAccumulatedFrame().width, dy: label.calculateAccumulatedFrame().height)
        emitter.particleScaleSpeed = -0.2
        emitter.particleBirthRate = 3000
        emitter.particleLifetime = 6.0
        emitter.particleColor = .systemYellow
        emitter.particleColorBlendFactor = 1.0
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 100
        emitter.emissionAngle = -.pi / 2
        emitter.particleAlpha = 0.4
        emitter.particleAlphaSpeed = -0
        emitter.particleBlendMode = .add
        emitter.position = CGPoint(x: 0, y: 300)
        emitter.fieldBitMask = BitMasks.cat2.rawValue
        addChild(emitter)
        
        /// Turbulence field affecting particles
        /// Physics fields use a different engine than physics bodies, are SIMD based, and appear to be deterministic
        let field = SKFieldNode.noiseField(withSmoothness: 1, animationSpeed: 1)
        field.strength = 1
        field.categoryBitMask = BitMasks.cat2.rawValue
        addChild(field)
    }
    
    // MARK: Physics Contacts
    
    func didBegin(_ contact: SKPhysicsContact) {
        feedback.impactOccurred(intensity: 0.5)
    }
    
    // MARK: Loop
    
    override func update(_ currentTime: TimeInterval) {
        /// First frame, initialize delta time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        
        /// Calculate delta time
        deltaTime = currentTime - lastUpdateTime
        
        /// Store for next frame
        lastUpdateTime = currentTime
        
        /// During offline rendering, even if we supply a fixed timestep, we get alternating
        /// delta time values because we are adding 1/60 each time (floating point precision)
        //print(deltaTime)
    }
    
}

// MARK: Controller

@Observable
class SKRenderController {
    
    var isRendering = false
    var progress: Double = 0
    var currentFrame = 0
    var totalFrames = 0
    var message: String?
    
    // MARK: Render Sequence
    
    func renderSequence(duration: Double, size: CGSize, renderScale: CGFloat, fps: Double, filter: CIFilter?) async {
        isRendering = true
        message = "Starting render..."
        
        totalFrames = Int(duration * fps)
        currentFrame = 0
        progress = 0
        
        let totalStartTime = Date()
        
        do {
            /// Create renderer once, reused for all frames
            let offlineRenderer = try SKOfflineRenderer(size: size, renderScale: renderScale, filter: filter)
            
            let outputDir = try createOutputDirectory()
            
            let pixelSize = CGSize(width: size.width * renderScale, height: size.height * renderScale)
            
            print("\n========================================")
            print("RENDERING TO: \(outputDir.path)")
            print("Resolution: \(Int(size.width))×\(Int(size.height)) points")
            print("Node count: \(offlineRenderer.renderer.scene.map { countAllNodes(in: $0) } ?? 0)")
            print("Scale: @\(Int(renderScale))x")
            print("Actual pixels: \(Int(pixelSize.width))×\(Int(pixelSize.height))")
            print("FPS: \(Int(fps))")
            print("Frames: \(totalFrames)")
            print("Filter: \(filter?.name ?? "None")")
            print("========================================\n")
            
            /// Fixed time step
            let deltaTime = 1.0 / fps
            var currentTime: TimeInterval = 0
            
            let renderStartTime = Date()
            
            /// Track parallel save operations for logging
            var saveOperations: [Task<Void, Never>] = []
            
            for frame in 0..<totalFrames {
                currentFrame = frame + 1
                currentTime += deltaTime
                
                /// Get CGImage for this frame
                let cgImage = try await offlineRenderer.renderFrame(atTime: currentTime)
                
                /// Save to disk on background thread (non-blocking)
                let saveTask = Task {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let filename = String(format: "frame_%05d.png", frame)
                            let fileURL = outputDir.appendingPathComponent(filename)
                            
                            do {
                                try self.saveImage(cgImage, to: fileURL)
                            } catch {
                                print("Failed to save frame \(frame): \(error)")
                            }
                            
                            DispatchQueue.main.async {
                                self.progress = Double(frame + 1) / Double(self.totalFrames)
                                
                                /// Print dot without newline; flush forces immediate display instead of buffering
                                print(".", terminator: "")
                                fflush(stdout)
                                
                                if frame % 60 == 0 && frame != 0{
                                    /// Print every 60 frames
                                    print(" \(frame + 1)/\(self.totalFrames)")
                                }
                                
                                continuation.resume()
                            }
                        }
                    }
                }
                
                saveOperations.append(saveTask)
            }
            
            let renderTime = Date().timeIntervalSince(renderStartTime)
            
            /// Wait for all disk writes to complete before finishing
            for saveTask in saveOperations {
                await saveTask.value
            }
            
            let totalTime = Date().timeIntervalSince(totalStartTime)
            
            print("\n========================================")
            print("RENDER COMPLETE")
            print("Location: \(outputDir.path)")
            print("Frames: \(totalFrames)")
            print("Rendering time: \(String(format: "%.2f", renderTime))s (\(String(format: "%.3f", renderTime / Double(totalFrames)))s/frame)")
            print("Saving time: \(String(format: "%.2f", totalTime - renderTime))s")
            print("Total time: \(String(format: "%.2f", totalTime))s (\(String(format: "%.3f", totalTime / Double(totalFrames)))s/frame)")
            print("========================================\n")
            
            message = "Saved \(totalFrames) frames in \(String(format: "%.1f", totalTime))s"
            
        } catch {
            let totalTime = Date().timeIntervalSince(totalStartTime)
            print("\n========================================")
            print("RENDER FAILED: \(error)")
            print("Failed after: \(String(format: "%.2f", totalTime))s")
            print("========================================\n")
            message = "Error: \(error.localizedDescription)"
        }
        
        isRendering = false
    }
    
    // MARK: Files
    
    private func createOutputDirectory() throws -> URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let outputDir = documentDirectory.appendingPathComponent("SKRender_\(timestamp)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir
    }
    
    private func saveImage(_ image: CGImage, to url: URL) throws {
        let uiImage = UIImage(cgImage: image)
        guard let pngData = uiImage.pngData() else {
            throw RenderError.failedToEncodePNG
        }
        try pngData.write(to: url)
    }
    
    // MARK: Helpers
    
    private func countAllNodes(in node: SKNode) -> Int {
        return 1 + node.children.reduce(0) { $0 + countAllNodes(in: $1) }
    }
}

// MARK: Renderer

class SKOfflineRenderer {
    
    let renderer: SKRenderer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderTexture: MTLTexture
    private let sceneSize: CGSize
    private let backgroundColor: MTLClearColor
    private let startTime: TimeInterval
    
    // MARK: Init
    
    init(size: CGSize, renderScale: CGFloat, filter: CIFilter?) throws {
        /// Scene size in points
        self.sceneSize = size
        
        /// Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.noMetalDevice
        }
        self.device = device
        
        /// Create command queue factory
        guard let commandQueue = device.makeCommandQueue() else {
            throw RenderError.noCommandQueue
        }
        self.commandQueue = commandQueue
        
        /// Output size is in pixels (points × scale factor)
        /// @1x: 1920×1080 points → 1920×1080 pixels
        /// @3x: 1920×1080 points → 5760×3240 pixels
        let pixelWidth = Int(size.width * renderScale)
        let pixelHeight = Int(size.height * renderScale)
        
        /// Create render texture
        let textureDesc = MTLTextureDescriptor()
        textureDesc.pixelFormat = .bgra8Unorm
        textureDesc.width = pixelWidth
        textureDesc.height = pixelHeight
        textureDesc.usage = [.renderTarget, .shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDesc) else {
            throw RenderError.noTexture
        }
        self.renderTexture = texture
        
        /// Create SKRenderer and scene
        /// Scene size is in points
        /// SKRenderer automatically maps viewport (points) to texture (pixels) at the correct scale
        renderer = SKRenderer(device: device)
        let scene = SKRenderScene(size: size, scaleFactor: renderScale, filter: filter)
        renderer.scene = scene
        
        self.backgroundColor = scene.backgroundColor.metalClearColor
        
        /// Store absolute start time for particle systems
        /// SKScene's update() expects system time
        /// Without this, particles are not rendered
        self.startTime = CACurrentMediaTime()
    }
    
    // MARK: Render Frame
    
    /// Renders one frame at the specified time
    func renderFrame(atTime time: TimeInterval) async throws -> CGImage {
        /// withCheckedThrowingContinuation bridges Metal's callback-based API to async/await
        try await withCheckedThrowingContinuation { continuation in
            /// Convert relative time to absolute time
            /// This ensures particles are rendered
            let absoluteTime = startTime + time
            renderer.update(atTime: absoluteTime)
            
            /// Configure render pass descriptor
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            /// Create command buffer for this frame
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                continuation.resume(throwing: RenderError.noCommandBuffer)
                return
            }
            
            /// Render scene into texture
            /// Metal automatically handles the scale factor mapping
            let viewport = CGRect(origin: .zero, size: sceneSize) /// viewport values appear to be ignored
            renderer.render(
                withViewport: viewport,
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor
            )
            
            /// addCompletedHandler is called when GPU work is done for this frame
            /// renderTexture is now ready
            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self = self else {
                    continuation.resume(throwing: RenderError.rendererDeallocated)
                    return
                }
                
                do {
                    /// Convert texture to CGImage
                    let cgImage = try convertToCGImage(renderTexture)
                    continuation.resume(returning: cgImage)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            /// Submit command buffer to GPU
            /// commit() sends all queued commands to the GPU for execution
            commandBuffer.commit()
        }
    }
    
    // MARK: Encode Image
    
    private func convertToCGImage(_ texture: MTLTexture) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let rowBytes = width * bytesPerPixel
        
        /// Copy pixel data from Metal texture
        /// This could be made faster by using IOSurface to back the render texture
        var pixelData = [UInt8](repeating: 0, count: height * rowBytes)
        texture.getBytes(
            &pixelData,
            bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        guard let dataProvider = CGDataProvider(data: Data(pixelData) as CFData) else {
            throw RenderError.failedToCreateDataProvider
        }
        
        /// Create CGImage with BGRA format
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw RenderError.failedToCreateCGImage
        }
        
        return cgImage
    }
}

// MARK: Error Messages
/**
 
 User defined error messages for logging.
 
 */
enum RenderError: Error, LocalizedError {
    case noMetalDevice
    case noCommandQueue
    case noTexture
    case noCommandBuffer
    case rendererDeallocated
    case failedToCreateDataProvider
    case failedToCreateCGImage
    case failedToEncodePNG
    
    var errorDescription: String? {
        switch self {
        case .noMetalDevice: return "Metal not available on this device"
        case .noCommandQueue: return "Failed to create Metal command queue"
        case .noTexture: return "Failed to create render texture"
        case .noCommandBuffer: return "Failed to create command buffer"
        case .rendererDeallocated: return "Renderer was deallocated during rendering"
        case .failedToCreateDataProvider: return "Failed to create data provider from texture"
        case .failedToCreateCGImage: return "Failed to create CGImage"
        case .failedToEncodePNG: return "Failed to encode PNG data"
        }
    }
}
