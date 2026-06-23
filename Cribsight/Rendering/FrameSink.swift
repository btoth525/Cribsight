import Foundation
import WebRTC
import CoreVideo
import QuartzCore

/// An `RTCVideoRenderer` that keeps only the most recent decoded frame as a
/// `CVPixelBuffer`, so the Metal renderer can pull it each display tick. Also
/// records when the last frame arrived for the reconnect watchdog.
final class FrameSink: NSObject, RTCVideoRenderer {

    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?
    private var rotation: RTCVideoRotation = ._0
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: RTCVideoRenderer

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }

        let buffer: CVPixelBuffer?
        if let cv = frame.buffer as? RTCCVPixelBuffer {
            buffer = cv.pixelBuffer
        } else {
            buffer = FrameSink.makePixelBuffer(from: frame.buffer.toI420())
        }
        guard let pb = buffer else { return }

        lock.lock()
        pixelBuffer = pb
        rotation = frame.rotation
        lastFrameTime = CACurrentMediaTime()
        lock.unlock()
    }

    // MARK: Access

    var latest: (buffer: CVPixelBuffer, rotation: RTCVideoRotation)? {
        lock.lock(); defer { lock.unlock() }
        guard let pb = pixelBuffer else { return nil }
        return (pb, rotation)
    }

    /// Seconds since the last frame, or `.infinity` if none yet.
    var ageSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard lastFrameTime > 0 else { return .infinity }
        return CACurrentMediaTime() - lastFrameTime
    }

    // MARK: I420 → NV12 fallback (used only when frames aren't hardware-decoded)

    private static func makePixelBuffer(from i420: RTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(i420.width)
        let height = Int(i420.height)
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var out: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                         attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        if let yDest = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let destStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let srcStride = Int(i420.strideY)
            let dst = yDest.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                memcpy(dst.advanced(by: row * destStride),
                       i420.dataY.advanced(by: row * srcStride),
                       min(destStride, srcStride))
            }
        }

        if let cDest = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            let destStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            let cWidth = (width + 1) / 2
            let cHeight = (height + 1) / 2
            let strideU = Int(i420.strideU)
            let strideV = Int(i420.strideV)
            let dst = cDest.assumingMemoryBound(to: UInt8.self)
            for row in 0..<cHeight {
                let dRow = dst.advanced(by: row * destStride)
                let uRow = i420.dataU.advanced(by: row * strideU)
                let vRow = i420.dataV.advanced(by: row * strideV)
                for col in 0..<cWidth {
                    dRow[col * 2] = uRow[col]
                    dRow[col * 2 + 1] = vRow[col]
                }
            }
        }
        return pb
    }
}
