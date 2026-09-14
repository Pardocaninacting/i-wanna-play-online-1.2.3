/// ONLINE
// ============================================================================
// GML bitmap-font atlas pack: a pure-GML implementation of the FoxWriting (fw)
// API surface that our GM8.0 templates call.
//
// Why: on UPX-packed + Antidec-protected GM8.0 runners the native FoxWriting
// DLL cannot initialize (its GMAPI layer is version-locked and fails against
// that runner image), which used to abort the game. The converter therefore
// blocks the fw extension for that structural class - and this pack replaces
// the old do-nothing stubs so those games still render CJK text, without any
// DLL, loader or GMAPI dependency.
//
// Assets (deployed next to the exe by the converter when this pack is active):
//   __ONLINE_font.png  - the glyph atlas (white glyphs on transparent, RGBA)
//   __ONLINE_font.gbk  - glyph index:
//       header 12 B: "CGA1" | u16 lineHeight | u16 reserved | u32 count
//       record 12 B: u16 key | u16 x | u16 y | u16 w | u16 advance | i16 rawLeft
//     Records are sorted by key. key is ASCII's byte value, or for a GBK pair
//     1000 + (b0 - 0x81) * 191 + (b1 - 0x40) - the compact form keeps every key
//     below GameMaker 8's 32000 array-index limit (raw GBK codes exceed it).
//
// Glyph placement mirrors GaseousMarble's renderer (the atlas' original
// consumer): the source rect is (x, y, w, lineHeight) - the cell carries the
// glyph's natural vertical placement - and it is drawn at penX + rawLeft.
//
// Scope: GM8.0 only (the templates' #if GM80 branch). Strings are ANSI/GBK,
// exactly like the fw path, so no encoding conversion happens here.
// A missing glyph is skipped but still advances, so punctuation and spacing
// stay sane (the shipped atlas covers GB2312 + kana + fullwidth forms).
// ============================================================================

///// script @cjk_atlas_init
// Loads atlas + index into globals. Idempotent. Returns 1 on success, 0 when
// the assets are missing (the fw_* wrappers then degrade to no-ops).
globalvar @cjkAtlasReady, @cjkAtlasSprite, @cjkAtlasLineH, @cjkAtlasCount;
globalvar @cjkAtlasX, @cjkAtlasY, @cjkAtlasW, @cjkAtlasAdv, @cjkAtlasLeft, @cjkAtlasIdx;
globalvar @cjkAtlasFontN, @cjkAtlasFontSize, @cjkAtlasScale, @cjkAtlasCurFont;
globalvar @cjkAtlasHAlign, @cjkAtlasVAlign, @cjkAtlasLineSpacing, @cjkAtlasFontOX, @cjkAtlasFontOY;
globalvar @cjkAtlasYOffset;
globalvar @cjkLines, @cjkLineW, @cjkLineN;
var _f, _i, _n, _b0, _b1, _b2, _b3, _key, _pat, _fname;
if(@cjkAtlasReady == 1) return 1;
if(@cjkAtlasReady == -1) return 0;
@cjkAtlasReady = -1;
@cjkAtlasLineH = 17;
@cjkAtlasCount = 0;
@cjkAtlasFontN = 0;
@cjkAtlasScale = 1;
@cjkAtlasCurFont = -1;
@cjkAtlasHAlign = 0;
@cjkAtlasVAlign = 0;
@cjkAtlasLineSpacing = -1;
@cjkAtlasFontOX = 0;
@cjkAtlasFontOY = 0;
// Optical baseline shift, baked in by the converter (iwpo.cjk.yoffset, default
// 6 px). The bitmap atlas is a 16pt face whose ink sits higher in the GM line
// box than the FoxWriting/GDI+ text the HUD offsets were tuned against, so the
// glyphs are dropped by this many pixels to line up with the surrounding UI.
@cjkAtlasYOffset = %arg0;
@cjkLines[0] = "";
@cjkLineW[0] = 0;
@cjkLineN = 0;
_pat = "font.png";
_fname = "__ONLINE_" + _pat;
@cjkAtlasSprite = sprite_add(_fname, 0, false, false, 0, 0);
if(!sprite_exists(@cjkAtlasSprite)) return 0;
_pat = "font.gbk";
_f = file_bin_open("__ONLINE_" + _pat, 0);
if(_f < 0) return 0;
file_bin_seek(_f, 4);
_b0 = file_bin_read_byte(_f);
_b1 = file_bin_read_byte(_f);
@cjkAtlasLineH = _b0 + _b1 * 256;
file_bin_seek(_f, 8);
_b0 = file_bin_read_byte(_f);
_b1 = file_bin_read_byte(_f);
_b2 = file_bin_read_byte(_f);
_b3 = file_bin_read_byte(_f);
_n = _b0 + _b1 * 256 + _b2 * 65536 + _b3 * 16777216;
@cjkAtlasCount = _n;
file_bin_seek(_f, 12);
for(_i = 0; _i < _n; _i += 1){
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  _key = _b0 + _b1 * 256;
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  @cjkAtlasX[_i] = _b0 + _b1 * 256;
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  @cjkAtlasY[_i] = _b0 + _b1 * 256;
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  @cjkAtlasW[_i] = _b0 + _b1 * 256;
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  @cjkAtlasAdv[_i] = _b0 + _b1 * 256;
  _b0 = file_bin_read_byte(_f);
  _b1 = file_bin_read_byte(_f);
  _b2 = _b0 + _b1 * 256;
  if(_b2 >= 32768) _b2 = _b2 - 65536;
  @cjkAtlasLeft[_i] = _b2;
  @cjkAtlasIdx[_key] = _i + 1;
}
file_bin_close(_f);
@cjkAtlasReady = 1;
return 1;

