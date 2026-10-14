import AppKit
import Combine
import CryptoKit

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var error: String?
    let root: URL
    private var manifest: URL { root.appendingPathComponent("shelf.json") }
    var filesDirectory: URL { root.appendingPathComponent("Shelf", isDirectory: true) }
    init(root: URL) {
        self.root = root
        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                items = try JSONDecoder().decode([ShelfItem].self, from: Data(contentsOf: manifest))
                reconcileRawDrops()
            }
        } catch { self.error = "Could not load shelf: \(error.localizedDescription)" }
    }
    private func reconcileRawDrops() {
        // Earlier builds did not record a hash for generated drops. Upgrade their
        // metadata and collapse exact duplicates, retaining all backing files.
        var seen = Set<String>()
        var changed = false
        items = items.filter { item in
            guard item.managed, item.name.hasPrefix("Drop."), let url = item.resolve() else { return true }
            let hash = item.payloadHash ?? Self.fileHash(url)
            guard let hash else { return true }
            if !seen.insert(hash).inserted { changed = true; return false }
            return true
        }.map { item in
            var item = item
            if item.payloadHash == nil, item.managed, item.name.hasPrefix("Drop."), let url = item.resolve() {
                item.payloadHash = Self.fileHash(url)
                if item.payloadHash != nil { changed = true }
            }
            return item
        }
        if changed { save() }
    }
    private static func fileHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch { return nil }
    }
    func add(_ urls: [URL], copy: Bool = false) {
        for url in urls where url.isFileURL {
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let source = url.resolvingSymlinksInPath().standardizedFileURL
                if items.contains(where: { item in
                    guard let existing = item.resolve() else { return false }
                    return existing.resolvingSymlinksInPath().standardizedFileURL == source ||
                        item.sourceURL()?.resolvingSymlinksInPath().standardizedFileURL == source
                }) { continue }
                let temporary = url.path.hasPrefix(NSTemporaryDirectory()) || url.path.hasPrefix("/private/var/folders/")
                let alreadyStored = source.path.hasPrefix(filesDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/")
                let managed = copy || temporary || alreadyStored
                var stored = url
                if managed && !alreadyStored {
                    let folder = filesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    stored = folder.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: stored)
                }
                let bookmark = try stored.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                items.insert(ShelfItem(bookmark: bookmark, originalPath: stored.path, name: stored.lastPathComponent, managed: managed,
                                       sourcePath: source.path,
                                       sourceBookmark: try? source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)), at: 0)
            } catch { self.error = "Could not keep \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        save()
    }
    func add(data: Data, extension suffix: String) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !items.contains(where: { $0.payloadHash == hash && $0.resolve() != nil }) else { return }
        do {
            let folder = filesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Drop.\(suffix)")
            try data.write(to: url, options: .atomic)
            add([url])
            if let index = items.firstIndex(where: { $0.originalPath == url.path }) { items[index].managed = true; items[index].payloadHash = hash; save() }
        } catch { self.error = error.localizedDescription }
    }
    func clear() { remove(Set(items.map(\.id))) }
    func remove(_ ids: Set<UUID>) {
        // Managed files are retained so drags and clipboard references remain valid.
        items.removeAll { ids.contains($0.id) }; save()
    }
    private func save() {
        do { try JSONEncoder().encode(items).write(to: manifest, options: .atomic) }
        catch { self.error = "Could not save shelf: \(error.localizedDescription)" }
    }
}
