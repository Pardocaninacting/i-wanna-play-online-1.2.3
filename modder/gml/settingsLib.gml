/// ONLINE
// ============================================================================
// Settings menu: declarative row table, tab-0 layout and the account rows.
//
// The Settings tab used to be hand-laid-out with per-button coordinates and row
// indices that drifted with the PLAYER_LIST compile flag (row 7 meant "pick a
// player" in one build and "reconnect" in the other, with the vk_enter branch
// duplicated). Draw, keyboard, mouse and the action handlers all read one table
// now, and the geometry lives in one place:
//
//   global.__ONLINE_stgKind[i]  0 header, 1 status, 2 text, 3 select, 4 toggle, 5 button, 7 double header
//   global.__ONLINE_stgAct[i]   action id (@stg_act / @stg_act_dir dispatch it)
//   global.__ONLINE_stgLabel[i] label text
//   global.__ONLINE_stgX[i]     label x, global.__ONLINE_stgCX[i]/global.__ONLINE_stgCW[i] control x + width
//   global.__ONLINE_stgY[i]     row y (top)
//
// Layout (master-detail; menu_mock/DESIGN.md is the design source):
//
//   +------------------------------------------------------------+
//   | [Settings][Saves][Rating][Keys][Sync][Skins]               |
//   | CONNECTION              |  <detail for the focused row>    |
//   |  * Online   Server: ..  |                                  |
//   |  Reconnect now          |                                  |
//   | ACCOUNT                 |                                  |
//   |  Name:        QoLFirst  |                                  |
//   | GAMEPLAY                |                                  |
//   |  Lerp:             ON   |                                  |
//   |  ... (the list scrolls) |                                  |
//   +------------------------------------------------------------+
//   hint line (follows the focused row)                  [Close]
//
//   full layout: 268px list + 372px detail; narrow: list only (@detW = 0).
//
// GameMaker-8 constraints honoured here: no #else (the render pipeline knows
// #if/#if not/#endif only), no 8.1+-only functions (point_in_rectangle,
// string_trim, ...), and every globalvar declared by the script that owns it.
// ============================================================================

///// script @stg_init
// One-time defaults for the row table, the toast/clear state, the panel geometry
// and the account fallbacks.
//
// Called from worldCreate on EVERY create, because game_restart wipes globals:
// the acc* values are re-read by @account_load right after, and the fallbacks
// here keep the panel renderable even if that ever fails.
// args: none -> 0
var _w, _h;
global.__ONLINE_stgN = 0;
global.__ONLINE_stgHeight = 0;
global.__ONLINE_stgClearRow = -1;
global.__ONLINE_stgClearOld = "";
global.__ONLINE_stgToastMsg = "";
global.__ONLINE_stgToastKind = 0;
global.__ONLINE_stgToastUntil = 0;
global.__ONLINE_stgStatusMsg = "";
global.__ONLINE_accName = "";
global.__ONLINE_accPassword = "";
global.__ONLINE_accSource = 0;
global.__ONLINE_accStore = 0;
global.__ONLINE_accEnvManaged = 0;
global.__ONLINE_accWritePath = "";
// layout constants (the gate checks the whole table against the panel)
global.__ONLINE_stgRowH = 22;
global.__ONLINE_stgHeadH = 15;
// Panel geometry is derived by @stg_layout (worldCreate primes it via @stg_init,
// worldDrawGui re-derives it per frame) - a hardcoded size in the draw path once
// forked the two and the row table overflowed the panel.
// panel geometry + layout mode (see @stg_layout - narrow is the shipped layout)
@stgScroll = 0;
@stgFirst = 0;
@stgSbDrag = false;   // scrollbar thumb grab in progress
@stgSbGrab = 0;       // px offset of the grab point inside the thumb
@kbHoldUp = 0;        // held-frame counters drive the nav acceleration
@kbHoldDn = 0;
@stgNavKey = 0;   // set by the keyboard handler; the wheel must not follow
// The row table's per-row argument array. Only rows that carry one (save entries)
// write it, but the detail pane, @stg_value and the dispatcher all read it, so index
// 0 is created here: on GMS reading a variable that was never created aborts with
// "trying to index a variable which is not an array", and a build with no saves
// never added such a row.
global.__ONLINE_stgArg[0] = 0;
@stgTextDY = -2;   // text sits 2px lower than its box otherwise
@menuModePref = 0;
@menuMode = 0;
@colW = 600;
@detW = 0;
@spW = 600;
@spH = 460;
@spX = 0;
@spY = 0;
@stg_layout();
@tabH = 26;
@contentY = @spY + @tabH + 8;
@footerY = @spY + @spH - 34;   // footer separator y; hint + Close live below it
return 0;

///// script @stg_layout
// Picks the menu layout for the current view-port and (re)computes the panel
// geometry. Cheap - a handful of comparisons - so the draw code calls it every
// frame; that also keeps the menu right when a game changes its view port
// between rooms.
//
//   narrow : content column only (@detW = 0)
//   full   : content 268px + detail 372px, when the port is wide enough
//            (or when the per-game ini forces it, [config] menu_mode = 2)
//
// The @sp* / @colW / @detW variables are the CALLER's (world instance) - never
// declared globalvar here, for the same reason @account_apply must not.
// args: none -> 0
var _w, _h, _full;
// Never READ @hudWinW/@hudWinH here. They are set by the Draw GUI event, and
// @stg_init runs from Create - on GMS2.3 reading an instance variable that was
// never assigned is a fatal error ("not set before reading it"), which is exactly
// how this crashed on the GMS side. Seed from the engine's own metrics instead,
// then fall back, then publish the result for the draw pass.
#if STUDIO
_w = display_get_gui_width();
_h = display_get_gui_height();
#endif
#if not STUDIO
_w = 0;
_h = 0;
#endif
if(_w < 1 || _h < 1){
  if(view_enabled){
    _w = view_wport[0];
    _h = view_hport[0];
  }else{
    _w = room_width;
    _h = room_height;
  }
}
if(_w < 1) _w = 640;
if(_h < 1) _h = 480;
_full = false;
if(@menuModePref == 2) _full = true;
if(@menuModePref == 0 && _w >= 660 && _h >= 420) _full = true;
if(_full){
  @colW = 268;
  @detW = 372;
}else{
  @colW = 600;
  @detW = 0;
}
@spW = @colW + @detW;
@spH = 460;
if(@spW > _w - 16){
  // not enough room: shrink, and give up the detail column before squeezing the
  // content below a usable width
  @spW = _w - 16;
  @colW = @spW - @detW;
  if(@detW > 0 && @colW < 260){
    @detW = 0;
    @colW = @spW;
  }
}
if(@spH > _h - 16) @spH = _h - 16;
@spX = floor((_w - @spW) / 2);
@spY = floor((_h - @spH) / 2);
if(@spX < 0) @spX = 0;
if(@spY < 0) @spY = 0;
@menuMode = 0;
if(@detW > 0) @menuMode = 1;
return 0;

