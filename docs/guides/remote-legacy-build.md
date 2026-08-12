---
title: Remote Legacy Build Mac
status: provisional
type: guide
---

# Remote Legacy Build Mac

This guide turns an isolated Intel Mac with OS X Mavericks and Xcode 6.2 into a
build node for RetroLive. Source editing, Git, and GitHub access remain on the
modern development Mac. The legacy Mac receives a one-way source mirror and
builds the camera target, including code signing when configured. Installation
and launch remain an explicit action in Xcode 6.2.

An archived-toolchain build is distinct from a current-SDK compile check. A
successful build is also not proof of installation, launch, camera behavior, or
device compatibility. Read [`ios-6-build-environment.md`](ios-6-build-environment.md)
for the evidence and preservation requirements.

## Security and repository boundaries

Treat the Mavericks Mac as an offline appliance:

- keep it off the public internet and do not give it GitHub credentials;
- enable Remote Login only for a dedicated build user on a trusted LAN;
- use a dedicated SSH key and do not reuse a GitHub key;
- do not forward its SSH port through a router;
- keep `.git`, source edits, commits, and pushes on the modern Mac;
- keep signing certificates, private keys, profiles, xcconfig files, device
  identifiers, hostnames, and user paths out of the repository.

The script synchronizes only `legacy-camera/`. It verifies a marker before
using `rsync --delete`, and build output lives outside the mirrored source.
Synchronization is intentionally one-way; do not edit the mirrored source on
the build Mac.

## Public and private files

The repository contains the reusable parts:

```text
tools/legacy-remote.sh
tools/legacy-remote-worker.sh
tools/legacy-remote.env.example
tools/legacy-rsync-excludes.txt
```

The following remain private and are ignored or stored outside the checkout:

```text
.retrolive-legacy.env
~/RetroLivePrivate/LegacySigning.xcconfig   # on the build Mac
login keychain certificate and private key # on the build Mac
provisioning profiles                      # on the build Mac
```

Both scripts use only POSIX shell features available on Mavericks. The legacy
Mac does not need Homebrew, Python 3, `jq`, or Git.

## 1. Prepare the legacy Mac

1. Preserve a backup of the Mavericks installation, Xcode application, SDKs,
   certificates, and profiles before changing the machine.
2. Create a standard user dedicated to legacy builds, for example
   `retrolive-builder`.
3. In **System Preferences > Sharing**, enable **Remote Login** only for that
   user. Do not expose TCP port 22 to the internet.
4. Give the Mac a stable DHCP address or a `.local` hostname.
5. Connect the iPhone by USB, trust the Mac, and confirm that Xcode 6.2 sees the
   exact device and OS version.
6. Set the correct date and time. Code signing can fail when an offline Mac's
   clock drifts.

Create a dedicated SSH key on the modern Mac. Start with an ECDSA P-256 key for
compatibility with the OpenSSH generation shipped around Mavericks:

```sh
ssh-keygen -t ecdsa -b 256 -f ~/.ssh/retrolive-air
```

Add only the public key to the build user's `~/.ssh/authorized_keys`. A
host-specific entry keeps compatibility settings and the private key out of the
project:

```sshconfig
Host retrolive-air
    HostName 192.168.1.50
    User retrolive-builder
    IdentityFile ~/.ssh/retrolive-air
    IdentitiesOnly yes
```

Verify the connection before continuing:

```sh
ssh retrolive-air /usr/bin/sw_vers
```

If the archived SSH server requires a legacy algorithm, enable it only inside
this host entry after reviewing the exact negotiation error. Do not weaken the
global SSH configuration.

## 2. Create the local configuration

From the repository root on the modern Mac:

```sh
cp tools/legacy-remote.env.example .retrolive-legacy.env
chmod 600 .retrolive-legacy.env
```

Edit the private copy. A minimal unsigned compile configuration is:

```sh
RETROLIVE_REMOTE=retrolive-air
RETROLIVE_REMOTE_ROOT=/Users/retrolive-builder/BuildMirror/RetroLive
RETROLIVE_REMOTE_DERIVED_DATA=/Users/retrolive-builder/BuildData/RetroLive
RETROLIVE_REMOTE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
RETROLIVE_CONFIGURATION=Debug
RETROLIVE_CODE_SIGNING_ALLOWED=NO
RETROLIVE_SIGNING_XCCONFIG=
```

