/**
 
 ## Error Messages
 
 User defined error messages for logging.
 
 Achraf Kassioui
 Created 20 Nov 2026
 Updated 3 Jan 2026
 
 */
import Foundation

enum RenderError: Error, LocalizedError {
    case noMetalDevice
    case noCommandQueue
    case noTexture
    case noCommandBuffer
    case rendererDeallocated
    case failedToCreateDataProvider
    case failedToCreateCGImage
    case failedToEncodePNG
    
    case failedToCreateVideoWriter
    case failedToCreateIOSurface
    case failedToCreateIOSurfaceTexture
    case noIOSurfaceTexture
    case noIOSurface
    case noPixelBufferPool
    case failedToCreatePixelBuffer
    case failedToGetPixelBufferAddress
    case failedToAppendFrame
    case videoWriterDeallocated
    case noBlitEncoder
    
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
            
        case .failedToCreateVideoWriter: return "Failed to create video writer"
        case .failedToCreateIOSurface: return "Failed to create IOSurface"
        case .failedToCreateIOSurfaceTexture: return "Failed to create IOSurface-backed texture"
        case .noIOSurfaceTexture: return "No IOSurface texture available"
        case .noIOSurface: return "No IOSurface available"
        case .noPixelBufferPool: return "No pixel buffer pool"
        case .failedToCreatePixelBuffer: return "Failed to create pixel buffer"
        case .failedToGetPixelBufferAddress: return "Failed to get pixel buffer address"
        case .failedToAppendFrame: return "Failed to append frame to video"
        case .videoWriterDeallocated: return "Video writer was deallocated"
        case .noBlitEncoder: return "Failed to create blit encoder"
        }
    }
}
