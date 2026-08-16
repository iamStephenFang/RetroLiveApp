import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SystemLivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    final class Coordinator {
        var displayedLivePhoto: PHLivePhoto?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        guard context.coordinator.displayedLivePhoto != livePhoto else { return }
        context.coordinator.displayedLivePhoto = livePhoto
        view.livePhoto = livePhoto
        DispatchQueue.main.async {
            view.startPlayback(with: .hint)
        }
    }
}

struct RemoteAssetPreviewView: View {
    @ObservedObject var model: ImporterViewModel
    let asset: CameraAssetSummary

    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var isPreparingLivePhoto = false
    @State private var previewError: String?

    private var state: ImporterAssetState {
        model.assetStates[asset.assetId] ?? .available
    }

    private var isSelected: Bool {
        model.selectedAssetIds.contains(asset.assetId)
    }

    private var displayedImage: UIImage? {
        image ?? model.thumbnailImages[asset.assetId]
    }

    private var importActionTitle: String {
        switch state {
        case .available, .cached: L10n.text("preview.import")
        case .failed, .cancelled: L10n.text("common.retry")
        default: state.title
        }
    }

    private var canImport: Bool {
        switch state {
        case .available, .cached, .failed, .cancelled: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let livePhoto {
                SystemLivePhotoView(livePhoto: livePhoto)
                    .ignoresSafeArea(edges: .horizontal)
            } else if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .scaledToFit()
            } else if let previewError {
                ContentUnavailableView(
                    L10n.text("preview.unavailable"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(previewError)
                )
                .foregroundStyle(.white)
            } else {
                ProgressView(L10n.text("preview.loading"))
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if isPreparingLivePhoto, displayedImage != nil, livePhoto == nil {
                VStack {
                    Spacer()
                    Label(L10n.text("preview.preparing_live"), systemImage: "livephoto")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(.bottom, 20)
                }
            } else if let previewError, displayedImage != nil, livePhoto == nil {
                VStack {
                    Spacer()
                    Label(previewError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle(previewDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if !model.selectionMode { model.setSelectionMode(true) }
                    model.toggleSelection(asset.assetId)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .disabled(!model.canSelect(asset.assetId) && !isSelected)
                .accessibilityLabel(
                    L10n.text(isSelected ? "batch.deselect_item" : "batch.select_item")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(importActionTitle) {
                model.importAsset(asset)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(
                isPreparingLivePhoto
                    || !canImport
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .task(id: asset.assetId) {
            await loadPreview()
        }
    }

    private var previewDate: String {
        guard let date = RetroLiveISO8601.date(from: asset.createdAt) else { return asset.createdAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func loadPreview() async {
        do {
            if asset.hasMotion == true {
                isPreparingLivePhoto = true
                defer { isPreparingLivePhoto = false }
                let preview = try await model.livePhotoPreview(for: asset)
                try Task.checkCancellation()
                image = preview.image
                livePhoto = preview.livePhoto
            } else {
                image = try await model.previewImage(for: asset)
            }
        } catch is CancellationError {
            return
        } catch {
            previewError = error.localizedDescription
        }
    }
}

struct ImportedAssetPreviewView: View {
    @ObservedObject var model: ImportedLibraryViewModel
    let item: ImportedLibraryItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var shareItemProvider: NSItemProvider?
    @State private var showsShareSheet = false
    @State private var showsInfo = false
    @State private var isPreparingShare = false
    @State private var isDeleting = false
    @State private var details: ImportedAssetDetails?
    @State private var detailsError: String?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let livePhoto {
                SystemLivePhotoView(livePhoto: livePhoto)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .ignoresSafeArea()
            } else if let errorMessage {
                ContentUnavailableView(
                    L10n.text("preview.unavailable"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView(L10n.text("preview.loading"))
            }
        }
        .navigationTitle(displayDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    prepareShare()
                } label: {
                    if isPreparingShare {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .imageScale(.medium)
                    }
                }
                .disabled(image == nil || isPreparingShare || isDeleting)
                .tint(Color.primary)
                .accessibilityLabel(L10n.text("library.preview.share"))

                Spacer()

                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .imageScale(.medium)
                }
                .disabled(isDeleting)
                .tint(Color.primary)
                .accessibilityLabel(L10n.text("library.preview.info"))

                Spacer()

                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(RetroPalette.destructive)
                    } else {
                        Image(systemName: "trash")
                            .font(.body)
                            .imageScale(.medium)
                            .foregroundStyle(RetroPalette.destructive)
                    }
                }
                .disabled(isPreparingShare || isDeleting)
                .accessibilityLabel(L10n.text("library.preview.delete"))
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let shareItemProvider {
                ActivityViewController(itemProvider: shareItemProvider)
            }
        }
        .sheet(isPresented: $showsInfo) {
            NavigationStack {
                List {
                    Section {
                        LabeledContent(
                            L10n.text("library.preview.info.type"),
                            value: L10n.text(
                                item.kind == .livePhoto ? "asset.kind.live_photo" : "asset.kind.photo"
                            )
                        )
                        LabeledContent(
                            L10n.text("library.preview.info.captured"),
                            value: (item.creationDate ?? item.importedAt)
                                .formatted(date: .abbreviated, time: .shortened)
                        )
                        LabeledContent(
                            L10n.text("library.preview.info.imported"),
                            value: item.importedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }

                    Section(L10n.text("library.preview.info.file")) {
                        if let details {
                            LabeledContent(
                                L10n.text("library.preview.info.filename"),
                                value: details.filename
                            )
                            LabeledContent(
                                L10n.text("library.preview.info.format"),
                                value: details.format
                            )
                            LabeledContent(
                                L10n.text("library.preview.info.dimensions"),
                                value: "\(details.pixelWidth) × \(details.pixelHeight)"
                            )
                            LabeledContent(
                                L10n.text("library.preview.info.size"),
                                value: ByteCountFormatter.string(
                                    fromByteCount: details.byteCount,
                                    countStyle: .file
                                )
                            )
                            if let latitude = details.latitude,
                               let longitude = details.longitude {
                                LabeledContent(
                                    L10n.text("library.preview.info.location"),
                                    value: coordinateDescription(
                                        latitude: latitude,
                                        longitude: longitude
                                    )
                                )
                            }
                        } else if let detailsError {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(detailsError, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button(L10n.text("common.retry")) {
                                    loadDetails()
                                }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(L10n.text("library.preview.info.size_loading"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle(L10n.text("library.preview.info"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("common.done")) { showsInfo = false }
                    }
                }
                .task(id: item.id) {
                    if details == nil && detailsError == nil {
                        await fetchDetails()
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert(
            L10n.text("error.operation_failed"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task(id: item.id) {
            do {
                image = try await model.previewImage(for: item)
                try Task.checkCancellation()
                livePhoto = try await model.livePhoto(for: item)
            } catch is CancellationError {
                return
            } catch {
                if image == nil { errorMessage = error.localizedDescription }
            }
        }
    }

    private var displayDate: String {
        (item.creationDate ?? item.importedAt).formatted(date: .abbreviated, time: .shortened)
    }

    private func prepareShare() {
        guard !isPreparingShare, let image else { return }
        isPreparingShare = true
        if let livePhoto {
            shareItemProvider = NSItemProvider(
                item: livePhoto,
                typeIdentifier: UTType.livePhoto.identifier
            )
        } else {
            shareItemProvider = NSItemProvider(object: image)
        }
        showsShareSheet = true
        isPreparingShare = false
    }

    private func deleteItem() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await model.delete(item)
                dismiss()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func loadDetails() {
        detailsError = nil
        Task { await fetchDetails() }
    }

    private func fetchDetails() async {
        do {
            details = try await model.details(for: item)
        } catch is CancellationError {
            return
        } catch {
            detailsError = error.localizedDescription
        }
    }

    private func coordinateDescription(latitude: Double, longitude: Double) -> String {
        let latitudeText = latitude.formatted(.number.precision(.fractionLength(5)))
        let longitudeText = longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(latitudeText), \(longitudeText)"
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let itemProvider: NSItemProvider

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])
        return UIActivityViewController(activityItemsConfiguration: configuration)
    }

    func updateUIViewController(_ viewController: UIActivityViewController, context: Context) {}
}

struct ImportedLibraryView: View {
    @ObservedObject var model: ImportedLibraryViewModel

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 160), spacing: 4)]

    var body: some View {
        Group {
            if model.access.canRead {
                libraryContent
            } else {
                accessContent
            }
        }
        .background(Color(uiColor: .systemBackground))
        .alert(
            L10n.text("error.operation_failed"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var libraryContent: some View {
        ScrollView {
            if model.isLoading && model.items.isEmpty {
                ProgressView(L10n.text("library.loading"))
                    .padding(.top, 60)
            } else if model.items.isEmpty {
                ContentUnavailableView(
                    L10n.text("library.empty"),
                    systemImage: "photo.stack",
                    description: Text(L10n.text("library.empty.note"))
                )
                .padding(.top, 44)
            } else {
                LazyVStack(spacing: 10) {
                    HStack {
                        Text(L10n.format("library.imported_count", model.items.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RetroPalette.secondaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(model.items) { item in
                            NavigationLink {
                                ImportedAssetPreviewView(model: model, item: item)
                            } label: {
                                libraryTile(item)
                            }
                            .buttonStyle(.plain)
                            .task(id: item.id) { model.loadThumbnail(for: item) }
                        }
                    }
                }
                .padding(4)
            }
        }
        .refreshable { await model.refresh() }
    }

    private func libraryTile(_ item: ImportedLibraryItem) -> some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .tertiarySystemFill)
            if let image = model.thumbnails[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind == .livePhoto ? "livephoto" : "photo")
                    .foregroundStyle(.secondary)
            }
            if item.kind == .livePhoto {
                Image(systemName: "livephoto")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.42), in: Circle())
                    .padding(7)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .accessibilityLabel(
            item.kind == .livePhoto
                ? L10n.text("asset.kind.live_photo")
                : L10n.text("asset.kind.photo")
        )
    }

    private var accessContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 76, height: 76)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 24)
                            )

                        Image(systemName: accessBadgeSymbol)
                            .font(.system(size: 21, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, accessBadgeColor)
                            .background(Color(uiColor: .systemBackground), in: Circle())
                            .offset(x: 5, y: 5)
                    }

                    VStack(spacing: 8) {
                        Text(accessTitle)
                            .font(.title2.bold())
                            .foregroundStyle(RetroPalette.ink)
                            .multilineTextAlignment(.center)

                        Text(accessNote)
                            .font(.subheadline)
                            .foregroundStyle(RetroPalette.secondaryInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessAction
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private var accessAction: some View {
        if model.access == .notDetermined {
            Button {
                Task { await model.requestAccess() }
            } label: {
                Label(L10n.text("library.access.action"), systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if model.access == .denied {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label(L10n.text("library.access.settings"), systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var accessTitle: String {
        model.access == .restricted
            ? L10n.text("library.access.restricted.title")
            : L10n.text("library.access.title")
    }

    private var accessNote: String {
        model.access == .restricted
            ? L10n.text("library.access.restricted.note")
            : L10n.text("library.access.note")
    }

    private var accessBadgeSymbol: String {
        switch model.access {
        case .notDetermined: "plus.circle.fill"
        case .restricted: "lock.circle.fill"
        default: "exclamationmark.circle.fill"
        }
    }

    private var accessBadgeColor: Color {
        switch model.access {
        case .notDetermined: RetroPalette.sage
        case .restricted: RetroPalette.mustard
        default: RetroPalette.destructive
        }
    }
}
