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
@notePtsN[@naSlot] = 0;
@noteText[@naSlot] = "";
if(argument0 == 1){
    // POLYLINE: points staged in @noteStageX/Y[0..@noteStageN-1]
    @notePtsN[@naSlot] = @noteStageN;
    for(@naJ = 0; @naJ < @noteStageN; @naJ += 1){
        @notePtsX[@naSlot * 24 + @naJ] = @noteStageX[@naJ];
        @notePtsY[@naSlot * 24 + @naJ] = @noteStageY[@naJ];
    }
}
if(argument0 == 3){
    // TEXT: payload staged in @noteStageText
    @noteText[@naSlot] = @noteStageText;
}
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

///// script @note_sender_info
// Resolves a note sender id to display name + team (onlinePlayer instances
// first, teamMap fallback) into @ntName/@ntTeam, and plays the arrival sound
// when notes are currently visible. Shared by the case 11 (legacy PING) and
// case 20 (NOTE) receivers.
// args: 0 senderID
@ntName = "?";
@ntTeam = -1;
for(@nsI = 0; @nsI < instance_number(@onlinePlayer); @nsI += 1){
    @nsP = instance_find(@onlinePlayer, @nsI);
    if(@nsP.@ID == argument0){
        @ntName = @nsP.@name;
        @ntTeam = @nsP.@team;
        break;
    }
}
if(@ntTeam < 0 || @ntTeam > 7){
    if(ds_map_exists(@teamMap, argument0)){
        @ntTeam = ds_map_find_value(@teamMap, argument0);
    }else{
        @ntTeam = 0;
    }
}
if(@noteCanvasMode != 2 && argument0 != @selfID && !@noteHideAll && !@noteHideOthers){
    #if STUDIO
        audio_play_sound(@sndChatbox, 0, false);
    #endif
    #if not STUDIO
        sound_play(@sndChatbox);
    #endif
}
return 0;

///// script @note_fire_poly
// Submits the staged polyline (@noteStageX/Y[0..@noteStageN-1]) as a NOTE
// POLYLINE (sub 1). Wire flags: bit0 = end arrowhead (always set); bit1 =
// flowing node chevrons — receivers derive that from the node count, so the
// bit is informational only. self = world instance.
// args: none
if(@noteStageN < 2) return 0;
if(@socket != -1 && @connected && @protocolVersion >= 4){
    __ONLINE_buffer_clear(@buffer);
    @npFlags = 1;
    if(@noteStageN > 2) @npFlags = 3;
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 1);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_uint8(@buffer, @npFlags);
        __ONLINE_buffer_write_uint8(@buffer, @noteStageN);
        for(@npI = 0; @npI < @noteStageN; @npI += 1){
            __ONLINE_buffer_write_float32(@buffer, @noteStageX[@npI]);
            __ONLINE_buffer_write_float32(@buffer, @noteStageY[@npI]);
        }
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, 20);
        __ONLINE_buffer_write_u8(@buffer, 1);
        __ONLINE_buffer_write_i32(@buffer, room);
        __ONLINE_buffer_write_u8(@buffer, @npFlags);
        __ONLINE_buffer_write_u8(@buffer, @noteStageN);
        for(@npI = 0; @npI < @noteStageN; @npI += 1){
            __ONLINE_buffer_write_float(@buffer, @noteStageX[@npI]);
            __ONLINE_buffer_write_float(@buffer, @noteStageY[@npI]);
        }
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@note_add(1, room, @noteStageX[0], @noteStageY[0], 0, @selfID, @name, @team);
#if STUDIO
    audio_play_sound(@sndChatbox, 0, false);
#endif
#if not STUDIO
    sound_play(@sndChatbox);
#endif
return 0;

///// script @note_fire_text
// Submits a TEXT note (sub 3, stringNT payload) at a world position.
// args: 0 x, 1 y, 2 text (already truncated/escaped by the caller)
if(argument2 == "") return 0;
if(@socket != -1 && @connected && @protocolVersion >= 4){
    __ONLINE_buffer_clear(@buffer);
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 3);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_float32(@buffer, argument0);
        __ONLINE_buffer_write_float32(@buffer, argument1);
        __ONLINE_buffer_write_string(@buffer, argument2);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, 20);
        __ONLINE_buffer_write_u8(@buffer, 3);
        __ONLINE_buffer_write_i32(@buffer, room);
        __ONLINE_buffer_write_float(@buffer, argument0);
        __ONLINE_buffer_write_float(@buffer, argument1);
        __ONLINE_buffer_write_string(@buffer, argument2);
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@noteStageText = argument2;
@note_add(3, room, argument0, argument1, 0, @selfID, @name, @team);
#if STUDIO
    audio_play_sound(@sndChatbox, 0, false);
