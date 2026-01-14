/**
 
 # View + Controller
 
 The overall structure of the app:
 
 - MainView: the app interface with SKView and render controls
 - SKRenderController: orchestrates rendering, manages progress, and handles file I/O
 - SKRenderScene: the SpriteKit content
 - SKOfflineRenderer: wraps SKRenderer, manages Metal textures and IOSurface, and converts to PNG
 - VideoWriter: encodes rendered frames to H.264 video via AVAssetWriter
 
 Achraf Kassioui
 Created 20 Nov 2025
 Updated 14 Jan 2026
 
 */
import SpriteKit
import SwiftUI

enum OutputFormat: String, Identifiable, CaseIterable {
    case video = "Video"
    case frames = "PNGs"
    
    /// Conform to Identifiable
    var id: String {
        self.rawValue
    }
}

enum RenderResolution: String, Identifiable, CaseIterable {
    case viewSize = "View Size"
    case ultraHD = "4K"
    case fullHD = "Full HD"
    case hd = "HD"
    
    var id: String {
        self.rawValue
    }
    
    func size(viewSize: CGSize) -> CGSize {
        switch self {
        case .viewSize: return viewSize
        case .ultraHD: return CGSize(width: 3840, height: 2160)
        case .fullHD: return CGSize(width: 1920, height: 1080)
        case .hd: return CGSize(width: 1280, height: 720)
        }
    }
}

// MARK: View

struct MainView: View {
    
    // MARK: State
    
    @State private var liveScene: RenderScene?
    @State private var controller = SKRenderController()
    
    @State private var renderDuration: TimeInterval = 5
    @State private var renderFPS: CGFloat = 60
    @State private var scaleFactor: CGFloat = 1
    @State private var renderResolution: RenderResolution = .viewSize
    @State private var imageFilter: CoreImageFilter = .none
    @State private var outputFormat: OutputFormat = .video
    @State private var videoBitrate: VideoBitrate = .high
    @State private var showShareSheet = false
    
    // MARK: Properties
    
    let uiLeftColumnWidth: Double = 90
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                
                // MARK: SKView
                
                if let scene = liveScene {
                    SpriteView(
                        scene: scene,
                        debugOptions: [.showsFPS, .showsNodeCount]
                    )
                    .onChange(of: controller.isRendering) { _, newValue in
                        liveScene?.isPaused = newValue
                    }
                }
                
                // MARK: UI
                
                VStack(alignment: .center) {
                    Spacer()
                    
                    if controller.isRendering {
                        
                        /// # Rendering Progress
                        
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
                                    .frame(width: uiLeftColumnWidth, alignment: .leading)
                                Text("\(Int(renderDuration))s")
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 40, alignment: .leading)
                                Slider(value: $renderDuration, in: 1...30, step: 1)
                            }
                            
                            /// # Resolution
                            