The mirror path must be absolute and contain only letters, numbers, underscore,
dot, slash, and hyphen because `rsync` passes it through a remote shell. The
mirror must be a dedicated directory because synchronization deletes remote
files that no longer exist under the local `legacy-camera/` directory. Other
remote paths may contain spaces when their shell assignments are quoted.

For example, an archived Xcode application with a filename containing spaces is
configured as:

```sh
RETROLIVE_REMOTE_DEVELOPER_DIR='/Applications/Xcode 6.2.app/Contents/Developer'
```

## 3. Initialize and inspect the build node

Initialization creates the dedicated source mirror, build-output directory, and
the marker that authorizes future synchronization:

```sh
./tools/legacy-remote.sh init
```

It refuses to mark an existing non-empty directory. After initialization, run:

```sh
./tools/legacy-remote.sh doctor
```

Review the reported macOS version, Xcode version, installed SDKs, paths, and
signing identities. `doctor` does not prove that the iPhone can install or run
the application.

## 4. Synchronize and build

Synchronize without building:

```sh
./tools/legacy-remote.sh sync
```

Build the iOS 6 camera scheme:

```sh
./tools/legacy-remote.sh build RetroLiveCamera
```

Build the Classic scheme:

```sh
./tools/legacy-remote.sh build RetroLiveClassic
```

`build` always synchronizes first. Each remote build records a timestamped log
under:

```text
<RETROLIVE_REMOTE_DERIVED_DATA>/RetroLiveLogs/
```

The source mirror also records the modern Mac's commit and whether
`legacy-camera/` had uncommitted changes in `.retrolive-source-state`. The
remote mirror does not contain `.git`.

## 5. Configure physical-device signing

The Debug configurations in the project intentionally set
`CODE_SIGNING_ALLOWED = NO` for compile-only checks. A device build must
override it without committing personal signing settings.

On a supported modern Mac, create or download a development certificate and a
provisioning profile that includes the target iPhone. Transfer the certificate
and profile to the build Mac through a trusted offline path, then:

1. import the certificate and its private key into the build user's login
   keychain;
2. install the provisioning profile for that user;
3. create `~/RetroLivePrivate/LegacySigning.xcconfig` on the build Mac;
4. never copy that file back into the repository.

The exact keys depend on the certificate and Xcode 6.2's manual-signing
behavior. A typical private file is:

```xcconfig
CODE_SIGN_IDENTITY = iPhone Developer
PROVISIONING_PROFILE = YOUR_PROFILE_UUID
PRODUCT_BUNDLE_IDENTIFIER = your.unique.bundle.identifier
```

Then update `.retrolive-legacy.env` on the modern Mac:

```sh
RETROLIVE_CODE_SIGNING_ALLOWED=YES
RETROLIVE_SIGNING_XCCONFIG=/Users/retrolive-builder/RetroLivePrivate/LegacySigning.xcconfig
```

Run `doctor` again, then build. Certificate validity, profile membership, the
device's actual OS, Xcode device support, and installation must each be checked
separately.

## 6. Install and run on the iPhone

Keep the synchronized project open in Xcode 6.2 on the build Mac, select the
USB-connected iPhone, and use **Product > Run** after the remote build succeeds.
The scripts intentionally do not automate installation or launch yet. This
keeps failures visible in the period Xcode toolchain and avoids adding an
unverified deployment dependency.

## Troubleshooting

### The script refuses to synchronize

Run `init` once. If the configured mirror already contains unrelated files,
choose a new empty directory rather than adding the marker manually.

### Xcode is not usable

Confirm `RETROLIVE_REMOTE_DEVELOPER_DIR` points to the archived Xcode's
`Contents/Developer` directory. Open Xcode locally once to accept any license or
first-launch prompts; do not script a system-wide Xcode switch unless this Mac
is dedicated to that toolchain.

### Compilation succeeds but installation fails

Compilation does not validate signing, device support, provisioning, or the
device OS. Re-run `doctor`, inspect the remote build log, then attempt Xcode Run
to obtain the period toolchain's native error message.

### A deleted local file remains on the build Mac

Only files excluded by `tools/legacy-rsync-excludes.txt` are preserved inside
the mirror. Other stale files are removed by `rsync --delete`. Check that the
file is inside the configured mirror rather than Derived Data.

### Use a different private configuration

Set the config path for one invocation:

```sh
RETROLIVE_REMOTE_CONFIG=/secure/path/another.env ./tools/legacy-remote.sh doctor
```
