import SwiftUI
import MetalKit

/// SwiftUI wrapper around an `MTKView` driven by a `DewarpRenderer`.
/// The renderer is owned by the pane view model so it survives view rebuilds.
struct MetalDewarpView: UIViewRepresentable {
    let renderer: DewarpRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        renderer.configure(view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Uniforms are read live by the renderer each draw; nothing to push here.
    }
}
