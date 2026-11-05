import SwiftUI
import GatherCore
import AppKit

struct ScreenshotImage: View {
    let item: Screenshot
    let cache: ThumbnailCache
    var pixels = 700
    @ViewState<NSImage?> private var image: NSImage?
    @ViewState<String?> private var failure: String?
    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(8) }
            else if let failure {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark").font(.title2)
                    Text("Preview unavailable").font(.caption)
                }.foregroundStyle(.secondary).help(failure)
            } else { ProgressView().controlSize(.small) }
        }
        .accessibilityLabel("Preview of \(item.title)")
        .task(id: "\(item.thumbnailKey)-\(pixels)-\(item.path)") {
            do {
                let cg = try await cache.thumbnail(for: item, pixels: pixels)
                guard !Task.isCancelled else { return }
                image = NSImage(cgImage: cg, size: .zero)
            } catch { failure = error.localizedDescription }
        }
    }
}
struct ScreenshotCard: View {
    let item: Screenshot
    let cache: ThumbnailCache
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenshotImage(item: item, cache: cache).frame(height: 190)
                .overlay(alignment: .topTrailing) {
                    if item.favorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(GatherTheme.accent).padding(7).background(.regularMaterial, in: Circle()).padding(8) }
                }
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    if item.tags.isEmpty {
                        Text(item.ocrStatus == "complete" ? "No tags yet" : "Reading text…").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(item.tags.prefix(2)), id: \.self) { ContentTagChip(name: $0) }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(item.captureDate, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? GatherTheme.accent : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.025), radius: 4, y: 2)
    }
}

