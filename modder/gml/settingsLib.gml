/// ONLINE
// ============================================================================
// Settings-menu row table (QoL phase 2).
//
// The Settings tab used to be laid out with hand-written coordinates and row
// indices that drifted with the PLAYER_LIST compile flag (row 7 meant "pick a
// player" in one build and "reconnect" in the other, with the vk_enter branch
// duplicated). Draw, keyboard navigation, mouse hit testing and the action
// handlers now all read one table:
//
//   @stgKind[i]  0 header, 1 status, 2 text, 3 select, 4 toggle, 5 button
//   @stgAct[i]   action id (@stg_act dispatches it)
//   @stgLabel[i] left-hand label
//   @stgY[i]     absolute y of the row (top)
//
// Geometry is fixed by these constants, so the panel height can be checked
// statically (the gate asserts the table fits the 400 px panel):
//
//   row height 20, header height 13, first row at @contentY + 2
//   label x   @spX + 14
//   control x @spX + 150 (buttons/values),  arrows @spX + 334 / @spX + 356
//
// Only tab 0 is table-driven; the other tabs keep their existing renderers.
// ============================================================================

///// script @stg_build_rows
// Rebuilds the tab-0 table for the current panel geometry.
// args: contentY -> 0
globalvar @stgN, @stgKind, @stgAct, @stgLabel, @stgY, @stgRowH, @stgHeadH;
var _y;
@stgN = 0;
_y = argument0 + 2;
@stg_row_add(0, 0, "Connection", _y); _y += @stgHeadH;
@stg_row_add(1, 0, "", _y); _y += @stgRowH;
@stg_row_add(5, 11, "Reconnect now", _y); _y += @stgRowH;
@stg_row_add(5, 15, "Apply & Reconnect", _y); _y += @stgRowH;
@stg_row_add(0, 0, "Account", _y); _y += @stgHeadH;
@stg_row_add(2, 12, "Name:", _y); _y += @stgRowH;
@stg_row_add(2, 13, "Password:", _y); _y += @stgRowH;
@stg_row_add(3, 14, "Store in:", _y); _y += @stgRowH;
@stg_row_add(0, 0, "Gameplay", _y); _y += @stgHeadH;
@stg_row_add(3, 1, "Team:", _y); _y += @stgRowH;
@stg_row_add(4, 2, "Lerp:", _y); _y += @stgRowH;
@stg_row_add(4, 3, "Save:", _y); _y += @stgRowH;
@stg_row_add(4, 4, "Fast:", _y); _y += @stgRowH;
@stg_row_add(3, 8, "PVP:", _y); _y += @stgRowH;
@stg_row_add(4, 9, "Bullets:", _y); _y += @stgRowH;
#if PLAYER_LIST
@stg_row_add(5, 10, "Player Objects:", _y); _y += @stgRowH;
#endif
@stg_row_add(0, 0, "Display", _y); _y += @stgHeadH;
@stg_row_add(3, 5, "Visual:", _y); _y += @stgRowH;
@stg_row_add(4, 6, "Indicator:", _y); _y += @stgRowH;
@stg_row_add(3, 7, "Spec Cam:", _y); _y += @stgRowH;
@stgHeight = _y - argument0;
return 0;

///// script @stg_row_add
// Appends one row (kind, action id, label, y) and returns its index.
// args: kind, act, label, y -> index
globalvar @stgN, @stgKind, @stgAct, @stgLabel, @stgY;
var _i;
_i = @stgN;
@stgKind[_i] = argument0;
@stgAct[_i] = argument1;
@stgLabel[_i] = argument2;
@stgY[_i] = argument3;
@stgN = _i + 1;
return _i;

///// script @stg_in_rect
// GM8.0-safe rectangle test: point_in_rectangle is 8.1+ only, and the shared
// templates have to run on 8.0 as well.
// args: px, py, x1, y1, x2, y2 -> 1/0
if(argument0 >= argument2 && argument0 <= argument4 && argument1 >= argument3 && argument1 <= argument5) return 1;
return 0;

///// script @stg_row_at
// Mouse hit test: argument0 = menu-space y, argument1 = fudge. Returns the row
// index or -1 (header rows and the status row are not clickable).
// args: y, extraHeight -> row index / -1
globalvar @stgN, @stgKind, @stgY, @stgRowH;
var _i;
_i = 0;
while(_i < @stgN){
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1){
    if(argument0 >= @stgY[_i] - 2 && argument0 < @stgY[_i] + @stgRowH + argument1) return _i;
  }
  _i += 1;
}
return -1;

