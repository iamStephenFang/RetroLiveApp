import SwiftUI

struct ContentView: View {
    @StateObject private var model = ImporterViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.selectedCamera == nil {
                    deviceList
                } else if model.deviceInfo == nil {
                    pairingView
                } else {
                    assetList
                }
            }
            .navigationTitle(model.deviceInfo?.deviceName ?? "RetroLive")
            .toolbar {
                if model.selectedCamera != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.text("common.disconnect")) { model.disconnect() }
                    }
                }
                if model.deviceInfo != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.refreshAssets() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isLoadingAssets)
                    }
                }
            }
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
        .task { model.startDiscovery() }
    }

    private var deviceList: some View {
        Group {
            if model.cameras.isEmpty {
                ContentUnavailableView(
                    L10n.text("device.none.title"),
                    systemImage: "iphone.radiowaves.left.and.right",
                    description: Text(L10n.text("device.none.description"))
                )
            } else {
                List(model.cameras) { camera in
                    Button {
                        model.select(camera)
                    } label: {
                        HStack {
                            Image(systemName: "camera")
                            VStack(alignment: .leading) {
                                Text(camera.name)
                                Text("\(camera.host):\(camera.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pairingView: some View {
        Form {
            Section(L10n.format("pairing.section", model.selectedCamera?.name ?? L10n.text("device.camera"))) {
                TextField(L10n.text("pairing.code.placeholder"), text: $model.pairingCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: model.pairingCode) { _, value in
                        model.pairingCode = String(value.filter(\.isNumber).prefix(6))
                    }
                Button(model.isPairing ? L10n.text("pairing.in_progress") : L10n.text("pairing.action")) {
                    model.pair()
                }
                .disabled(model.pairingCode.count != 6 || model.isPairing)
            }
            Section {
                Text(L10n.text("pairing.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assetList: some View {
        List {
            if let device = model.deviceInfo {
                Section {
                    LabeledContent(L10n.text("device.model"), value: device.modelIdentifier)
                    LabeledContent(L10n.text("device.system"), value: device.systemVersion)
                    LabeledContent(L10n.text("asset.count"), value: String(device.assetCount))
                }
            }
            Section(L10n.text("asset.section")) {
                if model.assets.isEmpty && !model.isLoadingAssets {
                    Text(L10n.text("asset.none"))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.assets) { asset in
                    assetRow(asset)
                }
            }
        }
        .overlay {
            if model.isLoadingAssets {
                ProgressView(L10n.text("asset.loading"))
            }
        }
    }

    private func assetRow(_ asset: CameraAssetSummary) -> some View {
        let state = model.assetStates[asset.assetId] ?? .available
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "livephoto")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(asset.assetId)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Text(asset.createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if case .downloading(let progress) = state {
                ProgressView(value: progress)
            }
            if case .failed(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if state == .needsConfirmation {
                Text(L10n.text("asset.needs_confirmation.note"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(state.title) {
                model.importAsset(asset)
            }
            .disabled(state.isBusy || state == .imported || state == .needsConfirmation)
        }
        .padding(.vertical, 4)
    }
}
