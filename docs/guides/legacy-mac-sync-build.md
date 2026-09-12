---
title: Legacy Mac Sync and Build
status: provisional
type: guide
---

# Legacy Mac Sync and Build

This workflow keeps development and Git on a modern Mac while using an isolated
Mac with OS X Mavericks and Xcode 6.2 for authentic legacy builds:

```text
Modern Mac: edit and run legacy-sync.sh
    -> SSH transport and rsync
Legacy Mac: run legacy-build.sh locally
    -> Xcode 6.2 Product > Run
iPhone: install over USB
```

The modern Mac does not remotely execute `xcodebuild`, install an application,
or launch the iPhone. The only network operation is the one-way file sync. Read
[`ios-6-build-environment.md`](ios-6-build-environment.md) for the distinction
between current-SDK checks, archived-toolchain builds, and physical-device
acceptance.

## Security boundaries

- Keep the Mavericks Mac off the public internet.
- Do not store GitHub credentials or a `.git` directory on it.
- Enable Remote Login only for a dedicated build user on a trusted LAN.
- Use a dedicated SSH key rather than a GitHub key.
- Do not expose its SSH port through the router.
- Keep certificates, private keys, provisioning profiles, device identifiers,
  and local xcconfig files outside Git.
- Treat synchronization as one-way; do not edit source in the build mirror.

The committed scripts contain no hostname, username, signing identity, profile
UUID, or device identifier. Private `.env` files are ignored by Git.

## Files

Public repository files:

```text
scripts/legacy-sync.sh               # run on the modern Mac
scripts/legacy-sync.env.example
scripts/legacy-build.sh              # run locally on the legacy Mac
scripts/legacy-build.env.example
scripts/legacy-rsync-excludes.txt
```

Private files:

```text
.retrolive-legacy-sync.env           # modern Mac
.retrolive-legacy-build.env          # legacy Mac
~/RetroLivePrivate/LegacySigning.xcconfig
```

The scripts use POSIX shell syntax and do not require Homebrew, Git, Python 3,
or `jq` on the legacy Mac.

## 1. Prepare SSH

On the legacy Mac, create a dedicated standard user such as
`retrolive-builder`. Enable **System Preferences > Sharing > Remote Login** only
for that user. Give the Mac a stable DHCP address or `.local` hostname.

Create a dedicated key on the modern Mac:

```sh
ssh-keygen -t ecdsa -b 256 -f ~/.ssh/retrolive-air
```

Install only its public key for the build user, then configure the modern Mac:

```sshconfig
Host retrolive-air
    HostName 192.168.1.50
    User retrolive-builder
    IdentityFile ~/.ssh/retrolive-air
    IdentitiesOnly yes
```

Verify the connection:

```sh
ssh retrolive-air /usr/bin/sw_vers
```

If Mavericks requires a legacy SSH algorithm, enable it only in this host entry
after checking the exact error. Do not weaken the global SSH configuration.

## 2. Create the build mirror

On the legacy Mac, create the destination once:

```sh
mkdir -p /Users/retrolive-builder/BuildMirror/RetroLive
```

This must be a dedicated directory. The sync script uses `rsync --delete` inside
its `legacy-camera/` child so that files removed on the modern Mac do not remain
in a later build.

## 3. Configure and run synchronization

On the modern Mac, from the repository root:

```sh
cp scripts/legacy-sync.env.example .retrolive-legacy-sync.env
chmod 600 .retrolive-legacy-sync.env
```

Edit the private file:

```sh
RETROLIVE_SYNC_REMOTE=retrolive-air
RETROLIVE_SYNC_ROOT=/Users/retrolive-builder/BuildMirror/RetroLive
```

The root must be absolute, at least three path components deep, and contain no
spaces or shell punctuation. Then synchronize:

```sh
./scripts/legacy-sync.sh
```

The script copies:

- `legacy-camera/`, excluding build output, user state, and `.DS_Store`;
- `scripts/legacy-build.sh`;
- `scripts/legacy-build.env.example`.

It does not copy `.git`, modern-importer, credentials, or private configuration.
Run the same command after each source change; `rsync` transfers only changed
data.

## 4. Configure the local legacy build

On the legacy Mac:

```sh
cd /Users/retrolive-builder/BuildMirror/RetroLive
cp scripts/legacy-build.env.example .retrolive-legacy-build.env
chmod 600 .retrolive-legacy-build.env
```

For an unsigned compile check:

```sh
RETROLIVE_DEVELOPER_DIR='/Applications/Xcode 6.2.app/Contents/Developer'
RETROLIVE_DERIVED_DATA=/Users/retrolive-builder/BuildData/RetroLive
RETROLIVE_CONFIGURATION=Debug
RETROLIVE_CODE_SIGNING_ALLOWED=NO
RETROLIVE_SIGNING_XCCONFIG=
```

Inspect the preserved environment:

```sh
./scripts/legacy-build.sh doctor
```

This reports macOS, Xcode, installed SDKs, Derived Data, signing mode, and code
signing identities. It does not prove device installation or runtime behavior.

## 5. Build locally on the legacy Mac

Build the iOS 6 camera:

```sh
./scripts/legacy-build.sh build RetroLiveCamera
```

Build the Classic camera:

```sh
./scripts/legacy-build.sh build RetroLiveClassic
```

The script invokes the selected archived Xcode directly and keeps Derived Data
outside the synchronized source tree.

## 6. Configure signing and run on iPhone

The Debug project settings intentionally disable signing for compile-only
checks. A physical-device build needs a valid development certificate and
private key, a provisioning profile containing the iPhone, Xcode device
support, the correct device OS, and an accurate system clock.

Keep manual settings in a private file on the legacy Mac, for example:

```xcconfig
CODE_SIGN_IDENTITY = iPhone Developer
PROVISIONING_PROFILE = YOUR_PROFILE_UUID
PRODUCT_BUNDLE_IDENTIFIER = your.unique.bundle.identifier
```

Then set:

```sh
RETROLIVE_CODE_SIGNING_ALLOWED=YES
RETROLIVE_SIGNING_XCCONFIG=/Users/retrolive-builder/RetroLivePrivate/LegacySigning.xcconfig
```

Run `doctor` and `build` again. Finally, open the synchronized Xcode project on
the legacy Mac, select the USB-connected iPhone, and use **Product > Run**. The
scripts intentionally do not automate installation or launch yet.

## Troubleshooting

### rsync reports that the destination does not exist

Create `RETROLIVE_SYNC_ROOT` manually on the legacy Mac before the first sync.
The script does not execute `mkdir` remotely.

### A removed source file remains on the legacy Mac

Confirm it is under the synchronized `legacy-camera/` directory and is not
listed in `scripts/legacy-rsync-excludes.txt`. The build and configuration files
outside that directory are intentionally preserved.

### Xcode cannot be found

Set `RETROLIVE_DEVELOPER_DIR` to the archived application's exact
`Contents/Developer` path. Spaces are supported when the value is quoted.

### Compilation succeeds but installation fails

Compilation alone does not validate signing, provisioning, device support, or
the device OS. Use Xcode's local Product > Run result as the installation
evidence.
