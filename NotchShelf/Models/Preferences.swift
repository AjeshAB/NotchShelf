import AppKit
import Combine

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var removeAfterDrag: Bool { didSet { defaults.set(removeAfterDrag, forKey: "removeAfterDrag") } }
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    @Published var historyDays: Int { didSet { defaults.set(historyDays, forKey: "historyDays") } }
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["clipboardEnabled": false, "historyLimit": 200, "historyDays": 30,
                                     "excludedApps": "com.1password.1password\ncom.agilebits.onepassword7\ncom.apple.keychainaccess"])
        clipboardEnabled = defaults.bool(forKey: "clipboardEnabled")
        removeAfterDrag = defaults.bool(forKey: "removeAfterDrag")
        historyLimit = defaults.integer(forKey: "historyLimit")
        historyDays = defaults.integer(forKey: "historyDays")
        excludedApps = defaults.string(forKey: "excludedApps") ?? ""
    }
    func excludes(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == bundleID }
    }
}

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var bookmark: Data
    var originalPath: String
    var name: String
    var addedAt = Date()
    var managed: Bool
    // Optional fields preserve compatibility with existing shelf manifests.
    var sourcePath: String? = nil
    var sourceBookmark: Data? = nil
    var payloadHash: String? = nil
    func sourceURL() -> URL? {
        if let sourceBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: sourceBookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale) { return url }
        }
        return sourcePath.map { URL(fileURLWithPath: $0) }
    }
    func resolve() -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale), FileManager.default.fileExists(atPath: url.path) { return url }
        let url = URL(fileURLWithPath: originalPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