///// script @stg_first_row
// First selectable row (used when the keyboard focus enters the panel).
// args: none -> row index
globalvar @stgN, @stgKind;
var _i;
_i = 0;
while(_i < @stgN){
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1) return _i;
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
  if(@stgKind[_i] != 0 && @stgKind[_i] != 1) return _i;
  _n += 1;
}
return argument0;

///// script @stg_status_text
// Live connection state for the status row (Q3 fills in the failure reasons;
// every value here comes from the existing socket state machine).
// args: none -> text
globalvar @stgStatusMsg;
if(@stgStatusMsg != "") return @stgStatusMsg;
if(@server == "") return "Server not configured";
if(@reconnecting) return "Reconnecting (" + string(@reconnectAttempts) + "/10)...";
if(@connected) return "Online";
if(@tcpState == 2) return "Online";
if(@socketConnectResult == 0) return "Cannot reach " + @server + ":" + string(@tcpPort);
if(!@connected) return "Connecting...";
return "Offline";

///// script @stg_status_color
// args: none -> colour matching @stg_status_text
if(@server == "") return c_gray;
if(@reconnecting) return make_color_rgb(220, 200, 60);
if(@connected || @tcpState == 2) return make_color_rgb(40, 180, 60);
if(@socketConnectResult == 0) return make_color_rgb(200, 60, 60);
return make_color_rgb(220, 200, 60);

///// script @stg_value
// Display string for a row (the panel never shows the raw password).
// args: row -> text
globalvar @stgAct, @stgKind;
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
  @specCamNames[0] = "Free"; @specCamNames[1] = "Locked";
  return @specCamNames[@specCamMode];
}
if(_a == 8){
  if(!@pvpAvail) return "N/A";
  @pvpModeNames[0] = "Off"; @pvpModeNames[1] = "Team"; @pvpModeNames[2] = "FFA";
  return @pvpModeNames[@pvpMode];
}
if(_a == 9){
  if(@pvpMode != 0) return @stg_onoff(@bulletShow) + " (locked)";
  return @stg_onoff(@bulletShow);
}
if(_a == 10) return "Pick";
if(_a == 11) return "Now";
return "";

///// script @stg_onoff
// args: flag -> "ON"/"OFF"
if(argument0) return "ON";
return "OFF";

///// script @stg_kind_of
// args: row -> kind
globalvar @stgKind;
return @stgKind[argument0];

///// script @stg_hint
// Bottom hint line for the focused row.
// args: row -> text
globalvar @stgAct;
var _a;
_a = @stgAct[argument0];
if(_a == 12) return "Your in-game name. Enter to edit (saved to the account store).";
if(_a == 13) return "Session key: players sharing it meet each other. Not an account password.";
if(_a == 14) return "Where the name and key are saved (Global = every game).";
if(_a == 15) return "Save the account and reconnect with the new identity.";
if(_a == 11) return "Drop the current connection and connect again.";
if(_a == 10) return "Choose which player object drives your character.";
if(_a == 1) return "Team colour used for names and the roster.";
if(_a == 8) return "Player versus player mode. Bullets stay visible while it is on.";
return "";

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
if(_a == 6){ @showArrows = !@showArrows; return 0; }
if(_a == 7){ @specCamMode = 1 - @specCamMode; return 0; }
if(_a == 8){ if(@pvpAvail){ @pvpMode += 1; if(@pvpMode > 2) @pvpMode = 0; @pvpChanged = true; } return 0; }
if(_a == 9){ if(@pvpMode == 0){ @bulletShow = !@bulletShow; @bulletChanged = true; } return 0; }
if(_a == 10){ @settingsOpen = false; @debug_pick_player = true; return 1; }
if(_a == 11){ @manualReconnect = true; @stg_toast("Reconnecting...", 1); return 0; }
if(_a == 12){ @acc_edit_name(); return 0; }
if(_a == 13){ @acc_edit_pass(); return 0; }
if(_a == 14){ @acc_toggle_store(); return 0; }
if(_a == 15){ @acc_apply_reconnect(); return 0; }
return 0;

///// script @stg_act_dir
// Directional variant used by Left/Right and by the < > arrow zones: select and
// toggle rows with a direction, everything else behaves like @stg_act.
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
if(_a == 6){
  @showArrows = !@showArrows;
  @stg_toast("Indicator: " + @stg_onoff(@showArrows), 1);
  return 0;
}
return @stg_act(argument0);

