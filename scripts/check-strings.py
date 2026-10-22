#!/usr/bin/env python3
"""Fail if a UI string literal in Sources/SpareApp has no pt-BR translation."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALLS = (
    r"(?:Text|Button|Label|Toggle|Section|ContentUnavailableView|LocalizedStringKey|"
    r"navigationTitle|help|confirmationDialog|Stepper|Picker|TextField|GroupBox|LabeledContent|"
    r"Overline|Stat|footerButton|unreadable)"
)
PATTERN = re.compile(CALLS + r'\(\s*(?:(?!verbatim\b)\w+:\s*)?"((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def source_keys():
    keys = set()
    for source in (ROOT / "Sources/SpareApp").rglob("*.swift"):
        for match in PATTERN.finditer(source.read_text(encoding="utf-8")):
            key = INTERPOLATION.sub("%@", match.group(1)).replace('\\"', '"')
            if key.strip():
                keys.add(key)
    return keys


def translations():
    path = ROOT / "Localization/pt-BR.lproj/Localizable.strings"
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def main():
    keys = source_keys()
    missing = sorted(keys - set(translations()))
    if missing:
        print("Missing pt-BR translations:")
        for key in missing:
            print(f"  {key!r}")
        sys.exit(1)
    print(f"strings ok ({len(keys)} keys)")


main()
