import SwiftUI

/// Bottom toolbar shown while arranging the layout: quick presets, add-camera,
/// and Done. Drag/resize/remove happen on the panes themselves (`LayoutCanvas`).
struct LayoutEditorBar: View {
    @ObservedObject var vm: MonitorViewModel
    var onSaveView: () -> Void

    private enum Preset { case single, columns, rows, spotlight, grid, pip }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetChip("Single", "rectangle") { apply(.single) }
                    presetChip("Side by side", "rectangle.split.2x1") { apply(.columns) }
                    presetChip("Stacked", "square.split.1x2") { apply(.rows) }
                    presetChip("One bigger", "rectangle.lefthalf.inset.filled") { apply(.spotlight) }
                    presetChip("Grid", "square.grid.2x2") { apply(.grid) }
                    presetChip("Picture-in-pic", "pip") { apply(.pip) }
                    if vm.config.cameras.contains(where: { $0.isFisheye }) {
                        presetChip("Split fisheye", "circle.circle") { splitFisheye() }
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 10) {
                addMenu
                Spacer()
                Button { onSaveView() } label: {
                    Label("Save view", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                }
                .glassButton()
                Button { vm.setEditingLayout(false) } label: {
                    Text("Done").frame(maxWidth: 90)
                }
                .glassButton(prominent: true)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 26)
        .padding(.horizontal, 16)
    }

    private func presetChip(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 88, height: 54)
            .glassPill()
        }
        .buttonStyle(.plain)
    }

    private var addMenu: some View {
        Menu {
            if vm.config.cameras.isEmpty {
                Text("No cameras yet")
            } else {
                ForEach(vm.config.cameras) { cam in
                    Button {
                        addCamera(cam.id)
                    } label: {
                        Label(cam.displayName, systemImage: cam.isFisheye ? "circle.circle" : "video")
                    }
                }
            }
        } label: {
            Label("Add pane", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassPill()
        }
    }

    // MARK: Actions

    /// All configured cameras, with currently-placed cameras first (preserving
    /// their existing order), followed by any not yet in the active layout.
    private func allCameraIDsInOrder() -> [UUID] {
        let placed = vm.activeLayout.slots.map { $0.cameraID }
        var seen = Set<UUID>()
        var ids = placed.filter { seen.insert($0).inserted }
        for cam in vm.config.cameras where !seen.contains(cam.id) {
            ids.append(cam.id)
        }
        return ids
    }

    private func apply(_ preset: Preset) {
        let all = allCameraIDsInOrder()
        guard !all.isEmpty else { return }
        let first = all[0]
        // For two-pane layouts, always produce exactly 2 panes even if only one
        // camera is configured (use the same camera twice as a starting point).
        let pair: [UUID] = all.count >= 2 ? Array(all.prefix(2)) : [first, first]
        var layout: PaneLayout
        switch preset {
        case .single:    layout = .columns(cameraIDs: [first])
        case .columns:   layout = .columns(cameraIDs: pair)
        case .rows:      layout = .rows(cameraIDs: pair)
        case .spotlight: layout = .spotlight(cameraIDs: all)
        case .grid:      layout = .auto(cameraIDs: all)
        case .pip:       layout = .pip(cameraIDs: pair)
        }
        layout.id = vm.activeLayout.id
        layout.name = vm.activeLayout.name
        vm.commitLayout(layout)
        Haptics.selection()
    }

    private func addCamera(_ id: UUID) {
        var layout = vm.activeLayout
        layout.slots.append(LayoutSlot(cameraID: id, x: 0.08, y: 0.08, width: 0.42, height: 0.42))
        vm.commitLayout(layout)
        Haptics.tap()
    }

    /// Adds one more fisheye pane each tap, distributing all fisheye slots evenly
    /// across the horizontal axis with distinct virtual-PTZ aims. Non-fisheye
    /// slots are left in place.
    private func splitFisheye() {
        guard let fish = vm.config.cameras.first(where: { $0.isFisheye }) else { return }
        var layout = vm.activeLayout
        let existing = layout.slots.filter { $0.cameraID == fish.id }.count
        let newCount = max(existing, 1) + 1
        let nonFish = layout.slots.filter { $0.cameraID != fish.id }
        let cw = 1.0 / Double(newCount)
        var fishSlots: [LayoutSlot] = []
        for i in 0..<newCount {
            // Spread virtual-PTZ aims evenly from -0.9 (left) to +0.9 (right).
            let panFrac = Double(i) / Double(max(newCount - 1, 1))
            let pan = -0.9 + panFrac * 1.8
            let orientation = ViewOrientation(pan: pan, tilt: 1.0, zoom: 1.8)
            fishSlots.append(LayoutSlot(
                cameraID: fish.id,
                x: Double(i) * cw, y: 0,
                width: cw, height: 1,
                view: SlotView(mode: .perspective, orientation: orientation)
            ))
        }
        layout.slots = nonFish + fishSlots
        vm.commitLayout(layout)
        Haptics.selection()
    }
}
