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
                        Button("断开") { model.disconnect() }
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
                "操作失败",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
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
                    "未发现设备",
                    systemImage: "iphone.radiowaves.left.and.right",
                    description: Text("请在旧设备的图库中打开 Transfer，并确认两台设备连接到同一 Wi-Fi。")
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
            Section("连接 \(model.selectedCamera?.name ?? "相机")") {
                TextField("六位配对码", text: $model.pairingCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: model.pairingCode) { _, value in
                        model.pairingCode = String(value.filter(\.isNumber).prefix(6))
                    }
                Button(model.isPairing ? "正在配对…" : "配对") {
                    model.pair()
                }
                .disabled(model.pairingCode.count != 6 || model.isPairing)
            }
            Section {
                Text("配对码显示在旧设备的 Transfer 页面，有效会话不会写入钥匙串。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assetList: some View {
        List {
            if let device = model.deviceInfo {
                Section {
                    LabeledContent("设备", value: device.modelIdentifier)
                    LabeledContent("系统", value: device.systemVersion)
                    LabeledContent("素材", value: String(device.assetCount))
                }
            }
            Section("素材") {
                if model.assets.isEmpty && !model.isLoadingAssets {
                    Text("相机中没有可导入的素材")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.assets) { asset in
                    assetRow(asset)
                }
            }
        }
        .overlay {
            if model.isLoadingAssets {
                ProgressView("正在读取素材…")
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
                Text("上次写入照片的结果无法确认。请先在“照片”中检查，避免重复导入。")
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
