import SwiftUI

struct ImporterOnboardingView: View {
    static let currentVersion = 1

    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header

                VStack(spacing: 24) {
                    feature(
                        icon: "iphone.gen2.radiowaves.left.and.right",
                        title: L10n.text("onboarding.connect.title"),
                        description: L10n.text("onboarding.connect.description")
                    )
                    feature(
                        icon: "livephoto",
                        title: L10n.text("onboarding.import.title"),
                        description: L10n.text("onboarding.import.description")
                    )
                    feature(
                        icon: "lock.shield",
                        title: L10n.text("onboarding.private.title"),
                        description: L10n.text("onboarding.private.description")
                    )
                }

            }
            .padding(.horizontal, 24)
            .padding(.top, 46)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onContinue) {
                Text(L10n.text("onboarding.continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(L10n.text("onboarding.continue.hint"))
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .accessibilityElement(children: .combine)
    }

    private var appIcon: UIImage? {
        let iconsKey = UIDevice.current.userInterfaceIdiom == .pad
            ? "CFBundleIcons~ipad"
            : "CFBundleIcons"
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: iconsKey) as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String]
        else {
            return nil
        }
        return iconFiles.reversed().lazy.compactMap { UIImage(named: $0) }.first
    }

    private func feature(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(RetroPalette.surface, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(RetroPalette.ink)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
