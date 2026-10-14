import AppKit
import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable { case shelf = "Shelf", clipboard = "Clipboard" }
    enum State: Equatable { case collapsed, peek, expanded(Tab) }
    @Published var state: State = .collapsed
    @Published var dragging = false
    @Published var outgoingDrag = false
    @Published var message: String?
    @Published var searchRequest = 0
    @Published var interactionHeld = false
    var onOpen: (() -> Void)?
    var navigateClipboard: ((Int) -> Void)?
    var pasteClipboardSelection: (() -> Void)?
    private var hoverTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    var expanded: Bool { if case .expanded = state { true } else { false } }
    var tab: Tab { if case let .expanded(tab) = state { tab } else { .shelf } }
    private var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.32)
    }
    func visibleSize(notch: CGSize, maximum: CGSize) -> CGSize {
        switch state {
        case .collapsed: return notch
        case .peek: return CGSize(width: min(max(notch.width + 80, 280), maximum.width), height: notch.height + 44)
        case .expanded(.shelf): return CGSize(width: maximum.width, height: min(240, maximum.height))
        case .expanded(.clipboard): return maximum
        }
    }
    func open(_ tab: Tab = .shelf, focusSearch: Bool = false) {
        hoverTask?.cancel()
        if !expanded { onOpen?(); NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if state != .expanded(tab) { withAnimation(motion) { state = .expanded(tab) } }
        if focusSearch { interactionHeld = false; searchRequest += 1 }
    }
    func collapse() {
        hoverTask?.cancel()
        if interactionHeld { interactionHeld = false }
        if state != .collapsed { withAnimation(motion) { state = .collapsed } }
    }
    func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard !interactionHeld else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(inside ? 100 : 300))
            guard !Task.isCancelled, let self, !self.interactionHeld else { return }
            if inside { self.open(self.tab) } else if !self.dragging { self.collapse() }
        }
    }
    func dragStarted() {
        dragging = true
        if !expanded { withAnimation(motion) { state = .peek } }
    }
    func dragEnded() { dragging = false; hover(false) }
    func toast(_ text: String) {
        messageTask?.cancel(); message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }; self?.message = nil
        }
    }
}

extension NSScreen {
    var notchRect: NSRect? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea, safeAreaInsets.top > 0, right.minX > left.maxX else { return nil }
        return NSRect(x: left.maxX, y: frame.maxY - safeAreaInsets.top, width: right.minX - left.maxX, height: safeAreaInsets.top)
    }
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
}
