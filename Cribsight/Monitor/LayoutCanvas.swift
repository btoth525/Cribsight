import SwiftUI

/// Renders the active layout's panes by normalized frame. In edit mode each pane
/// becomes draggable (move) with a bottom-right handle (resize) and a remove
/// button; edits snap to a 1/12 grid and persist via the view model.
struct LayoutCanvas: View {
    @ObservedObject var vm: MonitorViewModel
    let size: CGSize
    let onShowVitals: (CameraSettings) -> Void
    let onShowBabyControls: (CameraSettings) -> Void

    @State private var layout: PaneLayout
    @State private var activeSlot: UUID?
    @State private var startFrame: CGRect?
    @State private var showCameraMenu = false
    @State private var addTapPoint: CGPoint = .zero

    private let gap: CGFloat = 8
    private let grid = 1.0 / 12.0
    private let minTile = 2.0 / 12.0

    init(vm: MonitorViewModel, size: CGSize,
         onShowVitals: @escaping (CameraSettings) -> Void,
         onShowBabyControls: @escaping (CameraSettings) -> Void) {
        self._vm = ObservedObject(wrappedValue: vm)
        self.size = size
        self.onShowVitals = onShowVitals
        self.onShowBabyControls = onShowBabyControls
        _layout = State(initialValue: vm.activeLayout)
    }

    private var current: PaneLayout { vm.editingLayout ? layout : vm.activeLayout }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // In edit mode only, a tap on the empty canvas adds a camera. This
            // layer sits BEHIND the panes, so a tap on a pane hits the pane, not
            // this. Critically, when NOT editing it's absent entirely — otherwise
            // it would swallow taps meant for the parent's show/hide-controls
            // handler, leaving the control bar stuck hidden.
            if vm.editingLayout && !vm.config.cameras.isEmpty {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        addTapPoint = point
                        showCameraMenu = true
                    }
            }
            ForEach(current.slots) { slot in
                slotView(slot)
            }
        }
        .padding(gap / 2)
        .onChange(of: vm.activeLayout) { _, newValue in
            if activeSlot == nil { layout = newValue }
        }
        .onChange(of: vm.editingLayout) { _, editing in
            if editing { layout = vm.activeLayout }
        }
        .confirmationDialog("Add camera", isPresented: $showCameraMenu, titleVisibility: .visible) {
            ForEach(vm.config.cameras) { cam in
                Button(cam.displayName) {
                    addCameraAt(cam.id, point: addTapPoint)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Slot

    @ViewBuilder
    private func slotView(_ slot: LayoutSlot) -> some View {
        if let pane = vm.pane(forSlot: slot.id) {
            let w = max(1, slot.width * size.width - gap)
            let h = max(1, slot.height * size.height - gap)
            ZStack {
                CameraPaneView(pane: pane,
                               isFullscreen: false,
                               controlsVisible: !vm.editingLayout && !vm.locked && vm.controlsVisible,
                               interactive: !vm.editingLayout && !vm.locked,
                               vitalsService: vm.vitals,
                               onToggleFullscreen: { vm.toggleFullscreen(pane.id) },
                               onToast: { vm.showToast($0) },
                               onShowVitals: { onShowVitals(pane.camera) },
                               onBabyControls: { onShowBabyControls(pane.camera) })
                if vm.editingLayout {
                    editChrome(slot, paneName: pane.camera.displayName)
                }
            }
            .frame(width: w, height: h)
            .position(x: (slot.x + slot.width / 2) * size.width,
                      y: (slot.y + slot.height / 2) * size.height)
            .gesture(moveGesture(slot), including: vm.editingLayout ? .all : .subviews)
        }
    }

    private func editChrome(_ slot: LayoutSlot, paneName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.paneCornerRadius, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(Color.black.opacity(0.12))
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Label("Drag to move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .glassPill()
                    Spacer()
                    Button {
                        removeSlot(slot.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 30, height: 30)
                            .glassPill(tint: Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack {
                    Spacer()
                    resizeHandle(slot)
                }
            }
            .padding(10)
        }
    }

    private func resizeHandle(_ slot: LayoutSlot) -> some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .rotationEffect(.degrees(90))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.accent))
            .highPriorityGesture(resizeGesture(slot))
    }

    // MARK: Gestures

    private func moveGesture(_ slot: LayoutSlot) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if activeSlot != slot.id { activeSlot = slot.id; startFrame = slot.frame }
                guard let start = startFrame else { return }
                var f = start
                f.origin.x = start.origin.x + value.translation.width / max(1, size.width)
                f.origin.y = start.origin.y + value.translation.height / max(1, size.height)
                // Disable animations during live drag to prevent position-interpolation shake.
                withTransaction(Transaction(animation: .none)) {
                    mutate(slot.id) { $0.frame = f }
                }
            }
            .onEnded { _ in finishEdit() }
    }

    private func resizeGesture(_ slot: LayoutSlot) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if activeSlot != slot.id { activeSlot = slot.id; startFrame = slot.frame }
                guard let start = startFrame else { return }
                var f = start
                f.size.width = start.size.width + value.translation.width / max(1, size.width)
                f.size.height = start.size.height + value.translation.height / max(1, size.height)
                withTransaction(Transaction(animation: .none)) {
                    mutate(slot.id) { $0.frame = f }
                }
            }
            .onEnded { _ in finishEdit() }
    }

    // MARK: Mutation

    private func mutate(_ id: UUID, _ body: (inout LayoutSlot) -> Void) {
        guard let idx = layout.slots.firstIndex(where: { $0.id == id }) else { return }
        body(&layout.slots[idx])
        layout.slots[idx].normalize(minSize: minTile)
    }

    private func finishEdit() {
        // Snap without animations so the grid-lock jump is instant, not a spring.
        withTransaction(Transaction(animation: .none)) { snapToGrid() }
        activeSlot = nil
        startFrame = nil
        vm.commitLayout(layout)
        Haptics.tap()
    }

    private func snapToGrid() {
        for i in layout.slots.indices {
            var s = layout.slots[i]
            s.x = (s.x / grid).rounded() * grid
            s.y = (s.y / grid).rounded() * grid
            s.width = max(minTile, (s.width / grid).rounded() * grid)
            s.height = max(minTile, (s.height / grid).rounded() * grid)
            s.normalize(minSize: minTile)
            layout.slots[i] = s
        }
    }

    private func removeSlot(_ id: UUID) {
        layout.slots.removeAll { $0.id == id }
        vm.commitLayout(layout)
        Haptics.rigid()
    }

    /// Add a camera pane at the tapped canvas location.
    private func addCameraAt(_ id: UUID, point: CGPoint) {
        let normalX = max(0, point.x / max(1, size.width) - 0.2)
        let normalY = max(0, point.y / max(1, size.height) - 0.2)
        var slot = LayoutSlot(cameraID: id, x: normalX, y: normalY, width: 0.4, height: 0.4)
        slot.normalize(minSize: minTile)
        layout.slots.append(slot)
        vm.commitLayout(layout)
        Haptics.tap()
    }
}
