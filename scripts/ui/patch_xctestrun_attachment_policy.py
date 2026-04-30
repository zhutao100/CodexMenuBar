#!/usr/bin/env python3
"""Patch generated .xctestrun files to control XCTest attachment retention.

This is intended for privacy-preserving macOS/iOS UI loops that use
`xcodebuild build-for-testing` followed by `xcodebuild test-without-building`.
The generated .xctestrun plist is the last deterministic point where agents can
force automatic UI-testing screenshots to be discarded before the .xcresult is
created.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import shutil
import sys
from pathlib import Path
from typing import Any

VALID_LIFETIMES = {"keepAlways", "deleteOnSuccess", "keepNever"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch SystemAttachmentLifetime/UserAttachmentLifetime in an .xctestrun plist."
    )
    parser.add_argument("xctestrun", type=Path, help="Path to the generated .xctestrun file")
    parser.add_argument(
        "--system-attachment-lifetime",
        choices=sorted(VALID_LIFETIMES),
        default=None,
        help="Lifetime for automatic XCTest UI screenshots/system attachments",
    )
    parser.add_argument(
        "--user-attachment-lifetime",
        choices=sorted(VALID_LIFETIMES),
        default=None,
        help="Lifetime for explicit XCTAttachment instances created by test code",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Do not write a .bak copy before modifying the plist",
    )
    parser.add_argument("--dry-run", action="store_true", help="Report changes without writing")
    return parser.parse_args()


def is_test_bundle_dict(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    keys = set(value.keys())
    return bool(
        {"TestBundlePath", "TestHostPath", "UITargetAppPath", "ProductModuleName", "IsUITestBundle"}
        & keys
    )


def patch_dict(node: Any, system_lifetime: str | None, user_lifetime: str | None, path: str = "") -> list[dict[str, Any]]:
    changes: list[dict[str, Any]] = []

    if isinstance(node, dict):
        if is_test_bundle_dict(node):
            target_name = str(node.get("ProductModuleName") or node.get("TestBundlePath") or path or "<unknown>")
            if system_lifetime is not None:
                old = node.get("SystemAttachmentLifetime")
                if old != system_lifetime:
                    node["SystemAttachmentLifetime"] = system_lifetime
                    changes.append(
                        {
                            "target": target_name,
                            "key": "SystemAttachmentLifetime",
                            "old": old,
                            "new": system_lifetime,
                        }
                    )
            if user_lifetime is not None:
                old = node.get("UserAttachmentLifetime")
                if old != user_lifetime:
                    node["UserAttachmentLifetime"] = user_lifetime
                    changes.append(
                        {
                            "target": target_name,
                            "key": "UserAttachmentLifetime",
                            "old": old,
                            "new": user_lifetime,
                        }
                    )

        for key, value in node.items():
            changes.extend(patch_dict(value, system_lifetime, user_lifetime, f"{path}/{key}"))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            changes.extend(patch_dict(value, system_lifetime, user_lifetime, f"{path}[{index}]"))

    return changes


def main() -> int:
    args = parse_args()

    if args.system_attachment_lifetime is None and args.user_attachment_lifetime is None:
        print("No lifetime requested; pass --system-attachment-lifetime and/or --user-attachment-lifetime", file=sys.stderr)
        return 2

    if not args.xctestrun.is_file():
        print(f"Not a file: {args.xctestrun}", file=sys.stderr)
        return 2

    original = args.xctestrun.read_bytes()
    data = plistlib.loads(original)
    changes = patch_dict(data, args.system_attachment_lifetime, args.user_attachment_lifetime)

    report = {
        "path": str(args.xctestrun),
        "dry_run": bool(args.dry_run),
        "changes": changes,
    }
    print(json.dumps(report, indent=2, sort_keys=True))

    if args.dry_run or not changes:
        return 0

    if not args.no_backup:
        backup = args.xctestrun.with_suffix(args.xctestrun.suffix + ".bak")
        if not backup.exists():
            shutil.copy2(args.xctestrun, backup)

    args.xctestrun.write_bytes(plistlib.dumps(data, sort_keys=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
