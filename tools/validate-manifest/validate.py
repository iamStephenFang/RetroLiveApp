#!/usr/bin/env python3
"""Dependency-free semantic validator for RetroLive Manifest V1 fixtures.

The JSON Schema remains normative. This utility mirrors its Phase 0 invariants so
the repository can be validated without downloading a third-party package.
"""

import argparse
import json
import re
import sys
import uuid
from datetime import datetime
from pathlib import Path

SHA256 = re.compile(r"^[0-9a-f]{64}$")
SCHEMA_PATH = Path(__file__).resolve().parents[2] / "protocol" / "manifest.schema.json"


class UnsupportedSchemaVersion(ValueError):
    pass


def resolve_reference(root_schema, reference):
    if not reference.startswith("#/"):
        raise ValueError(f"Unsupported external schema reference: {reference}")
    value = root_schema
    for component in reference[2:].split("/"):
        value = value[component.replace("~1", "/").replace("~0", "~")]
    return value


def validate_schema_instance(instance, schema, root_schema, path="$"):
    if "anyOf" in schema:
        errors = []
        for candidate in schema["anyOf"]:
            try:
                validate_schema_instance(instance, candidate, root_schema, path)
                return
            except ValueError as error:
                errors.append(str(error))
        raise ValueError(f"{path}: value did not match any allowed schema")
    if "$ref" in schema:
        validate_schema_instance(instance, resolve_reference(root_schema, schema["$ref"]), root_schema, path)
    for item in schema.get("allOf", []):
        validate_schema_instance(instance, item, root_schema, path)

    expected = schema.get("type")
    type_matches = {
        "object": isinstance(instance, dict),
        "array": isinstance(instance, list),
        "string": isinstance(instance, str),
        "integer": isinstance(instance, int) and not isinstance(instance, bool),
        "number": isinstance(instance, (int, float)) and not isinstance(instance, bool),
        "boolean": isinstance(instance, bool),
        "null": instance is None,
    }
    if expected is not None and not type_matches.get(expected, False):
        raise ValueError(f"{path}: schema expected {expected}")
    if "const" in schema and instance != schema["const"]:
        raise ValueError(f"{path}: schema const mismatch")
    if "enum" in schema and instance not in schema["enum"]:
        raise ValueError(f"{path}: value is not in schema enum")
    if "minimum" in schema and instance < schema["minimum"]:
        raise ValueError(f"{path}: value is below schema minimum")
    if "maximum" in schema and instance > schema["maximum"]:
        raise ValueError(f"{path}: value exceeds schema maximum")
    if "exclusiveMinimum" in schema and instance <= schema["exclusiveMinimum"]:
        raise ValueError(f"{path}: value must exceed schema exclusiveMinimum")
    if isinstance(instance, str):
        if len(instance) < schema.get("minLength", 0):
            raise ValueError(f"{path}: string is shorter than schema minLength")
        if "pattern" in schema and re.search(schema["pattern"], instance) is None:
            raise ValueError(f"{path}: string does not match schema pattern")
        if schema.get("format") == "uuid":
            try:
                uuid.UUID(instance)
            except ValueError as error:
                raise ValueError(f"{path}: expected UUID") from error
        if schema.get("format") == "date-time":
            try:
                datetime.fromisoformat(instance.replace("Z", "+00:00"))
            except ValueError as error:
                raise ValueError(f"{path}: expected ISO-8601 date-time") from error
    if isinstance(instance, dict):
        for key in schema.get("required", []):
            if key not in instance:
                raise ValueError(f"{path}.{key}: required by schema")
        for key, child_schema in schema.get("properties", {}).items():
            if key in instance:
                validate_schema_instance(instance[key], child_schema, root_schema, f"{path}.{key}")


def require(mapping, key, expected_type, path):
    if key not in mapping:
        raise ValueError(f"{path}.{key}: required value is missing")
    value = mapping[key]
    if expected_type is int and (not isinstance(value, int) or isinstance(value, bool)):
        raise ValueError(f"{path}.{key}: expected integer")
    if expected_type is float and (not isinstance(value, (int, float)) or isinstance(value, bool)):
        raise ValueError(f"{path}.{key}: expected number")
    if expected_type not in (int, float) and not isinstance(value, expected_type):
        raise ValueError(f"{path}.{key}: expected {expected_type.__name__}")
    return value


def validate_resource(value, path, image=False):
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected object")
    filename = require(value, "filename", str, path)
    if filename in (".", "..") or "/" in filename or "\\" in filename or not filename:
        raise ValueError(f"{path}.filename: expected a safe basename")
    require(value, "mimeType", str, path)
    byte_length = require(value, "byteLength", int, path)
    if byte_length <= 0:
        raise ValueError(f"{path}.byteLength: must be positive")
    digest = require(value, "sha256", str, path)
    if not SHA256.fullmatch(digest):
        raise ValueError(f"{path}.sha256: expected 64 lowercase hexadecimal characters")
    if image:
        if require(value, "width", int, path) <= 0 or require(value, "height", int, path) <= 0:
            raise ValueError(f"{path}: image dimensions must be positive")


