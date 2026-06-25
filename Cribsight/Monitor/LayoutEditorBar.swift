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
                    // A fisheye can be added more than once for a second aim.
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

    private func placedCameraIDs() -> [UUID] {
        var seen = Set<UUID>()
        var ids = vm.activeLayout.slots.map { $0.cameraID }.filter { seen.insert($0).inserted }
        if ids.isEmpty { ids = vm.config.cameras.map { $0.id } }
        return ids
    }

    private func apply(_ preset: Preset) {
        let ids = placedCameraIDs()
        var layout: PaneLayout
        switch preset {
        case .single:    layout = .columns(cameraIDs: Array(ids.prefix(1)))
        case .columns:   layout = .columns(cameraIDs: ids)
        case .rows:      layout = .rows(cameraIDs: ids)
        case .spotlight: layout = .spotlight(cameraIDs: ids)
        case .grid:      layout = .auto(cameraIDs: ids)
        case .pip:       layout = .pip(cameraIDs: ids)
        }
        // Overwrite the active layout in place.
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

    /// One tap: turn a single ceiling fisheye into two side-by-side panes, each a
    /// virtual PTZ aimed at a different crib.
    private func splitFisheye() {
        guard let fish = vm.config.cameras.first(where: { $0.isFisheye }) else { return }
        let cribA = ViewOrientation(pan: -0.7, tilt: 1.0, zoom: 1.8)
        let cribB = ViewOrientation(pan: 0.7, tilt: 1.0, zoom: 1.8)
        var layout = vm.activeLayout
        layout.slots = [
            LayoutSlot(cameraID: fish.id, x: 0, y: 0, width: 0.5, height: 1,
                       view: SlotView(mode: .perspective, orientation: cribA)),
            LayoutSlot(cameraID: fish.id, x: 0.5, y: 0, width: 0.5, height: 1,
                       view: SlotView(mode: .perspective, orientation: cribB))
        ]
        vm.commitLayout(layout)
        Haptics.selection()
    }
}
