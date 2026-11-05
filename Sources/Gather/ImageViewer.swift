import SwiftUI
import AppKit
import GatherCore

/// A centered preview with a larger canvas and scrollable, full-resolution zoom.
struct ImagePreviewView: View {
    let item: Screenshot
    let cache: ThumbnailCache
    @Environment(\.dismiss) private var dismiss
    @ViewState<NSImage?> private var image: NSImage?
    @ViewState<String?> private var failure: String?
    @ViewState<CGFloat?> private var zoom: CGFloat?
    @ViewState<CGFloat?> private var pinchStart: CGFloat?
    @ViewState<Bool> private var expanded = false
    @ViewState<CGSize> private var viewport = .zero
    private var imageSize: CGSize { image?.size ?? CGSize(width: max(1, item.width), height: max(1, item.height)) }
    private var fit: CGFloat { max(0.01, min((viewport.width - 32) / imageSize.width, (viewport.height - 32) / imageSize.height, 1)) }
    private var scale: CGFloat { zoom ?? fit }
    private var largeSize: CGSize {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: max(700, min(1100, available.width * 0.85)), height: max(550, min(760, available.height * 0.8)))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(expanded ? "Smaller preview" : "Expand preview").accessibilityLabel(expanded ? "Smaller preview" : "Expand preview")
                Button("Fit") { zoom = nil }.help("Fit the entire image")
                Button("100%") { zoom = 1 }.help("View at actual image size")
                Button { zoom = max(0.05, scale / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom out").disabled(scale <= 0.05)
                Text("\(Int((scale * 100).rounded()))%").font(.caption.monospacedDigit()).frame(minWidth: 34)
                    .accessibilityLabel("Zoom level \(Int((scale * 100).rounded())) percent")
                Button { zoom = min(8, scale * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom in").disabled(scale >= 8)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            GeometryReader { geometry in
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                            .frame(width: max(geometry.size.width, imageSize.width * scale + 32),
                                   height: max(geometry.size.height, imageSize.height * scale + 32))
                            .contentShape(Rectangle())
                            .gesture(MagnificationGesture().onChanged { value in
                                if pinchStart == nil { pinchStart = scale }
                                zoom = min(8, max(0.05, (pinchStart ?? scale) * value))
                            }.onEnded { _ in pinchStart = nil })
                            .accessibilityLabel("Preview of \(item.title)")
                    }
                } else if let failure {
                    ContentUnavailableView("Preview unavailable", systemImage: "photo.badge.exclamationmark", description: Text(failure))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ProgressView("Opening image…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                Color.clear.frame(width: 0, height: 0)
                    .onAppear { viewport = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewport = size }
            }
        }
        .frame(width: expanded ? largeSize.width : 700, height: expanded ? largeSize.height : 550)
        .background(.white).preferredColorScheme(.light)
        .onExitCommand { dismiss() }
        .task(id: item.thumbnailKey) {
            do {
                let cg = try await cache.original(for: item)
                guard !Task.isCancelled else { return }
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            } catch { failure = error.localizedDescription }
        }
    }
}
