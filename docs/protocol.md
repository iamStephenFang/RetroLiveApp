# RetroLive Protocol V1

Protocol V1 consists of JSON metadata and immutable media files transferred over HTTP. `protocol/manifest.schema.json` is the normative Manifest definition. Examples and fixtures are informative test inputs.

## Compatibility rules

- `schemaVersion` is required and must be the integer `1` for V1 parsers.
- Unknown object properties are ignored so V1 can gain optional fields.
- Missing required fields, invalid field types, unsafe filenames, malformed SHA-256 values, and inconsistent time ranges are errors.
- A parser must report an unsupported version explicitly; it must not guess.
- All media durations and relative timestamps use seconds as JSON numbers.
- Media filenames are basenames only. `/`, `\\`, `.` and `..` are rejected.
- Declared byte lengths and hashes are untrusted until verified against downloaded files.
- `motion` is required but nullable. `null` describes a valid photo-only asset; an object describes a photo-plus-motion asset.
- `thumbnail` is optional. Clients may derive a display thumbnail from `photo.jpg`.
- Photo-only assets use zero for `stillImageTimeSeconds`, `preRollSeconds`, and `postRollSeconds`.

## Asset identity

`assetId` is a UUID identifying the immutable RetroLive asset. It may later be reused as the Live Photo pairing identifier, but it is not a Photos local identifier.

## Hashing

SHA-256 strings are 64 lowercase hexadecimal characters. A syntactically valid Manifest does not prove that its hashes match media; the importer performs that comparison after download.

## Evolution

Optional fields may be added without changing `schemaVersion`. Removing a field or changing its meaning requires a new protocol version and new fixtures.
