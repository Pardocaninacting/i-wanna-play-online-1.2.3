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
//   @stgKind[i]  0 header, 1 status, 2 text, 3 select, 4 toggle, 5 button, 7 double header
//   @stgAct[i]   action id (@stg_act / @stg_act_dir dispatch it)
//   @stgLabel[i] label text
//   @stgX[i]     label x, @stgCX[i]/@stgCW[i] control x + width
//   @stgY[i]     row y (top)
//
// Layout (panel 560x424, two columns for Gameplay/Display):
//
//   +----------------------------------------------------------+
//   | [Settings][Saves][Rating][Keys][Sync][Skins]             |
//   | CONNECTION                                               |
//   |  * Online                        Server: 1.2.3.4:8002    |
//   |  [ Reconnect now ]  [ Apply & Reconnect ]                |
//   | ACCOUNT                                                  |
//   |  Name:     [ QoLFirst                       ]  Global    |
//   |  Password: [ ******                         ]            |
//   |  Store in: Global  < >                                   |
//   | GAMEPLAY                    DISPLAY                      |
//   |  Team:  None < >            Visual:    All < >           |
//   |  Lerp:  [ ON ]              Indicator: [ OFF ]           |
//   |  ...                        Spec Cam:  Free < >          |
//   +----------------------------------------------------------+
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
globalvar @stgN, @stgHeight, @stgClearRow, @stgClearOld, @stgRowH, @stgHeadH;
globalvar @stgToastMsg, @stgToastKind, @stgToastUntil;
globalvar @stgStatusMsg;
globalvar @accName, @accPassword, @accSource, @accStore, @accEnvManaged, @accWritePath;
var _w, _h;
@stgN = 0;
@stgHeight = 0;
@stgClearRow = -1;
@stgClearOld = "";
@stgToastMsg = "";
@stgToastKind = 0;
@stgToastUntil = 0;
@stgStatusMsg = "";
@accName = "";
@accPassword = "";
@accSource = 0;
@accStore = 0;
@accEnvManaged = 0;
@accWritePath = "";
// layout constants (the gate checks the whole table against the panel)
@stgRowH = 24;
@stgHeadH = 16;
// panel geometry, clamped to the view-port (560x424 fits an 800x600 window)
if(view_enabled){
  _w = view_wport[0];
  _h = view_hport[0];
}else{
  _w = room_width;
  _h = room_height;
}
if(_w < 1) _w = 640;
if(_h < 1) _h = 480;
@spW = 560;
@spH = 444;
if(@spW > _w - 20) @spW = _w - 20;
if(@spH > _h - 20) @spH = _h - 20;
@hudWinW = _w;
@hudWinH = _h;
@spX = floor((_w - @spW) / 2);
@spY = floor((_h - @spH) / 2);
if(@spX < 0) @spX = 0;
if(@spY < 0) @spY = 0;
@tabH = 24;
@contentY = @spY + @tabH + 6;
return 0;

///// script @stg_build_rows
// Rebuilds the tab-0 table for the current panel geometry.
// args: contentY -> 0
globalvar @stgN, @stgKind, @stgAct, @stgLabel, @stgX, @stgCX, @stgCW, @stgY;
globalvar @stgRowH, @stgHeadH, @spX;
var _y, _l, _r, _lx, _rx;
@stgN = 0;
_y = argument0 + 2;
_l = @spX + 18;
_r = @spX + 292;
_lx = @spX + 150;
_rx = @spX + 398;
// --- connection
@stg_row_add(0, 0, "CONNECTION", _l, _y, 0, 0); _y += @stgHeadH;
@stg_row_add(1, 0, "", _l, _y, 0, 0); _y += @stgRowH;
@stg_row_add(5, 11, "", _l, _y, 118, 1); _y += @stgRowH;
@stg_row_add(5, 15, "", _l, _y, 118, 1); _y += @stgRowH;
// --- account
_y += 4;
@stg_row_add(0, 0, "ACCOUNT", _l, _y, 0, 0); _y += @stgHeadH;
@stg_row_add(2, 12, "Name:", _l, _y, 330, 0); _y += @stgRowH + 2;
@stg_row_add(2, 13, "Password:", _l, _y, 330, 0); _y += @stgRowH + 2;
@stg_row_add(3, 14, "Store in:", _l, _y, 90, 0); _y += @stgRowH;
// --- gameplay / display side by side
_y += 4;
@stg_row_add(7, 0, "GAMEPLAY|DISPLAY", _l, _y, _r, 0); _y += @stgHeadH;
@stg_row_add(3, 1, "Team:", _l, _y, 90, 0);
@stg_row_add(3, 5, "Visual:", _r, _y, 70, 0); _y += @stgRowH;
@stg_row_add(4, 2, "Lerp:", _l, _y, 70, 0);
@stg_row_add(4, 6, "Indicator:", _r, _y, 70, 0); _y += @stgRowH;
@stg_row_add(4, 3, "Save:", _l, _y, 70, 0);
@stg_row_add(3, 7, "Spec Cam:", _r, _y, 70, 0); _y += @stgRowH;
@stg_row_add(4, 4, "Fast:", _l, _y, 70, 0); _y += @stgRowH;
@stg_row_add(3, 8, "PVP:", _l, _y, 90, 0); _y += @stgRowH;
@stg_row_add(4, 9, "Bullets:", _l, _y, 70, 0); _y += @stgRowH;
#if PLAYER_LIST
@stg_row_add(5, 10, "Player Objects:", _l, _y, 118, 1); _y += @stgRowH;
#endif
@stgHeight = _y - argument0;
return 0;

