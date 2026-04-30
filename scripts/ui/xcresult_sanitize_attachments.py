#!/usr/bin/env python3
"""Create an agent-safe attachment tree from xcresult-exported attachments.

The script deliberately has no third-party dependencies. It supports the PNG
format that XCTest screenshots normally use, plus basic JPEG dimension probing
for redaction heuristics. Cropping is PNG-only.
"""

from __future__ import annotations

import argparse
import binascii
import json
import shutil
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
VALID_POLICIES = {"keep", "redact", "redact-suspect", "crop"}
VALID_ON_CROP_FAILURE = {"redact", "copy", "fail"}


@dataclass(frozen=True)
class ImageInfo:
    kind: str
    width: int
    height: int


@dataclass(frozen=True)
class CropRect:
    x: int
    y: int
    width: int
    height: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sanitize exported XCTest attachments before agents inspect them.")
    parser.add_argument("input_dir", type=Path, help="Raw exported attachments directory")
    parser.add_argument("output_dir", type=Path, help="Sanitized output directory")
    parser.add_argument(
        "--policy",
        choices=sorted(VALID_POLICIES),
        default="redact-suspect",
        help="keep: copy images; redact: redact all images; redact-suspect: redact large/fullscreen-looking images; crop: crop PNGs",
    )
    parser.add_argument(
        "--crop",
        default=None,
        metavar="X,Y,WIDTH,HEIGHT",
        help="Crop rectangle in top-left pixel coordinates, used with --policy crop",
    )
    parser.add_argument(
        "--max-pixels",
        type=int,
        default=2_500_000,
        help="Images at or above this pixel count are suspicious under redact-suspect",
    )
    parser.add_argument(
        "--min-width",
        type=int,
        default=1400,
        help="Images at or above this width are suspicious under redact-suspect",
    )
    parser.add_argument(
        "--min-height",
        type=int,
        default=900,
        help="Images at or above this height are suspicious under redact-suspect",
    )
    parser.add_argument(
        "--on-crop-failure",
        choices=sorted(VALID_ON_CROP_FAILURE),
        default="redact",
    )
    parser.add_argument("--report", type=Path, default=None, help="Write JSON report here")
    parser.add_argument("--clean", action="store_true", help="Remove output_dir before writing")
    return parser.parse_args()


def parse_crop(value: str | None) -> CropRect | None:
    if value is None:
        return None
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 4:
        raise ValueError("--crop must be X,Y,WIDTH,HEIGHT")
    x, y, width, height = (int(part) for part in parts)
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        raise ValueError("--crop values must be non-negative x/y and positive width/height")
    return CropRect(x=x, y=y, width=width, height=height)


def read_png_chunks(data: bytes) -> tuple[dict[str, Any], list[tuple[bytes, bytes]]]:
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    offset = len(PNG_SIGNATURE)
    chunks: list[tuple[bytes, bytes]] = []
    ihdr: dict[str, Any] | None = None

    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated PNG chunk header")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        ctype = data[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        crc_end = end + 4
        if crc_end > len(data):
            raise ValueError("truncated PNG chunk payload")
        payload = data[start:end]
        chunks.append((ctype, payload))
        if ctype == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            ihdr = {
                "width": width,
                "height": height,
                "bit_depth": bit_depth,
                "color_type": color_type,
                "compression": compression,
                "filter_method": filter_method,
                "interlace": interlace,
            }
        offset = crc_end
        if ctype == b"IEND":
            break

    if ihdr is None:
        raise ValueError("missing IHDR")
    return ihdr, chunks