///// script @stg_init
// One-time defaults for the row-table / toast / clear-confirm state. Called from
// worldCreate: only a script carrying the globalvar declarations may initialise
// them, because a bare assignment inside an event would create an instance
// variable of the same name instead.
//
// The panel geometry is primed here as well: the Settings hotkey is handled in
// EndStep, which runs BEFORE the draw event of the same frame, so on the first
// frame the panel opens @contentY/@spX would still be unset.
// args: none -> 0
globalvar @stgN, @stgHeight, @stgClearRow, @stgClearOld, @stgRowH, @stgHeadH;
globalvar @stgToastMsg, @stgToastKind, @stgToastUntil;
globalvar @stgStatusMsg;
globalvar @stgInitDone;
if(@stgInitDone == 1) return 0;
@stgInitDone = 1;
@stgN = 0;
@stgHeight = 0;
// layout constants (the gate checks the whole table against the 354 px content area)
@stgRowH = 18;
@stgHeadH = 12;
@stgClearRow = -1;
@stgClearOld = "";
@stgToastMsg = "";
@stgToastKind = 0;
@stgToastUntil = 0;
@stgStatusMsg = "";
// geometry fallback (worldDrawGui recomputes the same values every frame)
if(view_enabled){
  @hudWinW = view_wport[0];
  @hudWinH = view_hport[0];
}else{
  @hudWinW = room_width;
  @hudWinH = room_height;
}
if(@hudWinW < 1) @hudWinW = 640;
if(@hudWinH < 1) @hudWinH = 480;
@spW = 420;
@spH = 400;
@spX = floor((@hudWinW - @spW) / 2);
@spY = floor((@hudWinH - @spH) / 2);
if(@spX < 0) @spX = 0;
if(@spY < 0) @spY = 0;
@tabH = 22;
@contentY = @spY + @tabH + 6;
return 0;

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
// Panel text for the name row: the value, its source, and environment overrides.
// args: none -> text
globalvar @accName, @accEnvManaged;
var _n;
if(@accEnvManaged) return @accName + "  [env]";
_n = @accName;
if(string_length(_n) > 16) _n = string_copy(_n, 1, 13) + "...";
if(_n == "") return "(not set)";
return _n;

///// script @acc_label_pass
// Panel text for the session-key row. The raw value is NEVER drawn: a fixed
// six-star mask when set (a length-proportional mask would leak the length) and
// "(empty)" when the key is empty.
// args: none -> text
globalvar @accPassword, @accEnvManaged;
if(@accEnvManaged) return "******  [env]";
if(string_length(@accPassword) > 0) return "******";
return "(empty)";

///// script @acc_edit_name
// Modal edit of the name (GM8 has no inline text input with IME support, so the
// dialog is the only reliable way to type CJK). The dialog is prefilled with the
// current value, and GM8's get_string returns that default when the user
// cancels - so cancelling never clears the field.
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
  // Cancel and clear are indistinguishable on some dialog implementations: ask
  // before dropping a value the player already had (in-panel, no new modal).
  @stgClearRow = 12;
  @stgClearOld = _old;
  @stg_toast("Clear the name? Enter=Yes Esc=No", 1);
  return 0;
}
@accName = _v;
@account_save();
@stg_toast("Name saved", 0);
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
@account_save();
@stg_toast("Session key saved", 0);
return 0;

///// script @acc_clear_commit
// Applies a confirmed clear. args: none -> 0
globalvar @stgClearRow, @accName, @accPassword;
if(@stgClearRow == 12){
  @accName = "";
  if(@account_save()) @stg_toast("Name cleared", 2); else @stg_toast("Cannot write " + @accWritePath, 2);
}
if(@stgClearRow == 13){
  @accPassword = "";
  if(@account_save()) @stg_toast("Session key cleared", 2); else @stg_toast("Cannot write " + @accWritePath, 2);
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
globalvar @accStore, @accEnvManaged;
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
// @account_apply writes the caller's variables; the panel runs inside
// with(world) (see worldDrawGui), so the world instance owns the identity.
// args: none -> 0
var _ok;
_ok = @account_save();
@account_apply();
@manualReconnect = true;
if(_ok) @stg_toast("Applied - reconnecting", 0);
else @stg_toast("Applied locally (cannot write " + @accWritePath + ")", 2);
return 0;
