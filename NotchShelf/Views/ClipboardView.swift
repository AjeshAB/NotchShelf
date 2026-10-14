import SwiftUI
import ImageIO

struct ClipboardView: View {
    @ObservedObject var model: NotchViewModel
    @EnvironmentObject private var app: AppCoordinator
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var preferences: Preferences
    @State private var search = ""
    @State private var selected: UUID?
    @State private var pinnedOnly = false
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardEntry] {
        store.entries.filter { (!pinnedOnly || $0.pinned) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.sourceName.localizedCaseInsensitiveContains(search)) }
            .sorted { if $0.pinned != $1.pinned { return $0.pinned }; return $0.timestamp > $1.timestamp }
    }
    var body: some View {
        let entries = filtered
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clipboard", text: $search)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .focused($searchFocused).onSubmit { pasteSelected() }
                        .accessibilityLabel("Search clipboard")
                    if !search.isEmpty {
                        Button { search = ""; searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
                    }
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                Button { pinnedOnly.toggle() } label: {
                    Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(pinnedOnly ? .white : .secondary)
                        .frame(width: 36, height: 36).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(pinnedOnly ? .white.opacity(0.16) : .clear).interactive(), in: Circle())
                .help(pinnedOnly ? "Show all items" : "Show pinned items")
                .accessibilityLabel("Pinned only")
                .accessibilityValue(pinnedOnly ? "On" : "Off")
            }
            if entries.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(entries) { entry in
                                ClipboardRow(entry: entry, selected: selected == entry.id,
                                             pasteEnabled: app.accessibilityGranted,
                                             select: { selected = entry.id },
                                             paste: { app.paste(entry, model: model) },
                                             pin: { store.togglePin(entry) },
                                             copy: { if store.write(entry) { model.toast("Copied") } },
                                             delete: { store.delete(entry) })
                                    .id(entry.id)
                            }
                        }.padding(1)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selected) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            HStack(spacing: 6) {
                Text("\(entries.count) \(entries.count == 1 ? "item" : "items")")
                if !preferences.clipboardEnabled {
                    Text("·")
                    Button("History paused") { app.showSettings() }
                        .buttonStyle(.plain).help("Open clipboard settings")
                }
                Spacer()
                Text(app.accessibilityGranted ? "↩ Paste" : "↩ Copy")
                    .help("Use arrow keys to select an item. Press Return to \(app.accessibilityGranted ? "paste" : "copy"). Escape closes the panel.")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .onAppear {
            selected = entries.first?.id; refreshKeyboardHandlers()
            searchFocused = true
        }
        .onDisappear { model.navigateClipboard = nil; model.pasteClipboardSelection = nil }
        .onChange(of: model.searchRequest) { _, _ in searchFocused = true }
        .onChange(of: search) { _, _ in selected = filtered.first?.id; refreshKeyboardHandlers() }
        .onChange(of: pinnedOnly) { _, _ in selected = filtered.first?.id; refreshKeyboardHandlers() }
        .onChange(of: entries.map(\.id)) { _, ids in
            if let selected, ids.contains(selected) {} else { selected = ids.first }
            refreshKeyboardHandlers()
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? (pinnedOnly ? "pin" : "doc.on.clipboard") : "magnifyingglass")
                .font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            Text(!search.isEmpty ? "No matches" : pinnedOnly ? "No pinned items" : "Your clipboard is empty")
                .font(.system(size: 14, weight: .medium))
            Text(!search.isEmpty ? "Try a different search." : pinnedOnly ? "Pin an item to keep it here." : preferences.clipboardEnabled ? "Copied text, links, and images appear here." : "Enable clipboard history to get started.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !preferences.clipboardEnabled, search.isEmpty, !pinnedOnly {
                Button("Open Settings") { app.showSettings() }.buttonStyle(.glass).controlSize(.small)
            }
        }.padding(.horizontal, 12)
    }
    private func refreshKeyboardHandlers() {
        model.navigateClipboard = { move($0) }; model.pasteClipboardSelection = { pasteSelected() }
    }
    private func move(_ offset: Int) {
        let entries = filtered; guard !entries.isEmpty else { return }
        let index = entries.firstIndex { $0.id == selected } ?? (offset > 0 ? -1 : entries.count)
        selected = entries[min(max(index + offset, 0), entries.count - 1)].id
    }
    private func pasteSelected() { if let entry = filtered.first(where: { $0.id == selected }) { app.paste(entry, model: model) } }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let selected: Bool
    let pasteEnabled: Bool
    let select: () -> Void
    let paste: () -> Void
    let pin: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var thumbnail: NSImage?
    private var showActions: Bool { hovered || selected }
    private var preview: String {
        String(entry.title.prefix(240)).split(whereSeparator: \.isNewline).joined(separator: " ")
    }
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: entry.symbol).font(.system(size: 15, weight: .regular)).foregroundStyle(.secondary) }
            }
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(preview).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Text(entry.sourceName).lineLimit(1)
                    Text("·")
                    Text(entry.timestamp, style: .time).lineLimit(1)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                Button(action: pin) {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                        .frame(width: 26, height: 30)
                }
                .opacity(showActions || entry.pinned ? 1 : 0)
                .accessibilityHidden(!showActions && !entry.pinned)
                .help(entry.pinned ? "Unpin" : "Pin")
                .accessibilityLabel(entry.pinned ? "Unpin item" : "Pin item")
                Button(action: paste) {
                    Image(systemName: pasteEnabled ? "return" : "doc.on.doc")
                        .frame(width: 26, height: 30)
                }
                .opacity(showActions ? 1 : 0).accessibilityHidden(!showActions)
                .help(pasteEnabled ? "Paste into previous app" : "Copy")
                .accessibilityLabel(pasteEnabled ? "Paste item" : "Copy item")
            }.font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.white.opacity(selected ? 0.12 : hovered ? 0.075 : 0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(selected ? 0.1 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2, perform: paste)
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            Button("Copy", action: copy)
            Button(entry.pinned ? "Unpin" : "Pin", action: pin)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .task(id: entry.contentHash) {
            guard entry.kind == "image" else { return }
            if let cached = ClipboardThumbnails.cache.object(forKey: entry.contentHash as NSString) { thumbnail = cached; return }
            guard let data = entry.imageData else { return }
            let image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 80
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled, let image else { return }
            let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            ClipboardThumbnails.cache.setObject(result, forKey: entry.contentHash as NSString, cost: image.bytesPerRow * image.height)
            thumbnail = result
        }
    }
}

@MainActor
private enum ClipboardThumbnails {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100; cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
}