def png_info(path: Path) -> ImageInfo:
    with path.open("rb") as fh:
        header = fh.read(33)
    if not header.startswith(PNG_SIGNATURE) or len(header) < 33:
        raise ValueError("not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    return ImageInfo(kind="png", width=width, height=height)


def jpeg_info(path: Path) -> ImageInfo:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        raise ValueError("not a JPEG")
    offset = 2
    while offset + 4 < len(data):
        if data[offset] != 0xFF:
            offset += 1
            continue
        marker = data[offset + 1]
        offset += 2
        if marker in {0xD8, 0xD9, 0x01} or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(data):
            break
        length = struct.unpack(">H", data[offset : offset + 2])[0]
        if length < 2 or offset + length > len(data):
            break
        if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
            segment = data[offset + 2 : offset + length]
            if len(segment) >= 5:
                height, width = struct.unpack(">HH", segment[1:5])
                return ImageInfo(kind="jpeg", width=width, height=height)
        offset += length
    raise ValueError("could not find JPEG dimensions")


def image_info(path: Path) -> ImageInfo | None:
    try:
        return png_info(path)
    except Exception:
        pass
    try:
        return jpeg_info(path)
    except Exception:
        return None


def paeth_predictor(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def channels_for_png(color_type: int) -> int:
    return {
        0: 1,  # grayscale
        2: 3,  # RGB
        4: 2,  # grayscale + alpha
        6: 4,  # RGBA
    }[color_type]


def unfilter_png(raw: bytes, width: int, height: int, channels: int) -> list[bytearray]:
    stride = width * channels
    rows: list[bytearray] = []
    offset = 0
    previous = bytearray(stride)

    for _ in range(height):
        if offset >= len(raw):
            raise ValueError("truncated PNG image data")
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset : offset + stride])
        offset += stride
        if len(row) != stride:
            raise ValueError("truncated PNG row")

        if filter_type == 0:
            pass
        elif filter_type == 1:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + left) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                row[i] = (row[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                up = previous[i]
                row[i] = (row[i] + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                up = previous[i]
                up_left = previous[i - channels] if i >= channels else 0
                row[i] = (row[i] + paeth_predictor(left, up, up_left)) & 0xFF
        else:
            raise ValueError(f"unsupported PNG filter type: {filter_type}")

        rows.append(row)
        previous = row

    return rows


def png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    crc = binascii.crc32(chunk_type)
    crc = binascii.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", crc)


def write_png(path: Path, width: int, height: int, color_type: int, channels: int, rows: list[bytes]) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    payload = zlib.compress(raw, level=6)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(PNG_SIGNATURE + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", payload) + png_chunk(b"IEND", b""))


def crop_png(input_path: Path, output_path: Path, rect: CropRect) -> ImageInfo:
    data = input_path.read_bytes()
    ihdr, chunks = read_png_chunks(data)
    width = int(ihdr["width"])
    height = int(ihdr["height"])
    bit_depth = int(ihdr["bit_depth"])
    color_type = int(ihdr["color_type"])
    interlace = int(ihdr["interlace"])

    if bit_depth != 8:
        raise ValueError(f"unsupported PNG bit depth: {bit_depth}")
    if interlace != 0:
        raise ValueError("interlaced PNG is unsupported")
    try:
        channels = channels_for_png(color_type)
    except KeyError as exc:
        raise ValueError(f"unsupported PNG color type: {color_type}") from exc

    if rect.x >= width or rect.y >= height:
        raise ValueError(f"crop origin outside image: {rect} for {width}x{height}")
    crop_width = min(rect.width, width - rect.x)
    crop_height = min(rect.height, height - rect.y)
    if crop_width <= 0 or crop_height <= 0:
        raise ValueError(f"empty crop: {rect} for {width}x{height}")

    idat = b"".join(payload for ctype, payload in chunks if ctype == b"IDAT")
    rows = unfilter_png(zlib.decompress(idat), width, height, channels)
    left = rect.x * channels
    right = (rect.x + crop_width) * channels
    cropped = [bytes(row[left:right]) for row in rows[rect.y : rect.y + crop_height]]
    write_png(output_path, crop_width, crop_height, color_type, channels, cropped)
    return ImageInfo(kind="png", width=crop_width, height=crop_height)


def write_redacted_png(path: Path) -> ImageInfo:
    width = 320
    height = 120
    # RGBA gray placeholder. No text is embedded to avoid adding font/rendering dependencies.
    row = bytes([0x66, 0x66, 0x66, 0xFF]) * width
    rows = [row for _ in range(height)]
    write_png(path, width, height, 6, 4, rows)
    return ImageInfo(kind="png", width=width, height=height)


def is_suspicious(info: ImageInfo, args: argparse.Namespace) -> bool:
    return (
        info.width * info.height >= args.max_pixels
        or info.width >= args.min_width
        or info.height >= args.min_height
    )


def rel_output_path(output_root: Path, rel: Path, redacted_ext: bool = False) -> Path:
    if redacted_ext and rel.suffix.lower() not in {".png"}:
        return output_root / rel.with_suffix(rel.suffix + ".redacted.png")
    return output_root / rel


def process_file(path: Path, rel: Path, args: argparse.Namespace, crop_rect: CropRect | None) -> dict[str, Any]:
    info = image_info(path)

    if info is None:
        out = args.output_dir / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)
        return {"path": str(rel), "kind": "non-image", "action": "copy"}

    base: dict[str, Any] = {
        "path": str(rel),
        "kind": info.kind,
        "inputWidth": info.width,
        "inputHeight": info.height,
    }

    if args.policy == "keep":
        out = args.output_dir / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)
        return base | {"action": "copy"}

    if args.policy == "redact" or (args.policy == "redact-suspect" and is_suspicious(info, args)):
        out = rel_output_path(args.output_dir, rel, redacted_ext=True)
        redacted = write_redacted_png(out)
        return base | {"action": "redact", "output": str(out.relative_to(args.output_dir)), "outputWidth": redacted.width, "outputHeight": redacted.height}

    if args.policy == "redact-suspect":
        out = args.output_dir / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)
        return base | {"action": "copy-nonsuspect"}

    if args.policy == "crop":
        if crop_rect is None:
            raise ValueError("--policy crop requires --crop X,Y,WIDTH,HEIGHT")
        if info.kind != "png":
            if args.on_crop_failure == "fail":
                raise ValueError(f"cannot crop non-PNG image: {rel}")
            if args.on_crop_failure == "copy":
                out = args.output_dir / rel
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, out)
                return base | {"action": "copy-crop-unsupported"}
            out = rel_output_path(args.output_dir, rel, redacted_ext=True)
            redacted = write_redacted_png(out)
            return base | {"action": "redact-crop-unsupported", "output": str(out.relative_to(args.output_dir)), "outputWidth": redacted.width, "outputHeight": redacted.height}
        try:
            out = args.output_dir / rel
            cropped = crop_png(path, out, crop_rect)
            return base | {"action": "crop", "outputWidth": cropped.width, "outputHeight": cropped.height}
        except Exception as exc:
            if args.on_crop_failure == "fail":
                raise
            if args.on_crop_failure == "copy":
                out = args.output_dir / rel
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, out)
                return base | {"action": "copy-crop-failed", "error": str(exc)}
            out = rel_output_path(args.output_dir, rel, redacted_ext=True)
            redacted = write_redacted_png(out)
            return base | {"action": "redact-crop-failed", "error": str(exc), "output": str(out.relative_to(args.output_dir)), "outputWidth": redacted.width, "outputHeight": redacted.height}

    raise AssertionError(f"unknown policy {args.policy}")


def main() -> int:
    args = parse_args()
    crop_rect = parse_crop(args.crop)

    if not args.input_dir.is_dir():
        print(f"Not a directory: {args.input_dir}", file=sys.stderr)
        return 2

    if args.clean and args.output_dir.exists():
        shutil.rmtree(args.output_dir)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    files = [p for p in sorted(args.input_dir.rglob("*")) if p.is_file()]
    entries: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []

    for path in files:
        rel = path.relative_to(args.input_dir)
        try:
            entries.append(process_file(path, rel, args, crop_rect))
        except Exception as exc:
            errors.append({"path": str(rel), "error": str(exc)})
            if args.on_crop_failure == "fail":
                break

    report = {
        "inputDir": str(args.input_dir),
        "outputDir": str(args.output_dir),
        "policy": args.policy,
        "crop": None if crop_rect is None else crop_rect.__dict__,
        "files": entries,
        "errors": errors,
    }

    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    else:
        print(json.dumps(report, indent=2, sort_keys=True))

    return 1 if errors and args.on_crop_failure == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