///// script @cjk_atlas_glyph
// Resolves one character (single byte or GBK pair at position argument1 of
// argument0) to the glyph slot + 1. Returns 0 when there is no such glyph.
// Sets @cjkGlyphStep to the byte length consumed (1 or 2) and @cjkGlyphAdv to
// the fallback advance used when the glyph is missing.
// The lookup key is the compact form used by the index file: ASCII keeps its
// byte value, a GBK pair becomes 1000 + (b0 - 0x81) * 191 + (b1 - 0x40). Raw
// GBK codes reach 0xFEFE, past GameMaker 8's 32000 array-index limit; the
// compact form tops out at 24965.
globalvar @cjkAtlasIdx, @cjkGlyphSlot, @cjkGlyphStep, @cjkGlyphAdv;
var _c, _c2, _key;
@cjkGlyphStep = 1;
@cjkGlyphAdv = 8;
_c = ord(string_copy(argument0, argument1, 1));
if(_c >= 129){
  if(argument1 < string_length(argument0)){
    _c2 = ord(string_copy(argument0, argument1 + 1, 1));
    if(_c2 >= 64) _key = 1000 + (_c - 129) * 191 + (_c2 - 64);
    else _key = _c;
    @cjkGlyphStep = 2;
  }else{
    _key = _c;
  }
}else{
  _key = _c;
}
@cjkGlyphSlot = @cjkAtlasIdx[_key];
return @cjkGlyphSlot;

///// script @cjk_atlas_font_add
// Registers a font request. argument0 = requested pixel size (pt). The atlas is
// authored at 16pt, so the draw scale is size / 16. Returns a handle >= 1000.
globalvar @cjkAtlasFontN, @cjkAtlasFontSize;
var _h, _size;
_size = argument0;
if(_size <= 0) _size = 16;
_h = 1000 + @cjkAtlasFontN;
@cjkAtlasFontSize[@cjkAtlasFontN] = _size;
@cjkAtlasFontN += 1;
return _h;

///// script @cjk_atlas_wrap
// Wraps argument0 into @cjkLines[0 .. @cjkLineN-1] with per-line widths in
// @cjkLineW[]. argument1 = max line width (<= 0 disables wrapping).
// '#' is GameMaker's in-string newline; CR/LF also break. A CJK string may
// break between any two characters (no word segmentation needed); ASCII words
// are broken at the last space when one is available on the line.
globalvar @cjkAtlasIdx, @cjkAtlasAdv, @cjkAtlasScale, @cjkLines, @cjkLineW, @cjkLineN;
var _len, _i, _step, _slot, _adv, _cur, _curW, _c, _lastSpace, _lastSpaceW, _maxW;
_maxW = argument1;
_len = string_length(argument0);
// NOTE: the @ prefix is mandatory - a bare _cjkLineN would be a different
// (instance) variable, leaving the global line count to grow every frame and
// stacking one extra line under the text on every redraw.
@cjkLineN = 0;
_cur = "";
_curW = 0;
_lastSpace = 0;
_lastSpaceW = 0;
_i = 1;
while(_i <= _len){
  _c = ord(string_copy(argument0, _i, 1));
  if(_c == 13 || _c == 10 || _c == 35){
    @cjkLines[@cjkLineN] = _cur;
    @cjkLineW[@cjkLineN] = _curW;
    @cjkLineN += 1;
    _cur = "";
    _curW = 0;
    _lastSpace = 0;
    _lastSpaceW = 0;
    _i += 1;
  }else{
    _slot = @cjk_atlas_glyph(argument0, _i);
    _step = @cjkGlyphStep;
    _adv = @cjkGlyphAdv;
    if(_slot > 0) _adv = @cjkAtlasAdv[_slot - 1];
    if(_maxW > 0 && _curW + _adv * @cjkAtlasScale > _maxW && _curW > 0){
      if(_c == 32){
        // a space at the break point is consumed instead of drawn
        @cjkLines[@cjkLineN] = _cur;
        @cjkLineW[@cjkLineN] = _curW;
        @cjkLineN += 1;
        _cur = "";
        _curW = 0;
        _lastSpace = 0;
        _lastSpaceW = 0;
        _i += _step;
      }else{
        if(_lastSpace > 0 && _lastSpaceW < _curW){
          // break at the remembered space: keep the tail for the next line
          @cjkLines[@cjkLineN] = string_copy(_cur, 1, _lastSpace - 1);
          @cjkLineW[@cjkLineN] = _lastSpaceW;
          @cjkLineN += 1;
          _cur = string_delete(_cur, 1, _lastSpace);
          _curW = _curW - _lastSpaceW;
          _lastSpace = 0;
          _lastSpaceW = 0;
        }else{
          @cjkLines[@cjkLineN] = _cur;
          @cjkLineW[@cjkLineN] = _curW;
          @cjkLineN += 1;
          _cur = "";
          _curW = 0;
        }
      }
    }else{
      _cur += string_copy(argument0, _i, _step);
      _curW += _adv * @cjkAtlasScale;
      if(_c == 32){
        _lastSpace = string_length(_cur);
        _lastSpaceW = _curW;
      }
      _i += _step;
    }
  }
}
@cjkLines[@cjkLineN] = _cur;
@cjkLineW[@cjkLineN] = _curW;
@cjkLineN += 1;
return @cjkLineN;