def validate_manifest(document):
    if not isinstance(document, dict):
        raise ValueError("$: expected object")
    version = require(document, "schemaVersion", int, "$")
    if version != 1:
        raise UnsupportedSchemaVersion(f"unsupported schemaVersion {version}; supported versions: 1")

    asset_id = require(document, "assetId", str, "$")
    try:
        uuid.UUID(asset_id)
    except ValueError as error:
        raise ValueError("$.assetId: expected UUID") from error

    created_at = require(document, "createdAt", str, "$")
    try:
        created_date = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("$.createdAt: expected ISO-8601 date-time") from error
    created_milliseconds = require(document, "createdAtUnixMilliseconds", int, "$")
    if created_milliseconds < 0:
        raise ValueError("$.createdAtUnixMilliseconds: must be non-negative")
    if abs(created_date.timestamp() * 1000 - created_milliseconds) > 1:
        raise ValueError("$.createdAtUnixMilliseconds: must describe the same instant as createdAt")

    capture = require(document, "capture", dict, "$")
    if require(capture, "cameraPosition", str, "$.capture") not in ("front", "back"):
        raise ValueError("$.capture.cameraPosition: unsupported value")
    orientation = require(capture, "orientation", int, "$.capture")
    if not 1 <= orientation <= 8:
        raise ValueError("$.capture.orientation: must be between 1 and 8")
    require(capture, "mirrored", bool, "$.capture")
    if require(capture, "flashMode", str, "$.capture") not in ("off", "on", "auto"):
        raise ValueError("$.capture.flashMode: unsupported value")
    still_time = require(capture, "stillImageTimeSeconds", float, "$.capture")
    if still_time < 0:
        raise ValueError("$.capture.stillImageTimeSeconds: must be non-negative")
    if require(capture, "stillImageTimeAccuracy", str, "$.capture") not in ("measured", "estimated"):
        raise ValueError("$.capture.stillImageTimeAccuracy: unsupported value")
    for key in ("preRollSeconds", "postRollSeconds"):
        if require(capture, key, float, "$.capture") < 0:
            raise ValueError(f"$.capture.{key}: must be non-negative")

    photo = require(document, "photo", dict, "$")
    if "motion" not in document:
        raise ValueError("$.motion: required value is missing")
    motion = document["motion"]
    thumbnail = document.get("thumbnail")
    validate_resource(photo, "$.photo", image=True)
    if thumbnail is not None:
        validate_resource(thumbnail, "$.thumbnail", image=True)
    if motion is None:
        if still_time != 0 or capture["preRollSeconds"] != 0 or capture["postRollSeconds"] != 0:
            raise ValueError("$.capture: photo-only assets require zero motion timing values")
    else:
        validate_resource(motion, "$.motion")
        duration = require(motion, "durationSeconds", float, "$.motion")
        if duration <= 0:
            raise ValueError("$.motion.durationSeconds: must be positive")
        if still_time >= duration:
            raise ValueError("$.capture.stillImageTimeSeconds: must be before motion end")
        if require(motion, "width", int, "$.motion") <= 0 or require(motion, "height", int, "$.motion") <= 0:
            raise ValueError("$.motion: dimensions must be positive")
        if require(motion, "frameRate", float, "$.motion") <= 0:
            raise ValueError("$.motion.frameRate: must be positive")
        require(motion, "hasAudio", bool, "$.motion")

    device = require(document, "device", dict, "$")
    for key in ("modelIdentifier", "systemVersion", "appVersion"):
        if not require(device, key, str, "$.device"):
            raise ValueError(f"$.device.{key}: must not be empty")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    expectation = parser.add_mutually_exclusive_group()
    expectation.add_argument("--expect-invalid", action="store_true")
    expectation.add_argument("--expect-unsupported", action="store_true")
    args = parser.parse_args()

    try:
        with args.path.open("r", encoding="utf-8") as source:
            document = json.load(source)
        if isinstance(document, dict) and isinstance(document.get("schemaVersion"), int) and document["schemaVersion"] != 1:
            raise UnsupportedSchemaVersion(
                f"unsupported schemaVersion {document['schemaVersion']}; supported versions: 1"
            )
        with SCHEMA_PATH.open("r", encoding="utf-8") as schema_source:
            schema = json.load(schema_source)
        validate_schema_instance(document, schema, schema)
        validate_manifest(document)
    except UnsupportedSchemaVersion as error:
        if args.expect_unsupported:
            print(f"PASS unsupported: {args.path}: {error}")
            return 0
        print(f"FAIL unsupported: {args.path}: {error}", file=sys.stderr)
        return 2
    except (OSError, json.JSONDecodeError, ValueError) as error:
        if args.expect_invalid:
            print(f"PASS invalid: {args.path}: {error}")
            return 0
        print(f"FAIL invalid: {args.path}: {error}", file=sys.stderr)
        return 1

    if args.expect_invalid or args.expect_unsupported:
        print(f"FAIL unexpectedly valid: {args.path}", file=sys.stderr)
        return 1
    print(f"PASS valid: {args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