                            HStack {
                                Text("Resolution")
                                    .foregroundStyle(.white)
                                    .frame(width: uiLeftColumnWidth, alignment: .leading)
                                let currentSize = renderResolution.size(viewSize: geometry.size)
                                Text("\(Int(currentSize.width))×\(Int(currentSize.height))")
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 110, alignment: .leading)
                                Spacer()
                                Picker("", selection: $renderResolution) {
                                    ForEach(RenderResolution.allCases) { res in
                                        Text(res.rawValue).tag(res)
                                    }
                                }
                                .frame(width: 120)
                                .pickerStyle(.menu)
                                .tint(.white)
                            }
                            
                            /// # Scale
                            
                            HStack {
                                Text("Scale")
                                    .foregroundStyle(.white)
                                    .frame(width: uiLeftColumnWidth, alignment: .leading)
                                Picker("", selection: $scaleFactor) {
                                    Text("@1x").tag(CGFloat(1.0))
                                    Text("@2x").tag(CGFloat(2.0))
                                    Text("@3x").tag(CGFloat(3.0))
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            /// # Filter
                            
                            HStack {
                                Text("Image Filter")
                                    .foregroundStyle(.white)
                                    .frame(width: uiLeftColumnWidth, alignment: .leading)
                                Picker("", selection: $imageFilter) {
                                    ForEach(CoreImageFilter.allCases) { filter in
                                        Text(filter.rawValue).tag(filter)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(.white)
                                .onChange(of: imageFilter) { _, newFilter in
                                    liveScene?.applyFilter(newFilter)
                                }
                            }
                            
                            Divider()
                                .background(.white.opacity(0.3))
                            
                            HStack {
                                
                                /// # Render Button
                                
                                Button {
                                    Task {
                                        switch outputFormat {
                                        case .video:
                                            await controller.exportVideo(
                                                duration: renderDuration,
                                                size: renderResolution.size(viewSize: geometry.size),
                                                renderScale: scaleFactor,
                                                fps: renderFPS,
                                                imageFilter: imageFilter,
                                                bitrate: videoBitrate
                                                
                                            )
                                        case .frames:
                                            await controller.exportFrames(
                                                duration: renderDuration,
                                                size: renderResolution.size(viewSize: geometry.size),
                                                renderScale: scaleFactor,
                                                fps: renderFPS,
                                                imageFilter: imageFilter
                                            )
                                        }
                                    }
                                } label: {
                                    Text("Render")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                
                                /// # Output Format
                                
                                Picker(outputFormat.rawValue, selection: $outputFormat) {
                                    ForEach(OutputFormat.allCases) { format in
                                        Text(format.rawValue).tag(format)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)
                            }
                        }
                        .padding(16)
                        .background(.black.opacity(0.5), in: .rect(cornerRadius: 26))
                    }
                }
                .frame(maxWidth: controller.isRendering ? .infinity : 360)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20))
            }
            .onAppear {
                liveScene = RenderScene(size: geometry.size, scaleFactor: scaleFactor, imageFilter: imageFilter)
            }
        }
        .ignoresSafeArea()
        .background(.black)
        .sheet(isPresented: $showShareSheet) {
            /// Called when sheet is dismissed
            controller.clearCurrentVideo()
        } content: {
            if let videoURL = controller.currentVideoURL {
                ShareSheet(activityItems: [videoURL])
            }
        }
#if !targetEnvironment(simulator) && !targetEnvironment(macCatalyst) && os(iOS)
        .onChange(of: controller.currentVideoURL) { oldURL, newURL in
            if newURL != nil, oldURL != newURL {
                showShareSheet = true
            }
        }
#endif
    }
}

// MARK: Share Sheet
/**
 
 Triggered on iOS devices only, not simulator or Mac.
 This is on purpose, because console + file path are easy to access with simulator and Mac.
 
 */
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MainView()
}

// MARK: Controller

@Observable
class SKRenderController {
    
    var isRendering = false
    var progress: Double = 0
    var currentFrame = 0
    var totalFrames = 0
    
    /// For cleanup and sharing
    private(set) var currentVideoURL: URL?
    private var currentVideoWriter: VideoWriter?

    /// Update time tests
    enum CurrentTimeMode {
        case frozen           /// Same time every frame
        case backwards        /// Decreasing time
        case normal           /// Monotonically increasing
        case doubleSpeed
        case slowMotion
    }
    
    var currentTimeMode: CurrentTimeMode = .normal
    
    // MARK: Export Video
    
