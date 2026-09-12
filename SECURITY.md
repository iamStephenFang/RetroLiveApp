# Security Policy

## Supported versions

RetroLive is under active development. Security fixes are made on the default
branch and, when releases exist, on the latest supported release. Feature
branches, forks, unofficial binaries, and modified builds are not maintained by
this project.

The Legacy and Classic camera targets depend on archived Apple toolchains and
period hardware. A current-SDK build or host test does not establish that a fix
works on iOS 6 or iOS 8; reports and fixes for those targets remain pending until
the relevant physical-device checks are recorded.

## Reporting a vulnerability

Do not open a public issue containing an exploit, pairing code, bearer token,
private device information, or personal photo or video.

Use [GitHub private vulnerability reporting](https://github.com/iamStephenFang/RetroLive/security/advisories/new)
to report a vulnerability. If that form is unavailable, open a public issue
that asks the maintainer to establish a private contact channel, without
including sensitive details.

Include the affected target and revision, device and OS versions, reproduction
steps, impact, and the smallest safe proof of concept. Redact local addresses,
device names, tokens, signing information, filesystem paths, and personal media.
The maintainer will make a best-effort acknowledgement within seven days and
will coordinate disclosure after a fix or mitigation is available.

## LAN transfer security boundary

RetroLive transfer is explicitly started by the person using the camera and is
intended for a trusted local Wi-Fi network. The legacy server uses plaintext
HTTP for iOS 6 compatibility. Pairing limits accidental or unauthorized API
access, but it does not prevent another party on the same network from observing
traffic. Stop sharing when transfer is complete and do not use the feature on
public or otherwise untrusted Wi-Fi.

The documented lack of transport encryption is a known limitation. Please
report authentication bypasses, path traversal, access to uncommitted assets,
tokens that remain valid after sharing stops or the app backgrounds, exposure
outside the intended local-network boundary, denial-of-service conditions, and
ways to obtain media without completing pairing.

## Handling security changes

Security fixes should preserve the read-only transfer boundary, avoid logging
secrets or media, add focused regression coverage, and state which host,
simulator, archived-toolchain, and physical-device checks were actually run.
Do not treat a successful current-Xcode build as old-device acceptance.
