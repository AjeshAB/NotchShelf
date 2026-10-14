import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var app: AppCoordinator
    var body: some View { SettingsContent(preferences: app.preferences).environmentObject(app) }
}
private struct SettingsContent: View {
    @ObservedObject var preferences: Preferences
    @EnvironmentObject private var app: AppCoordinator
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("General") {
                    KeyboardShortcuts.Recorder("Open clipboard", name: .openClipboard)
                    Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            if SMAppService.mainApp.status == .requiresApproval { message = "Allow NotchShelf in System Settings → General → Login Items." }
                        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = error.localizedDescription }
                    }
                }
                Section("Shelf") {
                    Toggle("Remove items after a successful drag", isOn: $preferences.removeAfterDrag)
                    Text("⌘-click to select multiple files, then drag a file icon. Removing an item keeps its original file. Saved drop copies remain in Application Support.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Clipboard & privacy") {
                    Toggle("Record clipboard history", isOn: $preferences.clipboardEnabled)
                    Text("History stays on this Mac. Password-manager concealed and transient items are skipped. macOS may ask you to allow clipboard access.").font(.caption).foregroundStyle(.secondary)
                    Stepper("Keep \(preferences.historyLimit) recent items", value: $preferences.historyLimit, in: 50...1000, step: 50)
                    Stepper("Keep for \(preferences.historyDays) days", value: $preferences.historyDays, in: 1...90)
                    Text("Pinned items are kept until you delete them.").font(.caption).foregroundStyle(.secondary)
                    Text("Exclude apps (one bundle ID per line)").font(.caption)
                    TextEditor(text: $preferences.excludedApps).font(.system(size: 11, design: .monospaced)).frame(height: 62)
                    HStack {
                        Button("Enable Automatic Paste…") { app.requestAccessibility() }
                        Spacer()
                        Button("Clear Unpinned History…", role: .destructive) { confirmClear = true }
                    }
                    Text("Automatic paste uses Accessibility. Without it, items are copied so you can press ⌘V yourself.").font(.caption).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).foregroundStyle(.orange).font(.caption) } }
            }.formStyle(.grouped)
            HStack {
                Text("NotchShelf 0.1.0"); Spacer()
                Button("Show saved files") { NSWorkspace.shared.open(app.shelf.filesDirectory) }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 550, height: 630)
            .onChange(of: preferences.historyLimit) { _, _ in app.clipboard.prune() }
            .onChange(of: preferences.historyDays) { _, _ in app.clipboard.prune() }
            .alert("Clear unpinned history?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear History", role: .destructive) { app.clipboard.clearUnpinned() }
            } message: { Text("This permanently deletes unpinned clipboard items from NotchShelf. Pinned items stay.") }
    }
}