///// script @stg_row_add
// Appends one row and returns its index.
// args: kind, act, label, x, y, controlWidth, controlStyle -> index
//   controlStyle 0 = left-aligned button/box at x, 1 = wide button centred in the
//   column, 2 = toggle pill, 3 = select value + arrows
globalvar @stgN, @stgKind, @stgAct, @stgLabel, @stgX, @stgCX, @stgCW, @stgY, @stgStyle;
var _i;
_i = @stgN;
@stgKind[_i] = argument0;
@stgAct[_i] = argument1;
@stgLabel[_i] = argument2;
@stgX[_i] = argument3;
@stgY[_i] = argument4;
@stgCX[_i] = argument3 + 132;
@stgCW[_i] = argument5;
@stgStyle[_i] = argument6;
@stgN = _i + 1;
return _i;

///// script @stg_hit_row
// Mouse hit test in panel space. Returns the row index or -1; headers, the status
// row and non-interactive rows are skipped.
// args: mx, my -> row index / -1
globalvar @stgN, @stgKind, @stgX, @stgY, @stgCX, @stgCW, @stgRowH, @spW;
var _i;
_i = 0;
while(_i < @stgN){
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1 && @stgKind[_i] != 7){
    if(argument1 >= @stgY[_i] - 1 && argument1 < @stgY[_i] + @stgRowH - 2){
      // accept the whole row strip: label + control stay one click target
      if(argument0 >= @stgX[_i] - 4 && argument0 < @stgX[_i] + @stgCW[_i] + 168) return _i;
    }
  }
  _i += 1;
}
return -1;

///// script @stg_first_row
// First selectable row (keyboard focus entry point).
// args: none -> row index
globalvar @stgN, @stgKind;
var _i;
_i = 0;
while(_i < @stgN){
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1 && @stgKind[_i] != 7) return _i;
  _i += 1;
}
return 0;

///// script @stg_next_row
// Moves the selection by argument1 rows, skipping headers/status.
// args: from, delta -> new row index
globalvar @stgN, @stgKind;
var _i, _d, _n;
_i = argument0;
_d = argument1;
_n = 0;
while(_n < 64){
  _i += _d;
  if(_i < 0) return argument0;
  if(_i >= @stgN) return argument0;
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1 && @stgKind[_i] != 7) return _i;
  _n += 1;
}
return argument0;

///// script @stg_status_text
// Live connection state for the status row. Everything here comes from the
// existing socket state machine, so the panel works while offline.
// args: none -> text
globalvar @stgStatusMsg;
if(@stgStatusMsg != "") return @stgStatusMsg;
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
globalvar @accSource, @accEnvManaged;
if(@accEnvManaged) return "env";
if(@accSource == 2) return "folder";
if(@accSource == 3) return "global";
return "";

///// script @stg_value
// Display string for a row (the panel never shows the raw session key).
// args: row -> text
globalvar @stgAct;
var _a;
_a = @stgAct[argument0];
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
globalvar @stgKind;
return @stgKind[argument0];

///// script @stg_style_of
// args: row -> control style
globalvar @stgStyle;
return @stgStyle[argument0];

///// script @stg_hint
// Bottom hint line for the focused row.
// args: row -> text
globalvar @stgAct;
var _a;
_a = @stgAct[argument0];
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
globalvar @stgAct;
var _a;
_a = @stgAct[argument0];
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
globalvar @stgAct;
var _a;
_a = @stgAct[argument0];
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
globalvar @stgToastMsg, @stgToastKind, @stgToastUntil;
@stgToastMsg = argument0;
@stgToastKind = argument1;
@stgToastUntil = current_time + 2500;
return 0;