///// script @stg_build_rows
// Rebuilds the tab-0 table for the current panel geometry.
// args: contentY -> 0
var _y, _cl, _cf, _btnW, _fw, _ctlX;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
_cl = @spX + 16;                 // left column label x (content left edge)
_cf = @spX + 16 + 110;           // account field x
_btnW = @colW - 32;
_ctlX = @spX + @colW - 16 - 130;   // every control hugs the content right edge
_fw = @colW - 32 - 110;          // account field width follows the column
if(_fw < 120) _fw = 120;
// --- connection
@stg_row_add(0, 0, "CONNECTION", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(1, 0, "", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(5, 11, "", _cl, _y, _btnW, 1, _cl); _y += global.__ONLINE_stgRowH;
@stg_row_add(5, 15, "", _cl, _y, _btnW, 1, _cl); _y += global.__ONLINE_stgRowH;
// --- account
_y += 6;
@stg_row_add(0, 0, "ACCOUNT", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(2, 12, "Name", _cl, _y, _fw, 0, _cf); _y += global.__ONLINE_stgRowH + 2;
@stg_row_add(2, 13, "Password", _cl, _y, _fw, 0, _cf); _y += global.__ONLINE_stgRowH + 2;
@stg_row_add(3, 14, "Store in", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
// --- gameplay / display side by side
_y += 6;
// Gameplay and Display are always ONE column (maintainer decision):
// the detail pane carries the extra breadth, and a second column only
// made both halves harder to scan.
@stg_row_add(0, 0, "GAMEPLAY", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(3, 1, "Team", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 2, "Lerp", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 3, "Save", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 4, "Fast", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(3, 8, "PVP", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 9, "Bullets", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(0, 0, "DISPLAY", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(3, 5, "Visual", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 6, "Indicator", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(3, 7, "Spec Cam", _cl, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
#if PLAYER_LIST
@stg_row_add(5, 10, "Player Objects", _cl, _y, 130, 1, _ctlX); _y += global.__ONLINE_stgRowH;
#endif
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_fit_rows
// How many rows fit when row argument0 is drawn at argument1 and the band ends
// at argument2 - uses the table's own y values, so header heights are honoured.
// args: firstRow, y, bottom -> count
var _i, _base, _n, _h;
_i = argument0;
_base = global.__ONLINE_stgY[_i];
_n = 0;
while(_i < global.__ONLINE_stgN){
  // real height of row _i: the next row's y (headers are shorter)
  if(_i + 1 < global.__ONLINE_stgN){
    _h = global.__ONLINE_stgY[_i + 1] - global.__ONLINE_stgY[_i];
  }else{
    _h = global.__ONLINE_stgRowH;
  }
  if(global.__ONLINE_stgY[_i] - _base + argument1 + _h > argument2) break;
  _i += 1;
  _n += 1;
}
return _n;

///// script @stg_hit_row_view
// Mouse hit test in VIEW space: rows are drawn at stgY[i] - argument2, so the
// pointer is mapped through the same values (one grid, no drift).
// args: mx, my, yOffset -> row index / -1
var _i, _y, _h;
_i = 0;
while(_i < global.__ONLINE_stgN){
  _y = global.__ONLINE_stgY[_i] - argument2;

  if(_i + 1 < global.__ONLINE_stgN){

    _h = global.__ONLINE_stgY[_i + 1] - global.__ONLINE_stgY[_i];

  }else{

    _h = global.__ONLINE_stgRowH;

  }
  if(argument1 >= _y - 2 && argument1 < _y + _h - 2){
    // the row ends at its control's right edge - a fixed "+200" used to extend
    // the hover/click area well past the visible widget
    if(argument0 >= global.__ONLINE_stgX[_i] - 6 && argument0 < global.__ONLINE_stgCX[_i] + global.__ONLINE_stgCW[_i] + 8) return _i;
  }
  _i += 1;
}
return -1;

///// script @stg_wrap
// Draws text wrapped to argument3 px, at most argument4 lines, and returns the
// height used. GM8 has no text wrapping and the detail pane needs it for the
// description and for long single-token values such as a store path.
// args: x, y, text, width, maxLines -> height
var _rest, _line, _word, _sp, _h, _cnt, _fit;
_rest = argument2;
_h = 0;
_cnt = 0;
while(_rest != "" && _cnt < argument4){
  _line = "";
  while(_rest != ""){
    _sp = string_pos(" ", _rest);
    if(_sp > 0){
      _word = string_copy(_rest, 1, _sp - 1);
    }else{
      _word = _rest;
    }
    if(_line == "" && string_width(_word) > argument3 && string_length(_word) > 1){
      // No space to break at and the token does not fit: take the longest prefix
      // that does, and leave the remainder for the next line. (The old version cut
      // a single character, which never brought a long path inside the column.)
      _fit = string_length(_word);
      while(_fit > 1){
        if(string_width(string_copy(_word, 1, _fit)) <= argument3) break;
        _fit -= 1;
      }
      _line = string_copy(_word, 1, _fit);
      _rest = string_copy(_rest, _fit + 1, string_length(_rest) - _fit);
      break;
    }
    if(_line == ""){
      _line = _word;
    }else if(string_width(_line + " " + _word) <= argument3){
      _line = _line + " " + _word;
    }else{
      break;
    }
    if(_sp > 0){
      _rest = string_delete(_rest, 1, _sp);
    }else{
      _rest = "";
    }
  }
  draw_text(argument0, argument1 + _h, _line);
  _h += 16;
  _cnt += 1;
  if(_rest == "") break;
}
return _h;

///// script @stg_detail_desc
// Description for a row, keyed by action id so the wording lives in one place.
// Every statement here is about behaviour that exists in the code.
// args: act -> text
var _a;
_a = argument0;
// a pending destructive confirmation is cancelled by any other action
if(global.__ONLINE_stgClearRow >= 0 && _a != global.__ONLINE_stgClearRow) @acc_clear_cancel();
if(_a == 11) return "Drop the current connection and connect again.";
if(_a == 15) return "Save the account and reconnect with the new identity. No restart needed.";
if(_a == 12) return "Your in-game name. It is written to the account store and sent to the server when you connect.";
if(_a == 13) return "Session key: players who use the same key meet each other. It is not an account password and may be empty.";
if(_a == 14) return "Where name and key are saved. Global covers every game on this PC.";
if(_a == 1) return "Team colour, used for names and the roster.";
if(_a == 2) return "Interpolate remote players between network updates: smoother, but about one update behind.";
if(_a == 3) return "Shared online saves. The T key toggles this while playing.";
if(_a == 4) return "Fast save/load path, for engines that restart the room on load.";
if(_a == 8) return "Player versus player. Bullets stay visible while it is on.";
if(_a == 9) return "Share your bullets with the room. Locked on while PVP is enabled.";
if(_a == 5) return "How other players are drawn: full, names only, or hidden.";
if(_a == 6) return "Direction indicator above remote players.";
if(_a == 7) return "Spectator camera mode.";
if(_a == 20) return "Enter applies this save. F toggles favourite, 1-8 assigns a hotkey, Del clears it.";
if(_a == 21) return "Show only favourite saves.";
if(_a == 22) return "Deletes non-favourite saves.";
if(_a == 10) return "Choose which player object drives your character.";
if(_a >= 40 && _a <= 50) return "Rebind this action. Enter starts the capture, then press the key you want; Esc cancels.";
if(_a == 52) return "Restore every binding above to its default.";
if(_a == 53) return "Sends the listed global variables to everyone in the room, on save and whenever their bits change.";
if(_a == 55) return "A player skin from iwposkins. Enter applies it; the preview above shows its idle animation.";
if(_a == 56) return "When another player uses a skin you do not have, fetch it automatically.";
if(_a == 57) return "Unload the current skin and return to the game's default player sprite.";
if(_a == 54) return "Sent on save and whenever its bits change. Entries whose global is missing in this game are skipped (see Present).";
if(_a == 30) return "Ratings are stored per game on the server; everyone on this server shares the same listing.";
if(_a == 31) return "Your rating for this game. Left/Right steps through, digits 1-5 set directly, 0 means no rating.";
if(_a == 32) return "Whether you have cleared this game. Sent together with the stars.";
if(_a == 33) return "The server's response to your last submission. Two submissions need a few seconds between them.";
if(_a == 34) return "Sends the rating to the server.";
return "";

///// script @stg_draw_detail
// Draws the detail column for one row (full layout only: @detW > 0).
// Everything here is local - the previous version kept scratch state in
// @-prefixed instance variables and one of them could be read unset, which GM8
// treats as a fatal "Cannot compare arguments".
// args: row -> 0
var _a, _k, _x, _w, _y, _val, _i, _n, _head, _cnt, _txt, _fn, _acts, _vh;
_a = global.__ONLINE_stgAct[argument0];
_k = global.__ONLINE_stgKind[argument0];
_x = @spX + @colW + 12;
_w = @detW - 24;
_y = @stgTop + 2;
// column separator
draw_set_color(make_color_rgb(70, 80, 95));
draw_rectangle(@spX + @colW, @stgTop, @spX + @colW, @stgBottom, false);
// title
draw_set_halign(fa_left);
draw_set_color(c_white);
_txt = global.__ONLINE_stgLabel[argument0];
if(_txt == "") _txt = @stg_value(argument0);
if(_k == 1) _txt = "Connection";
if(_a == 20) _txt = "Save " + string(global.__ONLINE_stgArg[argument0] + 1);
draw_text(_x, _y, _txt);
_y += 22;
// value card (green frame when a toggle is on); the rating stars replace the
// card for the Stars row and sit at a FIXED slot (@stgTop + 24) so the click
// handler in worldDrawGui can hit-test them without replicating this layout
_val = @stg_value(argument0);
if(_a >= 40 && _a <= 50){
  // big key cap in the detail column (mock keysRows)
  draw_set_color(make_color_rgb(35, 35, 40));
  draw_rectangle(_x, _y, _x + 24 + string_width(_val) + 24, _y + 26, false);
  draw_set_color(make_color_rgb(225, 205, 90));
  draw_rectangle(_x, _y, _x + 24 + string_width(_val) + 24, _y + 26, true);
  draw_set_color(c_white);
  draw_text(_x + 12, _y + 6 + @stgTextDY, _val);
  _y += 36;
}
if(_a == 55){
  @stg_skin_preview(argument0, _x, _y);
  _y += 124;
}
if(_k == 3 && _a == 31){
  _sy = @stgTop + 24;
  for(_i = 1; _i <= 5; _i += 1){
    _sx = _x + (_i - 1) * 30;
    if(_i <= @rStars){
      draw_set_color(make_color_rgb(220, 190, 60));
    }else{
      draw_set_color(make_color_rgb(45, 45, 50));
    }
    draw_rectangle(_sx, _sy, _sx + 26, _sy + 22, false);
    draw_set_color(make_color_rgb(90, 90, 96));
    draw_rectangle(_sx, _sy, _sx + 26, _sy + 22, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_sx + 13, _sy + 3 + @stgTextDY, string(_i));
  }
  draw_set_halign(fa_left);
  _y = _sy + 32;
}
if((_k == 4 || _k == 3 || _k == 2) && _val != "" && _a != 31){
  if(_k == 4 && _val == "ON"){
    draw_set_color(make_color_rgb(50, 170, 80));
  }else{
    draw_set_color(make_color_rgb(95, 95, 100));
  }
  draw_rectangle(_x, _y, _x + min(_w, 24 + string_width(_val) + 24), _y + 22, true);
  draw_set_color(c_white);
  @stg_text_cjk(_x + 10, _y + 4 + @stgTextDY, _val, 0);
  _y += 32;
}
// status row: state card in the status colour (there is no latency measure)
if(_k == 1){
  _val = @stg_status_text();
  draw_set_color(@stg_status_color());
  draw_rectangle(_x, _y, _x + min(_w, 24 + string_width(_val) + 24), _y + 22, true);
  draw_set_color(c_white);
  draw_text(_x + 10, _y + 4 + @stgTextDY, _val);
  _y += 32;
}
// section context: walk back to this row's header, then count its options
_head = "";
_cnt = 0;
_i = argument0;
while(_i > 0){
  if(global.__ONLINE_stgKind[_i] == 0) break;
  _i -= 1;
}
if(global.__ONLINE_stgKind[_i] == 0){
  _head = global.__ONLINE_stgLabel[_i];
  _i += 1;
  while(_i < global.__ONLINE_stgN){
    if(global.__ONLINE_stgKind[_i] == 0) break;
    if(global.__ONLINE_stgKind[_i] != 1) _cnt += 1;
    _i += 1;
  }
}
if(string_length(_head) > 0){
  draw_set_color(make_color_rgb(120, 126, 134));
  if(_cnt == 1){
    draw_text(_x, _y, _head + " - 1 option");
  }else{
    draw_text(_x, _y, _head + " - " + string(_cnt) + " options");
  }
  _y += 18;
}
// description (wrapped to the column)
_txt = @stg_detail_desc(_a);
if(string_length(_txt) > 0){
  draw_set_color(make_color_rgb(190, 195, 200));
  _y += 4;
  _y += @stg_wrap(_x, _y, _txt, _w, 6);
}
// facts: only fields that exist in the engine (see GML_COMPAT/DESIGN section 9)
_fn = 0;
if(_a == 12){
  global.__ONLINE_detFK[0] = "Store";
  global.__ONLINE_detFV[0] = global.__ONLINE_accGlobalPath;
  _fn = 1;
}
if(_a == 13){
  global.__ONLINE_detFK[0] = "State";
  if(string_length(global.__ONLINE_accPassword) > 0){
    global.__ONLINE_detFV[0] = "set (masked)";
  }else{
    global.__ONLINE_detFV[0] = "empty";
  }
  _fn = 1;
}
if(_a == 20){
  @stgSvI = global.__ONLINE_stgArg[argument0];
  // The entry may be gone, or never existed: @stg_init primes index 0 of the
  // save arrays, so clamping here guarantees the reads below cannot hit an
  // undefined array (GMS aborts on that, GM8 does not).
  if(@stgSvI < 0 || @stgSvI >= @saveHistCount) @stgSvI = 0;
  global.__ONLINE_detFK[0] = "Room";  global.__ONLINE_detFV[0] = @stg_room_name(@stgSvI);
  global.__ONLINE_detFK[1] = "Position"; global.__ONLINE_detFV[1] = string(round(@saveHistX[@stgSvI])) + ", " + string(round(@saveHistY[@stgSvI]));
  global.__ONLINE_detFK[2] = "Gravity"; global.__ONLINE_detFV[2] = string(@saveHistGrav[@stgSvI]);
  if(@saveHistGrav[@stgSvI] > 0) global.__ONLINE_detFV[2] = "+" + global.__ONLINE_detFV[2];
  global.__ONLINE_detFK[3] = "Player";  global.__ONLINE_detFV[3] = @saveHistName[@stgSvI];
  global.__ONLINE_detFK[4] = "Saved";   global.__ONLINE_detFV[4] = @save_age_text(@stgSvI);
  global.__ONLINE_detFK[5] = "Hotkey";  global.__ONLINE_detFV[5] = string(@saveHistHotkey[@stgSvI]);
  if(@saveHistHotkey[@stgSvI] <= 0) global.__ONLINE_detFV[5] = "none";
  global.__ONLINE_detFK[6] = "Favourite"; global.__ONLINE_detFV[6] = @stg_onoff(@saveHistFav[@stgSvI]);
  _fn = 7;
}
if(_a == 11 || _a == 15){
  global.__ONLINE_detFK[0] = "Status"; global.__ONLINE_detFV[0] = @stg_status_text();
  global.__ONLINE_detFK[1] = "Server"; global.__ONLINE_detFV[1] = @stg_server_text();
  _fn = 2;
}
if(_k == 1){
  global.__ONLINE_detFK[0] = "Server";
  global.__ONLINE_detFV[0] = @stg_server_text();
  _fn = 1;
}
if(_a == 55){
  @stgI = global.__ONLINE_stgArg[argument0];
  @skin_parse(@stgI);   // the facts read parsed fields; cheap once parsed
  global.__ONLINE_detFK[0] = "Maker";  global.__ONLINE_detFV[0] = @skinMaker[@stgI];
  global.__ONLINE_detFK[1] = "Source"; global.__ONLINE_detFV[1] = @skinSource[@stgI];
  @skFTotal = 0;
  for(@skFJ = 0; @skFJ < 7; @skFJ += 1) @skFTotal += @skinFrames[@stgI, @skFJ];
  global.__ONLINE_detFK[2] = "Frames"; global.__ONLINE_detFV[2] = string(@skFTotal);
  global.__ONLINE_detFK[3] = "Status";
  if(!@skinHas[@stgI, 0]){
    global.__ONLINE_detFV[3] = "[!] no idle.png";
  }else if(@stgI == @skinLoaded){
    global.__ONLINE_detFV[3] = "loaded";
  }else{
    global.__ONLINE_detFV[3] = "not loaded";
  }
  _fn = 4;
}
if(_a == 54){
  @stgI = global.__ONLINE_stgArg[argument0];
  global.__ONLINE_detFK[0] = "Global";  global.__ONLINE_detFV[0] = "global." + @syncName[@stgI];
  global.__ONLINE_detFK[1] = "Bits";    global.__ONLINE_detFV[1] = string(@syncCount[@stgI]);
  global.__ONLINE_detFK[2] = "Slots";   global.__ONLINE_detFV[2] = string(@syncSlotCount[@stgI]) + " x 32-bit";
  global.__ONLINE_detFK[3] = "Present";
  if(variable_global_exists(@syncName[@stgI])){
    global.__ONLINE_detFV[3] = "yes";
  }else{
    global.__ONLINE_detFV[3] = "no - skipped";
  }
  _fn = 4;
}
if(_a == 33){
  global.__ONLINE_detFK[0] = "State";   global.__ONLINE_detFV[0] = @stg_rating_status();
  global.__ONLINE_detFK[1] = "Stars";   global.__ONLINE_detFV[1] = string(@rStars) + " / 5";
  global.__ONLINE_detFK[2] = "Cleared"; global.__ONLINE_detFV[2] = @stg_onoff(@rCleared);
  _fn = 3;
}
if(_a == 14){
  global.__ONLINE_detFK[0] = "This folder";
  global.__ONLINE_detFV[0] = global.__ONLINE_accLocalPath;
  global.__ONLINE_detFK[1] = "Env override";
  global.__ONLINE_detFV[1] = "IWPO_NAME / IWPO_PASSWORD";
  _fn = 2;
}
if(_fn > 0){
  // key column measured from the longest key: a fixed 80px let "This folder"
  // and "Env override" run into their values
  _kw = 72;
  _i = 0;
  while(_i < _fn){
    if(string_width(global.__ONLINE_detFK[_i]) + 10 > _kw) _kw = string_width(global.__ONLINE_detFK[_i]) + 10;
    _i += 1;
  }
  if(_kw > _w - 60) _kw = _w - 60;
  _y += 8;
  draw_set_color(make_color_rgb(70, 80, 95));
  draw_rectangle(_x, _y, _x + _w, _y + 1, false);
  _y += 8;
  _i = 0;
  while(_i < _fn){
    draw_set_color(make_color_rgb(120, 126, 134));
    draw_text(_x, _y + @stgTextDY, global.__ONLINE_detFK[_i]);
    draw_set_color(c_white);
    // wrap instead of truncating: a store path is long and the tail (the file
    // name) is the informative part, so cutting it off hid what the row was for.
    _vh = @stg_wrap(_x + _kw, _y + @stgTextDY, global.__ONLINE_detFV[_i], _w - _kw - 4, 2);
    // @stg_wrap measures with string_width; if a font under-reports, the line could
    // still run past the column, so the clamp below is a hard guarantee.
    if(_vh > 16) _y += (_vh - 16);
    _y += 16;
    _i += 1;
  }
}
// the row's action hint, at the bottom of the column
_acts = "";
if(_a == 12 || _a == 13) _acts = "Enter = edit";
if(_a == 14) _acts = "Left/Right = switch store";
if(_a == 11 || _a == 15) _acts = "Enter = run";
if(_a == 10) _acts = "Enter = pick";
if(_a == 20) _acts = "Enter = apply   F = favourite   1-8 = hotkey";
if(_a == 21) _acts = "Left/Right = toggle";
if(_a >= 40 && _a <= 50) _acts = "Enter = rebind";
if(_a == 52) _acts = "Enter = reset";
if(_a == 55) _acts = "Enter = apply";
if(_a == 57) _acts = "Enter = clear";
if(_a == 31) _acts = "Left/Right = change   1-5 = set";
if(_a == 34) _acts = "Enter = submit";
if(_a == 22){
  if(global.__ONLINE_stgClearRow == 22) _acts = "Click again to confirm"; else _acts = "Click to clear";
}
if(string_length(_acts) > 0){
  draw_set_color(make_color_rgb(150, 190, 230));
  draw_text(_x, @stgBottom - 18 + @stgTextDY, _acts);
}
return 0;
///// script @stg_plural
// args: n -> "s" or ""
if(argument0 == 1) return "";
return "s";

///// script @stg_fit_text
// Cuts text to argument1 px, appending "..." when it had to. GM8 has no
// ellipsis, and the detail column is narrow.
// args: text, width -> text
var _s, _n;
_s = argument0;
if(string_width(_s) <= argument1) return _s;
_n = string_length(_s);
while(_n > 1){
  if(string_width(string_copy(_s, 1, _n) + "...") <= argument1) break;
  _n -= 1;
}
return string_copy(_s, 1, _n) + "...";

///// script @kb_repeat
// Key repeat for menu navigation: 1 on the initial press, then again after
// argument1 frames of holding, then every argument2 frames. Only one key repeats
// at a time, so pressing another key takes over immediately.
// Two pitfalls handled here:
//   - the press frame can be consumed by another handler before this script runs
//     (the tab-strip focus block does exactly that): arm on the held state too,
//     or a held key after a tab switch never repeats at all
//   - GM8 re-fires keyboard_check_pressed on OS auto-repeat: a re-press while the
//     key is already armed must not reset the wait, or the internal rhythm never
//     outruns the OS repeat rate (~16/s)
// args: key, delayFrames, repeatFrames -> 1/0
var _k;
_k = argument0;
if(keyboard_check_pressed(_k) && @kbRepeatKey != _k){
  // fresh press (or takeover from another key)
  @kbRepeatKey = _k;
  @kbRepeatWait = argument1;
  return 1;
}
if(!keyboard_check(_k)){
  if(@kbRepeatKey == _k) @kbRepeatKey = -1;   // released: a re-press must re-arm
  return 0;
}
if(@kbRepeatKey != _k){
  // held but never armed: the press frame was consumed elsewhere - arm now
  @kbRepeatKey = _k;
  @kbRepeatWait = argument1;
  return 0;
}
if(@kbRepeatWait > 0){
  @kbRepeatWait -= 1;
  return 0;
}
@kbRepeatWait = argument2;
return 1;

///// script @stg_draw_table
// The shared menu panel renderer: scrollable row table, scrollbar, detail
// column, transient message and the footer hint. Used by every tab that is
// table-driven, so Settings and Saves cannot drift apart.
// The caller builds the row table first (@stg_build_rows / @stg_build_saves).
// args: none -> 0
		// QoL: one declarative table drives the layout (see gml/settingsLib.gml).
		// NOTE: the caller builds the row table (@stg_build_rows for Settings,
		// @stg_build_saves for Saves). Building it here silently replaced the
		// Saves table with the settings rows - which is exactly what happened.
		// The focused row must be a real option: a frame that starts with a header
		// or the status row would show that in the detail pane and highlight it.
		if(@kbRow[0] < 0) @kbRow[0] = @stg_first_row();
		if(@kbRow[0] >= global.__ONLINE_stgN) @kbRow[0] = @stg_first_row();
		if(global.__ONLINE_stgKind[@kbRow[0]] == 0 || global.__ONLINE_stgKind[@kbRow[0]] == 1){
			@kbRow[0] = @stg_first_row();
		}
		// Scrollable viewport. It scrolls by ROW INDEX, not by pixels: the table is
		// drawn on its own grid below @stgTop, so a row can never be half visible and
		// the pointer/focus mapping can never drift by a row (that was the bug).
		@stgTop = @contentY;
		@stgBottom = @footerY - 6;
		@stgViewH = @stgBottom - @stgTop;
		if(@stgFirst < 0) @stgFirst = 0;
		if(@stgFirst >= global.__ONLINE_stgN) @stgFirst = global.__ONLINE_stgN - 1;
		if(@stgFirst < 0) @stgFirst = 0;
		// Largest allowed first row: walk BACKWARDS from the last row accumulating
		// real heights until a screenful fits - that is the point past which the
		// band would show empty space. (The old "N - fit" moved with the current
		// first row, so late in the list it stopped limiting anything.)
		@stgMaxFirst = global.__ONLINE_stgN - 1;
		@stgAccum = 0;
		@stgBI = global.__ONLINE_stgN - 1;
		while(@stgBI >= 0){
			if(@stgBI + 1 < global.__ONLINE_stgN){
				@stgAccum += global.__ONLINE_stgY[@stgBI + 1] - global.__ONLINE_stgY[@stgBI];
			}else{
				@stgAccum += global.__ONLINE_stgRowH;
			}
			if(@stgAccum > @stgViewH) break;
			@stgMaxFirst = @stgBI;
			@stgBI -= 1;
		}
		if(@stgMaxFirst < 0) @stgMaxFirst = 0;
		// CLAMP FIRST, then fit: the previous order fitted against an out-of-range
		// first row and drew a single row for one frame (the flicker at the bottom).
		if(@stgFirst > @stgMaxFirst) @stgFirst = @stgMaxFirst;
		if(@stgFirst < 0) @stgFirst = 0;
		if(@kbFocus == 1 && @stgNavKey == 1){
			// keyboard move: pull the focused row back into the band, one row at a time
			if(@kbRow[0] < @stgFirst) @stgFirst = @kbRow[0];
			@stgGuard = 0;
			while(@stgGuard < 64){
				@stgFit = @stg_fit_rows(@stgFirst, @stgTop + 2, @stgBottom);
				if(@stgFit < 1) @stgFit = 1;
				if(@kbRow[0] < @stgFirst + @stgFit) break;
				@stgFirst += 1;
				@stgGuard += 1;
			}
			if(@stgFirst > @stgMaxFirst) @stgFirst = @stgMaxFirst;
		}
		@stgNavKey = 0;
		@stgFit = @stg_fit_rows(@stgFirst, @stgTop + 2, @stgBottom);
		if(@stgFit < 1) @stgFit = 1;
		// scrollbar geometry lives up here so a drag can move @stgFirst before the
		// row mapping (@stgYOff) is fixed for this frame
		@sbShow = (global.__ONLINE_stgN > @stgFit);
		@sbX = @spX + @colW - 10;
		@sbH = (@stgBottom - @stgTop - 2) * @stgFit / max(1, global.__ONLINE_stgN);
		if(@sbH < 16) @sbH = 16;
		if(@stgSbDrag){
			if(mouse_check_button(mb_left)){
				// thumb follows the pointer, keeping the grab offset
				@stgFirst = round((@my - @stgTop - 2 - @stgSbGrab) / max(1, @stgBottom - @stgTop - 2 - @sbH) * @stgMaxFirst);
				if(@stgFirst < 0) @stgFirst = 0;
				if(@stgFirst > @stgMaxFirst) @stgFirst = @stgMaxFirst;
			}else{
				@stgSbDrag = false;
			}
		}
		// ONE grid: the table stores a y per row (headers 18px, rows 24px), so both
		// drawing and hit testing shift those values by this single offset. The
		// previous version accumulated its own uniform grid and drifted from it -
		// that is what made clicks and the highlight land on the wrong row.
		@stgYOff = global.__ONLINE_stgY[@stgFirst] - (@stgTop + 2);
		@rowHover = @stg_hit_row_view(@mx, @my, @stgYOff);
		@rowI = 0;
		while(@rowI < global.__ONLINE_stgN){
			@rowY = global.__ONLINE_stgY[@rowI] - @stgYOff;
			@rowVis = true;
			if(@rowI < @stgFirst || @rowI >= @stgFirst + @stgFit) @rowVis = false;
			// real height (headers are shorter): the uniform stgRowH check used to
			// clip a header that actually fit the band
			@rowH = global.__ONLINE_stgRowH;
			if(@rowI + 1 < global.__ONLINE_stgN) @rowH = global.__ONLINE_stgY[@rowI + 1] - global.__ONLINE_stgY[@rowI];
			if(@rowY + @rowH > @stgBottom) @rowVis = false;
			if(@rowY < @stgTop) @rowVis = false;
			if(@rowVis){
			@rowK = global.__ONLINE_stgKind[@rowI];
			@rowX = global.__ONLINE_stgX[@rowI];
			@rowCX = global.__ONLINE_stgCX[@rowI];
			@rowCW = global.__ONLINE_stgCW[@rowI];
			@rowSty = global.__ONLINE_stgStyle[@rowI];
			@rowSel = (@kbFocus == 1 && @kbRow[0] == @rowI);
			if(@rowK != 0 && @rowK != 1 && @rowK != 7){
				// hover tint / keyboard focus share the row's exact bounds
				if(@rowSel){
					// full-width amber band with dark text (mock .row.sel); per-kind
					// controls keep their own colours, labels/values switch to dark
					draw_set_color(make_color_rgb(225, 205, 90));
					draw_rectangle(@spX + 10, @rowY + 1, @spX + @colW - 10, @rowY + global.__ONLINE_stgRowH - 3, false);
				}else if(@rowHover == @rowI){
					draw_set_color(make_color_rgb(35, 35, 40));
					draw_rectangle(@spX + 10, @rowY + 1, @spX + @colW - 10, @rowY + global.__ONLINE_stgRowH - 3, false);
				}
			}
			draw_set_halign(fa_left);
			if(@rowK == 0){
				// section header: label + a thin rule running to the content edge
				draw_set_color(make_color_rgb(150, 190, 230));
				draw_text(@rowX, @rowY, global.__ONLINE_stgLabel[@rowI]);
				draw_set_color(make_color_rgb(70, 80, 95));
				@rowRuleX = @rowX + string_width(global.__ONLINE_stgLabel[@rowI]) + 10;
				if(@rowRuleX < @spX + @colW - 16) draw_rectangle(@rowRuleX, @rowY + 8, @spX + @colW - 16, @rowY + 9, false);
			}else if(@rowK == 7){
				// two-column header: each label gets a short rule of its own
				@rowSplit = string_pos("|", global.__ONLINE_stgLabel[@rowI]);
				draw_set_color(make_color_rgb(150, 190, 230));
				draw_text(@rowX, @rowY, string_copy(global.__ONLINE_stgLabel[@rowI], 1, @rowSplit - 1));
				draw_set_color(make_color_rgb(70, 80, 95));
				@rowRuleX = @rowX + string_width(string_copy(global.__ONLINE_stgLabel[@rowI], 1, @rowSplit - 1)) + 10;
				if(@rowRuleX < @rowCX - 16) draw_rectangle(@rowRuleX, @rowY + 8, @rowCX - 16, @rowY + 9, false);
				draw_set_color(make_color_rgb(150, 190, 230));
				draw_text(@rowCX, @rowY, string_delete(global.__ONLINE_stgLabel[@rowI], 1, @rowSplit));
				draw_set_color(make_color_rgb(70, 80, 95));
				@rowRuleX = @rowCX + string_width(string_delete(global.__ONLINE_stgLabel[@rowI], 1, @rowSplit)) + 10;
				if(@rowRuleX < @spX + @colW - 16) draw_rectangle(@rowRuleX, @rowY + 8, @spX + @colW - 16, @rowY + 9, false);
			}else if(@rowK == 1){
				draw_set_color(@stg_status_color());
				draw_circle(@rowX + 8, @rowY + 9, 5, false);
				draw_set_color(c_white);
				draw_text(@rowX + 20, @rowY + 2 + @stgTextDY, @stg_status_text());
				// the server address only fits when the content column is wide enough
				if(string_width(@stg_status_text()) + string_width("Server: " + @stg_server_text()) + 48 < @colW){
					draw_set_color(make_color_rgb(150, 150, 150));
					draw_set_halign(fa_right);
					draw_text(@spX + @colW - 16, @rowY + 2 + @stgTextDY, "Server: " + @stg_server_text());
					draw_set_halign(fa_left);
				}
			}else{
				if(@rowSel){
					draw_set_color(make_color_rgb(16, 16, 20));
				}else{
					draw_set_color(c_white);
				}
				if(@rowK == 6){
					// entry label may carry a CJK room name
					@stg_text_cjk(@rowX, @rowY + 4 + @stgTextDY, global.__ONLINE_stgLabel[@rowI], 0);
				}else{
					draw_text(@rowX, @rowY + 4 + @stgTextDY, global.__ONLINE_stgLabel[@rowI]);
				}
				@rowV = @stg_value(@rowI);
				@rowBY = @rowY + 2;
				@rowBH = global.__ONLINE_stgRowH - 6;
				if(@rowK == 5){
					if(@rowSel){
						// selected: the amber band is the plate (mock parity)
						draw_set_color(make_color_rgb(16, 16, 20));
						draw_set_halign(fa_center);
						draw_text(@rowCX + floor(@rowCW / 2), @rowBY + 3 + @stgTextDY, @rowV);
					}else{
						// button: flat dark plate, brighter frame on hover
						draw_set_color(make_color_rgb(45, 45, 52));
						draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, false);
						if(@rowHover == @rowI){
							draw_set_color(make_color_rgb(150, 160, 175));
						}else{
							draw_set_color(make_color_rgb(90, 95, 105));
						}
						draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, true);
						draw_set_color(c_white);
						draw_set_halign(fa_center);
						draw_text(@rowCX + floor(@rowCW / 2), @rowBY + 3 + @stgTextDY, @rowV);
					}
				}else if(@rowK == 6){

				  // entry row (saves): label left, value right-aligned, no box

				draw_set_halign(fa_right);

				  if(@rowSel){
				    draw_set_color(make_color_rgb(16, 16, 20));
				  }else{
				    draw_set_color(make_color_rgb(190, 195, 200));
				  }

				  @stg_text_cjk(@spX + @colW - 16, @rowBY + 3 + @stgTextDY, @rowV, 2);

				  draw_set_halign(fa_left);

				}else if(@rowK == 3){
					// select: one bordered box, < value > inside
					draw_set_color(make_color_rgb(45, 45, 50));
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, false);
					draw_set_color(make_color_rgb(90, 90, 96));
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, true);
					draw_set_color(c_gray);
					draw_rectangle(@rowCX + 22, @rowBY + 1, @rowCX + 23, @rowBY + @rowBH - 1, false);
					draw_rectangle(@rowCX + @rowCW - 23, @rowBY + 1, @rowCX + @rowCW - 22, @rowBY + @rowBH - 1, false);
					draw_set_halign(fa_center);
					draw_set_color(make_color_rgb(170, 170, 175));
					draw_text(@rowCX + 11, @rowBY + 3 + @stgTextDY, "<");
					draw_text(@rowCX + @rowCW - 11, @rowBY + 3 + @stgTextDY, ">");
					draw_set_color(c_white);
					draw_text(@rowCX + floor(@rowCW / 2), @rowBY + 3 + @stgTextDY, @rowV);
				}else if(@rowK == 4){
						// toggle: compact right-aligned pill (a full-width bar read as a wall of
						// colour once several toggles stacked up)
						@rowPW = 46;
						@rowPX = @rowCX + @rowCW - @rowPW;
						if(@rowV == "ON"){
							draw_set_color(make_color_rgb(50, 170, 80));
						}else{
							draw_set_color(make_color_rgb(45, 45, 50));
						}
						draw_rectangle(@rowPX, @rowBY, @rowPX + @rowPW, @rowBY + @rowBH, false);
						if(@rowV == "ON"){
							draw_set_color(make_color_rgb(50, 170, 80));
						}else{
							draw_set_color(make_color_rgb(90, 90, 96));
						}
						draw_rectangle(@rowPX, @rowBY, @rowPX + @rowPW, @rowBY + @rowBH, true);
						draw_set_color(c_white);
						draw_set_halign(fa_center);
						draw_text(@rowPX + floor(@rowPW / 2), @rowBY + 3 + @stgTextDY, @rowV);
}else{
					// text row (name / session key): plain right-aligned value - the
					// edit dialog is modal, so there is no inline box to draw
					draw_set_halign(fa_right);
					if(@rowSel){
						draw_set_color(make_color_rgb(16, 16, 20));
					}else{
						draw_set_color(make_color_rgb(190, 195, 200));
					}
					@stg_text_cjk(@rowCX + @rowCW, @rowBY + 3 + @stgTextDY, @rowV, 2);
					draw_set_halign(fa_left);
				}
			}
			}
			@rowI += 1;
		}
		// side scrollbar (track + thumb) instead of the old "more" markers.
		// Geometry was computed above the row loop (a drag moves @stgFirst there);
		// the thumb brightens while dragged.
		if(@sbShow){
			draw_set_color(make_color_rgb(50, 50, 58));
			draw_rectangle(@sbX, @stgTop + 2, @sbX + 5, @stgBottom, false);
			@sbY = @stgTop + 2 + (@stgBottom - @stgTop - 2 - @sbH) * @stgFirst / max(1, @stgMaxFirst);
			if(@stgSbDrag){
				draw_set_color(make_color_rgb(190, 190, 205));
			}else{
				draw_set_color(make_color_rgb(150, 150, 165));
			}
			draw_rectangle(@sbX, @sbY, @sbX + 5, @sbY + @sbH, false);
		}
		draw_set_halign(fa_left);
		// footer: separator + hint + Close all live in the footer band (@footerY),
		// below the last row; the toast floats just above it and never overlaps
		// HOVER PREVIEWS, it does not select: the detail column and the footer
		// follow the pointer, while the amber cursor stays where the keyboard or
		// the last click put it. (Hover used to move the cursor itself - a parked
		// mouse then fought the arrow keys every frame.)
		@stgPrevRow = @kbRow[0];
		if(@rowHover >= 0){
			@stgPrevK = global.__ONLINE_stgKind[@rowHover];
			if(@stgPrevK != 0 && @stgPrevK != 7) @stgPrevRow = @rowHover;
		}
		// detail column (full layout only): what the list row cannot express
		if(@detW > 0) @stg_draw_detail(@stgPrevRow);

		if(@stg_toast_active()){
			// bottom-RIGHT: the footer hint owns the bottom-left
			draw_set_halign(fa_right);
			if(global.__ONLINE_stgToastKind == 0){
				draw_set_color(make_color_rgb(90, 220, 120));
			}else if(global.__ONLINE_stgToastKind == 1){
				draw_set_color(make_color_rgb(230, 210, 90));
			}else{
				draw_set_color(make_color_rgb(230, 110, 110));
			}
			// bottom-right of the DETAIL column when there is one: the content column's

			// right edge is where the last rows live, and the message collided with them

			@toastX = @spX + @colW - 16;

			if(@detW > 0) @toastX = @spX + @colW + @detW - 16;

			draw_text(@toastX, @stgBottom - 16, global.__ONLINE_stgToastMsg);
			draw_set_halign(fa_left);
		}
		draw_set_color(make_color_rgb(70, 80, 95));
		draw_rectangle(@spX + 16, @footerY, @spX + @spW - 16, @footerY + 1, false);
		draw_set_color(make_color_rgb(160, 160, 160));
		@stgHintRow = -1;
		if(@rowHover >= 0 && @stgPrevRow == @rowHover) @stgHintRow = @rowHover;
		if(@stgHintRow < 0 && @kbFocus == 1) @stgHintRow = @kbRow[0];
		if(@stgHintRow >= 0 && @stgHintRow < global.__ONLINE_stgN){
			draw_text(@spX + 16, @footerY + 10, @stg_fit_text(@stg_hint(@stgHintRow), @spW - 130));
		}else{
			draw_text(@spX + 16, @footerY + 10, @stg_fit_text("Up/Down rows   Left/Right tabs or values   Enter edit   F1 close", @spW - 130));
		}
return 0;
///// script @stg_room_name
// Save room display name. Saves written before room names were recorded come
// back as "" or "<undefined>" - present those as "?".
// args: save index -> text
var _r;
_r = @saveHistRoomName[argument0];
if(_r == "" || _r == "<undefined>") return "?";
return _r;

///// script @save_age_text
// Relative age of a save, exactly as the old panel computed it.
// args: index -> text
var _mins;
if(@saveHistTime[argument0] <= 0) return "?";
_mins = (date_current_datetime() - @saveHistTime[argument0]) * 1440;
if(_mins < 1) return "now";
if(_mins < 60) return string(round(_mins)) + "m";
if(_mins < 1440) return string(round(_mins / 60)) + "h";
if(_mins < 10080) return string(round(_mins / 1440)) + "d";
return string(date_get_month(@saveHistTime[argument0])) + "/" + string(date_get_day(@saveHistTime[argument0]));

///// script @stg_build_saves
// Row table for the Saves tab, using the same table the Settings tab uses (the
// list scrolls, so the old paging buttons are gone). Save rows carry their index
// in @stgArg so the dispatcher and the detail pane can read the real fields.
// args: contentY -> 0
var _y, _i, _n, _lbl;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
@stg_row_add(0, 0, "SAVE HISTORY", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
// newest first, honouring the all/favourites filter
_n = 0;
_i = @saveHistCount - 1;
while(_i >= 0){
  if(@saveHistFilter == 0 || @saveHistFav[_i]){
    // room + bare coords + age: "Save N" meant nothing while browsing; the
    // number survives as the detail pane's title
    _lbl = @stg_room_name(_i) + " " + string(round(@saveHistX[_i])) + "," + string(round(@saveHistY[_i])) + " " + @save_age_text(_i);
    if(@saveHistFav[_i]) _lbl = "* " + _lbl;
    _lbl = @stg_fit_text(_lbl, @colW - 32 - 56);
    _n += 1;
    // the hit zone is stgX..stgCX+stgCW+8 - a 0-width control made only the
    // first ~90px of every save row clickable
    @stg_row_add(6, 20, _lbl, @spX + 16, _y, @colW - 32, 0, @spX + 16);
    global.__ONLINE_stgArg[global.__ONLINE_stgN - 1] = _i;
    _y += global.__ONLINE_stgRowH;
  }
  _i -= 1;
}
if(_n == 0){
  if(@saveHistFilter) _lbl = "(no favourites)"; else _lbl = "(no saves yet)";
  @stg_row_add(2, 0, _lbl, @spX + 16, _y, 200, 0, 0); _y += global.__ONLINE_stgRowH;
}
_y += 6;
@stg_row_add(0, 0, "MANAGE", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(4, 21, "Favourites", @spX + 16, _y, 130, 0, @spX + @colW - 146); _y += global.__ONLINE_stgRowH;
@stg_row_add(5, 22, "", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_text_cjk
// Draws a panel string that may contain user text (account name, save player
// names), picking the path that exists in the current build:
//   ASCII             -> draw_text (the panel font stays as it is)
//   GM8.0             -> FoxWriting, the engine-agnostic CJK route this build has
//   GMS with CJK pack -> __ONLINE_cjk_draw_text, the call chat/notes/player list use
//   GMS without it    -> draw_text (the game font draws Chinese in that build)
// args: x, y, text, halign (0 left, 1 centre, 2 right) -> 0
var _i, _n, _c, _ascii;
_ascii = 1;
_n = string_length(argument2);
_i = 1;
while(_i <= _n){
  _c = ord(string_char_at(argument2, _i));
  if(_c < 32 || _c > 126){ _ascii = 0; break; }
  _i += 1;
}
if(_ascii){
  if(argument3 == 2){ draw_set_halign(fa_right); }else if(argument3 == 1){ draw_set_halign(fa_center); }else{ draw_set_halign(fa_left); }
  draw_text(argument0, argument1, argument2);
  draw_set_halign(fa_left);
  return 0;
}
#if GM80
// font first: it resets the alignment state
__ONLINE_fw_use_font(argument2);
fw_draw_set_valign(fa_top);
if(argument3 == 2){ fw_draw_set_halign(fa_right); }else if(argument3 == 1){ fw_draw_set_halign(fa_center); }else{ fw_draw_set_halign(fa_left); }
fw_draw_text_ext(argument0, argument1, argument2, 9999);
#endif
#if not GM80
#if CJKTEXT
global.__ONLINE_cjkHalign = argument3;
global.__ONLINE_cjkValign = 0;
__ONLINE_cjk_draw_text(argument0, argument1, argument2, 9999);
global.__ONLINE_cjkHalign = 0;
#endif
#if not CJKTEXT
if(argument3 == 2){ draw_set_halign(fa_right); }else if(argument3 == 1){ draw_set_halign(fa_center); }else{ draw_set_halign(fa_left); }
draw_text(argument0, argument1, argument2);
draw_set_halign(fa_left);
#endif
#endif
return 0;

///// script @stg_build_tab
// Builds the row table for one tab. Every tab is table-driven, so the shared
// renderer/input paths (@stg_draw_table, @stg_click_row, the nav block) cover
// all six without per-tab forks.
// args: tab -> 0
if(argument0 == 0) return @stg_build_rows(@contentY);
if(argument0 == 1) return @stg_build_saves(@contentY);
if(argument0 == 2) return @stg_build_rating(@contentY);
if(argument0 == 3) return @stg_build_keys(@contentY);
if(argument0 == 4) return @stg_build_sync(@contentY);
return @stg_build_skins(@contentY);

///// script @stg_build_rating
// Row table for the Rating tab. Only real fields (worldCreate: rStars,
// rCleared, ratingSubmitting/ratingResult/ratingResultTimer/ratingCooldown);
// the star boxes live in the detail pane (and are clickable there).
// args: contentY -> 0
var _y, _ctlX;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
_ctlX = @spX + @colW - 16 - 130;
@stg_row_add(0, 0, "THIS GAME", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(6, 30, @stg_fit_text(@gameName, @colW - 32), @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(0, 0, "RATING", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(3, 31, "Stars", @spX + 16, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 32, "Cleared", @spX + 16, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(0, 0, "STATUS", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(6, 33, "Last result", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(5, 34, "", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_keys_meta
// The 11 rebindable actions: labels and the world variables they write.
// (Rebuilt per call, exactly like the old hand layout did per frame.)
// args: none -> 0
@kbLabels[0] = "Visibility";   @kbKeys[0] = @keyVis;
@kbLabels[1] = "Toggle Save";  @kbKeys[1] = @keySave;
@kbLabels[2] = "Spectate";     @kbKeys[2] = @keySpectate;
@kbLabels[3] = "Chat Log";     @kbKeys[3] = @keyChatLog;
@kbLabels[4] = "Indicator";    @kbKeys[4] = @keyArrows;
@kbLabels[5] = "Options";      @kbKeys[5] = @keySettings;
@kbLabels[6] = "Player List";  @kbKeys[6] = @keyPlayerList;
@kbLabels[7] = "Chat";         @kbKeys[7] = @keyChat;
@kbLabels[8] = "Here";         @kbKeys[8] = @keyPing;
@kbLabels[9] = "Fast Load";    @kbKeys[9] = @keyFastLoad;
@kbLabels[10] = "Canvas";      @kbKeys[10] = @keyCanvas;
return 0;

///// script @stg_key_cap
// Display text for a key code (the old panel's exact rules).
// args: keycode -> text
var _k;
_k = argument0;
if(_k == 32) return "SPACE (32)";
if(_k >= 33 && _k <= 126) return chr(_k) + " (" + string(_k) + ")";
return "Key " + string(_k);

///// script @stg_build_keys
// Row table for the Keys tab: one entry per rebindable action + reset. The
// capture itself lives in worldEndStep's keybind block (@keybindEditing).
// args: contentY -> 0
var _y, _i;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
@stg_keys_meta();
@stg_row_add(0, 0, "KEY BINDINGS", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
for(_i = 0; _i < 11; _i += 1){
  @stg_row_add(6, 40 + _i, @kbLabels[_i], @spX + 16, _y, @colW - 32, 0, @spX + 16);
  global.__ONLINE_stgArg[global.__ONLINE_stgN - 1] = _i;
  _y += global.__ONLINE_stgRowH;
}
_y += 6;
@stg_row_add(0, 0, "RESET", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(5, 52, "", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_build_sync
// Row table for the Sync tab: the enable toggle + one entry per configured
// global. Fields verified at worldCreate (syncEnabled / syncEntryCount /
// syncName / syncCount; syncSlotCount computed at ini load). The list scrolls,
// so all 16 entries show - the old hand layout hard-capped at 10.
// args: contentY -> 0
var _y, _i, _ctlX;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
_ctlX = @spX + @colW - 16 - 130;
@stg_row_add(0, 0, "SYNC", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(4, 53, "Sync enabled", @spX + 16, _y, 130, 0, _ctlX); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(0, 0, "ENTRIES (" + string(@syncEntryCount) + " of 16)", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
if(@syncEntryCount == 0){
  @stg_row_add(2, 0, "(no entries configured)", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
}
for(_i = 0; _i < @syncEntryCount; _i += 1){
  @stg_row_add(6, 54, @stg_fit_text(@syncName[_i], @colW - 32 - 90), @spX + 16, _y, @colW - 32, 0, @spX + 16);
  global.__ONLINE_stgArg[global.__ONLINE_stgN - 1] = _i;
  _y += global.__ONLINE_stgRowH;
}
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_skin_preview
// Dwell-loads and draws the idle-frame preview for a skins entry row. Lives in
// the detail pane (full layout); the narrow layout has no preview (by design,
// narrow is list-only). The dwell means fast scrolling never thrashes
// sprite_add; the leak guard in worldDrawGui unloads when the menu closes.
// args: row, x, y -> 0
var _i;
_i = global.__ONLINE_stgAct[argument0];
if(_i != 55) return 0;   // only skin entries preview
_i = global.__ONLINE_stgArg[argument0];
if(_i < 0 || _i >= @skinVisCount) return 0;
if(@skinPrevRow != _i){
  @skinPrevRow = _i;
  @skinPrevTimer = 0;
  if(@skinPrevLoaded >= 0) @skin_prev_unload();
}
if(@skinPrevLoaded != _i){
  @skinPrevTimer += 1;
  if(@skinPrevTimer >= 15) @skin_prev_load(_i);
}
draw_set_color(make_color_rgb(8, 8, 10));
draw_rectangle(argument1, argument2, argument1 + 116, argument2 + 116, false);
draw_set_color(make_color_rgb(70, 80, 95));
draw_rectangle(argument1, argument2, argument1 + 116, argument2 + 116, true);
if(@skinPrevLoaded == _i && @skinPrevSpr[0] >= 0){
  // absolute per-frame pacing (same semantics as @skin_draw): one strip frame
  // per 100ms tick, no fast-forward on many-frame skins
  @pvFrames = @skinFrames[@skinPrevLoaded, 0];
  if(@pvFrames < 1) @pvFrames = 1;
  @pvFrame = floor(current_time / 100) mod @pvFrames;
  draw_sprite_ext(@skinPrevSpr[0], @pvFrame, argument1 + 58, argument2 + 86, 2, 2, 0, c_white, 1);
}else{
  draw_set_color(make_color_rgb(95, 101, 107));
  draw_set_halign(fa_center);
  draw_text(argument1 + 58, argument2 + 50 + @stgTextDY, "preview");
  draw_set_halign(fa_left);
}
return 0;

///// script @stg_build_skins
// Row table for the Skins tab: one entry per installed skin (the list scrolls,
// so the old 12-per-page pager is gone), then the manage rows. Fields come from
// skinLib's scan (skinName/skinMaker/skinSource/skinHas/skinFrames; see DESIGN
// 9.4). The preview lives in the detail pane.
// args: contentY -> 0
var _y, _i, _lbl;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
@stg_row_add(0, 0, "INSTALLED (" + string(@skinVisCount) + ")", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
if(@skinVisCount == 0){
  @stg_row_add(2, 0, "(no skins found in iwposkins)", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
}
// parse only what the viewport can show (plus a small margin): parsing every
// entry on the first visit was a visible ~1s hitch on big packs - the old
// pager parsed just its page per frame, this is the same amortisation
@skParseTo = @stgFirst + @stgFit + 2;
if(@skParseTo > @skinVisCount) @skParseTo = @skinVisCount;
for(@skPI = max(0, @stgFirst - 2); @skPI < @skParseTo; @skPI += 1) @skin_parse(@skPI);
for(_i = 0; _i < @skinVisCount; _i += 1){
  if(@skinParsed[_i]){
    _lbl = @skinName[_i] + " (" + @skinMaker[_i] + ")";
    if(!@skinHas[_i, 0]) _lbl = "[!] " + _lbl;
  }else{
    // unparsed (off-screen): the folder name; it upgrades on scroll-into-view
    _lbl = @skinDir[_i];
  }
  _lbl = @stg_fit_text(_lbl, @colW - 32 - 56);
  @stg_row_add(6, 55, _lbl, @spX + 16, _y, @colW - 32, 0, @spX + 16);
  global.__ONLINE_stgArg[global.__ONLINE_stgN - 1] = _i;
  _y += global.__ONLINE_stgRowH;
}
_y += 6;
@stg_row_add(0, 0, "MANAGE", @spX + 16, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(4, 56, "Auto-download", @spX + 16, _y, 130, 0, @spX + @colW - 146); _y += global.__ONLINE_stgRowH;
@stg_row_add(5, 57, "", @spX + 16, _y, @colW - 32, 0, @spX + 16); _y += global.__ONLINE_stgRowH;
global.__ONLINE_stgHeight = _y - argument0;
return 0;

///// script @stg_row_add
// Appends one row and returns its index.
// args: kind, act, label, x, y, controlWidth, controlStyle, cxOverride
//   controlStyle is retained for table compatibility but the renderer keys off
//   the row kind alone (the old style 2/3 variants no longer exist)
//   cxOverride 0 = control sits at x + 84 (the default column gap)
var _i;
_i = global.__ONLINE_stgN;
global.__ONLINE_stgKind[_i] = argument0;
global.__ONLINE_stgAct[_i] = argument1;
global.__ONLINE_stgLabel[_i] = argument2;
global.__ONLINE_stgX[_i] = argument3;
global.__ONLINE_stgY[_i] = argument4;
if(argument7 == 0){
  global.__ONLINE_stgCX[_i] = argument3 + 84;
}else{
  global.__ONLINE_stgCX[_i] = argument7;
}
global.__ONLINE_stgCW[_i] = argument5;
global.__ONLINE_stgStyle[_i] = argument6;
global.__ONLINE_stgN = _i + 1;
return _i;

///// script @stg_hit_row
// Mouse hit test in panel space. Returns the row index or -1; headers, the status
// row and non-interactive rows are skipped.
// args: mx, my -> row index / -1
// Hit zone: from 6px left of the label to the control's right edge + 6px -
// deliberately NOT wider, so clicks on empty panel space never fire a row.
var _i;
_i = 0;
while(_i < global.__ONLINE_stgN){
  if(global.__ONLINE_stgKind[_i] != 0 && global.__ONLINE_stgKind[_i] != 1 && global.__ONLINE_stgKind[_i] != 7){
    if(argument1 >= global.__ONLINE_stgY[_i] - 1 && argument1 < global.__ONLINE_stgY[_i] + global.__ONLINE_stgRowH - 2){
      if(argument0 >= global.__ONLINE_stgX[_i] - 6 && argument0 < global.__ONLINE_stgCX[_i] + global.__ONLINE_stgCW[_i] + 6) return _i;
    }
  }
  _i += 1;
}
return -1;

///// script @stg_first_row
// First selectable row (keyboard focus entry point).
// args: none -> row index
var _i;
_i = 0;
while(_i < global.__ONLINE_stgN){
  if(global.__ONLINE_stgKind[_i] != 0 && global.__ONLINE_stgKind[_i] != 1 && global.__ONLINE_stgKind[_i] != 7) return _i;
  _i += 1;
}
return 0;

///// script @stg_next_row
// Moves the selection by argument1 rows, skipping headers/status. Running off
// the end lands on the edge-most selectable row in that direction, so the
// accelerated multi-row steps stay useful at the list ends (a single-step
// caller at the edge gets its own row back, same as before).
// args: from, delta -> new row index
var _i, _d, _n;
_i = argument0;
_d = argument1;
_n = 0;
while(_n < 128){
  _i += _d;
  if(_i < 0 || _i >= global.__ONLINE_stgN){
    if(_d > 0){
      _i = global.__ONLINE_stgN - 1;
      while(_i > 0){
        if(global.__ONLINE_stgKind[_i] != 0 && global.__ONLINE_stgKind[_i] != 1 && global.__ONLINE_stgKind[_i] != 7) return _i;
        _i -= 1;
      }
    }else{
      _i = 0;
      while(_i < global.__ONLINE_stgN - 1){
        if(global.__ONLINE_stgKind[_i] != 0 && global.__ONLINE_stgKind[_i] != 1 && global.__ONLINE_stgKind[_i] != 7) return _i;
        _i += 1;
      }
    }
    return argument0;
  }
  if(global.__ONLINE_stgKind[_i] != 0 && global.__ONLINE_stgKind[_i] != 1 && global.__ONLINE_stgKind[_i] != 7) return _i;
  _n += 1;
}
return argument0;

///// script @stg_status_text
// Live connection state for the status row. Everything here comes from the
// existing socket state machine, so the panel works while offline.
// args: none -> text
if(global.__ONLINE_stgStatusMsg != "") return global.__ONLINE_stgStatusMsg;
if(@server == "") return "Server not configured";
if(@reconnecting) return "Reconnecting (" + string(@reconnectAttempts) + "/10)...";
if(@connected) return "Online";
if(@tcpState == 2) return "Online";
if(@socketConnectResult == 0) return "Cannot reach server";
if(@socketState > 0) return "Connecting...";
return "Offline";

///// script @stg_status_color
// args: none -> colour matching @stg_status_text
if(@server == "") return c_gray;
if(@reconnecting) return make_color_rgb(220, 200, 60);
if(@connected) return make_color_rgb(60, 200, 100);
if(@tcpState == 2) return make_color_rgb(60, 200, 100);
if(@socketConnectResult == 0) return make_color_rgb(220, 80, 80);
return make_color_rgb(220, 200, 60);

///// script @stg_rating_status
// One-line state of the rating pipeline (status row, detail facts, button).
// args: none -> text
if(@ratingSubmitting) return "Sending...";
if(@ratingCooldown > current_time) return "Cooldown " + string(max(1, ceil((@ratingCooldown - current_time) / 1000))) + "s";
if(@ratingResultTimer > current_time){
  if(@ratingResult == 1) return "Rating submitted!";
  if(@ratingResult == 2) return "Submit failed (cooldown)";
}
if(!@connected) return "Offline";
return "Idle";

///// script @stg_server_text
// Server address row content - what the client is actually pointed at, so an
// offline player can see whether the ini points somewhere stale.
// args: none -> text
if(@server == "") return "(none)";
return @server + ":" + string(@tcpPort);

///// script @stg_source_text
// Where the account values came from (shown next to the name row).
// args: none -> text
if(global.__ONLINE_accEnvManaged) return "env";
if(global.__ONLINE_accSource == 2) return "folder";
if(global.__ONLINE_accSource == 3) return "global";
return "";

///// script @stg_value
// Display string for a row (the panel never shows the raw session key).
// args: row -> text
var _a;
_a = global.__ONLINE_stgAct[argument0];
if(_a == 12) return @acc_label_name();
if(_a == 13) return @acc_label_pass();
if(_a == 14) return @account_store_label();
if(_a == 1){
  @teamNames[0] = "None"; @teamNames[1] = "Red"; @teamNames[2] = "Blue"; @teamNames[3] = "Yellow";
  @teamNames[4] = "Purple"; @teamNames[5] = "Green"; @teamNames[6] = "Orange"; @teamNames[7] = "Cyan";
  return string(@team) + " " + @teamNames[@team];
}
if(_a == 2) return @stg_onoff(@lerpEnabled);
if(_a == 3) return @stg_onoff(@save_enabled);
if(_a == 4) return @stg_onoff(@fastLoadEnabled);
if(_a == 5){
  @visNames[0] = "All"; @visNames[1] = "No Names"; @visNames[2] = "Hidden";
  return @visNames[@vis];
}
if(_a == 6) return @stg_onoff(@showArrows);
if(_a == 7){
  @specCamNames[0] = "Free"; @specCamNames[1] = "Follow";
  return @specCamNames[@specCamMode];
}
if(_a == 8){
  if(!@pvpAvail) return "N/A";
  @pvpModeNames[0] = "Off"; @pvpModeNames[1] = "Team"; @pvpModeNames[2] = "FFA";
  return @pvpModeNames[@pvpMode];
}
if(_a == 9){
  if(@pvpMode != 0) return "locked";
  return @stg_onoff(@bulletShow);
}
if(_a == 20){
  @stgSvI = global.__ONLINE_stgArg[argument0];
  // a build with no entries may not have created the array at all
  if(@stgSvI < 0 || @stgSvI >= @saveHistCount) return "";
  if(@saveHistHotkey[@stgSvI] > 0) return "key " + string(@saveHistHotkey[@stgSvI]);
  return "";
}
if(_a == 21) return @stg_onoff(@saveHistFilter);
if(_a == 22) return "Clear all";
if(_a == 10) return "Pick";
if(_a == 11) return "Reconnect now";
if(_a == 15) return "Apply & Reconnect";
if(_a >= 40 && _a <= 50){
  @stgI = global.__ONLINE_stgArg[argument0];
  if(@keybindEditing == @stgI) return "<press a key>";
  return @stg_key_cap(@kbKeys[@stgI]);
}
if(_a == 53) return @stg_onoff(@syncEnabled);
if(_a == 55){
  @stgI = global.__ONLINE_stgArg[argument0];
  if(@stgI == @skinLoaded) return "loaded";
  return "";
}
if(_a == 56) return @stg_onoff(@skinAutoDL);
if(_a == 57) return "Clear skin";
if(_a == 54){
  @stgI = global.__ONLINE_stgArg[argument0];
  return string(@syncCount[@stgI]) + " bits";
}
if(_a == 52) return "Reset keys";
if(_a == 31) return string(@rStars) + " / 5";
if(_a == 32) return @stg_onoff(@rCleared);
if(_a == 33) return @stg_rating_status();
if(_a == 34){
  if(@ratingSubmitting) return "Sending...";
  if(@ratingCooldown > current_time) return "Wait " + string(max(1, ceil((@ratingCooldown - current_time) / 1000))) + "s";
  return "Submit Rating";
}
return "";

///// script @stg_onoff
// args: flag -> "ON"/"OFF"
if(argument0) return "ON";
return "OFF";

///// script @stg_kind_of
// args: row -> kind
return global.__ONLINE_stgKind[argument0];

///// script @stg_style_of
// args: row -> control style
return global.__ONLINE_stgStyle[argument0];

///// script @stg_hint
// Bottom hint line for the focused row.
// args: row -> text
var _a;
_a = global.__ONLINE_stgAct[argument0];
if(_a == 12) return "Your in-game name - Enter to edit. Saved to the account store.";
if(_a == 13) return "Session key: players sharing it meet each other. Not an account password.";
if(_a == 14) return "Where name and key are saved (Global = shared by every game).";
if(_a == 15) return "Save the account and reconnect with the new identity (no restart).";
if(_a == 11) return "Drop the current connection and connect again.";
if(_a == 10) return "Choose which player object drives your character.";
if(_a == 1) return "Team colour used for names and the roster.";
if(_a == 2) return "Interpolate remote players between network updates.";
if(_a == 3) return "Shared online saves (T key toggles this in game).";
if(_a == 4) return "Fast save/load path for game_restart engines.";
if(_a == 5) return "How other players are drawn: full, names only, or hidden.";
if(_a == 6) return "Show the direction indicator above remote players.";
if(_a == 7) return "Spectator camera mode.";
if(_a == 8) return "Player versus player mode. Bullets stay visible while it is on.";
if(_a == 9) return "Share your bullets with the room (locked on in PVP).";
if(_a == 20) return "Enter applies this save. F favourite, 1-8 hotkey, Del clears.";
if(_a == 21) return "Show only favourite saves.";
if(_a == 22) return "Deletes every non-favourite save file.";
if(_a == 10) return "Choose which player object drives your character.";
if(_a >= 40 && _a <= 50) return "Enter or click starts capture, then press the key. Esc cancels.";
if(_a == 52) return "Restore every binding above to its default.";
if(_a == 53) return "Share the configured globals with the room.";
if(_a == 54) return "A synced global variable.";
if(_a == 55) return "Enter applies this skin. The detail pane previews its idle animation.";
if(_a == 56) return "Fetch unknown skins seen in the roster automatically.";
if(_a == 57) return "Back to the game's default player sprite.";
if(_a == 30) return "This game, as the server identifies it.";
if(_a == 31) return "Your rating: Left/Right steps, digits 1-5 set directly, 0 clears.";
if(_a == 32) return "Mark the game as cleared. Sent together with the stars.";
if(_a == 33) return "The server's response to your last submission.";
if(_a == 34) return "Send the rating to the server.";
return "Up/Down rows, Left/Right change, Enter edit - F1 or O closes.";

///// script @stg_click_row
// Mouse click on a list row - one model for every table-driven tab:
//   - a pending two-step confirm owns the click: same row commits, any other
//     row cancels (mouse parity with Enter/Esc)
//   - self-evident value controls (the < > arrows, the ON/OFF pill) act
//     immediately, and also select the row
//   - the body of an unselected row only SELECTS it: browse -> read the detail
//     -> act. A second click on the selected row activates it (= Enter).
// args: row -> 0
var _k, _cx, _cw, _ctl;
if(global.__ONLINE_stgClearRow >= 0){
  if(global.__ONLINE_stgAct[argument0] == global.__ONLINE_stgClearRow){
    @acc_clear_commit();
  }else{
    @acc_clear_cancel();
  }
  return 0;
}
_k = global.__ONLINE_stgKind[argument0];
if(_k == 0 || _k == 1 || _k == 7) return 0;
_cx = global.__ONLINE_stgCX[argument0];
_cw = global.__ONLINE_stgCW[argument0];
_ctl = false;
if(_k == 3){
  if(@mx >= _cx && @mx < _cx + 22){ @stg_act_dir(argument0, -1); _ctl = true; }
  if(@mx >= _cx + _cw - 22 && @mx <= _cx + _cw){ @stg_act_dir(argument0, 1); _ctl = true; }
}
if(_k == 4 && @mx >= _cx + _cw - 46 && @mx <= _cx + _cw){ @stg_act(argument0); _ctl = true; }
if(_ctl){
  @kbRow[0] = argument0;
  @kbFocus = 1;
  return 0;
}
if(@kbFocus == 1 && @kbRow[0] == argument0){
  @stg_act(argument0);
}else{
  @kbRow[0] = argument0;
  @kbFocus = 1;
}
return 0;

///// script @stg_act
// Performs the action bound to a row. Returns 1 when the action closed the menu.
// args: row -> 1/0
var _a;
_a = global.__ONLINE_stgAct[argument0];
if(_a == 1){
  @team += 1;
  if(@team > 7) @team = 0;
  @teamChanged = true;
  return 0;
}
if(_a == 2){ @lerpEnabled = !@lerpEnabled; @lerpChanged = true; return 0; }
if(_a == 3){
  @save_enabled = 1 - @save_enabled;
  @saveChanged = true;
  if(!@save_enabled){
    #if TEMPFILE
      if(file_exists("tempOnline2")) file_delete("tempOnline2");
    #endif
    @sSaved = false;
  }
  return 0;
}
if(_a == 4){ @fastLoadEnabled = !@fastLoadEnabled; @fastLoadChanged = true; return 0; }
if(_a == 5){ @vis += 1; if(@vis > 2) @vis = 0; @visChanged = true; return 0; }
if(_a == 6){ @showArrows = !@showArrows; @stg_toast("Indicator: " + @stg_onoff(@showArrows), 1); return 0; }
if(_a == 7){ @specCamMode = 1 - @specCamMode; @stg_toast("Spec Cam: " + @stg_value(argument0), 1); return 0; }
if(_a == 8){
  if(@pvpAvail){
    @pvpMode += 1;
    if(@pvpMode > 2) @pvpMode = 0;
    @pvpChanged = true;
    @stg_toast("PVP: " + @stg_value(argument0), 1);
  }else{
    @stg_toast("PVP is not available for this game", 1);
  }
  return 0;
}
if(_a == 9){
  if(@pvpMode == 0){
    @bulletShow = !@bulletShow;
    @bulletChanged = true;
  }else{
    @stg_toast("Bullets are locked on in PVP", 1);
  }
  return 0;
}
if(_a == 20){
  @saveHistApply = global.__ONLINE_stgArg[argument0];
  @settingsOpen = false;
  return 1;
}
if(_a == 21){ @saveHistFilter = 1 - @saveHistFilter; return 0; }
if(_a == 22){
  // destructive, so it takes two clicks: the first arms the confirmation, a
  // second click on the same button performs it (the pointer can always finish
  // what it started - no key is required, and Esc is not part of the flow).
  if(global.__ONLINE_stgClearRow == 22){
    @acc_clear_commit();
  }else{
    global.__ONLINE_stgClearRow = 22;
    @stg_toast("Click again to clear every non-favourite save", 1);
  }
  return 0;
}
if(_a == 10){ @settingsOpen = false; @debug_pick_player = true; return 1; }
if(_a == 11){ @manualReconnect = true; @stg_toast("Reconnecting...", 1); return 0; }
if(_a == 12){ @acc_edit_name(); return 0; }
if(_a == 13){ @acc_edit_pass(); return 0; }
if(_a == 14){ @acc_toggle_store(); return 0; }
if(_a == 15){ @acc_apply_reconnect(); return 0; }
if(_a == 31){
  @rStars += 1;
  if(@rStars > 5) @rStars = 0;
  return 0;
}
if(_a == 32){ @rCleared = 1 - @rCleared; return 0; }
if(_a == 30 || _a == 33) return 0;   // view-only entries
if(_a >= 40 && _a <= 50){
  // arm the capture; the keybind block in worldEndStep takes over while the
  // settings keyboard block is skipped (@keybindEditing >= 0)
  @keybindEditing = _a - 40;
  @keybindArmTimer = 6;
  return 0;
}
if(_a == 53){
  @syncEnabled = 1 - @syncEnabled;
  @syncEnabledChanged = true;
  return 0;
}
if(_a == 55){
  @skin_select(global.__ONLINE_stgArg[argument0]);
  return 0;
}
if(_a == 56){
  @skinAutoDL = 1 - @skinAutoDL;
  @skinAutoDLChanged = true;
  if(@skinAutoDL){
    // re-enabled: forget the one-per-hash notice/download marks so the next
    // roster replay re-triggers unknown skins as downloads
    for(@skH = 0; @skH < 8; @skH += 1) @skinHint[@skH] = "";
  }
  return 0;
}
if(_a == 57){
  @skin_clear();
  @stg_toast("Skin cleared", 1);
  return 0;
}
if(_a == 54) return 0;   // view-only entry
if(_a == 52){
  // the default set (the old Reset Keys button's exact values)
  @keyVis = 86; @keySave = 84; @keySpectate = 89; @keyChatLog = 85; @keyArrows = 73; @keySettings = 79;
  @keyPlayerList = 76; @keyChat = 32; @keyPing = 72; @keyFastLoad = 70; @keyCanvas = 78;
  @keybindEditing = -1;
  @keybindSave = true;
  @stg_toast("Keys reset to defaults", 1);
  return 0;
}
if(_a == 34){
  if(!@connected){ @stg_toast("Not connected", 1); return 0; }
  if(@ratingSubmitting) return 0;
  if(@ratingCooldown > current_time){ @stg_toast("Cooldown - wait " + string(max(1, ceil((@ratingCooldown - current_time) / 1000))) + "s", 1); return 0; }
  if(@rStars < 1){ @stg_toast("Pick 1-5 stars first", 1); return 0; }
  @ratingSubmit = true;
  return 0;
}
return 0;

///// script @stg_act_dir
// Directional variant used by Left/Right and the < > arrow zones.
// args: row, dir -> 1 when the action closed the menu
var _a;
_a = global.__ONLINE_stgAct[argument0];
if(_a == 31){
  @rStars += argument1;
  if(@rStars < 0) @rStars = 5;
  if(@rStars > 5) @rStars = 0;
  return 0;
}
if(_a == 1){
  @team += argument1;
  if(@team < 0) @team = 7;
  if(@team > 7) @team = 0;
  @teamChanged = true;
  return 0;
}
if(_a == 5){
  @vis += argument1;
  if(@vis < 0) @vis = 2;
  if(@vis > 2) @vis = 0;
  @visChanged = true;
  return 0;
}
if(_a == 7){
  @specCamMode = 1 - @specCamMode;
  @stg_toast("Spec Cam: " + @stg_value(argument0), 1);
  return 0;
}
if(_a == 8){
  if(@pvpAvail){
    @pvpMode += argument1;
    if(@pvpMode < 0) @pvpMode = 2;
    if(@pvpMode > 2) @pvpMode = 0;
    @pvpChanged = true;
    @stg_toast("PVP: " + @stg_value(argument0), 1);
  }else{
    @stg_toast("PVP is not available for this game", 1);
  }
  return 0;
}
return @stg_act(argument0);

///// script @stg_toast
// REMOVED: the transient pop-up duplicated what the detail pane and the footer
// hint already say, and it overlapped the list. Returning immediately keeps every
// call site valid while nothing is ever stored, so @stg_toast_active() stays false
// and no box is drawn anywhere.
// args: text, kind -> 0
return 0;

///// script @stg_toast_active
// args: none -> 1 while a toast is on screen
if(global.__ONLINE_stgToastMsg == "") return 0;
if(current_time > global.__ONLINE_stgToastUntil){ global.__ONLINE_stgToastMsg = ""; return 0; }
return 1;

// ---------------------------------------------------------------------------
// Account rows
// ---------------------------------------------------------------------------

///// script @acc_label_name
// Panel text for the name row.
// args: none -> text
var _n;
_n = global.__ONLINE_accName;
if(string_length(_n) > 22) _n = string_copy(_n, 1, 19) + "...";
if(_n == "") return "(not set)";
return _n;

///// script @acc_label_pass
// Session-key row text. The raw value is NEVER drawn: a fixed six-star mask when
// set (a length-proportional mask would leak the length) and "(empty)" when not.
// args: none -> text
if(global.__ONLINE_accEnvManaged) return "******";
if(string_length(global.__ONLINE_accPassword) > 0) return "******";
return "(empty)";

///// script @acc_edit_name
// Modal edit of the name (GM8 has no inline text input with IME support, so the
// dialog is the only reliable way to type CJK). The dialog is prefilled with the
// current value and GM8's get_string returns that default on cancel, so
// cancelling never clears the field.
// args: none -> 0
var _v, _old;
_old = global.__ONLINE_accName;
#if STUDIO
_v = get_string("Name", _old);
#endif
#if not STUDIO
#if CJKTEXT
_v = __ONLINE_ansi_to_utf8(wd_input_box("Name", "Enter your name:", _old));
#endif
#if not CJKTEXT
_v = wd_input_box("Name", "Enter your name:", _old);
#endif
#endif
_v = @account_trim(_v);
if(_v == _old) return 0;
if(_v == ""){
  global.__ONLINE_stgClearRow = 12;
  global.__ONLINE_stgClearOld = _old;
  @stg_toast("Clear the name? Enter=Yes Esc=No", 1);
  return 0;
}
global.__ONLINE_accName = _v;
if(@account_save()) @stg_toast("Name saved", 0); else @stg_toast("Cannot write " + global.__ONLINE_accWritePath, 2);
return 0;

///// script @acc_edit_pass
// Modal edit of the session key (same cancel semantics as the name).
// args: none -> 0
var _v, _old;
_old = global.__ONLINE_accPassword;
#if STUDIO
_v = get_string("Leave it empty for no password:", _old);
#endif
#if not STUDIO
#if CJKTEXT
_v = __ONLINE_ansi_to_utf8(wd_input_box("Password", "Leave it empty for no password:", _old));
#endif
#if not CJKTEXT
_v = wd_input_box("Password", "Leave it empty for no password:", _old);
#endif
#endif
_v = @account_trim(_v);
if(_v == _old) return 0;
if(_v == "" && _old != ""){
  global.__ONLINE_stgClearRow = 13;
  global.__ONLINE_stgClearOld = _old;
  @stg_toast("Clear the session key? Enter=Yes Esc=No", 1);
  return 0;
}
global.__ONLINE_accPassword = _v;
if(@account_save()) @stg_toast("Session key saved", 0); else @stg_toast("Cannot write " + global.__ONLINE_accWritePath, 2);
return 0;

///// script @acc_clear_commit
// Applies a confirmed clear. args: none -> 0
if(global.__ONLINE_stgClearRow == 22){
  @saveHistClearFiles = true;
  @stg_toast("Cleared every non-favourite save", 1);
  global.__ONLINE_stgClearRow = -1;
  return 0;
}
if(global.__ONLINE_stgClearRow == 12){
  global.__ONLINE_accName = "";
  if(@account_save()) @stg_toast("Name cleared", 1); else @stg_toast("Cannot write " + global.__ONLINE_accWritePath, 2);
}
if(global.__ONLINE_stgClearRow == 13){
  global.__ONLINE_accPassword = "";
  if(@account_save()) @stg_toast("Session key cleared", 1); else @stg_toast("Cannot write " + global.__ONLINE_accWritePath, 2);
}
global.__ONLINE_stgClearRow = -1;
return 0;

///// script @acc_clear_cancel
// Abandons a pending clear. args: none -> 0
global.__ONLINE_stgClearRow = -1;
@stg_toast("Kept the previous value", 1);
return 0;

///// script @acc_toggle_store
// Switches "Store in" between the global file and this game folder. The values
// are copied to the new target first, so switching can never lose them.
// args: none -> 0
var _ok, _to;
if(global.__ONLINE_accEnvManaged){
  @stg_toast("Managed by the environment (IWPO_NAME)", 1);
  return 0;
}
if(global.__ONLINE_accStore == 0) _to = 1; else _to = 0;
_ok = @account_set_store(_to);
if(_ok){
  if(_to == 1) @stg_toast("Saved to the game folder", 0);
  else @stg_toast("Saved globally", 0);
}else{
  @stg_toast("Cannot write " + global.__ONLINE_accWritePath, 2);
}
return 0;

///// script @acc_apply_reconnect
// Saves, pushes the values into the live identity and reconnects - no restart.
// @account_apply writes the caller's variables and the panel runs inside
// with(world) (see worldDrawGui), so the world instance owns the identity.
// args: none -> 0
var _ok;
_ok = @account_save();
@account_apply();
@manualReconnect = true;
if(_ok) @stg_toast("Applied - reconnecting", 0);
else @stg_toast("Applied locally (cannot write " + global.__ONLINE_accWritePath + ")", 2);
return 0;