    func exportVideo(
        duration: Double,
        size: CGSize,
        renderScale: CGFloat,
        fps: Double,
        imageFilter: CoreImageFilter,
        bitrate: VideoBitrate
    ) async {
        let exportStartTime: TimeInterval = CACurrentMediaTime()
        
        isRendering = true
        
        totalFrames = Int(duration * fps)
        currentFrame = 0
        progress = 0
        
        do {
            let pixelSize = CGSize(width: size.width * renderScale, height: size.height * renderScale)
            
            /// Create video file
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            
            let filename = "\(Int(duration))s_\(Int(fps))fps_\(currentTimeMode)_\(bitrate)_\(timestamp).mp4"
            let videoURL = documentDirectory.appendingPathComponent(filename)
            
            /// Create renderer with IOSurface
            let offlineRenderer = try SKOfflineRenderer(
                size: size,
                renderScale: renderScale,
                imageFilter: imageFilter,
                useIOSurface: true
            )
            
            guard let ioSurface = offlineRenderer.outputIOSurface else {
                throw RenderError.noIOSurface
            }
            
            /// Create video writer
            let videoWriter = try VideoWriter(
                url: videoURL,
                size: pixelSize,
                fps: Int(fps),
                bitrate: bitrate
            )
            
            /// Store for cleanup
            currentVideoWriter = videoWriter
            
            print("========================================")
            print("\n🎬 RENDER TO VIDEO")
            print("   Resolution:    \(Int(size.width))×\(Int(size.height)) points")
            print("   Scale:         @\(Int(renderScale))x")
            print("   Actual pixels: \(Int(pixelSize.width))×\(Int(pixelSize.height))")
            print("   FPS:           \(Int(fps))")
            print("   Frames:        \(totalFrames)")
            print("   Image Filter:  \(imageFilter.rawValue)")
            print("   Video quality: \(bitrate)")
            print()
            
            /// Always start from CACurrentMediaTime()
            /// Particles are not rendered if time values start at 0
            var currentTime: TimeInterval = 0 + CACurrentMediaTime()
            let deltaTime = 1.0 / fps
            var lastPrintedPercent = 0
            
            print("Rendering...")
            
            for frame in 0..<totalFrames {
                currentFrame = frame + 1
                
                /// Update time test: apply different time progression modes
                switch currentTimeMode {
                case .frozen:
                    currentTime += 0
                case .backwards:
                    currentTime -= deltaTime
                case .normal:
                    currentTime += deltaTime
                case .doubleSpeed:
                    currentTime += deltaTime * 2
                case .slowMotion:
                    currentTime += deltaTime / 4
                }
                
                /// Render to IOSurface
                try await offlineRenderer.renderToIOSurface(atTime: currentTime)
                
                /// Encode frame
                try videoWriter.appendFrame(from: ioSurface, frameIndex: frame)
                
                /// Progress
                let currentProgress = Double(frame + 1) / Double(totalFrames)
                progress = currentProgress
                
                /// Print progress at 10% intervals
                let percentComplete = Int(currentProgress * 100)
                if percentComplete >= lastPrintedPercent + 10 {
                    print("\(percentComplete)% ", terminator: "")
                    lastPrintedPercent = percentComplete
                }
            }
            
            /// Finish video
            let finalURL = try await videoWriter.finishWriting()
            
            /// Set currentVideoURL, this triggers the share sheet
            currentVideoURL = finalURL
            currentVideoWriter = nil
            
            let totalExportTime = CACurrentMediaTime() - exportStartTime
            
            print("\n\n✅ RENDER COMPLETE")
            print("   Total time: \(String(format: "%.2f", totalExportTime))s")
            print("   Video File: \(finalURL.path)")
            logDocumentDirectory()
        } catch {
            print("❌ RENDER FAILED: \(error)")
            
            /// Try partial save
            if let writer = currentVideoWriter {
                do {
                    print("Attempting partial save...")
                    let partialURL = try await writer.finishWriting()
                    currentVideoURL = partialURL
                    print("Partial save: \(partialURL.lastPathComponent)")
                } catch {
                    cleanupFailedRender()
                    print("Error: \(error.localizedDescription)")
                }
            } else {
                print("Error: \(error.localizedDescription)")
            }
        }
        
        currentVideoWriter = nil
        isRendering = false
    }
    
    // MARK: Export Frames
    
