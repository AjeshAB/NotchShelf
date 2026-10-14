import AppKit

@MainActor
final class DragWatcher {
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var active = false
    private var lastCount = NSPasteboard(name: .drag).changeCount
    func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            self?.handle(event); return event
        }) { monitors.append(monitor) }
    }
    private func beginWatchingDragEnd() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.finishDrag()
            }
        }
        timer.tolerance = 0.1
        self.timer = timer
        // Only active during an actual drag, including AppKit's tracking run loop.
        RunLoop.main.add(timer, forMode: .common)
    }
    private func finishDrag() {
        timer?.invalidate(); timer = nil
        guard active else { return }
        active = false; onEnd?()
    }
    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseUp { finishDrag(); return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastCount else { return }
        lastCount = board.changeCount
        guard board.availableType(from: [.fileURL, .png, .tiff, .string, .URL]) != nil else { return }
        guard !active else { return }
        active = true; beginWatchingDragEnd(); onStart?()
    }
    func stop() { monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); timer?.invalidate(); timer = nil; active = false }
}
