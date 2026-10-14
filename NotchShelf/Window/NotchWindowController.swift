import AppKit
import SwiftUI
import Combine

final class NotchPanel: NSPanel {
    init(rect: NSRect) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = false; isMovable = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController: NSWindowController {
    let model = NotchViewModel()
    let notchSize: CGSize
    let expandedWidth: CGFloat
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var subscription: AnyCancellable?
    private var wasInside = false
    private var pointerUpdateQueued = false
    private var pointerFallback: Timer?
    private var lastPointerLocation: NSPoint?
    private var cachedShapeSize = CGSize.zero
    private var cachedShape = Path()
    init(screen: NSScreen, coordinator: AppCoordinator) {
        let notch = screen.notchRect
        notchSize = notch?.size ?? CGSize(width: 164, height: 28)
        expandedWidth = min(480, screen.frame.width - 32)
        let height = min(380.0, screen.frame.height - 60)
        let center = notch?.midX ?? screen.frame.midX
        let panel = NotchPanel(rect: NSRect(x: center - expandedWidth / 2, y: screen.frame.maxY - height, width: expandedWidth, height: height))
        super.init(window: panel)
        model.onOpen = { [weak coordinator] in coordinator?.rememberFrontmostApp() }
        let view = NotchRootView(model: model, notchSize: notchSize, expandedWidth: expandedWidth, expandedHeight: height)
            .environmentObject(coordinator).environmentObject(coordinator.shelf).environmentObject(coordinator.clipboard)
            .environmentObject(coordinator.preferences)
        let hosting = TrackingHostingView(rootView: view)
        hosting.pointerChanged = { [weak self] in self?.updatePointer() }
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.queuePointerUpdate() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, panel.isKeyWindow { self.model.collapse(); panel.resignKey(); return nil }
            if event.type == .keyDown, panel.isKeyWindow, self.model.tab == .clipboard,
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                if event.keyCode == 125 { self.model.navigateClipboard?(1); return nil }
                if event.keyCode == 126 { self.model.navigateClipboard?(-1); return nil }
                if event.keyCode == 36 { self.model.pasteClipboardSelection?(); return nil }
            }
            self.updatePointer(); return event
        }
        panel.acceptsMouseMovedEvents = true
        subscription = model.$state.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updatePointer(scheduleHover: false) }
        }
        // Some system/drag interactions omit mouse-moved delivery. The fallback
        // only compares a point; it never redraws or publishes unchanged state.
        pointerFallback = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lastPointerLocation != NSEvent.mouseLocation else { return }
                self.updatePointer()
            }
        }
        pointerFallback?.tolerance = 0.3

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        pointerFallback?.invalidate(); pointerFallback = nil
        subscription?.cancel(); close()
    }
    func showClipboard() {
        model.interactionHeld = false
        model.open(.clipboard, focusSearch: true)
        window?.makeKeyAndOrderFront(nil)
        window?.ignoresMouseEvents = false
    }
    private func queuePointerUpdate() {
        guard !pointerUpdateQueued else { return }
        pointerUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerUpdateQueued = false
            self.updatePointer()
        }
    }
    private func updatePointer(scheduleHover: Bool = true) {
        guard let window else { return }
        let size = model.visibleSize(notch: notchSize, maximum: window.frame.size)
        let mouse = NSEvent.mouseLocation
        lastPointerLocation = mouse
        let local = CGPoint(x: mouse.x - window.frame.midX + size.width / 2, y: window.frame.maxY - mouse.y)
        let bounds = CGRect(origin: .zero, size: size)
        if size != cachedShapeSize {
            cachedShapeSize = size; cachedShape = NotchShape().path(in: bounds)
        }
        let hit = bounds.contains(local) && cachedShape.contains(local)
        let inside = hit || (!model.expanded && bounds.insetBy(dx: -4, dy: -4).contains(local))
        if window.ignoresMouseEvents != !hit { window.ignoresMouseEvents = !hit }
        if scheduleHover, inside != wasInside {
            wasInside = inside; model.hover(inside)
        }
        if !model.expanded {
            if model.interactionHeld { model.interactionHeld = false }
            if window.isKeyWindow { window.resignKey() }
        }
    }
}

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = min(12, rect.height / 3), bottom: CGFloat = min(25, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: top), control: CGPoint(x: rect.maxX - top, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        p.addLine(to: CGPoint(x: top + bottom, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: top, y: rect.maxY - bottom), control: CGPoint(x: top, y: rect.maxY))
        p.addLine(to: CGPoint(x: top, y: top))
        p.addQuadCurve(to: .zero, control: CGPoint(x: top, y: 0))
        p.closeSubpath(); return p
    }
}

@MainActor
private final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var pointerChanged: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); self.area = area
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?() }
    override func mouseExited(with event: NSEvent) { pointerChanged?() }
}
