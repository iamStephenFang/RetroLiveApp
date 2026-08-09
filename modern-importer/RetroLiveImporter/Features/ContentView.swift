import SwiftUI

enum RetroPalette {
    static let ink = Color(red: 0.14, green: 0.13, blue: 0.12)
    static let secondaryInk = Color(red: 0.40, green: 0.38, blue: 0.35)
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let persimmon = Color(red: 0.90, green: 0.29, blue: 0.17)
    static let mustard = Color(red: 0.95, green: 0.65, blue: 0.12)
    static let sage = Color(red: 0.45, green: 0.53, blue: 0.41)
}

struct ContentView: View {
    @StateObject private var model = ImporterViewModel()
    @FocusState private var pairingFieldFocused: Bool

    var body: some View {
        NavigationStack {
            deviceList
                .navigationDestination(isPresented: cameraIsSelected) {
                    selectedCameraView
                }
        }
        .tint(RetroPalette.persimmon)
        .preferredColorScheme(.light)
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
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(model.deviceInfo?.deviceName ?? model.selectedCamera?.name ?? "RetroLive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
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
        }
    }

    private var deviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                brandHeader

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
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 62, height: 62)
                    .background(RetroPalette.mustard, in: RoundedRectangle(cornerRadius: 20))
                Image(systemName: "livephoto")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(RetroPalette.persimmon, in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: 7, y: 7)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("app.title"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(RetroPalette.ink)
                Text(L10n.text("app.subtitle"))
                    .font(.body)
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
        }
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
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))

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
                            .background(Color.white, in: Capsule())
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RetroPalette.persimmon)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityHint(remembered ? L10n.text("device.remembered.hint") : L10n.text("device.connect.hint"))
    }

    private var emptyDeviceCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(RetroPalette.persimmon)
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
        .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private var restoringView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(RetroPalette.persimmon)
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
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                model.pairingErrorMessage == nil
                                    ? RetroPalette.ink.opacity(0.12)
                                    : RetroPalette.persimmon,
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
                                .tint(RetroPalette.persimmon)
                            Text(L10n.text("pairing.in_progress"))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RetroPalette.secondaryInk)
                    } else if let message = model.pairingErrorMessage {
                        VStack(spacing: 10) {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(RetroPalette.persimmon)
                                .multilineTextAlignment(.center)
                            if model.pairingCode.count == 6 {
                                Button(L10n.text("common.retry")) {
                                    model.retryPairing()
                                }
                                .font(.subheadline.bold())
                            }
                        }
                    } else {
                        Text(L10n.text("pairing.auto_note"))
                            .font(.caption)
                            .foregroundStyle(RetroPalette.secondaryInk)
                    }
                }
                .padding(18)
                .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 26))

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
                .tint(RetroPalette.sage)
                .padding(18)
                .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 22))

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

                if model.assets.isEmpty && !model.isLoadingAssets {
                    Text(L10n.text("asset.none"))
                        .font(.subheadline)
                        .foregroundStyle(RetroPalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 24))
                }

                ForEach(model.assets) { asset in
                    assetRow(asset)
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
                    .tint(RetroPalette.persimmon)
            }
        }
    }

    private func deviceSummary(_ device: CameraDeviceInfo) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName)
                    .font(.headline)
                    .foregroundStyle(RetroPalette.ink)
                Text("\(device.modelIdentifier) · iOS \(device.systemVersion)")
                    .font(.caption)
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(String(device.assetCount))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(RetroPalette.persimmon)
                Text(L10n.text("asset.count"))
                    .font(.caption2)
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
        }
        .padding(18)
        .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 22))
    }

    private func assetRow(_ asset: CameraAssetSummary) -> some View {
        let state = model.assetStates[asset.assetId] ?? .available
        return HStack(alignment: .top, spacing: 14) {
            assetThumbnail(asset)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            asset.hasMotion == true
                                ? L10n.text("asset.kind.live_photo")
                                : L10n.text("asset.kind.photo"),
                            systemImage: asset.hasMotion == true ? "livephoto" : "photo"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(RetroPalette.ink)
                        Text(formattedDate(asset.createdAt))
                            .font(.caption)
                            .foregroundStyle(RetroPalette.secondaryInk)
                    }
                    Spacer(minLength: 6)
                    if state == .imported {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(RetroPalette.sage)
                    }
                }

                if case .downloading(let progress) = state {
                    ProgressView(value: progress)
                        .tint(RetroPalette.persimmon)
                }
                if case .failed(let message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(RetroPalette.persimmon)
                        .lineLimit(2)
                }
                if state == .needsConfirmation {
                    Text(L10n.text("asset.needs_confirmation.note"))
                        .font(.caption)
                        .foregroundStyle(RetroPalette.mustard)
                        .lineLimit(3)
                }

                Button(state.title) {
                    model.importAsset(asset)
                }
                .font(.subheadline.bold())
                .foregroundStyle(state == .imported ? RetroPalette.sage : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    state == .imported ? RetroPalette.sage.opacity(0.13) : RetroPalette.persimmon,
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .disabled(state.isBusy || state == .imported || state == .needsConfirmation)
            }
        }
        .padding(12)
        .background(RetroPalette.paper, in: RoundedRectangle(cornerRadius: 22))
        .task(id: asset.assetId) {
            await model.loadThumbnail(for: asset)
        }
    }

    private func assetThumbnail(_ asset: CameraAssetSummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(RetroPalette.mustard.opacity(0.16))
            if let image = model.thumbnailImages[asset.assetId] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: asset.hasMotion == true ? "livephoto" : "photo")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(RetroPalette.mustard)
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = RetroLiveISO8601.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