    func exportFrames(
        duration: Double,
        size: CGSize,
        renderScale: CGFloat,
        fps: Double,
        imageFilter: CoreImageFilter
    ) async {
        let exportStartTime = CACurrentMediaTime()
        
        isRendering = true
        
        totalFrames = Int(duration * fps)
        currentFrame = 0
        progress = 0
        
        do {
            /// Create renderer once, reused for all frames
            let offlineRenderer = try SKOfflineRenderer(
                size: size,
                renderScale: renderScale,
                imageFilter: imageFilter,
                useIOSurface: false
            )
            
            let outputDir = try createOutputDirectory()
            
            let pixelSize = CGSize(width: size.width * renderScale, height: size.height * renderScale)
            
            print("========================================")
            print("\n🖼️ RENDER TO PNGs")
            print("   Resolution:    \(Int(size.width))×\(Int(size.height)) points")
            print("   Scale:         @\(Int(renderScale))x")
            print("   Actual pixels: \(Int(pixelSize.width))×\(Int(pixelSize.height))")
            print("   FPS:           \(Int(fps))")
            print("   Frames:        \(totalFrames)")
            print("   Image Filter:  \(imageFilter)")
            print()
            
            /// Update time
            var currentTime: TimeInterval = 0 + CACurrentMediaTime()
            let deltaTime = 1.0 / fps
            var lastPrintedPercent = 0
            
            /// Track parallel save operations for logging
            var saveOperations: [Task<Void, Never>] = []
            
            print("Rendering...")
            
            for frame in 0..<totalFrames {
                currentFrame = frame + 1
                
                /// Current time test: apply different time progression modes
                switch currentTimeMode {
                case .doubleSpeed:
                    currentTime += deltaTime * 2
                case .slowMotion:
                    currentTime += deltaTime / 4
                case .normal:
                    currentTime += deltaTime
                case .frozen:
                    currentTime = 0
                case .backwards:
                    currentTime -= deltaTime
                }
                
                /// Get CGImage for this frame
                let cgImage = try await offlineRenderer.renderToCGImage(atTime: currentTime)
                
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
                                /// Progress
                                let currentProgress = Double(frame + 1) / Double(self.totalFrames)
                                self.progress = currentProgress
                                
                                /// Print progress at 10% intervals
                                let percentComplete = Int(currentProgress * 100)
                                if percentComplete >= lastPrintedPercent + 10 {
                                    print("\(percentComplete)% ", terminator: "")
                                    lastPrintedPercent = percentComplete
                                }
                                
                                continuation.resume()
                            }
                        }
                    }
                }
                
                saveOperations.append(saveTask)
            }
            
            /// Wait for all disk writes to complete before finishing
            for saveTask in saveOperations {
                await saveTask.value
            }
            
            let totalExportTime = CACurrentMediaTime() - exportStartTime
            
            print("\n\n✅ RENDER COMPLETE")
            print("   Total time: \(String(format: "%.2f", totalExportTime))s")
            print("   Image Files: \(outputDir.path)")
            logDocumentDirectory()
            
        } catch {
            print("❌ RENDER FAILED: \(error)")
        }
        
        isRendering = false
    }
    
    // MARK: Files
    
    private func logDocumentDirectory() {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            if contents.isEmpty {
                print("📁 Document directory is empty")
            } else {
                print("\n📁 Document directory contains \(contents.count) item(s):")
                for url in contents {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = attributes?[.size] as? Int64 ?? 0
                    let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    print(" - \(url.lastPathComponent) (\(sizeString))")
                }
                print()
            }
        } catch {
            print("Failed to read document directory: \(error)")
        }
    }
    
    func clearCurrentVideo() {
        if let url = currentVideoURL {
            try? FileManager.default.removeItem(at: url)
            print("🗑️ Deleted: \(url.lastPathComponent)")
        }
        currentVideoURL = nil
    }
    
    private func cleanupFailedRender() {
        if let url = currentVideoURL {
            try? FileManager.default.removeItem(at: url)
            print("🗑️ Cleaned up failed render")
        }
        currentVideoURL = nil
        currentVideoWriter = nil
    }
    
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
    
}
