/// ONLINE
// ============================================================================
// Notes system script pack (opcode 20 NOTE; supersedes the PING marker
// arrays — legacy clients' opcode 11 pings are folded into the same store).
// The converter splits this file at the "///// script <name>" markers into
// standalone script assets (content before the first marker is dropped), so
// every section must be self-contained. No template argument placeholders.
//
// All scripts run with self = the world instance (called from worldEndStep /
// worldDraw), so they read/write the world instance variables from
// worldCreate.gml / worldCreateGMS.gml directly. All scripts return an
// explicit value: GM8.0 errors when a caller uses the result of a script
// that never returns one.
// ============================================================================

///// script @note_set_mode
// Single source for note-UI mode transitions (one setter, no parallel state
// edits). Modes: 0 idle, 2 wheel visible, 3 icon palette (modal). The wheel
// opens immediately on H press — a quick release lands in the center deadzone
// and re-fires the last icon, so tap and hold share one code path.
// @noteNoClick mirrors "any modal UI open" so the other HUD hotkeys can gate
// on it. No io_clear here: clearing input mid-gesture would kill held
// movement keys (fangame players hold shift / arrows while pinging) and
// would fake an H release into the state machine.
// Leaving to idle also restores the OS cursor if the wheel edge-clamp had
// captured it into the wheel center (see @note_warp_cursor).
// args: 0 mode
if(argument0 == 0 && @noteWarped){
    @noteWarped = 0;
    window_mouse_set(@noteMouseWX, @noteMouseWY);
}
@noteMode = argument0;
@noteNoClick = 0;
if(@noteMode >= 2){
    @noteNoClick = 1;
}
return 0;

///// script @note_warp_cursor
// Moves the OS cursor to a room position — used when the wheel's DRAW center
// was edge-clamped away from the anchor, so the gesture stays visually
// consistent with the on-screen wheel. Port-space conversion mirrors the
// HUD prelude (window 1:1 in the common windowed case).
// args: 0 room x, 1 room y
if(view_enabled && view_visible[0]){
    window_mouse_set((argument0 - view_xview[0]) * view_wport[0] / view_wview[0] + view_xport[0], (argument1 - view_yview[0]) * view_hport[0] / view_hview[0] + view_yport[0]);
}else{
    window_mouse_set(argument0 * window_get_width() / room_width, argument1 * window_get_height() / room_height);
}
return 0;

///// script @note_clamp_center
// Writes @noteCX/@noteCY: the anchor clamped 90px inside the active view
// (wheel/palette render + hover center). The note itself lands at the raw
// anchor; only the UI moves. View 0 is the reference, matching the existing
// EndStep-side view idiom.
// args: none
@noteCX = @noteAnchorX;
@noteCY = @noteAnchorY;
if(view_enabled && view_visible[0]){
    if(view_wview[0] > 180){
        @noteCX = min(max(@noteCX, view_xview[0] + 90), view_xview[0] + view_wview[0] - 90);
    }
    if(view_hview[0] > 180){
        @noteCY = min(max(@noteCY, view_yview[0] + 90), view_yview[0] + view_hview[0] - 90);
    }
}else{
    if(room_width > 180){
        @noteCX = min(max(@noteCX, 90), room_width - 90);
    }
    if(room_height > 180){
        @noteCY = min(max(@noteCY, 90), room_height - 90);
    }
}
return 0;

///// script @note_add
// Appends one note to the ring store. Per-sender-per-kind FIFO cap: when the
// sender already owns @notePerCap live notes of this kind, their OLDEST such
// note is evicted instead of the global head, so one spammer cannot flush
// everyone else's notes off the board.
// args: 0 kind (0=ICON), 1 room, 2 x, 3 y, 4 iconId, 5 senderID, 6 name, 7 team
@naSlot = -1;
@naCount = 0;
@naOldestSeq = -1;
@naOldestSlot = -1;
for(@naI = 0; @naI < @noteMax; @naI += 1){
    if(@noteSeqArr[@naI] < 0) continue;
    if(@noteKindArr[@naI] != argument0) continue;
    if(@noteSenderArr[@naI] != argument5) continue;
    @naCount += 1;
    if(@naOldestSlot < 0 || @noteSeqArr[@naI] < @naOldestSeq){
        @naOldestSeq = @noteSeqArr[@naI];
        @naOldestSlot = @naI;
    }
}
if(@naCount >= @notePerCap && @naOldestSlot >= 0){
    @naSlot = @naOldestSlot;
}else{
    @naSlot = @noteHead;
    @noteHead = (@noteHead + 1) mod @noteMax;
}
@noteKindArr[@naSlot] = argument0;
@noteRoomArr[@naSlot] = argument1;
@noteX[@naSlot] = argument2;
@noteY[@naSlot] = argument3;
@noteIcon[@naSlot] = argument4;
@noteSenderArr[@naSlot] = argument5;
@noteName[@naSlot] = argument6;
@noteTeamArr[@naSlot] = argument7;
@noteT[@naSlot] = current_time;
@noteSeqArr[@naSlot] = @noteSeq;
@noteSeq += 1;
return @naSlot;