#endif
#if not STUDIO
    sound_play(@sndChatbox);
#endif
return 0;

///// script @note_draw_poly
// Draws a stored POLYLINE note: 3px team-colored segments, an end arrowhead,
// and for 3+ nodes a stream of chevrons flowing along the path (movement
// direction/rhythm cue). No name label, no backing ring.
// args: 0 slot, 1 alpha
@npS = argument0;
@npA = argument1;
@npN = @notePtsN[@npS];
if(@npN < 2) return 0;
// proximity fade: distance from the local player to the nearest point of the
// PATH (point-to-segment per segment) — a long polyline crossing the player
// must fade too, not only near its first node
if(!@spectating && @pExists){
    @npFade = 1;
    for(@npI = 0; @npI < @npN - 1; @npI += 1){
        @npX1 = @notePtsX[@npS * 24 + @npI];
        @npY1 = @notePtsY[@npS * 24 + @npI];
        @npX2 = @notePtsX[@npS * 24 + @npI + 1];
        @npY2 = @notePtsY[@npS * 24 + @npI + 1];
        @npDX = @npX2 - @npX1;
        @npDY = @npY2 - @npY1;
        @npL2 = @npDX * @npDX + @npDY * @npDY;
        @npT = 0;
        if(@npL2 > 0) @npT = ((@X - @npX1) * @npDX + (@Y - @npY1) * @npDY) / @npL2;
        if(@npT < 0) @npT = 0;
        if(@npT > 1) @npT = 1;
        @npD = point_distance(@X, @Y, @npX1 + @npT * @npDX, @npY1 + @npT * @npDY);
        if(@npD / 100 < @npFade) @npFade = @npD / 100;
    }
    @npA *= @npFade;
    if(@npA <= 0) return 0;
}
@npCol = @teamColors[@noteTeamArr[@npS]];
if(@noteTeamArr[@npS] < 0 || @noteTeamArr[@npS] > 7) @npCol = @teamColors[0];
draw_set_alpha(@npA);
draw_set_color(@npCol);
@npTotal = 0;
for(@npI = 0; @npI < @npN - 1; @npI += 1){
    @npX1 = @notePtsX[@npS * 24 + @npI];
    @npY1 = @notePtsY[@npS * 24 + @npI];
    @npX2 = @notePtsX[@npS * 24 + @npI + 1];
    @npY2 = @notePtsY[@npS * 24 + @npI + 1];
    draw_line_width(@npX1, @npY1, @npX2, @npY2, 3);
    @npSegLen[@npI] = point_distance(@npX1, @npY1, @npX2, @npY2);
    @npTotal += @npSegLen[@npI];
    draw_circle(@npX1, @npY1, 2, false);
}
// end arrowhead
@npAX = @notePtsX[@npS * 24 + @npN - 2];
@npAY = @notePtsY[@npS * 24 + @npN - 2];
@npBX = @notePtsX[@npS * 24 + @npN - 1];
@npBY = @notePtsY[@npS * 24 + @npN - 1];
@npDir = point_direction(@npAX, @npAY, @npBX, @npBY);
draw_triangle(@npBX, @npBY, @npBX + lengthdir_x(12, @npDir + 150), @npBY + lengthdir_y(12, @npDir + 150), @npBX + lengthdir_x(12, @npDir - 150), @npBY + lengthdir_y(12, @npDir - 150), false);
// flowing chevrons (direction cue along the whole path)
if(@npN > 2 && @npTotal > 0){
    @npSpacing = 48;
    @npOff = (current_time * 0.045) mod @npSpacing;
    @npD = @npOff + 1;
    while(@npD < @npTotal){
        @npAcc = 0;
        @npI = 0;
        @npL = 0;
        while(@npI < @npN - 1){
            @npL = @npSegLen[@npI];
            if(@npAcc + @npL >= @npD) break;
            @npAcc += @npL;
            @npI += 1;
        }
        if(@npI >= @npN - 1) break;
        @npT = 0;
        if(@npL > 0) @npT = (@npD - @npAcc) / @npL;
        @npX1 = @notePtsX[@npS * 24 + @npI];
        @npY1 = @notePtsY[@npS * 24 + @npI];
        @npX2 = @notePtsX[@npS * 24 + @npI + 1];
        @npY2 = @notePtsY[@npS * 24 + @npI + 1];
        @npPX = @npX1 + (@npX2 - @npX1) * @npT;
        @npPY = @npY1 + @npT * (@npY2 - @npY1);
        @npDir = point_direction(@npX1, @npY1, @npX2, @npY2);
        @npFX = @npPX + lengthdir_x(4, @npDir);
        @npFY = @npPY + lengthdir_y(4, @npDir);
        draw_line_width(@npPX + lengthdir_x(5, @npDir + 140), @npPY + lengthdir_y(5, @npDir + 140), @npFX, @npFY, 2);
        draw_line_width(@npPX + lengthdir_x(5, @npDir - 140), @npPY + lengthdir_y(5, @npDir - 140), @npFX, @npFY, 2);
        @npD += @npSpacing;
    }
}
return 0;

