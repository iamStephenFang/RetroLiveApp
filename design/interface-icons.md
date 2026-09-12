# Interface icons

The legacy camera targets bundle PNG fallbacks because SF Symbols is unavailable before iOS 13. Run `swift design/generate-interface-icons.swift` from the repository root to regenerate the 1×, 2×, and 3× files in `legacy-camera/RetroLiveCamera/Resources/InterfaceIcons`.

These fallbacks are generated from Apple SF Symbols for use only in the Apple-platform apps in this repository. SF Symbols are licensed, copyrighted resources rather than copyright-free artwork. They are not covered by any open-source license that may otherwise apply to this repository; see `THIRD_PARTY_NOTICES.md`. Do not redistribute them as a standalone asset pack, use them on non-Apple platforms, or use them as an app icon, logo, or trademark.

- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Configuring and displaying symbol images in your UI](https://developer.apple.com/documentation/uikit/configuring-and-displaying-symbol-images-in-your-ui)