///// script @note_fire
// Fires an ICON note at a world position: sends opcode 20 sub 0 (the server
// downgrades it to a legacy opcode 11 ping for pre-v4 peers) and stores the
// note locally. Send-side version gate mirrors the bullet channel (a client
// this new never talks to a pre-v4 server in practice; the guard keeps the
// script safe if it ever does).
// args: 0 iconId, 1 x, 2 y
if(@socket != -1 && @connected && @protocolVersion >= 4){
    __ONLINE_buffer_clear(@buffer);
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 0);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_float32(@buffer, argument1);
        __ONLINE_buffer_write_float32(@buffer, argument2);
        __ONLINE_buffer_write_uint8(@buffer, argument0);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, 20);
        __ONLINE_buffer_write_u8(@buffer, 0);
        __ONLINE_buffer_write_i32(@buffer, room);
        __ONLINE_buffer_write_float(@buffer, argument1);
        __ONLINE_buffer_write_float(@buffer, argument2);
        __ONLINE_buffer_write_u8(@buffer, argument0);
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@note_add(0, room, argument1, argument2, argument0, @selfID, @name, @team);
@noteLastIcon = argument0;
#if STUDIO
    audio_play_sound(@sndChatbox, 0, false);
#endif
#if not STUDIO
    sound_play(@sndChatbox);
#endif
return 0;