///// script @cjk_atlas_draw
// Draws the lines produced by @cjk_atlas_wrap at argument0/argument1 using the
// current alignment, colour and alpha. argument2 = line advance in pixels.
//
// Every destination coordinate is rounded to a whole pixel before the glyph is
// blitted. GameMaker's own font renderer (and the GMS/CJKTEXT atlas path, which
// pre-rounds with round(x - w/2)) always rasterizes text on integer positions;
// a fractional origin makes the D3D sampler filter each glyph quad against its
// neighbours, which shows up as smeared/sheared strokes and a half-pixel
// vertical drift. The atlas is authored so a whole-pixel blit is 1:1.
globalvar @cjkLines, @cjkLineW, @cjkLineN, @cjkAtlasSprite, @cjkAtlasLineH, @cjkAtlasScale;
globalvar @cjkAtlasHAlign, @cjkAtlasVAlign, @cjkAtlasFontOX, @cjkAtlasFontOY, @cjkAtlasCurFont;
globalvar @cjkAtlasYOffset;
var _li, _lx, _ly, _len, _i, _step, _slot, _c, _col, _al, _gx, _gy;
_col = draw_get_color();
_al = draw_get_alpha();
_ly = argument1 + @cjkAtlasYOffset;
if(@cjkAtlasVAlign == 1){
  _ly -= @cjkLineN * argument2 / 2;
}else{
  if(@cjkAtlasVAlign == 2) _ly -= @cjkLineN * argument2;
}
_li = 0;
while(_li < @cjkLineN){
  _ly = round(_ly);
  _lx = argument0;
  if(@cjkAtlasHAlign == 1){
    _lx -= @cjkLineW[_li] / 2;
  }else{
    if(@cjkAtlasHAlign == 2) _lx -= @cjkLineW[_li];
  }
  _lx = round(_lx);
  _len = string_length(@cjkLines[_li]);
  _i = 1;
  while(_i <= _len){
    _slot = @cjk_atlas_glyph(@cjkLines[_li], _i);
    _step = @cjkGlyphStep;
    if(_slot > 0){
      _gx = round(_lx + (@cjkAtlasLeft[_slot - 1] + @cjkAtlasFontOX) * @cjkAtlasScale);
      _gy = round(_ly + @cjkAtlasFontOY * @cjkAtlasScale);
      draw_sprite_part_ext(@cjkAtlasSprite, 0, @cjkAtlasX[_slot - 1], @cjkAtlasY[_slot - 1], @cjkAtlasW[_slot - 1], @cjkAtlasLineH, _gx, _gy, @cjkAtlasScale, @cjkAtlasScale, _col, _al);
      _lx += @cjkAtlasAdv[_slot - 1] * @cjkAtlasScale;
    }else{
      _lx += @cjkGlyphAdv * @cjkAtlasScale;
    }
    _i += _step;
  }
  _ly += argument2;
  _li += 1;
}
return 0;

///// script @cjk_atlas_line_measure
// Width of a single unwrapped line (argument0) at the current scale.
globalvar @cjkAtlasAdv, @cjkAtlasScale;
var _len, _i, _step, _slot, _w;
_w = 0;
_len = string_length(argument0);
_i = 1;
while(_i <= _len){
  _slot = @cjk_atlas_glyph(argument0, _i);
  _step = @cjkGlyphStep;
  if(_slot > 0) _w += @cjkAtlasAdv[_slot - 1] * @cjkAtlasScale; else _w += @cjkGlyphAdv * @cjkAtlasScale;
  _i += _step;
}
return _w;

