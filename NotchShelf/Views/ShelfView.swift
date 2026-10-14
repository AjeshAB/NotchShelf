import SwiftUI
import QuartzCore

struct ShelfView: View {
    @ObservedObject var model: NotchViewModel
    @EnvironmentObject private var app: AppCoordinator
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = Set<UUID>()

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if shelf.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down").font(.system(size: 22, weight: .light))
                        Text("Drop files here").font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(model.dragging ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("File shelf. Drop files here to keep them.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                            ForEach(shelf.items) { item in
                                ShelfFileTile(item: item, selected: selection.contains(item.id),
                                    urls: { selection.contains(item.id) ? selectedURLs : [item.resolve()].compactMap { $0 } },
                                    onSelect: { select(item) },
                                    onPress: { model.interactionHeld = $0 },
                                    onDragStart: {
                                        model.interactionHeld = true; model.outgoingDrag = true; model.dragging = true
                                    }, onDragEnd: { success in
                                        model.outgoingDrag = false; model.interactionHeld = false; model.dragging = false
                                        if success && preferences.removeAfterDrag {
                                            shelf.remove(selection.contains(item.id) ? selection : [item.id]); selection.removeAll()
                                        }
                                        model.hover(false)
                                    })
                                .frame(height: 82)
                                .help(item.name)
                                .contextMenu {
                                    Button("Open") { if let url = item.resolve() { NSWorkspace.shared.open(url) } }
                                    Button("Show in Finder") { if let url = item.resolve() { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                    Divider()
                                    Button("Remove from shelf") {
                                        let ids: Set<UUID> = selection.contains(item.id) ? selection : [item.id]
                                        shelf.remove(ids); selection.subtract(ids)
                                    }
                                }
                            }
                        }.padding(1)
                    }
                }
            }

        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: model.dragging)
        .onChange(of: shelf.items.map(\.id)) { _, ids in selection.formIntersection(ids) }
    }
    private var selectedURLs: [URL] { shelf.items.filter { selection.contains($0.id) }.compactMap { $0.resolve() } }
    private func select(_ item: ShelfItem) {
        if NSEvent.modifierFlags.contains(.command) { if !selection.insert(item.id).inserted { selection.remove(item.id) } }
        else { selection = [item.id] }
    }
}

// AppKit owns the entire tile's mouse sequence. A SwiftUI tap recognizer around
// an NSImageView can consume mouseDown before the native dragging source gets it.
struct ShelfFileTile: NSViewRepresentable {
    let item: ShelfItem
    let selected: Bool
    let urls: () -> [URL]
    let onSelect: () -> Void
    let onPress: (Bool) -> Void
    let onDragStart: () -> Void
    let onDragEnd: (Bool) -> Void
    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.urls = urls; view.onSelect = onSelect; view.onPress = onPress
        view.onDragStart = onDragStart; view.onDragEnd = onDragEnd
        let shouldRefresh = view.loadedBookmark != item.bookmark || Date().timeIntervalSince(view.lastResolvedAt) > 5
        if shouldRefresh {
            let url = item.resolve()
            if view.loadedBookmark == nil || view.resolvedPath != url?.path {
                view.image = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "doc.badge.ellipsis", accessibilityDescription: "File unavailable")
            }
            view.resolvedPath = url?.path
            view.loadedBookmark = item.bookmark; view.lastResolvedAt = Date()
            view.available = url != nil
            view.toolTip = url == nil ? "File unavailable" : item.originalPath
        }
        let needsRedraw = shouldRefresh || view.filename != item.name || view.selected != selected
        view.filename = item.name; view.selected = selected
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(item.name)
        view.setAccessibilityHelp("Drag this file to another app. Command-click to select multiple files.")
        if needsRedraw { view.needsDisplay = true }
        view.updateHoverAppearance()
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onSelect: () -> Void = {}
    var onPress: (Bool) -> Void = { _ in }
    var onDragStart: () -> Void = {}
    var onDragEnd: (Bool) -> Void = { _ in }
    var loadedBookmark: Data?
    var resolvedPath: String?
    var lastResolvedAt = Date.distantPast
    var image: NSImage?
    var filename = ""
    var selected = false
    var available = true
    private var mouseStart: NSPoint?
    private var dragging = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHoverAppearance() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHoverAppearance() }
    func updateHoverAppearance() {
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = 12
        let color = NSColor.white.withAlphaComponent(hovered ? 0.075 : 0).cgColor
        guard layer.backgroundColor != color else { return }
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        layer.backgroundColor = color
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = previous; fade.toValue = color; fade.duration = 0.16
            layer.add(fade, forKey: "fileHover")
        }
    }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onSelect(); return true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.white.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        }
        image?.draw(in: NSRect(x: (bounds.width - 40) / 2, y: 8, width: 40, height: 40),
                    from: .zero, operation: .sourceOver, fraction: available ? 1 : 0.4, respectFlipped: true, hints: nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingMiddle
        (filename as NSString).draw(in: NSRect(x: 6, y: 56, width: max(0, bounds.width - 12), height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(available ? 0.9 : 0.45),
            .paragraphStyle: paragraph
        ])
    }
    override func mouseDown(with event: NSEvent) {
        mouseStart = event.locationInWindow; onPress(true)
    }
    override func mouseUp(with event: NSEvent) {
        if mouseStart != nil { onSelect() }
        mouseStart = nil
        if !dragging { onPress(false) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseStart = nil
        let files = urls()
        guard !files.isEmpty else { onPress(false); return }
        dragging = true
        let point = convert(event.locationInWindow, from: nil)
        let items = Self.draggingItems(for: files, at: point)
        onDragStart()
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }
    static func draggingItems(for files: [URL], at point: NSPoint) -> [NSDraggingItem] {
        files.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: point.x - 20 + CGFloat(index * 5), y: point.y - 20, width: 40, height: 40),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false; mouseStart = nil; onPress(false); onDragEnd(!operation.isEmpty)
    }
}
