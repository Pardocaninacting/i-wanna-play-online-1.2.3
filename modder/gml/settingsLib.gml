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
// Layout (panel 600x460, two columns for Gameplay/Display):
//
//   +------------------------------------------------------------+
//   | [Settings][Saves][Rating][Keys][Sync][Skins]               |
//   | CONNECTION                                                 |
//   |  * Online                          Server: 1.2.3.4:8002    |
//   |  [ Reconnect now ]                                         |
//   |  [ Apply & Reconnect ]                                     |
//   | ACCOUNT                                                    |
//   |  Name:     [ QoLFirst                              ]       |
//   |  Password: [ ******                                ]       |
//   |  Store in: [ Global ]                                      |
//   | GAMEPLAY                    DISPLAY                        |
//   |  Team:  [ None < > ]        Visual:    [ All < > ]         |
//   |  Lerp:  [ ON ]              Indicator: [ OFF ]             |
//   |  ...                        Spec Cam:  [ Free < > ]        |
//   +------------------------------------------------------------+
//   hint line
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
global.__ONLINE_stgRowH = 24;
global.__ONLINE_stgHeadH = 18;
// Panel geometry is derived by @stg_layout (worldCreate primes it via @stg_init,
// worldDrawGui re-derives it per frame) - a hardcoded size in the draw path once
// forked the two and the row table overflowed the panel.
// panel geometry + layout mode (see @stg_layout - narrow is the shipped layout)
@stgScroll = 0;
@stgFirst = 0;
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
//   narrow (default) : content 600px - exactly the layout that ships today
//   full             : content 420px + detail 220px, only when the port is wide
//                      enough (or when the per-game ini forces it)
//
// The @sp* / @colW / @detW variables are the CALLER's (world instance) - never
// declared globalvar here, for the same reason @account_apply must not.
// args: none -> 0
var _w, _h, _full;
_w = @hudWinW;
_h = @hudWinH;
if(_w < 1 || _h < 1){
  if(view_enabled){
    _w = view_wport[0];
    _h = view_hport[0];
  }else{
    _w = room_width;
    _h = room_height;
  }
  @hudWinW = _w;
  @hudWinH = _h;
}
if(_w < 1) _w = 640;
if(_h < 1) _h = 480;
_full = false;
if(@menuModePref == 2) _full = true;
if(@menuModePref == 0 && _w >= 660 && _h >= 420) _full = true;
if(_full){
  @colW = 420;
  @detW = 220;
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
  if(@detW > 0 && @colW < 360){
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
var _y, _cl, _cr, _cf, _btnW, _fw;
global.__ONLINE_stgN = 0;
_y = argument0 + 2;
_cl = @spX + 16;                 // left column label x (content left edge)
// The two-column Gameplay|Display arrangement needs the full 600px column;
// when the detail pane takes part of the panel (@colW < 560) the sections
// stack instead - that is what the full layout uses._cr = @spX + 16 + 284;

_cf = @spX + 16 + 110;           // account field x
_btnW = 240;
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
@stg_row_add(2, 12, "Name:", _cl, _y, _fw, 0, _cf); _y += global.__ONLINE_stgRowH + 2;
@stg_row_add(2, 13, "Password:", _cl, _y, _fw, 0, _cf); _y += global.__ONLINE_stgRowH + 2;
@stg_row_add(3, 14, "Store in:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
// --- gameplay / display side by side
_y += 6;
// Gameplay and Display are always ONE column (maintainer decision):
// the detail pane carries the extra breadth, and a second column only
// made both halves harder to scan.
@stg_row_add(0, 0, "GAMEPLAY", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(3, 1, "Team:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 2, "Lerp:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 3, "Save:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 4, "Fast:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(3, 8, "PVP:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 9, "Bullets:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
_y += 6;
@stg_row_add(0, 0, "DISPLAY", _cl, _y, 0, 0, 0); _y += global.__ONLINE_stgHeadH;
@stg_row_add(3, 5, "Visual:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(4, 6, "Indicator:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
@stg_row_add(3, 7, "Spec Cam:", _cl, _y, 130, 0, 0); _y += global.__ONLINE_stgRowH;
#if PLAYER_LIST
@stg_row_add(5, 10, "Player Objects:", _cl, _y, 150, 1, _cf); _y += global.__ONLINE_stgRowH;
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
    if(argument0 >= global.__ONLINE_stgX[_i] - 6 && argument0 < global.__ONLINE_stgX[_i] + global.__ONLINE_stgCW[_i] + 200) return _i;
  }
  _i += 1;
}
return -1;

///// script @stg_wrap
// Draws text wrapped to argument3 px, at most argument4 lines, and returns the
// height used. GM8 has no text wrapping, and the detail pane needs it.
// args: x, y, text, width, maxLines -> height
var _rest, _line, _word, _sp, _h, _cnt;
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
    if(_line == ""){
      if(string_width(_word) > argument3 && string_length(_word) > 1){
        // a single word longer than the column: hard-break it
        _word = string_copy(_word, 1, max(1, string_length(_word) - 1));
      }
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
if(_a == 10) return "Choose which player object drives your character.";
return "";

///// script @stg_draw_detail
// Draws the detail column for one row (full layout only: @detW > 0).
// Everything here is local - the previous version kept scratch state in
// @-prefixed instance variables and one of them could be read unset, which GM8
// treats as a fatal "Cannot compare arguments".
// args: row -> 0
var _a, _k, _x, _w, _y, _val, _i, _n, _head, _cnt, _txt, _fn, _acts;
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
draw_text(_x, _y, global.__ONLINE_stgLabel[argument0]);
_y += 22;
// value card (green frame when a toggle is on)
_val = @stg_value(argument0);
if(_k == 4 || _k == 3 || _k == 5){
  if(_k == 4 && _val == "ON"){
    draw_set_color(make_color_rgb(50, 170, 80));
  }else{
    draw_set_color(make_color_rgb(95, 95, 100));
  }
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
  global.__ONLINE_detFK[1] = "Used by";
  global.__ONLINE_detFV[1] = "roster, chat, saves";
  _fn = 2;
}
if(_a == 13){
  global.__ONLINE_detFK[0] = "State";
  if(string_length(global.__ONLINE_accPassword) > 0){
    global.__ONLINE_detFV[0] = "set (masked)";
  }else{
    global.__ONLINE_detFV[0] = "empty";
  }
  global.__ONLINE_detFK[1] = "Shown as";
  global.__ONLINE_detFV[1] = "****** (never drawn)";
  _fn = 2;
}
if(_a == 14){
  global.__ONLINE_detFK[0] = "This folder";
  global.__ONLINE_detFV[0] = global.__ONLINE_accLocalPath;
  global.__ONLINE_detFK[1] = "Env override";
  global.__ONLINE_detFV[1] = "IWPO_NAME / IWPO_PASSWORD";
  _fn = 2;
}
if(_fn > 0){
  _y += 8;
  draw_set_color(make_color_rgb(70, 80, 95));
  draw_rectangle(_x, _y, _x + _w, _y + 1, false);
  _y += 8;
  _i = 0;
  while(_i < _fn){
    draw_set_color(make_color_rgb(120, 126, 134));
    draw_text(_x, _y + @stgTextDY, global.__ONLINE_detFK[_i]);
    draw_set_color(c_white);
    draw_text(_x + 80, _y + @stgTextDY, global.__ONLINE_detFV[_i]);
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
if(string_length(_acts) > 0){
  draw_set_color(make_color_rgb(150, 190, 230));
  draw_text(_x, @stgBottom - 18 + @stgTextDY, _acts);
}
return 0;
///// script @stg_plural
// args: n -> "s" or ""
if(argument0 == 1) return "";
return "s";

///// script @stg_row_add
// Appends one row and returns its index.
// args: kind, act, label, x, y, controlWidth, controlStyle, cxOverride
//   controlStyle 0 = left-aligned button/box at x, 1 = wide button centred in the
//   column, 2 = toggle pill, 3 = select value + arrows
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
// Moves the selection by argument1 rows, skipping headers/status.
// args: from, delta -> new row index
var _i, _d, _n;
_i = argument0;
_d = argument1;
_n = 0;
while(_n < 64){
  _i += _d;
  if(_i < 0) return argument0;
  if(_i >= global.__ONLINE_stgN) return argument0;
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
  if(@pvpMode != 0) return @stg_onoff(@bulletShow) + " lock";
  return @stg_onoff(@bulletShow);
}
if(_a == 10) return "Pick";
if(_a == 11) return "Reconnect now";
if(_a == 15) return "Apply & Reconnect";
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
return "Up/Down rows, Left/Right change, Enter edit - F1 or O closes.";

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
if(_a == 10){ @settingsOpen = false; @debug_pick_player = true; return 1; }
if(_a == 11){ @manualReconnect = true; @stg_toast("Reconnecting...", 1); return 0; }
if(_a == 12){ @acc_edit_name(); return 0; }
if(_a == 13){ @acc_edit_pass(); return 0; }
if(_a == 14){ @acc_toggle_store(); return 0; }
if(_a == 15){ @acc_apply_reconnect(); return 0; }
return 0;

///// script @stg_act_dir
// Directional variant used by Left/Right and the < > arrow zones.
// args: row, dir -> 1 when the action closed the menu
var _a;
_a = global.__ONLINE_stgAct[argument0];
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
// Transient panel message (2.5 s): kind 0 = green, 1 = yellow, 2 = red.
// args: text, kind -> 0
global.__ONLINE_stgToastMsg = argument0;
global.__ONLINE_stgToastKind = argument1;
global.__ONLINE_stgToastUntil = current_time + 2500;
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
_v = get_string("Session key (empty = open session)", _old);
#endif
#if not STUDIO
#if CJKTEXT
_v = __ONLINE_ansi_to_utf8(wd_input_box("Password", "Session key (empty = open session):", _old));
#endif
#if not CJKTEXT
_v = wd_input_box("Password", "Session key (empty = open session):", _old);
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
