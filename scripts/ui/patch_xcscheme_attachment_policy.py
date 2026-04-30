#!/usr/bin/env python3
"""Patch shared .xcscheme TestAction attachment policy attributes.

Use this only when the project commits shared schemes and you intentionally want
source-controlled screenshot retention policy. For one-off agent runs, prefer
`ui_loop.sh --reuse-build --system-attachment-lifetime keepNever`, which patches
the generated .xctestrun instead of modifying project files.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

VALID_LIFETIMES = {"keepAlways", "deleteOnSuccess", "keepNever"}
VALID_CAPTURE_FORMATS = {"screenshots", "screenRecording"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Patch TestAction screenshot/attachment policy in .xcscheme files.")
    parser.add_argument("paths", nargs="+", type=Path, help=".xcscheme file(s), or directories to search")
    parser.add_argument("--system-attachment-lifetime", choices=sorted(VALID_LIFETIMES), default="keepNever")
    parser.add_argument("--preferred-screen-capture-format", choices=sorted(VALID_CAPTURE_FORMATS), default=None)
    parser.add_argument("--no-backup", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def iter_scheme_paths(paths: list[Path]) -> list[Path]:
    out: list[Path] = []
    for path in paths:
        if path.is_dir():
            out.extend(sorted(path.rglob("*.xcscheme")))
        elif path.is_file() and path.suffix == ".xcscheme":
            out.append(path)
        else:
            print(f"Skipping non-scheme path: {path}", file=sys.stderr)
    return out


def indent(elem: ET.Element, level: int = 0) -> None:
    # ElementTree.indent exists in Python 3.9+, but keep this self-contained for older Xcode CLT Python builds.
    i = "\n" + level * "   "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "   "
        for child in elem:
            indent(child, level + 1)
        if not child.tail or not child.tail.strip():
            child.tail = i
    if level and (not elem.tail or not elem.tail.strip()):
        elem.tail = i


def patch_one(path: Path, args: argparse.Namespace) -> dict[str, object]:
    tree = ET.parse(path)
    root = tree.getroot()
    test_actions = root.findall(".//TestAction")
    changes: list[dict[str, object]] = []

    for index, action in enumerate(test_actions):
        old = action.get("systemAttachmentLifetime")
        if old != args.system_attachment_lifetime:
            action.set("systemAttachmentLifetime", args.system_attachment_lifetime)
            changes.append(
                {
                    "testActionIndex": index,
                    "key": "systemAttachmentLifetime",
                    "old": old,
                    "new": args.system_attachment_lifetime,
                }
            )

        if args.preferred_screen_capture_format is not None:
            old = action.get("preferredScreenCaptureFormat")
            if old != args.preferred_screen_capture_format:
                action.set("preferredScreenCaptureFormat", args.preferred_screen_capture_format)
                changes.append(
                    {
                        "testActionIndex": index,
                        "key": "preferredScreenCaptureFormat",
                        "old": old,
                        "new": args.preferred_screen_capture_format,
                    }
                )

    if changes and not args.dry_run:
        if not args.no_backup:
            backup = path.with_suffix(path.suffix + ".bak")
            if not backup.exists():
                shutil.copy2(path, backup)
        indent(root)
        tree.write(path, encoding="UTF-8", xml_declaration=True)

    return {"path": str(path), "changes": changes}


def main() -> int:
    args = parse_args()
    paths = iter_scheme_paths(args.paths)
    if not paths:
        print("No .xcscheme files found", file=sys.stderr)
        return 2

    report = {
        "dry_run": bool(args.dry_run),
        "schemes": [patch_one(path, args) for path in paths],
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
