import AppKit
import SwiftUI

struct DictionaryAccessoryControl: NSViewRepresentable {
    var canRemove: Bool
    var onAdd: () -> Void
    var onRemove: () -> Void
    var onImport: () -> Void
    var onExport: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdd: onAdd, onRemove: onRemove, onImport: onImport, onExport: onExport)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: [
                NSImage(named: NSImage.addTemplateName) ?? NSImage(),
                NSImage(named: NSImage.removeTemplateName) ?? NSImage(),
                NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多词典操作") ?? NSImage()
            ],
            trackingMode: .momentary,
            target: context.coordinator,
            action: #selector(Coordinator.segmentClicked(_:))
        )
        control.segmentStyle = .smallSquare
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .vertical)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setToolTip("添加词条", forSegment: 0)
        control.setToolTip("删除词条", forSegment: 1)
        control.setToolTip("导入或导出词典", forSegment: 2)
        control.setAccessibilityLabel("词典操作")
        updateNSView(control, context: context)
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.onAdd = onAdd
        context.coordinator.onRemove = onRemove
        context.coordinator.onImport = onImport
        context.coordinator.onExport = onExport
        nsView.setEnabled(canRemove, forSegment: 1)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onAdd: () -> Void
        var onRemove: () -> Void
        var onImport: () -> Void
        var onExport: () -> Void

        init(
            onAdd: @escaping () -> Void,
            onRemove: @escaping () -> Void,
            onImport: @escaping () -> Void,
            onExport: @escaping () -> Void
        ) {
            self.onAdd = onAdd
            self.onRemove = onRemove
            self.onImport = onImport
            self.onExport = onExport
        }

        @objc func segmentClicked(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0:
                onAdd()
            case 1:
                onRemove()
            case 2:
                showMoreMenu(from: sender)
            default:
                break
            }
        }

        private func showMoreMenu(from control: NSSegmentedControl) {
            let menu = NSMenu()
            let importItem = NSMenuItem(title: "导入…", action: #selector(importDictionary), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)
            let exportItem = NSMenuItem(title: "导出…", action: #selector(exportDictionary), keyEquivalent: "")
            exportItem.target = self
            menu.addItem(exportItem)

            var originX = CGFloat.zero
            for segment in 0..<2 {
                let width = control.width(forSegment: segment)
                originX += width > 0 ? width : control.bounds.width / 3
            }
            menu.popUp(positioning: nil, at: NSPoint(x: originX, y: control.bounds.height), in: control)
        }

        @objc private func importDictionary() {
            onImport()
        }

        @objc private func exportDictionary() {
            onExport()
        }
    }
}
