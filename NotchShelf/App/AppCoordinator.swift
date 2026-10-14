import AppKit
import SwiftUI
import SwiftData
import KeyboardShortcuts
import ApplicationServices
import Combine

extension KeyboardShortcuts.Name {
    static let openClipboard = Self("openClipboard", default: .init(.v, modifiers: [.option, .command]))
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    let preferences = Preferences()
    let shelf: ShelfStore
    let clipboard: ClipboardStore
    let dragWatcher = DragWatcher()
    private(set) var panels: [NotchWindowController] = []
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    private var settingsWindow: NSWindow?
    let container: ModelContainer

    override init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchShelf", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            container = try ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(url: root.appendingPathComponent("Clipboard.store")))
        } catch {
            // Never silently replace or erase a database that failed to open.
            let alert = NSAlert(); alert.messageText = "NotchShelf could not open its data"
            alert.informativeText = error.localizedDescription; alert.runModal()
            fatalError("Cannot open clipboard database: \(error)")
        }
        shelf = ShelfStore(root: root)
        clipboard = ClipboardStore(container: container, preferences: preferences)
        super.init()
    }
    func start() {
        rebuildPanels(); clipboard.prune(); clipboard.start()
        dragWatcher.onStart = { [weak self] in self?.panels.forEach { $0.model.dragStarted() } }
        dragWatcher.onEnd = { [weak self] in self?.panels.forEach { $0.model.dragEnded() } }
        dragWatcher.start()
        KeyboardShortcuts.onKeyUp(for: .openClipboard) { [weak self] in self?.openClipboard() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels() }
        })
    }

    func stop() {
        clipboard.stop(); dragWatcher.stop()
        panels.forEach { $0.stop() }; observers.forEach(NotificationCenter.default.removeObserver)
    }
    var activePanel: NotchWindowController? {
        panels.first { $0.window?.screen?.frame.contains(NSEvent.mouseLocation) == true } ?? panels.first
    }
    func rebuildPanels() {
        panels.forEach { $0.stop() }; panels.removeAll()
        let builtIn = NSScreen.screens.filter(\.isBuiltIn)
        let screens = builtIn.isEmpty ? Array(NSScreen.screens.prefix(1)) : builtIn
        panels = screens.map { NotchWindowController(screen: $0, coordinator: self) }
    }
    func rememberFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }
    }
    func openClipboard() { rememberFrontmostApp(); activePanel?.showClipboard() }
    func openShelf() { rememberFrontmostApp(); activePanel?.model.open(.shelf) }
    func showSettings() {
        panels.forEach { $0.model.collapse() }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environmentObject(self))
            let window = NSWindow(contentViewController: controller)
            window.delegate = self
            window.title = "NotchShelf Settings"; window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 550, height: 630)); window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow { settingsWindow = nil }
    }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    func paste(_ entry: ClipboardEntry, model: NotchViewModel) {
        guard clipboard.write(entry) else { model.toast("Could not copy this item"); return }
        guard accessibilityGranted, let target = previousApp, !target.isTerminated else {
            model.toast("Copied — press ⌘V in your app"); return
        }
        model.interactionHeld = false; model.collapse()
        target.activate(options: [])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                model.toast("Copied — press ⌘V in your app"); return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
}
