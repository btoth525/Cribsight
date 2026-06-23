import SwiftUI

/// Bottom toolbar shown while arranging the layout: quick presets, add-camera,
/// and Done. Drag/resize/remove happen on the panes themselves (`LayoutCanvas`).
struct LayoutEditorBar: View {
    @ObservedObject var vm: MonitorViewModel

    private enum Preset { case columns, rows, spotlight, grid, pip }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetChip("Side by side", "rectangle.split.2x1") { apply(.columns) }
                    presetChip("Stacked", "square.split.1x2") { apply(.rows) }
                    presetChip("One bigger", "rectangle.lefthalf.inset.filled") { apply(.spotlight) }
                    presetChip("Grid", "square.grid.2x2") { apply(.grid) }
                    presetChip("Picture-in-pic", "pip") { apply(.pip) }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 10) {
                addMenu
                Spacer()
                Button { vm.setEditingLayout(false) } label: {
                    Text("Done").frame(maxWidth: 120)
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
            let placed = Set(vm.activeLayout.slots.map { $0.cameraID })
            let available = vm.config.cameras.filter { !placed.contains($0.id) }
            if available.isEmpty {
                Text("All cameras are placed")
            } else {
                ForEach(available) { cam in
                    Button(cam.displayName) { addCamera(cam.id) }
                }
            }
        } label: {
            Label("Add camera", systemImage: "plus")
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
}
