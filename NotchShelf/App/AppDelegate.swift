import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var coordinator = AppCoordinator()
    private var statusItem: NSStatusItem?
    private var updater: SPUStandardUpdaterController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Unit tests must not install global monitors or record the real pasteboard.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        coordinator.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "NotchShelf")
        let menu = NSMenu()
        add("Open Shelf", action: #selector(openShelf), to: menu)
        add("Clipboard History", action: #selector(openClipboard), to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(settings), to: menu)
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty,
           let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            add("Check for Updates…", action: #selector(checkUpdates), to: menu)
        }
        menu.addItem(.separator()); add("Quit NotchShelf", action: #selector(quit), to: menu, key: "q")
        item.menu = menu; statusItem = item
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome"); coordinator.showSettings()
        }
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    @objc private func openShelf() { coordinator.openShelf() }
    @objc private func openClipboard() { coordinator.openClipboard() }
    @objc private func settings() { coordinator.showSettings() }
    @objc private func checkUpdates() { updater?.checkForUpdates(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { coordinator.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
