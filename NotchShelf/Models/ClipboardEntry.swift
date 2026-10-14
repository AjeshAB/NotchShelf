import SwiftData
import Foundation
import CryptoKit

@Model
final class ClipboardEntry {
    @Attribute(.unique) var id: UUID
    var kind: String
    var text: String
    @Attribute(.externalStorage) var richText: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var filePaths: [String]
    var sourceName: String
    var sourceBundleID: String
    var timestamp: Date
    var pinned: Bool
    var contentHash: String

    init(kind: String, text: String = "", richText: Data? = nil, imageData: Data? = nil,
         filePaths: [String] = [], sourceName: String = "Unknown app", sourceBundleID: String = "") {
        self.id = UUID(); self.kind = kind; self.text = text; self.richText = richText
        self.imageData = imageData; self.filePaths = filePaths
        self.sourceName = sourceName; self.sourceBundleID = sourceBundleID
        self.timestamp = Date(); self.pinned = false
        self.contentHash = Self.hash(kind: kind, text: text, richText: richText, imageData: imageData, paths: filePaths)
    }
    static func hash(kind: String, text: String, richText: Data?, imageData: Data?, paths: [String]) -> String {
        // Length prefixes keep field boundaries unambiguous.
        var hasher = SHA256()
        for field in [Data(kind.utf8), Data(text.utf8), richText ?? Data(), imageData ?? Data()] + paths.map({ Data($0.utf8) }) {
            hasher.update(data: Data("\(field.count):".utf8)); hasher.update(data: field)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    var title: String {
        switch kind {
        case "image": return "Copied image"
        case "files": return filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        default: return text
        }
    }
    var symbol: String {
        switch kind { case "image": "photo"; case "files": "doc.on.doc"; case "link": "link"; default: "text.alignleft" }
    }
}
