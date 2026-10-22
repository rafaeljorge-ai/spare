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
    r"Overline|Stat|valueStepper|settingRow|accessibilityLabel|accessibilityValue|footerButton|unreadable)"
)
PATTERN = re.compile(CALLS + r'\(\s*(?:(?!verbatim\b)\w+:\s*)?"((?:[^"\\]|\\.)*)"')
# Labeled arguments that carry UI text (`ScreenHeader(title:subtitle:)`, `ToolNotice(text:)`, ...) and
# `String(localized:)`, used by the notifications.
LABELED = re.compile(r'\b(?:title|subtitle|confirm|text):\s*"((?:[^"\\]|\\.)*)"')
LOCALIZED_STRING = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def source_keys():
    keys = set()
    for source in (ROOT / "Sources/SpareApp").rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        for pattern in (PATTERN, LABELED, LOCALIZED_STRING):
            for match in pattern.finditer(text):
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


def plural_keys():
    """Keys translated through Localizable.stringsdict (counts use %lld there, %@ in the source)."""
    path = ROOT / "Localization/pt-BR.lproj/Localizable.stringsdict"
    if not path.exists():
        return set()
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    return {key.replace("%lld", "%@") for key in json.loads(result.stdout)}


def main():
    keys = source_keys()
    missing = sorted(keys - set(translations()) - plural_keys())
    if missing:
        print("Missing pt-BR translations:")
        for key in missing:
            print(f"  {key!r}")
        sys.exit(1)
    print(f"strings ok ({len(keys)} keys)")


main()
