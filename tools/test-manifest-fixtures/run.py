#!/usr/bin/env python3
"""Run the shared Manifest fixture catalog through every host-side parser."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "protocol" / "fixtures"
CATALOG = FIXTURES / "cases.json"
VALIDATOR = ROOT / "tools" / "validate-manifest" / "validate.py"
LEGACY_TOOL = ROOT / "tools" / "test-legacy-parser" / "main.m"
LEGACY_SOURCES = ROOT / "legacy-camera" / "RetroLiveCamera" / "Assets"
SUPPORTED_EXPECTATIONS = {"valid", "invalid", "unsupported"}


def load_cases():
    with CATALOG.open(encoding="utf-8") as source:
        document = json.load(source)
    cases = document.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("fixtures/cases.json must contain a non-empty cases array")

    names = []
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("every fixture case must be an object")
        name = case.get("name")
        expectation = case.get("expectation")
        if not isinstance(name, str) or not name:
            raise ValueError("every fixture case must have a non-empty name")
        if expectation not in SUPPORTED_EXPECTATIONS:
            raise ValueError(f"{name}: unsupported expectation {expectation!r}")
        if name in names:
            raise ValueError(f"duplicate fixture case: {name}")
        names.append(name)
        if not (FIXTURES / name / "manifest.json").is_file():
            raise ValueError(f"{name}: manifest.json is missing")

    discovered = {path.parent.name for path in FIXTURES.glob("*/manifest.json")}
    unlisted = discovered - set(names)
    missing = set(names) - discovered
    if unlisted or missing:
        raise ValueError(
            f"fixture catalog mismatch; unlisted={sorted(unlisted)}, missing={sorted(missing)}"
        )
    return cases


def expectation_flag(expectation):
    if expectation == "invalid":
        return "--expect-invalid"
    if expectation == "unsupported":
        return "--expect-unsupported"
    return None


def run_case(command_prefix, case):
    command = [str(component) for component in command_prefix]
    flag = expectation_flag(case["expectation"])
    if flag:
        command.append(flag)
    command.append(str(FIXTURES / case["name"] / "manifest.json"))
    subprocess.run(command, check=True)


def compile_legacy_parser(output):
    subprocess.run(
        [
            "clang",
            "-fobjc-arc",
            "-framework",
            "Foundation",
            "-I",
            str(LEGACY_SOURCES),
            str(LEGACY_TOOL),
            str(LEGACY_SOURCES / "RLVAssetManifest.m"),
            str(LEGACY_SOURCES / "RLVManifestParser.m"),
            "-o",
            str(output),
        ],
        check=True,
    )


def main():
    try:
        cases = load_cases()
        print(f"Running {len(cases)} shared Manifest fixtures with Python", flush=True)
        for case in cases:
            run_case([sys.executable, VALIDATOR], case)

        with tempfile.TemporaryDirectory(prefix="retrolive-manifest-fixtures-") as directory:
            legacy_parser = Path(directory) / "retrolive-legacy-parser"
            compile_legacy_parser(legacy_parser)
            print(f"Running {len(cases)} shared Manifest fixtures with Objective-C", flush=True)
            for case in cases:
                run_case([legacy_parser], case)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL shared Manifest fixtures: {error}", file=sys.stderr)
        return 1

    print(f"PASS shared Manifest fixtures: {len(cases)} cases x 2 parsers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
