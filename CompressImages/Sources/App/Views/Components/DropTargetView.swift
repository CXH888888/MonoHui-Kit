import SwiftUI

struct DropTargetView: NSViewRepresentable {
    @Binding var imageItems: [ImageItem]
    @Binding var isTargeted: Bool

    func makeNSView(context: Context) -> NSView {
        let view = DropTargetNSView()
        view.imageItems = $imageItems
        view.isTargeted = $isTargeted
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {}
}

class DropTargetNSView: NSView {
    var imageItems: Binding<[ImageItem]>?
    var isTargeted: Binding<Bool>?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted?.wrappedValue = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted?.wrappedValue = false
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        for url in urls {
            imageItems?.wrappedValue.append(ImageItem(url: url))
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }
}
