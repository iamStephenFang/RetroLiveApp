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
Legacy Mac: choose one local workflow
    -> Xcode Product > Run -> USB iPhone
    -> legacy-package.sh -> unsigned IPA and metadata
Modern Mac: legacy-package-fetch.sh -> rsync artifacts back
GitHub release: upload manually
```

The run workflow and package workflow are separate. The modern Mac may invoke
the package script remotely to produce a release artifact, but it never
remotely installs an application or launches the iPhone. Read
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
scripts/legacy-package.sh            # run locally on the legacy Mac
scripts/legacy-package-fetch.sh      # run on the modern Mac
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

On the legacy Mac, use a dedicated standard user when possible. Enable
**System Preferences > Sharing > Remote Login** only for that user. Give the
Mac a stable DHCP address or `.local` hostname. The examples below use
`your-user`; replace it with the actual account name on the legacy Mac.

Create a dedicated key on the modern Mac:

```sh
ssh-keygen -t ecdsa -b 256 -f ~/.ssh/retrolive-air
```

Install only its public key for the build user, then configure the modern Mac:

```sshconfig
Host retrolive-air
    HostName 192.168.1.50
    User your-user
    IdentityFile ~/.ssh/retrolive-air
    IdentitiesOnly yes
    ControlMaster auto
    ControlPersist 60
    ControlPath ~/.ssh/retrolive-%C
```

The short-lived control connection is scoped to this host and lets the two
rsync operations share one SSH authentication.

Verify the connection:

```sh
ssh retrolive-air /usr/bin/sw_vers
```

Mavericks ships an old SSH server. If a current SSH client reports that the
server offers only `ssh-rsa`/`ssh-dss`, or closes the connection during key
exchange, add the following compatibility options to this host entry:

```sshconfig
Host retrolive-air
    HostKeyAlgorithms ssh-rsa
    KexAlgorithms diffie-hellman-group14-sha1
    Ciphers aes128-ctr
    MACs hmac-sha1
```

This exact combination was required for a current OpenSSH client to complete a
handshake with the OpenSSH 6.2 server on the Mavericks build Mac. Keep these
weaker legacy algorithms inside the dedicated `Host retrolive-air` block; never
place them under `Host *`. Confirm the negotiated settings and connection before
running rsync:

```sh
ssh -G retrolive-air | grep -E '^(hostname|user|port|hostkeyalgorithms|kexalgorithms|ciphers|macs) '
ssh -v retrolive-air /usr/bin/sw_vers
```

## 2. Create the build mirror

On the legacy Mac, create the destination once:

```sh
mkdir -p /Users/your-user/Developer/RetroLive
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
RETROLIVE_SYNC_ROOT=/Users/your-user/Developer/RetroLive
```

The root must be absolute, at least three path components deep, contain no
spaces or shell punctuation, and contain no `.` or `..` path components. Preview
the changes, then synchronize:

```sh
./scripts/legacy-sync.sh --dry-run
./scripts/legacy-sync.sh
```

The dry run lists additions, updates, and deletions without changing the legacy
Mac. A normal run prints the same itemized change list while applying it.

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
cd /Users/your-user/Developer/RetroLive
cp scripts/legacy-build.env.example .retrolive-legacy-build.env
chmod 600 .retrolive-legacy-build.env
```

For an unsigned compile check:

```sh
RETROLIVE_DEVELOPER_DIR='/Applications/Xcode 6.2.app/Contents/Developer'
RETROLIVE_DERIVED_DATA=/Users/your-user/Library/Developer/Xcode/DerivedData
RETROLIVE_PACKAGE_ROOT=/Users/your-user/Developer/RetroLive/Artifacts
RETROLIVE_CONFIGURATION=Debug
RETROLIVE_PACKAGE_CONFIGURATION=Release
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
under the user's standard Xcode data directory. Each scheme uses a separate
child directory so their Xcode build databases cannot collide.

Build both schemes sequentially:

```sh
./scripts/legacy-build.sh build all
```

## 6. Create and fetch an unsigned IPA

For a GitHub release, the archived Mac can create a standard IPA container
without a certificate, private key, or provisioning profile. The resulting
application is not installable as-is on a physical iPhone; whoever installs it
must sign it for the target device or use an appropriate sideloading workflow.

Set the same artifact path in both private configuration files:

```sh
# .retrolive-legacy-build.env on the legacy Mac
RETROLIVE_PACKAGE_ROOT=/Users/your-user/Developer/RetroLive/Artifacts/Legacy

# .retrolive-legacy-sync.env on the modern Mac
RETROLIVE_REMOTE_PACKAGE_ROOT=/Users/your-user/Developer/RetroLive/Artifacts
RETROLIVE_LOCAL_PACKAGE_ROOT=Artifacts
```

After synchronizing the source, run this on the modern Mac:

```sh
./scripts/legacy-package-fetch.sh RetroLiveCamera
```

The command invokes the package script over SSH and fetches the IPA, SHA-256
file, and build metadata into `Artifacts/Legacy/`. Build both legacy targets
with `./scripts/legacy-package-fetch.sh all`. The package script always passes
`CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO`; it assembles the IPA
as `Payload/<App>.app` and validates the ZIP before writing the checksum.

## 7. Run on a physical iPhone (separate from packaging)

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
RETROLIVE_SIGNING_XCCONFIG=/Users/your-user/Developer/RetroLivePrivate/LegacySigning.xcconfig
```

Run `doctor` and `build` again if you want a command-line build check. Then,
separately, open the synchronized Xcode project on the legacy Mac, select the
USB-connected iPhone, and use **Product > Run**. This Xcode action builds,
signs, installs, and launches the app for device testing; it does not consume
or produce the unsigned GitHub-release IPA. The scripts intentionally do not
automate device installation or launch.

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
