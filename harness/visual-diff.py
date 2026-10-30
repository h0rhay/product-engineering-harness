#!/usr/bin/env python3
"""Find what changed between two screenshots and crop it at full resolution.

Usage: visual-diff.py <before.png> <after.png> <crop-prefix>

Lines up identical pixel rows, so a change that pushes the page down shows as the change
alone, not as everything below it. Prints one line per changed band. Standard library
only, so it works on any project with python3. Exit 1 if an image cannot be read.
"""
import difflib, struct, sys, zlib
from collections import Counter

MAX_CROPS = 6
CONTEXT = 60
MERGE_GAP = 40
MAX_CROP_HEIGHT = 1200


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat = 8, []
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or color not in (2, 6) or interlace:
                raise ValueError("unsupported PNG format")
            bpp = 3 if color == 2 else 4
        elif kind == b"IDAT":
            idat.append(body)
        pos += 12 + length
    raw, stride, rows, prev = zlib.decompress(b"".join(idat)), w * bpp, [], bytes(w * bpp)
    for y in range(h):
        start = y * (stride + 1)
        kind, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = row[i - bpp] if i >= bpp else 0
                b, c = prev[i], prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = bytes(row)
        rows.append(prev)
    return w, bpp, rows


def write_png(path, w, bpp, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    header = struct.pack(">IIBBBBB", w, len(rows), 8, 2 if bpp == 3 else 6, 0, 0, 0)
    pixels = zlib.compress(b"".join(b"\0" + r for r in rows))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b""))


def runs(rows):
    """Run-length encode rows: flat backgrounds repeat, and difflib slows badly on repeats."""
    out = []
    for y, row in enumerate(rows):
        if out and out[-1][0] == row:
            out[-1][2] = y + 1
        else:
            out.append([row, y, y + 1])
    return out


def changed_bands(before, after):
    ra, rb = runs(before), runs(after)
    keys_a, keys_b = [r[0] for r in ra], [r[0] for r in rb]
    matcher = difflib.SequenceMatcher(None, keys_a, keys_b, autojunk=False)
    bands = []
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        y1 = ra[i1][1] if i1 < len(ra) else len(before)
        y2 = ra[i2 - 1][2] if i2 > i1 else y1
        y3 = rb[j1][1] if j1 < len(rb) else len(after)
        y4 = rb[j2 - 1][2] if j2 > j1 else y3
        if bands and y1 - bands[-1][1] <= MERGE_GAP and y3 - bands[-1][3] <= MERGE_GAP:
            bands[-1][1], bands[-1][3] = y2, y4
        else:
            bands.append([y1, y2, y3, y4])
    return bands


def main_colour(rows, y1, y2, bpp):
    if y2 <= y1:
        return "none"
    counts = Counter()
    for row in rows[y1:y2:max(1, (y2 - y1) // 40)]:
        for i in range(0, len(row), bpp * 4):
            counts[bytes(row[i:i + 3])] += 1
    return "#" + counts.most_common(1)[0][0].hex()


def crop(path, w, bpp, rows, y1, y2):
    top, bottom = max(0, y1 - CONTEXT), min(len(rows), y2 + CONTEXT)
    write_png(path, w, bpp, rows[top:min(bottom, top + MAX_CROP_HEIGHT)])
    return path


def main():
    before_path, after_path, prefix = sys.argv[1:4]
    try:
        wa, bppa, before = read_png(before_path)
        wb, bppb, after = read_png(after_path)
    except (OSError, ValueError, struct.error, zlib.error, UnboundLocalError) as e:
        print(f"could not read screenshots: {e}", file=sys.stderr)
        return 1
    if wa != wb:
        print(f"page widths differ: before {wa}px, after {wb}px")
    bands = changed_bands(before, after)
    if not bands:
        print("no pixel differences")
        return 0
    # Height changes first, then the largest: a small structural change must not lose its
    # crop to a run of changed numbers higher up the page.
    ranked = sorted(bands, key=lambda b: ((b[1] - b[0]) == (b[3] - b[2]), -max(b[1] - b[0], b[3] - b[2])))
    cropped = {id(b): n for n, b in enumerate(ranked[:MAX_CROPS], 1)}
    for b in bands:
        y1, y2, y3, y4 = b
        line = (f"before y={y1}-{y2} ({y2 - y1}px, mostly {main_colour(before, y1, y2, bppa)}) -> "
                f"after y={y3}-{y4} ({y4 - y3}px, mostly {main_colour(after, y3, y4, bppb)})")
        n = cropped.get(id(b))
        if n:
            a = crop(f"{prefix}-{n}-before.png", wa, bppa, before, y1, y2)
            c = crop(f"{prefix}-{n}-after.png", wb, bppb, after, y3, y4)
            line += f"; crops {a} {c}"
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
