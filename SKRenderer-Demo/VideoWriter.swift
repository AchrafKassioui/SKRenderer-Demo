/**
 
 ## Video Writer
 
 Encodes frames from IOSurface to H.264 video.
 Reusable across SpriteKit, RealityKit, or any Metal-based renderer.
 
 Usage:
 - Create writer with parameters
 - Call appendFrame() for each frame to add to the video
 - Call finishWriting() to finalize the video file
 
 Achraf Kassioui
 Created 3 Jan 2026
 Updated 5 Jan 2026
 
 */
import AVFoundation

// MARK: Encoding Quality
/**
 
 Bitrate calculation: (width × height / 1,000,000) × qualityMultiplier
 More pixels = more data to compress.
 Larger resolutions need proportionally more bitrate to maintain quality.
 
 */
enum VideoBitrate {
    case low        /// ~2 Mbps per Megapixel
    case medium     /// ~8 Mbps/MP
    case high       /// ~20 Mbps/MP
    case veryHigh   /// ~50 Mbps/MP
    
    
    func calculate(for size: CGSize) -> Int {
        let megapixels = (size.width * size.height) / 1_000_000
        let multiplier: Double
        
        switch self {
        case .low: multiplier = 2_000_000
        case .medium: multiplier = 8_000_000
        case .high: multiplier = 20_000_000
        case .veryHigh: multiplier = 50_000_000
        }
        
        return Int(megapixels * multiplier)
    }
}

class VideoWriter {
    
    // MARK: Properties
    
    let videoURL: URL
    
    private let assetWriter: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int
    
    // MARK: Init
    
    init(url: URL, size: CGSize, fps: Int, bitrate: VideoBitrate) throws {
        self.videoURL = url
        self.fps = fps
        
        /// Remove existing file
        try? FileManager.default.removeItem(at: url)
        
        /// Create writer
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        
        /// Configure video encoding settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            /**
             
             # Color Settings
             
             ## sRGB
             
             AVVideoColorPropertiesKey: [
                 AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                 AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                 AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
             ]
             
             ## Display P3
             
             AVVideoColorPropertiesKey: [
                 AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                 AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                 AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
             ]
             
             ## sRGB Transfer Function
             
             This setting is the closest to SKView's colors.
             
             AVVideoColorPropertiesKey: [
                 AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                 AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                 AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
             ]
             
             */
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                /// Higher bitrate = better quality, larger file size
                AVVideoAverageBitRateKey: bitrate.calculate(for: size),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                /// Disable B-frames for faster encoding (offline rendering doesn't need them)
                AVVideoAllowFrameReorderingKey: false,
                /// Use main profile for better compatibility
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        /// Create writer input
        /// expectsMediaDataInRealTime = false ensures no frames are dropped
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        /// Configure pixel buffer attributes
        /// BGRA format matches Metal texture output
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        guard assetWriter.canAdd(writerInput) else {
            throw RenderError.failedToCreateVideoWriter
        }
        
        assetWriter.add(writerInput)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
    }
    
    // MARK: Append
   
    /// Append a single frame from IOSurface to the video
    /// Frame index determines presentation time (frameIndex / fps)
    func appendFrame(from ioSurface: IOSurface, frameIndex: Int) throws {
        guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
            throw RenderError.noPixelBufferPool
        }
        
        /// Wait for encoder to be ready
        /// Offline rendering can wait as long as needed
        while !writerInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        /// Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            throw RenderError.failedToCreatePixelBuffer
        }
        
        /// Lock buffers for CPU access
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        ioSurface.lock(options: .readOnly, seed: nil)
        defer { ioSurface.unlock(options: .readOnly, seed: nil) }
        
        guard let pixelBufferBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw RenderError.failedToGetPixelBufferAddress
        }
        
        /// Fast memcpy from IOSurface to pixel buffer
        /// IOSurface is in GPU memory, pixel buffer goes to video encoder
        let ioSurfaceBaseAddress = ioSurface.baseAddress
        let height = ioSurface.height
        let ioSurfaceBytesPerRow = ioSurface.bytesPerRow
        let pixelBufferBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        if ioSurfaceBytesPerRow == pixelBufferBytesPerRow {
            /// Simple case: rows match, single memcpy
            memcpy(pixelBufferBaseAddress, ioSurfaceBaseAddress, height * ioSurfaceBytesPerRow)
        } else {
            /// Rows don't match: copy row by row
            let copyBytesPerRow = min(ioSurfaceBytesPerRow, pixelBufferBytesPerRow)
            for row in 0..<height {
                memcpy(
                    pixelBufferBaseAddress.advanced(by: row * pixelBufferBytesPerRow),
                    ioSurfaceBaseAddress.advanced(by: row * ioSurfaceBytesPerRow),
                    copyBytesPerRow
                )
            }
        }
        
        /// Calculate presentation time for this frame
        let frameTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
        
        /// Append to video stream
        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) else {
            throw RenderError.failedToAppendFrame
        }
    }
    
    // MARK: Finish
    
    /// Finalize the video file
    /// Returns the final video URL on success
    func finishWriting() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            writerInput.markAsFinished()
            
            assetWriter.finishWriting { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: RenderError.videoWriterDeallocated)
                    return
                }
                
                if let error = self.assetWriter.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: self.videoURL)
                }
            }
        }
    }
    
}