///// script @stg_toast_active
// args: none -> 1 while a toast is on screen
globalvar @stgToastMsg, @stgToastUntil;
if(@stgToastMsg == "") return 0;
if(current_time > @stgToastUntil){ @stgToastMsg = ""; return 0; }
return 1;

// ---------------------------------------------------------------------------
// Account rows
// ---------------------------------------------------------------------------

///// script @acc_label_name
// Panel text for the name row.
// args: none -> text
globalvar @accName, @accEnvManaged;
var _n;
_n = @accName;
if(string_length(_n) > 22) _n = string_copy(_n, 1, 19) + "...";
if(_n == "") return "(not set)";
return _n;

///// script @acc_label_pass
// Session-key row text. The raw value is NEVER drawn: a fixed six-star mask when
// set (a length-proportional mask would leak the length) and "(empty)" when not.
// args: none -> text
globalvar @accPassword, @accEnvManaged;
if(@accEnvManaged) return "******";
if(string_length(@accPassword) > 0) return "******";
return "(empty)";

///// script @acc_edit_name
// Modal edit of the name (GM8 has no inline text input with IME support, so the
// dialog is the only reliable way to type CJK). The dialog is prefilled with the
// current value and GM8's get_string returns that default on cancel, so
// cancelling never clears the field.
// args: none -> 0
globalvar @accName;
var _v, _old;
_old = @accName;
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
  @stgClearRow = 12;
  @stgClearOld = _old;
  @stg_toast("Clear the name? Enter=Yes Esc=No", 1);
  return 0;
}
@accName = _v;
if(@account_save()) @stg_toast("Name saved", 0); else @stg_toast("Cannot write " + @accWritePath, 2);
return 0;

///// script @acc_edit_pass
// Modal edit of the session key (same cancel semantics as the name).
// args: none -> 0
globalvar @accPassword;
var _v, _old;
_old = @accPassword;
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
  @stgClearRow = 13;
  @stgClearOld = _old;
  @stg_toast("Clear the session key? Enter=Yes Esc=No", 1);
  return 0;
}
@accPassword = _v;
if(@account_save()) @stg_toast("Session key saved", 0); else @stg_toast("Cannot write " + @accWritePath, 2);
return 0;

///// script @acc_clear_commit
// Applies a confirmed clear. args: none -> 0
globalvar @stgClearRow, @accName, @accPassword, @accWritePath;
if(@stgClearRow == 12){
  @accName = "";
  if(@account_save()) @stg_toast("Name cleared", 1); else @stg_toast("Cannot write " + @accWritePath, 2);
}
if(@stgClearRow == 13){
  @accPassword = "";
  if(@account_save()) @stg_toast("Session key cleared", 1); else @stg_toast("Cannot write " + @accWritePath, 2);
}
@stgClearRow = -1;
return 0;

///// script @acc_clear_cancel
// Abandons a pending clear. args: none -> 0
globalvar @stgClearRow;
@stgClearRow = -1;
@stg_toast("Kept the previous value", 1);
return 0;

///// script @acc_toggle_store
// Switches "Store in" between the global file and this game folder. The values
// are copied to the new target first, so switching can never lose them.
// args: none -> 0
globalvar @accStore, @accEnvManaged, @accWritePath;
var _ok, _to;
if(@accEnvManaged){
  @stg_toast("Managed by the environment (IWPO_NAME)", 1);
  return 0;
}
if(@accStore == 0) _to = 1; else _to = 0;
_ok = @account_set_store(_to);
if(_ok){
  if(_to == 1) @stg_toast("Saved to the game folder", 0);
  else @stg_toast("Saved globally", 0);
}else{
  @stg_toast("Cannot write " + @accWritePath, 2);
}
return 0;

///// script @acc_apply_reconnect
// Saves, pushes the values into the live identity and reconnects - no restart.
// @account_apply writes the caller's variables and the panel runs inside
// with(world) (see worldDrawGui), so the world instance owns the identity.
// args: none -> 0
globalvar @accWritePath;
var _ok;
_ok = @account_save();
@account_apply();
@manualReconnect = true;
if(_ok) @stg_toast("Applied - reconnecting", 0);
else @stg_toast("Applied locally (cannot write " + @accWritePath + ")", 2);
return 0;
