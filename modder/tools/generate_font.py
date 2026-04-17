"""
Generate a combined font sprite atlas for IWPO CJK text rendering.

Produces a PNG sprite sheet and a .gly binary glyph metrics file.
The atlas combines:
  - Berlin Sans FB Demi 9pt (ASCII printable chars 0x20-0x7E)
  - Microsoft YaHei 9pt (GB2312 Chinese characters + CJK punctuation)

GLY binary format:
  Header (14 bytes):
    magic:       'GLY\x01\x01\x00' (6 bytes)
    line_height: uint16
    top:         int16  (min_glyph_top, i.e. highest ascent above origin)
    count:       uint32
  Per glyph (14 bytes):
    key:     uint32  (Unicode code point)
    x:       uint16  (x position in sprite)
    y:       uint16  (y position in sprite)
    w:       uint16  (visual width in sprite)
    advance: int16   (horizontal cursor advance)
    left:    int16   (left bearing for drawing offset)

Keys use Unicode code points — GaseousMarble decodes the input string
as UTF-8 via ICU and looks up glyphs by code point.
"""

import math
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont


def get_gb2312_chars():
    """Generate all GB2312 characters with their Unicode code point keys."""
    chars = []
    # GB2312 zones 01-09: symbols, numbers, Latin, Kana, etc. (A1A1-A9FE)
    for high in range(0xA1, 0xAA):
        for low in range(0xA1, 0xFF):
            gbk_bytes = bytes([high, low])
            try:
                ch = gbk_bytes.decode('gbk')
                if ch.isprintable() and ch.strip():
                    chars.append((ord(ch), ch))
            except (UnicodeDecodeError, ValueError):
                pass
    # GB2312 zones 16-87: Chinese characters (B0A1-F7FE)
    for high in range(0xB0, 0xF8):
        for low in range(0xA1, 0xFF):
            gbk_bytes = bytes([high, low])
            try:
                ch = gbk_bytes.decode('gbk')
                if ch.isprintable():
                    chars.append((ord(ch), ch))
            except (UnicodeDecodeError, ValueError):
                pass
    return chars


def generate_font(
    output_dir: str,
    output_name: str = "__ONLINE_font",
    ascii_font: str = "Berlin Sans FB Demi",
    cjk_font: str = "Microsoft YaHei",
    font_size: int = 9,
):
    """Generate the combined sprite atlas PNG + GLY binary."""

    # Build character list: (key, char, font_obj)
    ascii_font_obj = ImageFont.truetype(ascii_font, font_size)
    cjk_font_obj = ImageFont.truetype(cjk_font, font_size)

    glyphs = []  # list of (key, char, font_obj)

    # ASCII printable characters (0x20-0x7E)
    for code in range(0x20, 0x7F):
        ch = chr(code)
        glyphs.append((code, ch, ascii_font_obj))

    # GB2312 characters
    gb_chars = get_gb2312_chars()
    for key, ch in gb_chars:
        glyphs.append((key, ch, cjk_font_obj))

    print(f"Total glyphs: {len(glyphs)} (ASCII: 95, CJK: {len(gb_chars)})")

    # Measure all glyphs
    tmp_img = Image.new('RGBA', (1, 1))
    tmp_draw = ImageDraw.Draw(tmp_img)
    glyph_spacing = 1

    glyph_data = []  # (key, font, char, w, advance, left, top, bottom)
    min_glyph_top = 0
    max_glyph_bottom = 0
    total_line_width = 0
    max_glyph_width = 0

    for key, ch, font_obj in glyphs:
        tmp_draw.font = font_obj
        (l, t, r, b) = [round(v) for v in tmp_draw.textbbox((0, 0), ch)]
        w = r - l
        advance = round(tmp_draw.textlength(ch))

        min_glyph_top = min(min_glyph_top, t)
        max_glyph_bottom = max(max_glyph_bottom, b)
        total_line_width += w + glyph_spacing
        max_glyph_width = max(max_glyph_width, w)

        glyph_data.append((key, font_obj, ch, w, advance, l, t, b))

    total_line_width -= glyph_spacing
    line_height = max_glyph_bottom - min_glyph_top

    print(f"Line height: {line_height}, top offset: {min_glyph_top}")

    # Calculate roughly square sprite dimensions
    sprite_width = max(
        math.ceil(
            (line_height + math.sqrt(line_height**2 + 4 * total_line_width * (line_height + glyph_spacing))) / 2
        ),
        max_glyph_width,
    )

    # Compute actual dimensions with line wrapping
    cur_x = 0
    line_num = 1
    max_line_w = 0
    for key, font_obj, ch, w, advance, l, t, b in glyph_data:
        if cur_x + w > sprite_width and cur_x > 0:
            max_line_w = max(max_line_w, cur_x - glyph_spacing)
            cur_x = 0
            line_num += 1
        cur_x += w + glyph_spacing

    max_line_w = max(max_line_w, cur_x - glyph_spacing)
    sprite_width = max_line_w
    sprite_height = (line_height + glyph_spacing) * line_num - glyph_spacing

    print(f"Sprite size: {sprite_width} x {sprite_height}")

    # Generate sprite and glyph binary
    image = Image.new('RGBA', (sprite_width, sprite_height))
    draw = ImageDraw.Draw(image)

    os.makedirs(output_dir, exist_ok=True)
    png_path = os.path.join(output_dir, output_name + ".png")
    gly_path = os.path.join(output_dir, output_name + ".gly")

    with open(gly_path, 'wb') as f:
        # Header
        f.write(b'GLY\x01\x01\x00')
        f.write(struct.pack('<HhI', line_height, min_glyph_top, len(glyph_data)))

        x = 0
        y = 0
        for key, font_obj, ch, w, advance, l, t, b in glyph_data:
            if x + w > sprite_width and x > 0:
                x = 0
                y += line_height + glyph_spacing

            # Write glyph record
            f.write(struct.pack('<IHHHhh', key, x, y, w, advance, l))

            # Draw glyph into sprite
            draw_x = x - l
            draw_y = y - min_glyph_top
            draw.font = font_obj
            draw.text((draw_x, draw_y), ch, fill='white')

            x += w + glyph_spacing

    image.save(png_path, 'PNG', optimize=True)

    # Stats
    png_size = os.path.getsize(png_path)
    gly_size = os.path.getsize(gly_path)
    print(f"Output: {png_path} ({png_size:,} bytes)")
    print(f"Output: {gly_path} ({gly_size:,} bytes)")
    print(f"Total: {png_size + gly_size:,} bytes")


if __name__ == "__main__":
    output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
    fonts_dir = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
    generate_font(
        output_dir=output_dir,
        output_name="__ONLINE_font",
        ascii_font=os.path.join(fonts_dir, "BRLNSDB.TTF"),   # Berlin Sans FB Demi Bold
        cjk_font=os.path.join(fonts_dir, "msyh.ttc"),        # Microsoft YaHei
        font_size=12,
    )
