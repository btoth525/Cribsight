import Foundation
import MetalKit
import CoreVideo
import UIKit
import WebRTC

/// Owns the Metal pipeline for one pane: pulls the latest frame from its
/// `FrameSink`, builds Y / CbCr textures, and draws them through the dewarp
/// shader. The `uniforms` are updated by the view model as gestures change.
final class DewarpRenderer: NSObject, MTKViewDelegate {

    /// The frame source, owned by the `CameraSource`. Several renderers (one per
    /// pane) can read the same sink, so one fisheye stream drives many aimed
    /// dewarp views without extra decoding or network connections.
    let sink: FrameSink

    /// Updated on the main thread by the pane view model.
    var uniforms = DewarpUniformsData()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    init(sink: FrameSink) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            preconditionFailure("Metal is required but unavailable on this device.")
        }
        self.sink = sink
        self.device = device
        self.queue = queue
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        buildPipeline()
    }

    /// Configure an MTKView to be driven by this renderer.
    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFill
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            assertionFailure("Default Metal library not found.")
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vsFullscreen")
        desc.fragmentFunction = library.makeFunction(name: "fsDewarp")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline = pipeline,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        guard let latest = sink.latest,
              let yTex = makeTexture(latest.buffer, plane: 0, format: .r8Unorm),
              let cbcrTex = makeTexture(latest.buffer, plane: 1, format: .rg8Unorm) else {
            clear(drawable: drawable, rpd: rpd)
            return
        }

        var u = uniforms
        let w = CVPixelBufferGetWidth(latest.buffer)
        let h = max(1, CVPixelBufferGetHeight(latest.buffer))
        u.texAspect = Float(w) / Float(h)
        u.viewAspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
        u.rotation = Int32(Self.rotationIndex(latest.rotation))

        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.02, 0.03, 1)

        let cmd = queue.makeCommandBuffer()
        let enc = cmd?.makeRenderCommandEncoder(descriptor: rpd)
        enc?.setRenderPipelineState(pipeline)
        enc?.setFragmentTexture(yTex, index: 0)
        enc?.setFragmentTexture(cbcrTex, index: 1)
        enc?.setFragmentBytes(&u, length: MemoryLayout<DewarpUniformsData>.stride, index: 0)
        enc?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc?.endEncoding()
        cmd?.present(drawable)
        cmd?.commit()

        if let cache = textureCache { CVMetalTextureCacheFlush(cache, 0) }
    }

    // MARK: Snapshot

    /// Render the current frame (with current dewarp settings) to an image.
    func snapshot(size: CGSize) -> UIImage? {
        guard let pipeline = pipeline,
              let latest = sink.latest,
              let yTex = makeTexture(latest.buffer, plane: 0, format: .r8Unorm),
              let cbcrTex = makeTexture(latest.buffer, plane: 1, format: .rg8Unorm) else { return nil }

        let width = max(16, Int(size.width))
        let height = max(16, Int(size.height))
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: width, height: height,
                                                               mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: texDesc) else { return nil }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.02, 0.03, 1)

        var u = uniforms
        let w = CVPixelBufferGetWidth(latest.buffer)
        let h = max(1, CVPixelBufferGetHeight(latest.buffer))
        u.texAspect = Float(w) / Float(h)
        u.viewAspect = Float(width) / Float(height)
        u.rotation = Int32(Self.rotationIndex(latest.rotation))

        let cmd = queue.makeCommandBuffer()
        let enc = cmd?.makeRenderCommandEncoder(descriptor: rpd)
        enc?.setRenderPipelineState(pipeline)
        enc?.setFragmentTexture(yTex, index: 0)
        enc?.setFragmentTexture(cbcrTex, index: 1)
        enc?.setFragmentBytes(&u, length: MemoryLayout<DewarpUniformsData>.stride, index: 0)
        enc?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc?.endEncoding()
        cmd?.commit()
        cmd?.waitUntilCompleted()

        return Self.image(from: target)
    }

    // MARK: Helpers

    private func makeTexture(_ pb: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pb, plane)
        let height = CVPixelBufferGetHeightOfPlane(pb, plane)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pb, nil, format, width, height, plane, &cvTexture)
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return texture
    }

    private func clear(drawable: CAMetalDrawable, rpd: MTLRenderPassDescriptor) {
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.02, 0.03, 1)
        let cmd = queue.makeCommandBuffer()
        let enc = cmd?.makeRenderCommandEncoder(descriptor: rpd)
        enc?.endEncoding()
        cmd?.present(drawable)
        cmd?.commit()
    }

    private static func rotationIndex(_ rotation: RTCVideoRotation) -> Int {
        switch rotation {
        case ._0: return 0
        case ._90: return 1
        case ._180: return 2
        case ._270: return 3
        @unknown default: return 0
        }
    }

    private static func image(from texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var data = [UInt8](repeating: 0, count: rowBytes * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        // Keep the buffer pointer valid through CGContext creation + makeImage.
        return data.withUnsafeMutableBytes { ptr -> UIImage? in
            guard let base = ptr.baseAddress else { return nil }
            texture.getBytes(base, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
            guard let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
                  let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }
}
