/**
 
 ## Offline Renderer
 
 Wraps SKRenderer, manages Metal textures and IOSurface, and converts to PNG.
 
 Achraf Kassioui
 Created 26 Nov 2025
 Updated 5 Jan 2026
 
 */
import SpriteKit

class SKOfflineRenderer {
    
    // MARK: Properties
    
    let renderer: SKRenderer
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderTexture: MTLTexture
    private var depthStencilTexture: MTLTexture?
    private var outputTexture: MTLTexture? /// IOSurface-backed, we blip to this
    private(set) var outputIOSurface: IOSurface? /// Video writer reads from this
    private let sceneSize: CGSize
    private let backgroundColor: MTLClearColor
    private let startTime: TimeInterval
    
    // MARK: Init
    
    init(size: CGSize, renderScale: CGFloat, imageFilter: CoreImageFilter, useIOSurface: Bool) throws {
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
        
        /// Create depth/stencil texture for SKRenderer
        let depthStencilDesc = MTLTextureDescriptor()
        depthStencilDesc.pixelFormat = .depth32Float_stencil8
        depthStencilDesc.width = pixelWidth
        depthStencilDesc.height = pixelHeight
        depthStencilDesc.usage = .renderTarget
        depthStencilDesc.storageMode = .private
        
        depthStencilTexture = device.makeTexture(descriptor: depthStencilDesc)
        
        /// Create SKRenderer and scene
        /// Scene size is in points
        /// SKRenderer automatically maps viewport (points) to texture (pixels) at the correct scale
        renderer = SKRenderer(device: device)
        let scene = SKRenderScene(size: size, scaleFactor: renderScale, imageFilter: imageFilter)
        renderer.scene = scene
        
        self.backgroundColor = scene.backgroundColor.metalClearColor
        
        /// Store absolute start time for particle systems
        /// SKScene's update() expects system time
        /// Without this, particles are not rendered
        self.startTime = CACurrentMediaTime()
        
        /// Setup IOSurface-backed texture for video output
        if useIOSurface {
            try setupIOSurfaceTexture(width: pixelWidth, height: pixelHeight)
        }
    }
    
    // MARK: IOSurface Texture
    
    private func setupIOSurfaceTexture(width: Int, height: Int) throws {
        let bytesPerPixel = 4
        let alignment = 16
        let bytesPerRow = ((width * bytesPerPixel + alignment - 1) / alignment) * alignment
        
        let surfaceProperties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerRow: bytesPerRow,
            .bytesPerElement: bytesPerPixel,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        
        guard let ioSurface = IOSurface(properties: surfaceProperties) else {
            throw RenderError.failedToCreateIOSurface
        }
        self.outputIOSurface = ioSurface
        
        let desc = MTLTextureDescriptor()
        desc.width = width
        desc.height = height
        desc.pixelFormat = .bgra8Unorm
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .shared
        
#if targetEnvironment(macCatalyst) || os(macOS)
        outputTexture = device.makeTexture(descriptor: desc, iosurface: ioSurface as! IOSurfaceRef, plane: 0)
#else
        outputTexture = device.makeTexture(descriptor: desc, iosurface: ioSurface, plane: 0)
#endif
        
        guard outputTexture != nil else {
            throw RenderError.failedToCreateIOSurfaceTexture
        }
    }
    
    // MARK: Render To Video
    /**
     
     Render frame and copy to IOSurface for video encoding
     
     Pipeline: SpriteKit → render texture (GPU memory) → blit → IOSurface-backed texture → CPU can read for video encoder
     The blit copies GPU texture data to IOSurface, which can be accessed by both GPU and CPU without additional copies
     
     */
    func renderFrameToIOSurface(atTime time: TimeInterval) async throws {
        guard let outputTexture = outputTexture else {
            throw RenderError.noIOSurfaceTexture
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let currentTime = startTime + time
            renderer.update(atTime: currentTime)
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            /// If i dont use a stencil texture, rendering crashes on simulator, device, and Mac
            /// Without stencil, rendering only works on Xcode Live Preview
            if let depthStencilTexture = depthStencilTexture {
                renderPassDescriptor.depthAttachment.texture = depthStencilTexture
                renderPassDescriptor.depthAttachment.loadAction = .clear
                renderPassDescriptor.depthAttachment.storeAction = .dontCare
                renderPassDescriptor.depthAttachment.clearDepth = 1.0
                
                renderPassDescriptor.stencilAttachment.texture = depthStencilTexture
                renderPassDescriptor.stencilAttachment.loadAction = .clear
                renderPassDescriptor.stencilAttachment.storeAction = .dontCare
                renderPassDescriptor.stencilAttachment.clearStencil = 0
            }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                continuation.resume(throwing: RenderError.noCommandBuffer)
                return
            }
            
            let viewport = CGRect(origin: .zero, size: sceneSize)
            renderer.render(
                withViewport: viewport,
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor
            )
            
            /// Blit (GPU copy) render texture to IOSurface-backed texture
            /// This is a fast GPU-to-GPU copy that makes the frame accessible to CPU for video encoding
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                continuation.resume(throwing: RenderError.noBlitEncoder)
                return
            }
            
            blitEncoder.copy(
                from: renderTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: renderTexture.width, height: renderTexture.height, depth: 1),
                to: outputTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
            
            commandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            
            commandBuffer.commit()
        }
    }
    
    // MARK: Render to Image
    
    /// Renders one frame at the specified time
    func renderFrame(atTime time: TimeInterval) async throws -> CGImage {
        /// withCheckedThrowingContinuation bridges Metal's callback-based API to async/await
        try await withCheckedThrowingContinuation { continuation in
            /// Get current time from starting time + supplied time
            let currentTime = startTime + time
            renderer.update(atTime: currentTime)
            
            /// Configure render pass descriptor
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            /// Set depth/stencil if available
            if let depthStencilTexture = depthStencilTexture {
                renderPassDescriptor.depthAttachment.texture = depthStencilTexture
                renderPassDescriptor.depthAttachment.loadAction = .clear
                renderPassDescriptor.depthAttachment.storeAction = .dontCare
                renderPassDescriptor.depthAttachment.clearDepth = 1.0
                
                renderPassDescriptor.stencilAttachment.texture = depthStencilTexture
                renderPassDescriptor.stencilAttachment.loadAction = .clear
                renderPassDescriptor.stencilAttachment.storeAction = .dontCare
                renderPassDescriptor.stencilAttachment.clearStencil = 0
            }
            
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
    
}

// MARK: MTLTexture to CGImage
/**
 
 Convert Metal texture to CGImage for PNG export.
 Uses getBytes() to copy GPU texture to CPU memory.
 This path is for PNG export only. Video encoding uses IOSurface for faster CPU access.
 
 */
func convertToCGImage(_ texture: MTLTexture) throws -> CGImage {
    let width = texture.width
    let height = texture.height
    let bytesPerPixel = 4
    let rowBytes = width * bytesPerPixel
    
    /// Copy pixel data from GPU texture
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
