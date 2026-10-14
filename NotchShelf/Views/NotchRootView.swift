import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    let notchSize: CGSize
    let expandedWidth: CGFloat
    let expandedHeight: CGFloat
    @EnvironmentObject private var app: AppCoordinator
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var clipboard: ClipboardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTarget = false
    @State private var clearRequest: ClearRequest = .files
    @State private var showClearConfirmation = false
    @State private var heldBeforeClear = false

    private enum ClearRequest {
        case files, unpinned, allHistory
        var title: String {
            switch self {
            case .files: return "Clear all files from the shelf?"
            case .unpinned: return "Clear unpinned clipboard history?"
            case .allHistory: return "Clear all clipboard history?"
            }
        }
        var message: String {
            switch self {
            case .files: return "This removes every shelf entry. Your original files and saved copies stay on this Mac."
            case .unpinned: return "Unpinned items will be permanently removed from history. Pinned items and your current clipboard stay."
            case .allHistory: return "All history, including pinned items, will be permanently removed. Your current clipboard stays."
            }
        }
    }

    private var visibleSize: CGSize {
        model.visibleSize(notch: notchSize, maximum: CGSize(width: expandedWidth, height: expandedHeight))
    }
    private var contentHeight: CGFloat { model.tab == .shelf ? min(240, expandedHeight) : expandedHeight }
    private var status: String? { shelf.error ?? clipboard.error ?? model.message }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape().fill(.black)
                if model.expanded {
                    VStack(spacing: 10) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                tabButton("Files", tab: .shelf)
                                tabButton("Clipboard", tab: .clipboard)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) { clearMenu }
                        if model.tab == .clipboard {
                            ClipboardView(model: model)
                        } else {
                            ShelfView(model: model)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, notchSize.height + 14)
                    .padding(.bottom, status == nil ? 22 : 42)
                    // Lay out at the destination size; only the outer silhouette changes.
                    // This prevents text and file grids reflowing on every animation frame.
                    .frame(width: expandedWidth, height: contentHeight)
                    .transition(.opacity)
                } else if model.state == .peek {
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        .padding(.top, notchSize.height + 12)
                        .transition(.opacity)
                }
            }
            .frame(width: visibleSize.width, height: visibleSize.height, alignment: .top)
            .clipShape(NotchShape())
            .contentShape(NotchShape())
            .overlay(alignment: .bottom) {
                if model.expanded, let status {
                    HStack(spacing: 8) {
                        Text(status).font(.system(size: 11)).lineLimit(1).help(status)
                        if shelf.error != nil || clipboard.error != nil {
                            Button { shelf.error = nil; clipboard.error = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                        }
                    }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.bottom, 14)
                }
            }
            .onDrop(of: [.fileURL, .image, .text, .url], isTargeted: $dropTarget) { providers in
                receiveDrop(providers, app: app, model: model)
            }
            .onChange(of: dropTarget) { _, targeted in if targeted { model.open(.shelf) } }
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.state)
            Spacer(minLength: 0)
        }
        .frame(width: expandedWidth, height: expandedHeight, alignment: .top)
        .preferredColorScheme(.dark)
        .alert(clearRequest.title, isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                switch clearRequest {
                case .files: shelf.clear(); model.toast("Shelf cleared")
                case .unpinned: clipboard.clearUnpinned(); model.toast("Unpinned history cleared")
                case .allHistory: clipboard.clearAll(); model.toast("Clipboard history cleared")
                }
            }
        } message: { Text(clearRequest.message) }
        .onChange(of: showClearConfirmation) { _, showing in
            if !showing { model.interactionHeld = heldBeforeClear }
        }
    }
    private var clearMenu: some View {
        Menu {
            if model.tab == .shelf {
                Button("Clear Files…", systemImage: "trash", role: .destructive) { requestClear(.files) }
                    .disabled(shelf.items.isEmpty)
            } else {
                Button("Clear Unpinned…", systemImage: "pin.slash", role: .destructive) { requestClear(.unpinned) }
                    .disabled(!clipboard.entries.contains { !$0.pinned })
                Divider()
                Button("Clear All History…", systemImage: "trash", role: .destructive) { requestClear(.allHistory) }
                    .disabled(clipboard.entries.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30).contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .glassEffect(.regular.interactive(), in: Circle())
        .help(model.tab == .shelf ? "File options" : "Clipboard options")
        .accessibilityLabel(model.tab == .shelf ? "File options" : "Clipboard options")
    }
    private func requestClear(_ request: ClearRequest) {
        heldBeforeClear = model.interactionHeld
        model.interactionHeld = true
        clearRequest = request; showClearConfirmation = true
    }
    private func tabButton(_ title: String, tab: NotchViewModel.Tab) -> some View {
        Button {
            if tab == .clipboard { app.openClipboard() }
            else { model.interactionHeld = false; model.open(.shelf) }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: model.tab == tab ? .semibold : .medium))
                .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.65))
                .frame(width: 112, height: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(model.tab == tab ? .white.opacity(0.16) : .clear).interactive(), in: Capsule())
        .accessibilityAddTraits(model.tab == tab ? [.isSelected] : [])
    }

}

@MainActor
@discardableResult
func receiveDrop(_ providers: [NSItemProvider], app: AppCoordinator, model: NotchViewModel) -> Bool {
    let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || ($0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)) }
    guard !accepted.isEmpty else { return false }
    model.interactionHeld = true
    Task { @MainActor in
        var urls: [URL] = []
        for provider in accepted {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let data = await loadDropData(provider, type: UTType.fileURL.identifier)
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { urls.append(url) }
            } else {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let type = [UTType.png, .jpeg, .tiff].first { provider.hasItemConformingToTypeIdentifier($0.identifier) } ?? .image
                    if let data = await loadDropData(provider, type: type.identifier),
                       let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let identifier = CGImageSourceGetType(source),
                       let suffix = UTType(identifier as String)?.preferredFilenameExtension {
                        app.shelf.add(data: data, extension: suffix)
                    }
                } else {
                    let textType = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .text) == true } ?? UTType.url.identifier
                    if let data = await loadDropData(provider, type: textType) { app.shelf.add(data: data, extension: "txt") }
                }
            }
        }
        if !urls.isEmpty { app.shelf.add(urls) }
        model.dragging = false; model.interactionHeld = false; model.open(.shelf)
    }
    return true
}
private func loadDropData(_ provider: NSItemProvider, type: String) async -> Data? {
    await withCheckedContinuation { continuation in
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
    }
}