struct CopyScreenshotTextButton: View {
    let model: AppModel
    let item: Screenshot
    var body: some View {
        Button { model.copyText(item) } label: {
            Label(model.copiedTextID == item.id ? "Text copied" : "Copy Text",
                  systemImage: model.copiedTextID == item.id ? "checkmark" : "doc.on.doc")
        }
        .font(.caption)
        .disabled(item.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(item.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? (item.ocrStatus == "complete" ? "No readable text found" : "Text recognition hasn’t finished")
              : "Copy screenshot text (⇧⌘C when selected)")
    }
}

struct InspectorView: View {
    @Bindable var model: AppModel
    let item: Screenshot
    @ViewState<String> private var title = ""
    @ViewState<String> private var tags = ""
    @ViewState<Bool> private var readable = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Details").font(.headline).foregroundStyle(.secondary); Spacer()
                    Button { model.update(item.id) { $0.favorite.toggle() } } label: { Image(systemName: item.favorite ? "heart.fill" : "heart") }.buttonStyle(.plain).foregroundStyle(GatherTheme.accent).help("Toggle favorite").accessibilityLabel(item.favorite ? "Remove favorite" : "Add favorite")
                }
                ScreenshotImage(item: item, cache: model.cache, pixels: 1200).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 9))
                    .onTapGesture(count: 2) { model.openImage(item) }
                    .nativeFileDrag(item: item, model: model) { model.selectedID = item.id }
                    .help("Double-click to open, or drag the image into another app")
                if !readable {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Original unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                        Text("The file may have moved, been deleted, or need permission. A cached preview can still be shown.").font(.caption)
                        Button("Grant Access…", action: model.grantAgain)
                        Button("Locate Original…") { model.locate(item) }
                    }.padding(12).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Friendly title", text: $title).font(.system(size: 17, weight: .semibold)).textFieldStyle(.plain).onSubmit(saveTitle)
                        .onChange(of: title) { _, value in
                            guard value != item.title else { return }
                            model.update(item.id) { $0.title = value; $0.manualTitle = true }
                        }
                    Text(item.manualTitle ? "Custom title · original filename unchanged" : item.ocrStatus == "complete" ? "Suggested from screenshot text" : "Original filename stays unchanged").font(.caption2).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Category")
                    Picker("Category", selection: Binding(get: { item.category }, set: { category in model.update(item.id) { $0.category = category; $0.manualCategory = true } })) {
                        ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        fieldLabel(item.manualTags ? "Tags · edited by you" : "Tags · from screenshot text")
                        Spacer()
                        Menu {
                            ForEach(model.availableTags.filter { name in !item.tags.contains { ContentTags.key($0) == ContentTags.key(name) } }, id: \.self) { name in
                                Button(name) { model.addTag(name, to: item.id) }
                            }
                            Divider()
                            Button("Create New Tag…") { model.showNewTag = true }
                        } label: { Image(systemName: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add or create tag")
                    }
                    if !item.tags.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 6) {
                            ForEach(item.tags, id: \.self) { name in
                                HStack(spacing: 4) {
                                    Text(name).lineLimit(1)
                                    Button { model.removeTag(name, from: item.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                        .buttonStyle(.plain).accessibilityLabel("Remove tag \(name)")
                                }.font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(GatherTheme.accent.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    TextField("Add tags, separated by commas", text: $tags).textFieldStyle(.roundedBorder)
                        .onSubmit(saveTags)
                    Button("Save Tags", action: saveTags).font(.caption)
                }
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Collections")
                    if model.collections.isEmpty { Text("Create a collection in the sidebar.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(model.collections) { collection in
                        Toggle(collection.name, isOn: Binding(get: { item.collections.contains(collection.id) }, set: { enabled in
                            model.update(item.id) { screenshot in
                                screenshot.collections.removeAll { $0 == collection.id }
                                if enabled { screenshot.collections.append(collection.id) }
                            }
                        })).toggleStyle(.checkbox)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        fieldLabel("Text in screenshot")
                        Spacer()
                        CopyScreenshotTextButton(model: model, item: item)
                    }
                    if item.ocrStatus == "failed" {
                        Text(item.processingError ?? "Text recognition failed.").font(.caption).foregroundStyle(.secondary)
                        Button("Retry Text Recognition") { model.retryOCR(item.id) }
                    } else if item.ocrStatus != "complete" {
                        Text("Waiting for local text recognition…").font(.caption).foregroundStyle(.secondary)
                    } else if item.extractedText.isEmpty {
                        Text("No readable text found. You can set a category manually.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView { Text(item.extractedText).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 180).padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Toggle("Reviewed", isOn: Binding(get: { !item.inbox }, set: { value in model.update(item.id) { $0.inbox = !value } })).toggleStyle(.checkbox)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("File information")
                    info("Filename", item.originalFilename)
                    info("Captured", item.captureDate.formatted(date: .abbreviated, time: .shortened))
                    info("Imported", item.importDate.formatted(date: .abbreviated, time: .shortened))
                    info("Dimensions", "\(item.width) × \(item.height)")
                    info("Size", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    Text(item.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(4)
                    Button { model.showInFinder(item) } label: { Label("Show in Finder", systemImage: "folder") }
                    Button(role: .destructive) { model.requestDeletion([item.id]) } label: { Label("Delete Screenshot…", systemImage: "trash") }.disabled(!model.canDelete)
                }
            }.padding(22)
        }.frame(minWidth: 270, idealWidth: 300, maxWidth: 400)
        .onAppear { title = item.title; tags = item.tags.joined(separator: ", ") }
        .onChange(of: item.title) { old, new in if title == old { title = new } }
        .onChange(of: item.tags) { old, new in if tags == old.joined(separator: ", ") { tags = new.joined(separator: ", ") } }
        .task(id: item.path) {
            readable = await Task.detached { FileManager.default.isReadableFile(atPath: item.path) }.value
        }
    }
    func fieldLabel(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
    func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.caption)
    }
    func saveTitle() { model.update(item.id) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines); $0.manualTitle = true } }
    func saveTags() {
        let values = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        model.update(item.id) { $0.tags = ContentTags.normalize(values); $0.manualTags = true }
    }
}