///// script @note_draw_icon
// Draws one vector-zone note glyph (iconId 0..9: 0..8 = legacy PING shapes,
// 9 = X "fake/wrong"). Caller owns draw state: font + fa_center/fa_middle
// must be set before the call (glyphs 0 and 8 draw text); alpha and color
// are applied internally and NOT restored (callers save/restore around
// their loops).
// args: 0 iconId, 1 x, 2 y, 3 scale, 4 alpha, 5 anim age ms
@ndId = floor(argument0);
if(@ndId < 0 || @ndId > 9) @ndId = 4;
@ndX = argument1;
@ndY = argument2;
@ndS = argument3;
@ndA = argument4;
@ndAge = argument5;
draw_set_alpha(@ndA);
if(@ndId == 0){
    @ndBob = round(sin(@ndAge * 0.010) * @ndS);
    @ndR = 8 * @ndS + sin(@ndAge * 0.008) * 1.2 * @ndS;
    draw_set_color(make_color_rgb(88, 118, 150));
    draw_circle(@ndX, @ndY, @ndR, true);
    draw_set_color(c_black);
    draw_text(@ndX - 1, @ndY + @ndBob, "?");
    draw_text(@ndX + 1, @ndY + @ndBob, "?");
    draw_text(@ndX, @ndY - 1 + @ndBob, "?");
    draw_text(@ndX, @ndY + 1 + @ndBob, "?");
    draw_set_color(c_white);
    draw_text(@ndX, @ndY + @ndBob, "?");
}
if(@ndId == 1 || @ndId == 3 || @ndId == 5 || @ndId == 7){
    @ndLen = (6 + sin(@ndAge * 0.014) * 1.5) * @ndS;
    @ndTail = 2 * @ndS;
    draw_set_color(c_white);
    if(@ndId == 1){
        draw_triangle(@ndX - 5 * @ndS, @ndY, @ndX + 5 * @ndS, @ndY, @ndX, @ndY - @ndLen, false);
        draw_rectangle(@ndX - @ndTail, @ndY, @ndX + @ndTail, @ndY + @ndLen, false);
    }
    if(@ndId == 3){
        draw_triangle(@ndX, @ndY - 5 * @ndS, @ndX, @ndY + 5 * @ndS, @ndX - @ndLen, @ndY, false);
        draw_rectangle(@ndX, @ndY - @ndTail, @ndX + @ndLen, @ndY + @ndTail, false);
    }
    if(@ndId == 5){
        draw_triangle(@ndX, @ndY - 5 * @ndS, @ndX, @ndY + 5 * @ndS, @ndX + @ndLen, @ndY, false);
        draw_rectangle(@ndX - @ndLen, @ndY - @ndTail, @ndX, @ndY + @ndTail, false);
    }
    if(@ndId == 7){
        draw_triangle(@ndX - 5 * @ndS, @ndY, @ndX + 5 * @ndS, @ndY, @ndX, @ndY + @ndLen, false);
        draw_rectangle(@ndX - @ndTail, @ndY - @ndLen, @ndX + @ndTail, @ndY, false);
    }
}
if(@ndId == 2){
    @ndSafeR = (8 + sin(@ndAge * 0.010) * 1.3) * @ndS;
    draw_set_alpha(@ndA * 0.24);
    draw_set_color(make_color_rgb(74, 222, 128));
    draw_circle(@ndX, @ndY, @ndSafeR, false);
    draw_set_alpha(@ndA);
    draw_circle(@ndX, @ndY, 8 * @ndS, true);
    draw_set_color(c_black);
    draw_line_width(@ndX - 5 * @ndS, @ndY + 1 * @ndS, @ndX - 1 * @ndS, @ndY + 5 * @ndS, 3);
    draw_line_width(@ndX - 1 * @ndS, @ndY + 5 * @ndS, @ndX + 6 * @ndS, @ndY - 4 * @ndS, 3);
    draw_set_color(c_white);
    draw_line_width(@ndX - 5 * @ndS, @ndY, @ndX - 1 * @ndS, @ndY + 4 * @ndS, 2);
    draw_line_width(@ndX - 1 * @ndS, @ndY + 4 * @ndS, @ndX + 6 * @ndS, @ndY - 5 * @ndS, 2);
}
if(@ndId == 4){
    @ndInner = 3 * @ndS;
    if((@ndAge div 200) mod 2 == 0) @ndInner = 5 * @ndS;
    draw_set_color(c_white);
    draw_circle(@ndX, @ndY, 7 * @ndS, true);
    draw_circle(@ndX, @ndY, @ndInner, true);
    draw_line_width(@ndX - 11 * @ndS, @ndY, @ndX - 6 * @ndS, @ndY, 2);
    draw_line_width(@ndX + 6 * @ndS, @ndY, @ndX + 11 * @ndS, @ndY, 2);
    draw_line_width(@ndX, @ndY - 11 * @ndS, @ndX, @ndY - 6 * @ndS, 2);
    draw_line_width(@ndX, @ndY + 6 * @ndS, @ndX, @ndY + 11 * @ndS, 2);
    draw_circle(@ndX, @ndY, 1, false);
}
if(@ndId == 6){
    @ndWaitR = 8 * @ndS + sin(@ndAge * 0.008) * 0.8 * @ndS;
    @ndWaitH = 6 * @ndS + sin(@ndAge * 0.010) * 1.0 * @ndS;
    @ndWaitGap = 4 * @ndS + sin(@ndAge * 0.008) * 0.7 * @ndS;
    draw_set_color(make_color_rgb(88, 106, 122));
    draw_circle(@ndX, @ndY, @ndWaitR, true);
    draw_set_color(c_white);
    draw_rectangle(@ndX - @ndWaitGap - 2, @ndY - @ndWaitH, @ndX - @ndWaitGap + 2, @ndY + @ndWaitH, false);
    draw_rectangle(@ndX + @ndWaitGap - 2, @ndY - @ndWaitH, @ndX + @ndWaitGap + 2, @ndY + @ndWaitH, false);
}
if(@ndId == 8){
    @ndWarnCol = make_color_rgb(250, 204, 21);
    if((@ndAge div 100) mod 2 == 0) @ndWarnCol = make_color_rgb(251, 191, 36);
    draw_set_color(@ndWarnCol);
    draw_triangle(@ndX - 10 * @ndS, @ndY + 8 * @ndS, @ndX + 10 * @ndS, @ndY + 8 * @ndS, @ndX, @ndY - 10 * @ndS, false);
    draw_set_color(c_black);
    draw_text(@ndX, @ndY + 1 * @ndS, "!");
}
if(@ndId == 9){
    // X mark: "fake / wrong" semantics (fake block, trap, bait).
    draw_set_color(c_black);
    draw_line_width(@ndX - 6 * @ndS, @ndY - 6 * @ndS, @ndX + 6 * @ndS, @ndY + 6 * @ndS, 3);
    draw_line_width(@ndX - 6 * @ndS, @ndY + 6 * @ndS, @ndX + 6 * @ndS, @ndY - 6 * @ndS, 3);
    draw_set_color(make_color_rgb(239, 68, 68));
    draw_line_width(@ndX - 6 * @ndS, @ndY - 6 * @ndS, @ndX + 6 * @ndS, @ndY + 6 * @ndS, 2);
    draw_line_width(@ndX - 6 * @ndS, @ndY + 6 * @ndS, @ndX + 6 * @ndS, @ndY - 6 * @ndS, 2);
}
return 0;