// ---------------------------------------------------------------------------
// FoxWriting API surface used by the GM8.0 templates.
// ---------------------------------------------------------------------------

///// script fw_add_font
// fw_add_font(name, size, bold, italic, underline) -> font handle (>= 0)
@cjk_atlas_init();
return @cjk_atlas_font_add(argument1);

///// script fw_add_font_from_file
// fw_add_font_from_file(path, size, bold, italic, underline) -> font handle.
// The atlas is self-contained, so the TTF path is accepted and ignored.
@cjk_atlas_init();
return @cjk_atlas_font_add(argument1);

///// script fw_set_font_offset
// fw_set_font_offset(handle, x, y) -> 0. Pixel offset applied when drawing.
// The atlas carries one shared offset (the templates set it once, for the CJK
// font); it is applied to every glyph draw.
globalvar @cjkAtlasFontOX, @cjkAtlasFontOY;
@cjkAtlasFontOX = argument1;
@cjkAtlasFontOY = argument2;
return 0;

///// script fw_draw_set_font
// fw_draw_set_font(handle) -> 0
// The atlas is a bitmap: scaling it DOWN (the templates ask for 9pt against a
// 16pt-authored atlas) turns 12 px CJK glyphs into unreadable 6-7 px mush, so
// the draw scale never drops below 1. Larger requests still scale up.
globalvar @cjkAtlasCurFont, @cjkAtlasScale, @cjkAtlasFontSize, @cjkAtlasFontN;
var _idx, _size;
_idx = argument0 - 1000;
_size = 16;
if(_idx >= 0 && _idx < @cjkAtlasFontN) _size = @cjkAtlasFontSize[_idx];
if(_size <= 0) _size = 16;
@cjkAtlasCurFont = argument0;
@cjkAtlasScale = _size / 16;
if(@cjkAtlasScale < 1) @cjkAtlasScale = 1;
return 0;

///// script fw_draw_set_halign
// fw_draw_set_halign(align) -> 0   (GameMaker fa_left / fa_center / fa_right)
globalvar @cjkAtlasHAlign;
@cjkAtlasHAlign = argument0;
return 0;

///// script fw_draw_set_valign
// fw_draw_set_valign(align) -> 0   (GameMaker fa_top / fa_middle / fa_bottom)
globalvar @cjkAtlasVAlign;
@cjkAtlasVAlign = argument0;
return 0;

///// script fw_draw_set_line_spacing
// fw_draw_set_line_spacing(px) -> 0   (< 0 restores the atlas line height)
globalvar @cjkAtlasLineSpacing;
@cjkAtlasLineSpacing = argument0;
return 0;

///// script fw_draw_text_ext
// fw_draw_text_ext(x, y, str, maxW) -> 0
globalvar @cjkAtlasReady, @cjkAtlasLineSpacing, @cjkAtlasLineH, @cjkAtlasScale;
var _adv;
@cjk_atlas_init();
if(@cjkAtlasReady != 1) return 0;
@cjk_atlas_wrap(argument2, argument3);
_adv = @cjkAtlasLineSpacing;
if(_adv <= 0) _adv = @cjkAtlasLineH * @cjkAtlasScale;
@cjk_atlas_draw(argument0, argument1, _adv);
return 0;

///// script fw_draw_text
// fw_draw_text(x, y, str) -> 0
return fw_draw_text_ext(argument0, argument1, argument2, 0);

///// script fw_string_width
// fw_string_width(str) -> pixel width of the single line
@cjk_atlas_init();
return @cjk_atlas_line_measure(argument0);

///// script fw_string_width_ext
// fw_string_width_ext(str, sep, maxW) -> widest wrapped line
globalvar @cjkLineW, @cjkLineN;
var _i, _w;
@cjk_atlas_init();
@cjk_atlas_wrap(argument0, argument2);
_w = 0;
_i = 0;
while(_i < @cjkLineN){
  if(@cjkLineW[_i] > _w) _w = @cjkLineW[_i];
  _i += 1;
}
return _w;

///// script fw_string_height_ext
// fw_string_height_ext(str, sep, maxW) -> height of the wrapped text
globalvar @cjkLineN, @cjkAtlasLineSpacing, @cjkAtlasLineH, @cjkAtlasScale;
var _adv;
@cjk_atlas_init();
@cjk_atlas_wrap(argument0, argument2);
_adv = @cjkAtlasLineSpacing;
if(_adv <= 0) _adv = @cjkAtlasLineH * @cjkAtlasScale;
return @cjkLineN * _adv;

///// script fw_string_height
// fw_string_height(str) -> height of one line
return fw_string_height_ext(argument0, -1, 0);