///// script @note_draw_text
// Draws a stored TEXT note: team-colored single-line text centered at the
// anchor over a dim backing plate, 4-direction outline. No name label (the
// text itself is the message). Platform branches mirror the name-label code.
// Caller owns the font (already set by the notes draw preamble).
// args: 0 slot, 1 alpha
@nxS = argument0;
@nxA = argument1;
@nxText = @noteText[@nxS];
if(@nxText == "") return 0;
@nxX = @noteX[@nxS];
@nxY = @noteY[@nxS];
@nxCol = @teamColors[@noteTeamArr[@nxS]];
if(@noteTeamArr[@nxS] < 0 || @noteTeamArr[@nxS] > 7) @nxCol = @teamColors[0];
draw_set_alpha(@nxA);
#if GM80
    // FoxWriting path (GM8.0): fw align stubs pass through to GM's draw
    // state, so leave them at the ambient center/middle (restoring left/top
    // here would misalign every glyph drawn later this frame)
    __ONLINE_fw_use_font(@nxText);
    @nxW = fw_string_width_ext(@nxText, -1, 9999);
    draw_set_alpha(@nxA * 0.5);
    draw_set_color(c_black);
    draw_rectangle(@nxX - @nxW / 2 - 4, @nxY - 9, @nxX + @nxW / 2 + 4, @nxY + 9, false);
    draw_set_alpha(@nxA);
    fw_draw_set_halign(fa_center);
    fw_draw_set_valign(fa_middle);
    fw_draw_text_ext(@nxX + 1, @nxY, @nxText, 9999);
    fw_draw_text_ext(@nxX - 1, @nxY, @nxText, 9999);
    fw_draw_text_ext(@nxX, @nxY + 1, @nxText, 9999);
    fw_draw_text_ext(@nxX, @nxY - 1, @nxText, 9999);
    draw_set_color(@nxCol);
    fw_draw_text_ext(@nxX, @nxY, @nxText, 9999);
#endif
#if CJKTEXT
    @nxW = __ONLINE_cjk_string_width_ext(@nxText, -1, 9999);
    @nxH = __ONLINE_cjk_string_height_ext(@nxText, -1, 9999);
    @nxLX = round(@nxX - @nxW * 0.5);
    @nxLY = round(@nxY - @nxH * 0.5);
    draw_set_alpha(@nxA * 0.5);
    draw_set_color(c_black);
    draw_rectangle(@nxLX - 4, @nxLY - 2, @nxLX + @nxW + 4, @nxLY + @nxH + 2, false);
    draw_set_alpha(@nxA);
    global.__ONLINE_cjkHalign = 0;
    global.__ONLINE_cjkValign = 0;
    __ONLINE_cjk_draw_text(@nxLX - 1, @nxLY, @nxText, 9999);
    __ONLINE_cjk_draw_text(@nxLX + 1, @nxLY, @nxText, 9999);
    __ONLINE_cjk_draw_text(@nxLX, @nxLY - 1, @nxText, 9999);
    __ONLINE_cjk_draw_text(@nxLX, @nxLY + 1, @nxText, 9999);
    draw_set_color(@nxCol);
    __ONLINE_cjk_draw_text(@nxLX, @nxLY, @nxText, 9999);
#endif
#if not GM80
#if not CJKTEXT
    @nxW = string_width(@nxText);
    @nxH = string_height(@nxText);
    @nxLX = round(@nxX - @nxW * 0.5);
    @nxLY = round(@nxY - @nxH * 0.5);
    draw_set_alpha(@nxA * 0.5);
    draw_set_color(c_black);
    draw_rectangle(@nxLX - 4, @nxLY - 2, @nxLX + @nxW + 4, @nxLY + @nxH + 2, false);
    draw_set_alpha(@nxA);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_text(@nxLX - 1, @nxLY, @nxText);
    draw_text(@nxLX + 1, @nxLY, @nxText);
    draw_text(@nxLX, @nxLY - 1, @nxText);
    draw_text(@nxLX, @nxLY + 1, @nxText);
    draw_set_color(@nxCol);
    draw_text(@nxLX, @nxLY, @nxText);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
#endif
#endif
return 0;
