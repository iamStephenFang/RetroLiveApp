import SwiftUI

enum RetroPalette {
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let destructive = Color(uiColor: .systemRed)
    static let mustard = Color(red: 0.95, green: 0.65, blue: 0.12)
    static let sage = Color(red: 0.45, green: 0.53, blue: 0.41)
}

struct ContentView: View {
    @StateObject private var model = ImporterViewModel()
    @StateObject private var libraryModel = ImportedLibraryViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var pairingFieldFocused: Bool
    @State private var selectedTab: ImporterTab = .devices
    @State private var previewAsset: CameraAssetSummary?

    private let assetGridColumns = [
        GridItem(.adaptive(minimum: 92, maximum: 128), spacing: 4)
    ]

    private enum ImporterTab: Hashable {
        case devices
        case library
        case settings
    }

    var body: some View {
        tabs
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
        .sensoryFeedback(.error, trigger: model.pairingFailureCount)
        .task { model.startDiscovery() }
        .onChange(of: selectedTab) { _, tab in
            switch tab {
            case .library:
                Task { await libraryModel.refresh() }
            case .devices:
                Task { await model.refreshImportStatuses() }
            case .settings:
                break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.disconnectForBackground()
            case .active:
                model.startDiscovery()
                if selectedTab == .library {
                    Task { await libraryModel.refresh() }
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            deviceNavigation
                .tabItem { Label(L10n.text("tab.devices"), systemImage: "iphone.gen2") }
                .tag(ImporterTab.devices)
            libraryNavigation
                .tabItem { Label(L10n.text("tab.library"), systemImage: "photo.stack") }
                .tag(ImporterTab.library)
            settingsNavigation
                .tabItem { Label(L10n.text("tab.settings"), systemImage: "gearshape") }
                .tag(ImporterTab.settings)
        }
    }

    private var deviceNavigation: some View {
        NavigationStack {
            deviceList
                .navigationDestination(isPresented: cameraIsSelected) {
                    selectedCameraView
                        .navigationDestination(item: $previewAsset) { asset in
                            RemoteAssetPreviewView(model: model, asset: asset)
                        }
                }
        }
    }

    private var libraryNavigation: some View {
        NavigationStack {
            ImportedLibraryView(model: libraryModel)
                .navigationTitle(L10n.text("tab.library"))
        }
    }

    private var settingsNavigation: some View {
        NavigationStack {
            ImporterSettingsView(model: model)
        }
    }

    private var cameraIsSelected: Binding<Bool> {
        Binding(
            get: { model.selectedCamera != nil },
            set: { isSelected in
                if !isSelected {
                    model.disconnect()
                }
            }
        )
    }

    private var selectedCameraView: some View {
        Group {
            if model.isRestoringSession {
                restoringView
            } else if model.deviceInfo == nil {
                pairingView
            } else {
                assetList
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(model.selectionMode ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.deviceInfo != nil {
                    Button(model.selectionMode ? L10n.text("common.cancel") : L10n.text("batch.select")) {
                        model.setSelectionMode(!model.selectionMode)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if model.deviceInfo != nil {
                    Menu {
                        Button(L10n.text("common.disconnect")) {
                            model.disconnect()
                        }
                        if let camera = model.selectedCamera, model.isRemembered(camera) {
                            Button(L10n.text("device.forget"), role: .destructive) {
                                model.forgetSelectedDevice()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if model.selectionMode {
                    Button {
                        model.selectAllAvailable()
                    } label: {
                        Label(L10n.text("batch.select_all"), systemImage: "checkmark.circle")
                    }

                    Spacer()

                    Text(L10n.format("batch.selected_count", model.selectedCount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(RetroPalette.secondaryInk)

                    Spacer()

                    Button {
                        model.startSelectedImports()
                    } label: {
                        Label(L10n.text("batch.import"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedCount == 0 || model.isPreparingBatch)
                }
            }
        }
    }

    private var deviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("device.nearby"))
                    .font(.title3.bold())
                    .foregroundStyle(RetroPalette.ink)

                if model.cameras.isEmpty {
                    emptyDeviceCard
                } else {
                    ForEach(model.cameras) { camera in
                        deviceCard(camera)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(L10n.text("tab.devices"))
    }

    private func deviceCard(_ camera: DiscoveredCamera) -> some View {
        let remembered = model.isRemembered(camera)
        return Button {
            model.select(camera)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "iphone.gen2")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(RetroPalette.ink)
                    .frame(width: 50, height: 50)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(camera.name)
                            .font(.headline)
                            .foregroundStyle(RetroPalette.ink)
                            .lineLimit(1)
                        if remembered {
                            Label(L10n.text("device.remembered"), systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RetroPalette.sage)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(verbatim: camera.hostDescription)
                            .font(.caption)
                            .foregroundStyle(RetroPalette.secondaryInk)
                            .lineLimit(1)
                        Text(verbatim: String(camera.port))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(RetroPalette.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(uiColor: .systemBackground), in: Capsule())
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityHint(remembered ? L10n.text("device.remembered.hint") : L10n.text("device.connect.hint"))
    }

    private var emptyDeviceCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(L10n.text("device.none.title"))
                .font(.headline)
                .foregroundStyle(RetroPalette.ink)
            Text(L10n.text("device.none.description"))
                .font(.subheadline)
                .foregroundStyle(RetroPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 38)
        .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var restoringView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(L10n.text("pairing.reconnecting"))
                .font(.headline)
                .foregroundStyle(RetroPalette.ink)
            Text(L10n.text("pairing.reconnecting.note"))
                .font(.subheadline)
                .foregroundStyle(RetroPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pairingView: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 12) {
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 52))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, RetroPalette.mustard)
                    Text(L10n.text("pairing.title"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(RetroPalette.ink)
                        .multilineTextAlignment(.center)
                    Text(L10n.format(
                        "pairing.description",
                        model.selectedCamera?.name ?? L10n.text("device.camera")
                    ))
                    .font(.subheadline)
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    TextField(
                        "",
                        text: $model.pairingCode,
                        prompt: Text("••••••").foregroundStyle(RetroPalette.secondaryInk.opacity(0.35))
                    )
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(12)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($pairingFieldFocused)
                    .frame(height: 78)
                    .padding(.horizontal, 16)
                    .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                model.pairingErrorMessage == nil
                                    ? RetroPalette.ink.opacity(0.12)
                                    : RetroPalette.destructive,
                                lineWidth: model.pairingErrorMessage == nil ? 1 : 2
                            )
                    }
                    .onChange(of: model.pairingCode) { _, value in
                        model.updatePairingCode(value)
                    }
                    .disabled(model.isPairing)

                    if model.isPairing {
                        HStack(spacing: 9) {
                            ProgressView()
                            Text(L10n.text("pairing.in_progress"))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RetroPalette.secondaryInk)
                    } else if let message = model.pairingErrorMessage {
                        VStack(spacing: 10) {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(RetroPalette.destructive)
                                .multilineTextAlignment(.center)
                            if model.pairingCode.count == 6 {
                                Button(L10n.text("common.retry")) {
                                    model.retryPairing()
                                }
                                .font(.subheadline.bold())
                            }
                        }
                    }
                }

                Toggle(isOn: $model.rememberDevice) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("pairing.remember"))
                            .font(.headline)
                            .foregroundStyle(RetroPalette.ink)
                        Text(L10n.text("pairing.remember.note"))
                            .font(.caption)
                            .foregroundStyle(RetroPalette.secondaryInk)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)

                Text(L10n.text("pairing.note"))
                    .font(.footnote)
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .onAppear { pairingFieldFocused = true }
    }

    private var assetList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let device = model.deviceInfo {
                    deviceSummary(device)
                }

                if !model.visibleQueueItems.isEmpty {
                    queueSummary
                }

                if model.assets.isEmpty && !model.isLoadingAssets {
                    Text(L10n.text("asset.none"))
                        .font(.subheadline)
                        .foregroundStyle(RetroPalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                }

                LazyVGrid(columns: assetGridColumns, spacing: 4) {
                    ForEach(model.assets) { asset in
                        assetGridItem(asset)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 34)
        }
        .refreshable { await model.refreshAssets() }
        .overlay {
            if model.isLoadingAssets && model.assets.isEmpty {
                ProgressView(L10n.text("asset.loading"))
            }
        }
    }

    private var queueSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("queue.title"), systemImage: "list.number")
                    .font(.headline)
                Spacer()
                if model.isQueuePaused {
                    Button(L10n.text("queue.resume")) { model.resumeQueue() }
                } else {
                    Button(L10n.text("queue.pause")) { model.pauseQueue() }
                }
            }
            ForEach(model.visibleQueueItems) { item in
                HStack(spacing: 10) {
                    Image(systemName: queueIcon(item.status))
                        .foregroundStyle(queueStatusColor(item.status))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formattedDate(item.summary.createdAt))
                            .font(.subheadline)
                        Text(queueStatusTitle(item))
                            .font(.caption)
                            .foregroundStyle(RetroPalette.secondaryInk)
                        if item.status == .downloading {
                            ProgressView(value: item.progress)
                        }
                    }
                    Spacer()
                    if item.status == .failed || item.status == .cancelled {
                        Button(L10n.text("common.retry")) { model.retryQueueItem(item.id) }
                            .font(.caption.bold())
                    } else if item.status == .needsConfirmation {
                        Menu {
                            Button(L10n.text("queue.reimport"), role: .destructive) {
                                model.explicitlyReimportUnconfirmed(item.id)
                            }
                        } label: { Image(systemName: "exclamationmark.triangle.fill") }
                    } else if !item.status.isTerminal {
                        Button(role: .destructive) { model.cancelQueueItem(item.id) } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                }
            }
            if model.visibleQueueItems.contains(where: { $0.status == .imported || $0.status == .cancelled }) {
                Button(L10n.text("queue.clear_finished")) { model.clearFinishedQueueItems() }
                    .font(.caption.bold())
            }
        }
        .padding(16)
        .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func deviceSummary(_ device: CameraDeviceInfo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                deviceIdentity(device)
                Spacer(minLength: 12)
                deviceAssetCount(device.assetCount)
            }

            VStack(alignment: .leading, spacing: 14) {
                deviceIdentity(device)
                Divider()
                HStack {
                    Label(L10n.text("device.connected"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(RetroPalette.sage)
                    Spacer()
                    deviceAssetCount(device.assetCount)
                }
            }
        }
        .padding(16)
        .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private func deviceIdentity(_ device: CameraDeviceInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen2")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(device.deviceName)
                    .font(.headline)
                    .foregroundStyle(RetroPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    deviceMetadataChip(device.modelIdentifier, systemImage: "cpu")
                    deviceMetadataChip("iOS \(device.systemVersion)", systemImage: "gearshape")
                }
            }
        }
    }

    private func deviceMetadataChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(RetroPalette.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .systemBackground).opacity(0.72), in: Capsule())
    }

    private func deviceAssetCount(_ count: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(count))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(Color.accentColor)
            Text(L10n.text("asset.count"))
                .font(.caption2)
                .foregroundStyle(RetroPalette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func assetGridItem(_ asset: CameraAssetSummary) -> some View {
        let state = model.assetStates[asset.assetId] ?? .available
        let canSelect = model.canSelect(asset.assetId)
        let isSelected = model.selectedAssetIds.contains(asset.assetId)
        let isEnabled = !model.selectionMode || canSelect

        return Button {
            if model.selectionMode {
                model.toggleSelection(asset.assetId)
            } else {
                previewAsset = asset
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                assetThumbnail(asset)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    HStack(alignment: .top) {
                        if asset.hasMotion == true {
                            Image(systemName: "livephoto")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        Spacer(minLength: 0)
                        assetStatusBadge(
                            state: state,
                            isSelected: isSelected,
                            canSelect: canSelect
                        )
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formattedGridDate(asset.createdAt))
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Text(state.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        if case .downloading(let progress) = state {
                            ProgressView(value: progress)
                                .tint(.white)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.16),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
            .opacity(isEnabled ? 1 : 0.62)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(assetAccessibilityLabel(asset, state: state))
        .accessibilityAddTraits(model.selectionMode && isSelected ? .isSelected : [])
        .accessibilityHint(
            model.selectionMode
                ? L10n.text(isSelected ? "batch.deselect_item" : "batch.select_item")
                : L10n.text("preview.open")
        )
        .task(id: asset.assetId) {
            await model.loadThumbnail(for: asset)
        }
    }

    private func assetThumbnail(_ asset: CameraAssetSummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .tertiarySystemFill))
            if let image = model.thumbnailImages[asset.assetId] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: asset.hasMotion == true ? "livephoto" : "photo")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func assetStatusBadge(
        state: ImporterAssetState,
        isSelected: Bool,
        canSelect: Bool
    ) -> some View {
        if model.selectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    isSelected ? Color.white : Color.white.opacity(canSelect ? 0.92 : 0.48),
                    isSelected ? Color.accentColor : Color.black.opacity(0.42)
                )
        } else if let icon = assetStateIcon(state) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(6)
                .background(assetStateColor(state), in: Circle())
        }
    }

    private func assetStateIcon(_ state: ImporterAssetState) -> String? {
        switch state {
        case .available: nil
        case .imported: "checkmark"
        case .failed: "exclamationmark"
        case .needsConfirmation: "questionmark"
        case .paused: "pause.fill"
        case .cancelled: "xmark"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private func assetStateColor(_ state: ImporterAssetState) -> Color {
        switch state {
        case .imported: RetroPalette.sage
        case .failed, .cancelled: RetroPalette.destructive
        case .needsConfirmation, .paused: RetroPalette.mustard
        default: Color.accentColor
        }
    }

    private func queueStatusColor(_ status: ImportQueueItemStatus) -> Color {
        switch status {
        case .imported: RetroPalette.sage
        case .failed, .cancelled: RetroPalette.destructive
        case .needsConfirmation, .paused: RetroPalette.mustard
        default: Color.accentColor
        }
    }

    private func assetAccessibilityLabel(
        _ asset: CameraAssetSummary,
        state: ImporterAssetState
    ) -> String {
        let kind = asset.hasMotion == true
            ? L10n.text("asset.kind.live_photo")
            : L10n.text("asset.kind.photo")
        return "\(kind), \(formattedDate(asset.createdAt)), \(state.title)"
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = RetroLiveISO8601.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedGridDate(_ value: String) -> String {
        guard let date = RetroLiveISO8601.date(from: value) else { return value }
        return date.formatted(date: .numeric, time: .omitted)
    }

    private func queueStatusTitle(_ item: ImportQueueItem) -> String {
        switch item.status {
        case .queued: L10n.text("asset.state.queued")
        case .downloading: L10n.format("asset.action.downloading", Int(item.progress * 100))
        case .verifying: L10n.text("asset.state.verifying")
        case .cached: L10n.text("asset.state.cached")
        case .assembling: L10n.text("asset.state.assembling")
        case .authorizing: L10n.text("asset.state.authorizing")
        case .importing: L10n.text("asset.state.importing")
        case .imported: L10n.text("asset.state.imported")
        case .needsConfirmation: L10n.text("asset.state.needs_confirmation")
        case .failed: item.errorMessage ?? L10n.text("queue.unknown_error")
        case .paused: L10n.text("asset.state.paused")
        case .cancelled: L10n.text("asset.state.cancelled")
        }
    }

    private func queueIcon(_ status: ImportQueueItemStatus) -> String {
        switch status {
        case .imported: "checkmark.circle.fill"
        case .needsConfirmation, .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .queued: "clock.fill"
        default: "arrow.triangle.2.circlepath"
        }
    }

}
