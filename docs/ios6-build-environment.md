# iOS 6 Build Environment

The legacy target is Objective-C/UIKit with `IPHONEOS_DEPLOYMENT_TARGET = 6.0` and uses only APIs available on iOS 6.

An authentic device build requires a preserved toolchain capable of installing and signing for the target device. Keep that environment isolated from the modern importer toolchain and record:

- Xcode build number and macOS version
- iOS 6 SDK path and code-signing identity
- device model and exact iOS version
- third-party source snapshots, checksums, and license files

The legacy source uses ARC, Foundation collection accessors rather than modern subscripting, does not use Swift, and parses JSON through `NSJSONSerialization`.

Current Xcode can still inspect the project, but it may no longer build an iOS 6 deployment target. A successful modern-host syntax check is not a substitute for an archived-toolchain device build.
