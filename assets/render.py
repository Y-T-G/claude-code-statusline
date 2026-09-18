#!/usr/bin/env python3
"""Render the status line output as a PNG, so the README shows real output.

Usage: statusline.sh full | python3 assets/render.py assets/full.png "full mode"

Needs cairosvg (pip install cairosvg) and a monospace font. Without cairosvg it
writes the intermediate SVG next to the target instead.
"""
import math, re, sys

LEVELS = (0, 95, 135, 175, 215, 255)
BASE16 = ("000000", "800000", "008000", "808000", "000080", "800080", "008080", "c0c0c0",
          "808080", "ff0000", "00ff00", "ffff00", "0000ff", "ff00ff", "00ffff", "ffffff")


def xterm(i: int) -> str:
    if i < 16:
        return "#" + BASE16[i]
    if i < 232:
        i -= 16
        return "#%02x%02x%02x" % (LEVELS[i // 36], LEVELS[i % 36 // 6], LEVELS[i % 6])
    v = 8 + 10 * (i - 232)
    return "#%02x%02x%02x" % (v, v, v)


def spans(line: str):
    color, out = None, []
    for part in re.split(r"\x1b\[([0-9;]*)m", line):
        if re.fullmatch(r"[0-9;]*", part) and part != line:
            m = re.fullmatch(r"38;5;(\d+)", part)
            color = xterm(int(m.group(1))) if m else None
        elif part:
            out.append((part, color))
    return out


SIZE, PAD = 15.0, 18.0
CHAR_W = SIZE * 0.6  # the advance of the monospace fonts below
FONT = "DejaVu Sans Mono, SFMono-Regular, Menlo, Consolas, monospace"


def svg(text: str, caption: str) -> str:
    parts = spans(text)
    plain = "".join(p for p, _ in parts)
    w = math.ceil(max(len(plain) * CHAR_W, len(caption) * 7.5) + 2 * PAD + 20)
    h = math.ceil(2 * PAD + SIZE * 3.4)
    # textLength pins every run to its measured width, so a different font
    # cannot push the line past the edge
    tspans = "".join(
        '<tspan fill="{}" textLength="{:.1f}" lengthAdjust="spacing">{}</tspan>'.format(
            c or "#e6e6e6", len(t) * CHAR_W, t.replace("&", "&amp;").replace("<", "&lt;"))
        for t, c in parts
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" font-family="{FONT}">
  <rect width="100%" height="100%" rx="10" fill="#17171b"/>
  <rect x="{PAD - 8:.0f}" y="{PAD - 6:.0f}" width="{w - 2 * PAD + 16:.0f}" height="{SIZE * 1.8:.0f}" rx="6" fill="none" stroke="#3a3a42"/>
  <text x="{PAD:.0f}" y="{PAD + SIZE:.0f}" font-size="{SIZE}" fill="#6b6b76">&gt; {caption}</text>
  <text x="{PAD:.0f}" y="{PAD + SIZE * 2.8:.0f}" font-size="{SIZE}" xml:space="preserve">{tspans}</text>
</svg>
'''


if __name__ == "__main__":
    out, caption = sys.argv[1], sys.argv[2]
    body = svg(sys.stdin.read().rstrip("\n"), caption)
    try:
        import cairosvg
    except ImportError:
        out = out.rsplit(".", 1)[0] + ".svg"
        with open(out, "w") as fh:
            fh.write(body)
    else:
        cairosvg.svg2png(bytestring=body.encode(), write_to=out, scale=2)
    print(out)
