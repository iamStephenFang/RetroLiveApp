import SwiftUI

struct ImporterSettingsView: View {
    @ObservedObject var model: ImporterViewModel

    @State private var confirmsCacheCleanup = false
    @State private var confirmsForgettingDevices = false

    var body: some View {
        List {
            Section {
                if let storage = model.storageOverview {
                    storageRow("storage.cache", bytes: storage.managedBytes)
                } else {
                    HStack {
                        Text(L10n.text("storage.usage"))
                        Spacer()
                        ProgressView()
                    }
                }
            } header: {
                Text(L10n.text("storage.title"))
            } footer: {
                Text(L10n.text("storage.cache.note"))
            }

            Section {
                Button(L10n.text("storage.cleanup.action"), role: .destructive) {
                    confirmsCacheCleanup = true
                }
                Button(L10n.text("devices.forget_all.action"), role: .destructive) {
                    confirmsForgettingDevices = true
                }
            } footer: {
                Text(L10n.text("devices.remembered.note"))
            }

            Section(L10n.text("settings.system")) {
                Button(L10n.text("settings.open_system")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }

            Section(L10n.text("settings.about")) {
                linkRow(
                    "settings.whats_new",
                    destination: URL(string: "https://github.com/iamStephenFang/RetroLive/releases")!
                )
                linkRow(
                    "settings.privacy",
                    destination: URL(string: "https://retrolive.pages.dev/privacy")!
                )
                linkRow(
                    "settings.website",
                    destination: URL(string: "https://retrolive.pages.dev")!
                )
                HStack {
                    Text(L10n.text("settings.version"))
                    Spacer()
                    Text(versionDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L10n.text("tab.settings"))
        .task { await model.refreshStorageOverview() }
        .refreshable { await model.refreshStorageOverview() }
        .alert(
            L10n.text("storage.cleanup.confirm.title"),
            isPresented: $confirmsCacheCleanup
        ) {
            Button(L10n.text("storage.cleanup.confirm.action"), role: .destructive) {
                model.cleanCachedData()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("storage.cleanup.confirm.message"))
        }
        .alert(
            L10n.text("devices.forget_all.confirm.title"),
            isPresented: $confirmsForgettingDevices
        ) {
            Button(L10n.text("devices.forget_all.confirm.action"), role: .destructive) {
                model.forgetAllRememberedDevices()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("devices.forget_all.confirm.message"))
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func storageRow(_ key: String, bytes: Int64) -> some View {
        HStack {
            Text(L10n.text(key))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .foregroundStyle(.secondary)
        }
    }

    private func linkRow(_ key: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(L10n.text(key))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
        }
    }
}
