/// ONLINE
// ============================================================================
// Notes system script pack (opcode 20 NOTE; supersedes the PING marker
// arrays - legacy clients' opcode 11 pings are folded into the same store).
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
// opens immediately on H press - a quick release lands in the center deadzone
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
// Moves the OS cursor to a room position - used when the wheel's DRAW center
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
// Writes @noteCX/@noteCY: the anchor clamped inside the active view with a
// per-mode inset (the wheel needs 90px; the icon matrix needs more).
// args: 0 halfW, 1 halfH (both required - GM8 defaults missing args to 0)
// The note itself lands at the raw anchor; only the UI moves. View 0 is the
// reference, matching the existing EndStep-side view idiom.
@noteCX = @noteAnchorX;
@noteCY = @noteAnchorY;
if(view_enabled && view_visible[0]){
    if(view_wview[0] > argument0 * 2){
        @noteCX = min(max(@noteCX, view_xview[0] + argument0), view_xview[0] + view_wview[0] - argument0);
    }
    if(view_hview[0] > argument1 * 2){
        @noteCY = min(max(@noteCY, view_yview[0] + argument1), view_yview[0] + view_hview[0] - argument1);
    }
}else{
    if(room_width > argument0 * 2){
        @noteCX = min(max(@noteCX, argument0), room_width - argument0);
    }
    if(room_height > argument1 * 2){
        @noteCY = min(max(@noteCY, argument1), room_height - argument1);
    }
}
return 0;

///// script @note_add
// Appends one note to the ring store. Per-sender-per-kind FIFO cap: when the
// sender already owns @notePerCap live notes of this kind, their OLDEST such
// note is evicted instead of the global head, so one spammer cannot flush
// everyone else's notes off the board.
// args: 0 kind (0=ICON), 1 room, 2 x, 3 y, 4 iconId, 5 senderID, 6 name,
// 7 team, 8 wireSeq (the sender-side u16 on the wire; -1 for legacy PING)
@naSlot = -1;
@naCount = 0;
@naOldestSeq = -1;
@naOldestSlot = -1;
@naCap = @notePerCap;
if(argument0 == 2) @naCap = 4;   // strokes: tighter per-sender cap (anti-spam)
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
if(@naCount >= @naCap && @naOldestSlot >= 0){
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
@noteWireArr[@naSlot] = argument8;
@noteSeq += 1;
if(argument5 == @selfID) @noteDirty = 1;
@notePtsN[@naSlot] = 0;
@noteText[@naSlot] = "";
if(argument0 == 1 || argument0 == 2){
    // POLYLINE/STROKE: points staged in @noteStageX/Y[0..@noteStageN-1]
    // (@noteStageBrk marks pen-up boundaries; polylines are all-zero)
    @notePtsN[@naSlot] = @noteStageN;
    for(@naJ = 0; @naJ < @noteStageN; @naJ += 1){
        @notePtsX[@naSlot, @naJ] = @noteStageX[@naJ];
        @notePtsY[@naSlot, @naJ] = @noteStageY[@naJ];
        @notePtsBrk[@naSlot, @naJ] = @noteStageBrk[@naJ];
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
@nfSeq = @note_next_seq();
if(@socket != -1 && @connected){
    __ONLINE_buffer_clear(@buffer);
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 0);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_uint16(@buffer, @nfSeq);
        __ONLINE_buffer_write_float32(@buffer, argument1);
        __ONLINE_buffer_write_float32(@buffer, argument2);
        __ONLINE_buffer_write_uint8(@buffer, argument0);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, 20);
        __ONLINE_buffer_write_u8(@buffer, 0);
        __ONLINE_buffer_write_i32(@buffer, room);
        __ONLINE_buffer_write_u16(@buffer, @nfSeq);
        __ONLINE_buffer_write_float(@buffer, argument1);
        __ONLINE_buffer_write_float(@buffer, argument2);
        __ONLINE_buffer_write_u8(@buffer, argument0);
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@note_add(0, room, argument1, argument2, argument0, @selfID, @name, @team, @nfSeq);
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
@ndX = argument1;
@ndY = argument2;
@ndS = argument3;
@ndA = argument4;
@ndAge = argument5;
// atlas zone: iconId 16-47 draw the 32x32 cell (iconId-16) of the 8x4 grid;
// a missing/invalid atlas falls back to the vector HERE glyph
if(@ndId >= 16 && @ndId <= 47){
    if(@noteAtlasSpr >= 0){
        if(sprite_exists(@noteAtlasSpr)){
            @ndCell = @ndId - 16;
            draw_sprite_part_ext(@noteAtlasSpr, 0, (@ndCell mod 8) * 32, (@ndCell div 8) * 32, 32, 32, @ndX - 16 * @ndS, @ndY - 16 * @ndS, @ndS, @ndS, c_white, @ndA);
            return 0;
        }
    }
    @ndId = 4;
}
if(@ndId < 0 || @ndId > 9) @ndId = 4;
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
// args: 0 senderID, 1 silent (1 = no arrival sound; sync replays)
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
if(!argument1 && @noteCanvasMode != 2 && argument0 != @selfID && !@noteHideAll && !@noteHideOthers){
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
// flowing node chevrons - receivers derive that from the node count, so the
// bit is informational only. self = world instance.
// args: none
if(@noteStageN < 2) return 0;
@nfSeq = @note_next_seq();
if(@socket != -1 && @connected){
    __ONLINE_buffer_clear(@buffer);
    @npFlags = 1;
    if(@noteStageN > 2) @npFlags = 3;
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 1);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_uint16(@buffer, @nfSeq);
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
        __ONLINE_buffer_write_u16(@buffer, @nfSeq);
        __ONLINE_buffer_write_u8(@buffer, @npFlags);
        __ONLINE_buffer_write_u8(@buffer, @noteStageN);
        for(@npI = 0; @npI < @noteStageN; @npI += 1){
            __ONLINE_buffer_write_float(@buffer, @noteStageX[@npI]);
            __ONLINE_buffer_write_float(@buffer, @noteStageY[@npI]);
        }
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@note_add(1, room, @noteStageX[0], @noteStageY[0], 0, @selfID, @name, @team, @nfSeq);
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
@nfSeq = @note_next_seq();
if(@socket != -1 && @connected){
    __ONLINE_buffer_clear(@buffer);
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, 20);
        __ONLINE_buffer_write_uint8(@buffer, 3);
        __ONLINE_buffer_write_int32(@buffer, room);
        __ONLINE_buffer_write_uint16(@buffer, @nfSeq);
        __ONLINE_buffer_write_float32(@buffer, argument0);
        __ONLINE_buffer_write_float32(@buffer, argument1);
        __ONLINE_buffer_write_string(@buffer, argument2);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, 20);
        __ONLINE_buffer_write_u8(@buffer, 3);
        __ONLINE_buffer_write_i32(@buffer, room);
        __ONLINE_buffer_write_u16(@buffer, @nfSeq);
        __ONLINE_buffer_write_float(@buffer, argument0);
        __ONLINE_buffer_write_float(@buffer, argument1);
        __ONLINE_buffer_write_string(@buffer, argument2);
    #endif
    __ONLINE_socket_write_message(@socket, @buffer);
}
@noteStageText = argument2;
@note_add(3, room, argument0, argument1, 0, @selfID, @name, @team, @nfSeq);
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
// PATH (point-to-segment per segment) - a long polyline crossing the player
// must fade too, not only near its first node
if(!@spectating && @pExists){
    @npFade = 1;
    for(@npI = 0; @npI < @npN - 1; @npI += 1){
        @npX1 = @notePtsX[@npS, @npI];
        @npY1 = @notePtsY[@npS, @npI];
        @npX2 = @notePtsX[@npS, @npI + 1];
        @npY2 = @notePtsY[@npS, @npI + 1];
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
@npCol = @teamColors[0];
if(@noteTeamArr[@npS] >= 0 && @noteTeamArr[@npS] <= 7) @npCol = @teamColors[@noteTeamArr[@npS]];
draw_set_alpha(@npA);
draw_set_color(@npCol);
@npTotal = 0;
for(@npI = 0; @npI < @npN - 1; @npI += 1){
    @npX1 = @notePtsX[@npS, @npI];
    @npY1 = @notePtsY[@npS, @npI];
    @npX2 = @notePtsX[@npS, @npI + 1];
    @npY2 = @notePtsY[@npS, @npI + 1];
    draw_line_width(@npX1, @npY1, @npX2, @npY2, 3);
    @npSegLen[@npI] = point_distance(@npX1, @npY1, @npX2, @npY2);
    @npTotal += @npSegLen[@npI];
    draw_circle(@npX1, @npY1, 2, false);
}
// end arrowhead
@npAX = @notePtsX[@npS, @npN - 2];
@npAY = @notePtsY[@npS, @npN - 2];
@npBX = @notePtsX[@npS, @npN - 1];
@npBY = @notePtsY[@npS, @npN - 1];
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
        @npX1 = @notePtsX[@npS, @npI];
        @npY1 = @notePtsY[@npS, @npI];
        @npX2 = @notePtsX[@npS, @npI + 1];
        @npY2 = @notePtsY[@npS, @npI + 1];
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
@nxCol = @teamColors[0];
if(@noteTeamArr[@nxS] >= 0 && @noteTeamArr[@nxS] <= 7) @nxCol = @teamColors[@noteTeamArr[@nxS]];
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

///// script @note_rdp
// Ramer-Douglas-Peucker simplify (epsilon 2px) on the staged stroke
// @noteStageX/Y[0..@noteStageN-1], iterative (explicit stack; GM8 recursion
// is stack-fragile at 480 points). Runs are delimited by @noteStageBrk
// (pen-up boundaries): each sub-path is simplified independently, never
// smoothed across a pen lift. Kept points are compacted back into the
// staging arrays (break flags preserved). Returns the new point count.
@rdpOut = 0;
@rdpStart = 0;
while(@rdpStart < @noteStageN){
    @rdpEnd = @rdpStart + 1;
    while(@rdpEnd < @noteStageN && @noteStageBrk[@rdpEnd] == 0) @rdpEnd += 1;
    for(@rdpI = @rdpStart; @rdpI < @rdpEnd; @rdpI += 1) @noteKeep[@rdpI] = 0;
    @noteKeep[@rdpStart] = 1;
    @noteKeep[@rdpEnd - 1] = 1;
    @rdpStackN = 0;
    @rdpSA[0] = @rdpStart; @rdpSB[0] = @rdpEnd - 1; @rdpStackN = 1;
    while(@rdpStackN > 0){
        @rdpStackN -= 1;
        @rdpA = @rdpSA[@rdpStackN];
        @rdpB = @rdpSB[@rdpStackN];
        if(@rdpB - @rdpA < 2) continue;
        @rdpAX = @noteStageX[@rdpA];
        @rdpAY = @noteStageY[@rdpA];
        @rdpBX = @noteStageX[@rdpB];
        @rdpBY = @noteStageY[@rdpB];
        @rdpDX = @rdpBX - @rdpAX;
        @rdpDY = @rdpBY - @rdpAY;
        @rdpLen = sqrt(@rdpDX*@rdpDX + @rdpDY*@rdpDY);
        @rdpMaxD = 0;
        @rdpMaxI = -1;
        for(@rdpI = @rdpA + 1; @rdpI < @rdpB; @rdpI += 1){
            if(@rdpLen > 0){
                @rdpD = abs(@rdpDY * @noteStageX[@rdpI] - @rdpDX * @noteStageY[@rdpI] + @rdpBX * @rdpAY - @rdpBY * @rdpAX) / @rdpLen;
            }else{
                @rdpD = point_distance(@noteStageX[@rdpI], @noteStageY[@rdpI], @rdpAX, @rdpAY);
            }
            if(@rdpD > @rdpMaxD){
                @rdpMaxD = @rdpD;
                @rdpMaxI = @rdpI;
            }
        }
        if(@rdpMaxD > 2 && @rdpMaxI >= 0){
            @noteKeep[@rdpMaxI] = 1;
            @rdpSA[@rdpStackN] = @rdpA; @rdpSB[@rdpStackN] = @rdpMaxI; @rdpStackN += 1;
            @rdpSA[@rdpStackN] = @rdpMaxI; @rdpSB[@rdpStackN] = @rdpB; @rdpStackN += 1;
        }
    }
    // compact the run into the write cursor (break flag on the run head)
    for(@rdpI = @rdpStart; @rdpI < @rdpEnd; @rdpI += 1){
        if(@noteKeep[@rdpI]){
            @noteStageX[@rdpOut] = @noteStageX[@rdpI];
            @noteStageY[@rdpOut] = @noteStageY[@rdpI];
            @noteStageBrk[@rdpOut] = 0;
            if(@rdpI == @rdpStart && @rdpOut > 0) @noteStageBrk[@rdpOut] = 1;
            @rdpOut += 1;
        }
    }
    @rdpStart = @rdpEnd;
}
@noteStageN = @rdpOut;
return @rdpOut;

///// script @note_fire_stroke
// Finalizes the staged drawing (@noteStageX/Y[0..@noteStageN-1] with
// @noteStageBrk pen-up boundaries): RDP simplify, then send as NOTE STROKE
// chunks (sub 2). Wire chunk: u8 strokeId, u8 chunkIdx|bit6=pen-up start|
// bit7=final, u8 n(1..240), i32 x0, i32 y0, then (n-1) i16 deltas. Each
// sub-path starts a new chunk; over-long sub-paths split mid-path as
// continuation chunks. Stored locally as one kind-2 note either way.
// args: none
if(@noteStageN < 1) return 0;
@note_rdp();
if(@noteStageN < 1) return 0;
@nfSid = @noteStrokeSeq;
@noteStrokeSeq = (@noteStrokeSeq + 1) mod 256;
@nfSeq = @note_next_seq();
@nfOfs = 0;
@nfChunk = 0;
while(@nfOfs < @noteStageN){
    // chunk spans until 240 points or the next pen-up boundary
    @nfN = 0;
    while(@nfOfs + @nfN < @noteStageN && @nfN < 240){
        if(@nfN > 0 && @noteStageBrk[@nfOfs + @nfN]) break;
        @nfN += 1;
    }
    @nfFlags = 0;
    if(@noteStageBrk[@nfOfs]) @nfFlags = 64;
    if(@nfOfs + @nfN >= @noteStageN) @nfFlags += 128;
    if(@socket != -1 && @connected){
        __ONLINE_buffer_clear(@buffer);
        #if not GMNET
            __ONLINE_buffer_write_uint8(@buffer, 20);
            __ONLINE_buffer_write_uint8(@buffer, 2);
            __ONLINE_buffer_write_int32(@buffer, room);
            __ONLINE_buffer_write_uint16(@buffer, @nfSeq);
            __ONLINE_buffer_write_uint8(@buffer, @nfSid);
            __ONLINE_buffer_write_uint8(@buffer, (@nfChunk mod 64) + @nfFlags);
            __ONLINE_buffer_write_uint8(@buffer, @nfN);
            __ONLINE_buffer_write_int32(@buffer, @noteStageX[@nfOfs]);
            __ONLINE_buffer_write_int32(@buffer, @noteStageY[@nfOfs]);
            for(@nfI = 1; @nfI < @nfN; @nfI += 1){
                __ONLINE_buffer_write_int16(@buffer, @noteStageX[@nfOfs + @nfI] - @noteStageX[@nfOfs + @nfI - 1]);
                __ONLINE_buffer_write_int16(@buffer, @noteStageY[@nfOfs + @nfI] - @noteStageY[@nfOfs + @nfI - 1]);
            }
        #endif
        #if GMNET
            __ONLINE_buffer_write_u8(@buffer, 20);
            __ONLINE_buffer_write_u8(@buffer, 2);
            __ONLINE_buffer_write_i32(@buffer, room);
            __ONLINE_buffer_write_u16(@buffer, @nfSeq);
            __ONLINE_buffer_write_u8(@buffer, @nfSid);
            __ONLINE_buffer_write_u8(@buffer, (@nfChunk mod 64) + @nfFlags);
            __ONLINE_buffer_write_u8(@buffer, @nfN);
            __ONLINE_buffer_write_i32(@buffer, @noteStageX[@nfOfs]);
            __ONLINE_buffer_write_i32(@buffer, @noteStageY[@nfOfs]);
            for(@nfI = 1; @nfI < @nfN; @nfI += 1){
                __ONLINE_buffer_write_i16(@buffer, @noteStageX[@nfOfs + @nfI] - @noteStageX[@nfOfs + @nfI - 1]);
                __ONLINE_buffer_write_i16(@buffer, @noteStageY[@nfOfs + @nfI] - @noteStageY[@nfOfs + @nfI - 1]);
            }
        #endif
        __ONLINE_socket_write_message(@socket, @buffer);
    }
    @nfOfs += @nfN;
    @nfChunk += 1;
}
@note_add(2, room, @noteStageX[0], @noteStageY[0], 0, @selfID, @name, @team, @nfSeq);
#if STUDIO
    audio_play_sound(@sndChatbox,  0, false);
#endif
#if not STUDIO
    sound_play(@sndChatbox);
#endif
return 0;

///// script @note_draw_stroke
// Draws a stored STROKE note (a multi-sub-path drawing): team-colored 3px
// path with round joints; @notePtsBrk marks pen-up boundaries (no segment
// drawn into a break point). Same path-proximity fade rule as polylines.
// No arrowhead/chevrons.
// args: 0 slot, 1 alpha
@nsS = argument0;
@nsA = argument1;
@nsN = @notePtsN[@nsS];
if(@nsN < 1) return 0;
if(!@spectating && @pExists && @nsN >= 2){
    @nsFade = 1;
    for(@nsI = 0; @nsI < @nsN - 1; @nsI += 1){
        if(@notePtsBrk[@nsS, @nsI + 1]) continue;
        @nsX1 = @notePtsX[@nsS, @nsI];
        @nsY1 = @notePtsY[@nsS, @nsI];
        @nsX2 = @notePtsX[@nsS, @nsI + 1];
        @nsY2 = @notePtsY[@nsS, @nsI + 1];
        @nsDX = @nsX2 - @nsX1;
        @nsDY = @nsY2 - @nsY1;
        @nsL2 = @nsDX * @nsDX + @nsDY * @nsDY;
        @nsT = 0;
        if(@nsL2 > 0) @nsT = ((@X - @nsX1) * @nsDX + (@Y - @nsY1) * @nsDY) / @nsL2;
        if(@nsT < 0) @nsT = 0;
        if(@nsT > 1) @nsT = 1;
        @nsD = point_distance(@X, @Y, @nsX1 + @nsT * @nsDX, @nsY1 + @nsT * @nsDY);
        if(@nsD / 100 < @nsFade) @nsFade = @nsD / 100;
    }
    @nsA *= @nsFade;
    if(@nsA <= 0) return 0;
}
@nsCol = @teamColors[0];
if(@noteTeamArr[@nsS] >= 0 && @noteTeamArr[@nsS] <= 7) @nsCol = @teamColors[@noteTeamArr[@nsS]];
draw_set_alpha(@nsA);
draw_set_color(@nsCol);
for(@nsI = 0; @nsI < @nsN - 1; @nsI += 1){
    if(@notePtsBrk[@nsS, @nsI + 1]) continue;
    draw_line_width(@notePtsX[@nsS, @nsI], @notePtsY[@nsS, @nsI], @notePtsX[@nsS, @nsI + 1], @notePtsY[@nsS, @nsI + 1], 3);
}
for(@nsI = 0; @nsI < @nsN; @nsI += 1){
    draw_circle(@notePtsX[@nsS, @nsI], @notePtsY[@nsS, @nsI], 1.5, false);
}
return 0;

///// script @note_stroke_recv
// Reassembles STROKE chunks into 8 pending slots keyed by (sender, strokeId).
// Wire chunk: u8 strokeId, u8 chunkIdx|bit6=pen-up start|bit7=final, u8 n,
// i32 x0, i32 y0 (absolute), then (n-1) i16 deltas. Pen-up chunks start a new
// sub-path (break flag at its first point). Final chunk commits one kind-2
// note via the staging arrays. Orphan slots expire after 5s (the STROKE rate
// limiter can legitimately drop chunks).
// args: 0 senderID, 1 replay (past-toast, silent), 2 wire seq
// (caller has just read sub + room + seq into @ntSub/@ntRoom/@ntSeq)
#if not GMNET
    @nsSid = __ONLINE_buffer_read_uint8(@buffer);
    @nsChunk = __ONLINE_buffer_read_uint8(@buffer);
    @nsN = __ONLINE_buffer_read_uint8(@buffer);
#endif
#if GMNET
    @nsSid = __ONLINE_buffer_read_u8(@buffer);
    @nsChunk = __ONLINE_buffer_read_u8(@buffer);
    @nsN = __ONLINE_buffer_read_u8(@buffer);
#endif
// expire stale pending strokes
for(@nsI = 0; @nsI < 8; @nsI += 1){
    if(@noteStrokeN[@nsI] > 0 && current_time - @noteStrokeT[@nsI] > 5000){
        @noteStrokeN[@nsI] = 0;
        @noteStrokeOwner[@nsI] = "";
    }
}
// find or allocate the slot for this (sender, stroke)
@nsSlot = -1;
for(@nsI = 0; @nsI < 8; @nsI += 1){
    if(@noteStrokeN[@nsI] > 0 && @noteStrokeOwner[@nsI] == argument0 && @noteStrokeSid[@nsI] == @nsSid){
        @nsSlot = @nsI;
        break;
    }
}
if(@nsSlot < 0){
    for(@nsI =  0; @nsI < 8; @nsI += 1){
        if(@noteStrokeN[@nsI] ==  0){
            @nsSlot = @nsI;
            break;
        }
    }
    if(@nsSlot < 0){
        // all slots busy: evict the stalest
        @nsSlot = 0;
        @nsOld = @noteStrokeT[0];
        for(@nsI = 1; @nsI < 8; @nsI += 1){
            if(@noteStrokeT[@nsI] < @nsOld){
                @nsOld = @noteStrokeT[@nsI];
                @nsSlot = @nsI;
            }
        }
    }
    @noteStrokeOwner[@nsSlot] = argument0;
    @noteStrokeSid[@nsSlot] = @nsSid;
    @noteStrokeN[@nsSlot] = 0;
}
// decode: absolute first point + i16 deltas, appended to the slot
@nsBase = @noteStrokeN[@nsSlot];
if(@nsBase + @nsN <= 480){
    #if not GMNET
        @nsX = __ONLINE_buffer_read_int32(@buffer);
        @nsY = __ONLINE_buffer_read_int32(@buffer);
    #endif
    #if GMNET
        @nsX = __ONLINE_buffer_read_i32(@buffer);
        @nsY = __ONLINE_buffer_read_i32(@buffer);
    #endif
    @noteStrokePtsX[@nsSlot, @nsBase] = @nsX;
    @noteStrokePtsY[@nsSlot, @nsBase] = @nsY;
    @noteStrokeBrk[@nsSlot, @nsBase] = 0;
    if(@nsChunk >=  64 && @nsBase > 0){
        if((@nsChunk mod 128) >= 64) @noteStrokeBrk[@nsSlot, @nsBase] = 1;
    }
    @nsBase += 1;
    for(@nsI = 1; @nsI < @nsN; @nsI += 1){
        #if not GMNET
            @nsX += __ONLINE_buffer_read_int16(@buffer);
            @nsY += __ONLINE_buffer_read_int16(@buffer);
        #endif
        #if GMNET
            @nsX += __ONLINE_buffer_read_i16(@buffer);
            @nsY += __ONLINE_buffer_read_i16(@buffer);
        #endif
        @noteStrokePtsX[@nsSlot, @nsBase] = @nsX;
        @noteStrokePtsY[@nsSlot, @nsBase] = @nsY;
        @noteStrokeBrk[@nsSlot, @nsBase] = 0;
        @nsBase += 1;
    }
    @noteStrokeN[@nsSlot] = @nsBase;
    @noteStrokeT[@nsSlot] = current_time;
}
if(@nsChunk >= 128 && @noteStrokeN[@nsSlot] >= 1){
    // final chunk: hand over via the staging arrays and commit
    @noteStageN = @noteStrokeN[@nsSlot];
    for(@nsI = 0; @nsI < @noteStageN; @nsI += 1){
        @noteStageX[@nsI] = @noteStrokePtsX[@nsSlot, @nsI];
        @noteStageY[@nsI] = @noteStrokePtsY[@nsSlot, @nsI];
        @noteStageBrk[@nsI] = @noteStrokeBrk[@nsSlot, @nsI];
    }
    @note_sender_info(argument0, argument1);
    if(!@note_dup(2, @ntRoom, @noteStageX[0], @noteStageY[0], @noteStageN, @ntName)){
        @ntSlot = @note_add(2, @ntRoom, @noteStageX[0], @noteStageY[0], 0, argument0, @ntName, @ntTeam, argument2);
        if(argument1) @noteT[@ntSlot] = current_time - 999999999;
    }
    @noteStrokeN[@nsSlot] = 0;
    @noteStrokeOwner[@nsSlot] = "";
}
return 0;

///// script @note_atlas_load
// Loads the built-in icon atlas (iwponotes/icons.png, one 256x128 frame as an
// 8x4 grid of 32x32 cells = iconId 16-47). The sprite id is registered with
// the skin bookkeeper so a game_restart frees it exactly (S1: no blind range
// sweeps). Cells draw via draw_sprite_part_ext. A missing/invalid atlas
// falls back to the vector glyphs. Returns the sprite id (or -1).
// args: none
if(@noteAtlasSpr >= 0){
    if(sprite_exists(@noteAtlasSpr)){
        sprite_delete(@noteAtlasSpr);
    }
    @noteAtlasSpr = -1;
}
@noteAtlasSpr = -1;
if(!file_exists("iwponotes" + chr(92) + "icons.png")) return -1;
@noteAtlasSpr = sprite_add("iwponotes" + chr(92) + "icons.png", 1, false, false, 0, 0);
if(@noteAtlasSpr >= 0){
    if(sprite_get_width(@noteAtlasSpr) != 256 || sprite_get_height(@noteAtlasSpr) != 128){
        sprite_delete(@noteAtlasSpr);
        @noteAtlasSpr = -1;
    }
}
@skin_spr_save();
return @noteAtlasSpr;

///// script @note_render_all
// The whole world-space notes/annotations layer + off-screen arrows, shared
// by two call sites with identical world coordinates:
//  - worldDraw (group 8) for GM8.0/8.1 and GMS
//  - worldDrawGui (group 11, GM8GUI only) under a view-rect ortho sandwich,
//    because group-8 primitives never rasterize in d3d-started rooms (E1).
// Runs with self = the world instance either way.
/// ONLINE
// OFF-SCREEN ARROWS
if(@showArrows || @spectating){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@arVX = 0;
	@arVY = 0;
	@arVW = room_width;
	@arVH = room_height;
	if(view_enabled && view_visible[view_current]){
		@arVX = view_xview[view_current];
		@arVY = view_yview[view_current];
		@arVW = view_wview[view_current];
		@arVH = view_hview[view_current];
	}
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	@arMargin = 16;
	@arInner = 8;
	for(@arI = 0; @arI < instance_number(@onlinePlayer); @arI += 1){
		@arP = instance_find(@onlinePlayer, @arI);
		if(@arP.@oRoom == room && @arP.visible){
		@arPX = @arP.x;
		@arPY = @arP.y;
		if(@arPX < @arVX || @arPX > @arVX + @arVW || @arPY < @arVY || @arPY > @arVY + @arVH){
		@arSX = @arVX + @arVW / 2;
		@arSY = @arVY + @arVH / 2;
		@arDX = @arPX - @arSX;
		@arDY = @arPY - @arSY;
		@arDist = sqrt(@arDX * @arDX + @arDY * @arDY);
		if(@arDist > 0){
			@arVX2 = @arDX / @arDist;
			@arVY2 = @arDY / @arDist;
		}else{
			@arVX2 = 0;
			@arVY2 = 0;
		}
		@arLen = @arDist;
		if(@arVY2 < 0){
			@arLen = min(@arLen, ((@arVY + @arMargin) - @arSY) / @arVY2);
		}
		if(@arVY2 > 0){
			@arLen = min(@arLen, ((@arVY + @arVH - @arMargin) - @arSY) / @arVY2);
		}
		if(@arVX2 < 0){
			@arLen = min(@arLen, ((@arVX + @arMargin) - @arSX) / @arVX2);
		}
		if(@arVX2 > 0){
			@arLen = min(@arLen, ((@arVX + @arVW - @arMargin) - @arSX) / @arVX2);
		}
		@arLen -= @arInner;
		@arAlpha = max(0.2, 1.2 - (@arDist - @arLen) / 1250);
		@arDrawX = @arSX + @arVX2 * @arLen;
		@arDrawY = @arSY + @arVY2 * @arLen;
		@arSize = 14;
		@arTipX = @arDrawX + @arVX2 * @arSize;
		@arTipY = @arDrawY + @arVY2 * @arSize;
		@arTailX = @arDrawX - @arVX2 * @arSize;
		@arTailY = @arDrawY - @arVY2 * @arSize;
		draw_set_alpha(@arAlpha);
		draw_set_color(c_black);
		draw_arrow(@arTailX+2, @arTailY, @arTipX+2, @arTipY, @arSize);
		draw_arrow(@arTailX-2, @arTailY, @arTipX-2, @arTipY, @arSize);
		draw_arrow(@arTailX, @arTailY+2, @arTipX, @arTipY+2, @arSize);
		draw_arrow(@arTailX, @arTailY-2, @arTipX, @arTipY-2, @arSize);
		@_tc = c_white;
		@arTeam = @arP.@team;
		if(@arTeam >= 0 && @arTeam <= 7){
			@_tc = @teamColors[@arTeam];
		}
		draw_set_color(@_tc);
		draw_arrow(@arTailX, @arTailY, @arTipX, @arTipY, @arSize);
		@arLblX = @arDrawX - @arVX2 * 24;
		@arLblY = @arDrawY - @arVY2 * 24;
		draw_set_valign(fa_center);
		draw_set_halign(fa_center);
		@arDispName = @arP.@name;
		#if GM80
		@arDispName = __ONLINE_gbk_trunc(@arDispName, 8, "..");
		#endif
		#if CJKTEXT
		@arDispName = __ONLINE_gbk_trunc(@arDispName, 8, "..");
		#endif
		#if not GM80
		#if not CJKTEXT
		if(string_length(@arDispName) > 8) @arDispName = string_copy(@arDispName, 1, 8) + "..";
		#endif
		#endif
		draw_set_color(c_black);
		#if GM80
		fw_draw_set_halign(fa_center);
		fw_draw_set_valign(fa_center);
		__ONLINE_fw_use_font(@arDispName);
		fw_draw_text_ext(@arLblX+1, @arLblY, @arDispName, 9999);
		fw_draw_text_ext(@arLblX-1, @arLblY, @arDispName, 9999);
		fw_draw_text_ext(@arLblX, @arLblY+1, @arDispName, 9999);
		fw_draw_text_ext(@arLblX, @arLblY-1, @arDispName, 9999);
		draw_set_color(@_tc);
		fw_draw_text_ext(@arLblX, @arLblY, @arDispName, 9999);
		#endif
		#if CJKTEXT
		global.__ONLINE_cjkHalign = 1;
		global.__ONLINE_cjkValign = 1;
		__ONLINE_cjk_draw_text(@arLblX+1, @arLblY, @arDispName, 9999);
		__ONLINE_cjk_draw_text(@arLblX-1, @arLblY, @arDispName, 9999);
		__ONLINE_cjk_draw_text(@arLblX, @arLblY+1, @arDispName, 9999);
		__ONLINE_cjk_draw_text(@arLblX, @arLblY-1, @arDispName, 9999);
		draw_set_color(@_tc);
		__ONLINE_cjk_draw_text(@arLblX, @arLblY, @arDispName, 9999);
		#endif
		#if not GM80
		#if not CJKTEXT
		draw_text(@arLblX+1, @arLblY, @arDispName);
		draw_text(@arLblX-1, @arLblY, @arDispName);
		draw_text(@arLblX, @arLblY+1, @arDispName);
		draw_text(@arLblX, @arLblY-1, @arDispName);
		draw_set_color(@_tc);
		draw_text(@arLblX, @arLblY, @arDispName);
		#endif
		#endif
		}
		}
	}
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	// GM80: no fw_draw_set_* restore here - the fw align stubs pass through
	// to GM's draw state, and the other note draw sites deliberately leave
	// center/middle set (see @note_draw_text). Restoring left/top here
	// misaligns every glyph drawn later this frame.
	#if CJKTEXT
	global.__ONLINE_cjkHalign = 0;
	global.__ONLINE_cjkValign = 0;
	#endif
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
}
// PING DRAW
{
	@pdAlpha = draw_get_alpha();
	@pdColor = draw_get_color();
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	draw_set_halign(fa_center);
	draw_set_valign(fa_middle);
	for(@i = 0; @i < @noteMax; @i += 1){
		if(@noteCanvasMode == 2) break;
		if(@noteSeqArr[@i] < 0) continue;
		if(@noteHideAll) continue;
		if(@noteRoomArr[@i] != room) continue;
		if(@noteHideOthers && @noteSenderArr[@i] != @selfID) continue;
		@pAge = current_time - @noteT[@i];
		if(@pAge < 0) @pAge = 0;
		// every kind shares the emoji's appear-stay-disappear timing (per-kind
		// 15s/20s variants were dropped: inconsistent, not richer)
		@pToastMs = @noteToastMs;
		@pOuterAlpha = 0;
		@pOuterR = 0;
		if(@pAge < @pToastMs){
			@pT = @pAge / @pToastMs;
			if(@pT < 0.053){
				@pK = @pT / 0.053;
				@pScale = 1.15 - 0.15 * (1 - @pK) * (1 - @pK);
				@pA = @pK;
				@pOuterAlpha = 1 - @pK;
				@pOuterR = 16 * (1 + 0.6 * @pK);
			}else if(@pT < 0.833){
				@pScale = 1;
				@pA = 1;
			}else{
				@pK = (@pT - 0.833) / 0.167;
				@pScale = 1 - 0.08 * @pK;
				@pA = 1 - @pK;
			}
		}else{
			// past toast: only the canvas layer (mode 1) still shows the note,
			// dimmed and with glyph animations frozen at the toast end
			if(@noteCanvasMode != 1) continue;
			@pScale = 0.92;
			@pA = 0.25;
			@pAge = @pToastMs;
		}
		@pX = round(@noteX[@i]);
		@pY = round(@noteY[@i]);
		if(!@spectating && @pExists && @noteKindArr[@i] != 1){
			@pA *= min(1, point_distance(@X, @Y, @pX, @pY) / 100);
		}
		if(@pA < 0) @pA = 0;
		if(@pA <= 0) continue;
		@pNT = @noteTeamArr[@i];
		if(@pNT < 0 || @pNT > 7) @pNT = 0;
		@pNC = @teamColors[@pNT];
		if(@noteKindArr[@i] == 1){
			// polyline: no backing ring (the path is the mark)
			@note_draw_poly(@i, @pA);
		}else if(@noteKindArr[@i] == 2){
			// freehand stroke: same, minus arrowhead/chevrons
			@note_draw_stroke(@i, @pA);
		}else if(@noteKindArr[@i] == 3){
			// text note: the text itself is the mark
			@note_draw_text(@i, @pA);
		}else{
			draw_set_alpha(@pA * 0.55);
			draw_set_color(c_black);
			draw_circle(@pX, @pY, 16 * @pScale, false);
			draw_set_alpha(@pA);
			draw_set_color(@pNC);
			draw_circle(@pX, @pY, 18 * @pScale, true);
			draw_circle(@pX, @pY, 19 * @pScale, true);
			if(@pOuterAlpha > 0){
				draw_set_alpha(@pA * @pOuterAlpha * 0.6);
				draw_circle(@pX, @pY, @pOuterR * @pScale, true);
			}
			draw_set_alpha(@pA);
			@note_draw_icon(@noteIcon[@i], @pX, @pY, @pScale, @pA, @pAge);
		}
		// sender name label for every kind (attribution), transient mode only -
		// the canvas layer stays nameless
		draw_set_alpha(@pA);
		if(@noteName[@i] != "" && @noteCanvasMode != 1){
			@pNameDrawX = @pX;
			@pNameDrawY = @pY - 22;
			#if CJKTEXT
			@pNameDrawW = __ONLINE_cjk_string_width_ext(@noteName[@i], -1, 9999);
			@pNameDrawH = __ONLINE_cjk_string_height_ext(@noteName[@i], -1, 9999);
			@pNameDrawX = round(@pX - @pNameDrawW * 0.5);
			@pNameDrawY = round((@pY - 22) - @pNameDrawH * 0.5);
			#endif
			#if not GM80
			#if not CJKTEXT
			@pNameDrawW = string_width(@noteName[@i]);
			@pNameDrawH = string_height(@noteName[@i]);
			@pNameDrawX = round(@pX - @pNameDrawW * 0.5);
			@pNameDrawY = round((@pY - 22) - @pNameDrawH * 0.5);
			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			#endif
			#endif
			draw_set_color(c_black);
			#if GM80
			fw_draw_set_halign(fa_center);
			fw_draw_set_valign(fa_middle);
			__ONLINE_fw_use_font(@noteName[@i]);
			fw_draw_text_ext(@pX - 1, @pY - 22, @noteName[@i], 9999);
			fw_draw_text_ext(@pX + 1, @pY - 22, @noteName[@i], 9999);
			fw_draw_text_ext(@pX, @pY - 23, @noteName[@i], 9999);
			fw_draw_text_ext(@pX, @pY - 21, @noteName[@i], 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 0;
			global.__ONLINE_cjkValign = 0;
			__ONLINE_cjk_draw_text(@pNameDrawX - 1, @pNameDrawY, @noteName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX + 1, @pNameDrawY, @noteName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY - 1, @noteName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY + 1, @noteName[@i], 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@pNameDrawX - 1, @pNameDrawY, @noteName[@i]);
			draw_text(@pNameDrawX + 1, @pNameDrawY, @noteName[@i]);
			draw_text(@pNameDrawX, @pNameDrawY - 1, @noteName[@i]);
			draw_text(@pNameDrawX, @pNameDrawY + 1, @noteName[@i]);
			#endif
			#endif
			draw_set_color(@pNC);
			#if GM80
			fw_draw_text_ext(@pX, @pY - 22, @noteName[@i], 9999);
			#endif
			#if CJKTEXT
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY, @noteName[@i], 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@pNameDrawX, @pNameDrawY, @noteName[@i]);
			draw_set_halign(fa_center);
			draw_set_valign(fa_middle);
			#endif
			#endif
		}
	}
	// anchor crosshair while the wheel/palette is active (what you aim at is what fires: the
	// note lands here even when the wheel itself is edge-clamped away)
	// (defensive: the notes loop above can leave GM draw alignment dirty -
	// the GM8 fw align stubs pass through to draw_set_halign/valign)
	draw_set_halign(fa_center);
	draw_set_valign(fa_middle);
	if(@noteMode >= 2){
		draw_set_alpha(0.9);
		draw_set_color(c_black);
		draw_line_width(@noteAnchorX - 7, @noteAnchorY, @noteAnchorX + 7, @noteAnchorY, 3);
		draw_line_width(@noteAnchorX, @noteAnchorY - 7, @noteAnchorX, @noteAnchorY + 7, 3);
		draw_set_color(c_white);
		draw_line_width(@noteAnchorX - 7, @noteAnchorY, @noteAnchorX + 7, @noteAnchorY, 1);
		draw_line_width(@noteAnchorX, @noteAnchorY - 7, @noteAnchorX, @noteAnchorY + 7, 1);
	}
	// level-1 wheel (mode 2): corners = quick icons, edges = tools, center =
	// last-used icon
	if(@noteMode == 2){
		@wcx = @noteCX;
		@wcy = @noteCY;
		@wstep = 38;
		@wTeam = @team;
		if(@wTeam < 0 || @wTeam > 7) @wTeam = 0;
		draw_set_alpha(0.5);
		draw_set_color(c_black);
		draw_circle(@wcx, @wcy, 80, false);
		for(@row = 0; @row < 3; @row += 1){
			for(@col = 0; @col < 3; @col += 1){
				@cellIdx = @row * 3 + @col;
				@cx = round(@wcx + (@col - 1) * @wstep);
				@cy = round(@wcy + (@row - 1) * @wstep);
				// corners/center carry icons; W edge = more icons (active);
				// N/E/S edges = tools (drawn disabled)
				@cellIcon = -1;
				if(@cellIdx == 0) @cellIcon = 8;
				if(@cellIdx == 2) @cellIcon = 0;
				if(@cellIdx == 6) @cellIcon = 9;
				if(@cellIdx == 8) @cellIcon = 2;
				if(@cellIdx == 4) @cellIcon = @noteLastIcon;
				draw_set_alpha(0.22);
				draw_set_color(c_black);
				draw_circle(@cx, @cy, 14, false);
				if(@cellIdx == @noteWheelHover){
					draw_set_alpha(0.62);
					draw_set_color(@teamColors[@wTeam]);
					draw_circle(@cx, @cy, 12, false);
					draw_set_alpha(1);
					draw_set_color(c_white);
					draw_circle(@cx, @cy, 13, true);
				}else{
					draw_set_alpha(0.34);
					draw_set_color(c_dkgray);
					draw_circle(@cx, @cy, 12, true);
				}
				if(@cellIcon >= 0){
					@note_draw_icon(@cellIcon, @cx, @cy, 0.8, 1, current_time);
				}else if(@cellIdx == 1){
					// arrow tool (active)
					draw_set_alpha(1);
					draw_set_color(c_white);
					draw_line_width(@cx - 5, @cy + 5, @cx + 3, @cy - 3, 2);
					draw_triangle(@cx + 1, @cy - 7, @cx + 7, @cy - 1, @cx + 6, @cy - 6, false);
				}else if(@cellIdx == 5){
					// brush tool
					draw_set_alpha(1);
					draw_set_color(c_white);
					draw_line_width(@cx - 5, @cy + 5, @cx + 3, @cy - 3, 3);
					draw_triangle(@cx + 2, @cy - 2, @cx + 7, @cy - 7, @cx + 6, @cy - 1, false);
				}else if(@cellIdx == 7){
					// text tool (active)
					draw_set_alpha(1);
					draw_set_color(c_white);
					draw_text(@cx, @cy, "T");
				}else if(@cellIdx == 3){
					// more icons: opens the palette
					draw_set_alpha(1);
					draw_set_color(c_white);
					draw_circle(@cx - 4, @cy - 4, 2, false);
					draw_circle(@cx + 4, @cy - 4, 2, false);
					draw_circle(@cx - 4, @cy + 4, 2, false);
					draw_circle(@cx + 4, @cy + 4, 2, false);
				}
			}
		}
	}
	// icon matrix (mode 3): modal 8x6 grid, all icons at once (no paging).
	// identity mapping cell == iconId; cells 10-15 are undecided placeholders.
	if(@noteMode == 3){
		@wcx = @noteCX;
		@wcy = @noteCY;
		@wTeam = @team;
		if(@wTeam < 0 || @wTeam > 7) @wTeam = 0;
		draw_set_alpha(0.72);
		draw_set_color(c_black);
		draw_roundrect(@wcx - 160, @wcy - 124, @wcx + 160, @wcy + 124, false);
		draw_set_alpha(1);
		draw_set_color(c_dkgray);
		draw_roundrect(@wcx - 160, @wcy - 124, @wcx + 160, @wcy + 124, true);
		@wstep = 36;
		for(@cellIdx = 0; @cellIdx < 48; @cellIdx += 1){
			@cx = round(@wcx +((@cellIdx mod 8) - 3.5) * @wstep);
			@cy = round(@wcy + ((@cellIdx div 8) - 2.5) * @wstep);
			@npPh = 0;
			if(@cellIdx > 9 && @cellIdx < 16) @npPh = 1;
			draw_set_alpha(0.22);
			draw_set_color(c_black);
			draw_circle(@cx, @cy, 14, false);
			if(@cellIdx == @notePaletteHover && @npPh == 0){
				draw_set_alpha(0.62);
				draw_set_color(@teamColors[@wTeam]);
				draw_circle(@cx, @cy, 12, false);
				draw_set_alpha(1);
				draw_set_color(c_white);
				draw_circle(@cx, @cy, 13, true);
			}else{
				draw_set_alpha(0.34);
				draw_set_color(c_dkgray);
				draw_circle(@cx, @cy, 12, true);
			}
			if(@npPh){
				// undecided slot: dotted placeholder
				draw_set_alpha(0.30);
				draw_set_color(c_gray);
				draw_circle(@cx, @cy, 5, true);
			}else{
				@note_draw_icon(@cellIdx, @cx, @cy, 0.9, 1, current_time);
			}
			if(@cellIdx == @notePaletteLast){
				draw_set_alpha(1);
				draw_set_color(@teamColors[@wTeam]);
				draw_circle(@cx, @cy + 18, 2, false);
			}
		}
	}
	// in-progress polyline preview (mode 4): staged segments + node dots +
	// live segment to the cursor with arrowhead, plus a controls hint
	if(@noteMode == 4){
		@pvTeam = @team;
		if(@pvTeam < 0 || @pvTeam > 7) @pvTeam = 0;
		draw_set_alpha(0.9);
		draw_set_color(@teamColors[@pvTeam]);
		for(@pvI = 0; @pvI < @noteStageN - 1; @pvI += 1){
			draw_line_width(@noteStageX[@pvI], @noteStageY[@pvI], @noteStageX[@pvI + 1], @noteStageY[@pvI + 1], 3);
			draw_circle(@noteStageX[@pvI], @noteStageY[@pvI], 3, false);
		}
		@pvLX = @noteStageX[@noteStageN - 1];
		@pvLY = @noteStageY[@noteStageN - 1];
		draw_circle(@pvLX, @pvLY, 3, false);
		if(point_distance(@pvLX, @pvLY, mouse_x, mouse_y) > 2){
			draw_line_width(@pvLX, @pvLY, mouse_x, mouse_y, 3);
			@pvDir = point_direction(@pvLX, @pvLY, mouse_x, mouse_y);
			draw_triangle(mouse_x, mouse_y, mouse_x + lengthdir_x(12, @pvDir + 150), mouse_y + lengthdir_y(12, @pvDir + 150), mouse_x + lengthdir_x(12, @pvDir - 150), mouse_y + lengthdir_y(12, @pvDir - 150), false);
		}
		draw_set_alpha(0.8);
		draw_set_color(c_white);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		@stg_text_cjk(round(mouse_x + 14), round(mouse_y + 10), @L(global.__ONLINE_LK_HUD_NOTE_HINT_NODE, "LMB node / H done / RMB undo"), 0);
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
	}
	// in-progress stroke preview (mode 5): the staged drawing so far
	// (sub-path breaks respected) + cursor dot
	if(@noteMode == 5){
		@pvTeam = @team;
		if(@pvTeam < 0 || @pvTeam > 7) @pvTeam = 0;
		draw_set_alpha(0.9);
		draw_set_color(@teamColors[@pvTeam]);
		if(@noteStageN >= 2){
			for(@pvI = 0; @pvI < @noteStageN - 1; @pvI += 1){
				if(@noteStageBrk[@pvI + 1] == 0){
					draw_line_width(@noteStageX[@pvI], @noteStageY[@pvI], @noteStageX[@pvI + 1], @noteStageY[@pvI + 1], 3);
				}
				if(@noteStageBrk[@pvI] == 1 || @pvI == 0){
					draw_circle(@noteStageX[@pvI], @noteStageY[@pvI], 2.5, false);
				}
			}
		}
		draw_circle(mouse_x, mouse_y, 2, false);
		draw_set_alpha(0.8);
		draw_set_color(c_white);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		@stg_text_cjk(round(mouse_x + 14), round(mouse_y + 10), @L(global.__ONLINE_LK_HUD_NOTE_HINT_DRAW, "LMB draw / H done / RMB undo"), 0);
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
	}
	// modal UI cursor: the game's own cursor sprite draws below our layer, so
	// repaint a crosshair on top while any notes UI is open (mode >= 2)
	if(@noteMode >= 2){
		draw_set_alpha(1);
		draw_set_color(c_black);
		draw_line_width(mouse_x - 6, mouse_y, mouse_x + 6, mouse_y, 3);
		draw_line_width(mouse_x, mouse_y - 6, mouse_x, mouse_y + 6, 3);
		draw_set_color(c_white);
		draw_line_width(mouse_x - 6, mouse_y, mouse_x + 6, mouse_y, 1);
		draw_line_width(mouse_x, mouse_y - 6, mouse_x, mouse_y + 6, 1);
	}
	draw_set_alpha(@pdAlpha);
	draw_set_color(@pdColor);
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	if(font_exists(0)){
		draw_set_font(0);
	}
}
return 0;

///// script @note_next_seq
// Per-session sender-side note sequence (u16). Combined with the sender id it
// uniquely identifies a note for dedup (sync replay) and DELETE.
// args: none
@noteSeqSend = (@noteSeqSend + 1) mod 65536;
return @noteSeqSend;

///// script @note_persist
// Writes the notes store to "@notes" (next to the game / sandbox on GMS) so
// drawings survive game_restart and relaunch. Entries keep their sender seq
// so a server sync replay dedups against them. Loaded entries come back
// past-toast (visible in canvas mode, silent in transient).
// args: none
__ONLINE_buffer_clear(@savesBuffer);
#if not GMNET
    __ONLINE_buffer_write_uint32(@savesBuffer, 1313428292);   // magic
    __ONLINE_buffer_write_uint8(@savesBuffer, 1);             // format v1
#endif
#if GMNET
    __ONLINE_buffer_write_u32(@savesBuffer, 1313428292);
    __ONLINE_buffer_write_u8(@savesBuffer, 1);
#endif
@npcN = 0;
for(@npcI = 0; @npcI < @noteMax; @npcI += 1){
    if(@noteSeqArr[@npcI] >= 0 && @noteSenderArr[@npcI] == @selfID) @npcN += 1;
}
#if not GMNET
    __ONLINE_buffer_write_uint16(@savesBuffer, @npcN);
#endif
#if GMNET
    __ONLINE_buffer_write_u16(@savesBuffer, @npcN);
#endif
for(@npcI = 0; @npcI < @noteMax; @npcI += 1){
    if(@noteSeqArr[@npcI] < 0) continue;
    if(@noteSenderArr[@npcI] != @selfID) continue;
    #if not GMNET
        __ONLINE_buffer_write_uint8(@savesBuffer, @noteKindArr[@npcI]);
        __ONLINE_buffer_write_int32(@savesBuffer, @noteRoomArr[@npcI]);
        __ONLINE_buffer_write_float32(@savesBuffer, @noteX[@npcI]);
        __ONLINE_buffer_write_float32(@savesBuffer, @noteY[@npcI]);
        __ONLINE_buffer_write_uint8(@savesBuffer, @noteIcon[@npcI]);
        __ONLINE_buffer_write_uint8(@savesBuffer, @noteTeamArr[@npcI]);
        __ONLINE_buffer_write_uint16(@savesBuffer, @noteWireArr[@npcI]);
        __ONLINE_buffer_write_string(@savesBuffer, @noteName[@npcI]);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@savesBuffer, @noteKindArr[@npcI]);
        __ONLINE_buffer_write_i32(@savesBuffer, @noteRoomArr[@npcI]);
        __ONLINE_buffer_write_float(@savesBuffer, @noteX[@npcI]);
        __ONLINE_buffer_write_float(@savesBuffer, @noteY[@npcI]);
        __ONLINE_buffer_write_u8(@savesBuffer, @noteIcon[@npcI]);
        __ONLINE_buffer_write_u8(@savesBuffer, @noteTeamArr[@npcI]);
        __ONLINE_buffer_write_u16(@savesBuffer, @noteWireArr[@npcI]);
        __ONLINE_buffer_write_string(@savesBuffer, @noteName[@npcI]);
    #endif
    if(@noteKindArr[@npcI] == 1 || @noteKindArr[@npcI] == 2){
        #if not GMNET
            __ONLINE_buffer_write_uint16(@savesBuffer, @notePtsN[@npcI]);
        #endif
        #if GMNET
            __ONLINE_buffer_write_u16(@savesBuffer, @notePtsN[@npcI]);
        #endif
        for(@npcJ = 0; @npcJ < @notePtsN[@npcI]; @npcJ += 1){
            #if not GMNET
                __ONLINE_buffer_write_float32(@savesBuffer, @notePtsX[@npcI, @npcJ]);
                __ONLINE_buffer_write_float32(@savesBuffer, @notePtsY[@npcI, @npcJ]);
                __ONLINE_buffer_write_uint8(@savesBuffer, @notePtsBrk[@npcI, @npcJ]);
            #endif
            #if GMNET
                __ONLINE_buffer_write_float(@savesBuffer, @notePtsX[@npcI, @npcJ]);
                __ONLINE_buffer_write_float(@savesBuffer, @notePtsY[@npcI, @npcJ]);
                __ONLINE_buffer_write_u8(@savesBuffer, @notePtsBrk[@npcI, @npcJ]);
            #endif
        }
    }
    if(@noteKindArr[@npcI] == 3){
        __ONLINE_buffer_write_string(@savesBuffer, @noteText[@npcI]);
    }
}
#if not GMNET
    __ONLINE_buffer_write_to_file(@savesBuffer, "@notes");
#endif
#if GMNET
    __ONLINE_buffer_save(@savesBuffer, "@notes");
#endif
return @npcN;

///// script @note_persist_load
// Restores the notes store written by @note_persist. Silently no-ops on a
// missing/corrupt file. Restored notes are past-toast (old news).
// args: none
if(!file_exists("@notes")) return 0;
__ONLINE_buffer_clear(@savesBuffer);
#if not GMNET
    __ONLINE_buffer_read_from_file(@savesBuffer, "@notes");
    if(__ONLINE_buffer_read_uint32(@savesBuffer) != 1313428292) return 0;
    if(__ONLINE_buffer_read_uint8(@savesBuffer) != 1) return 0;
    @nplN = __ONLINE_buffer_read_uint16(@savesBuffer);
#endif
#if GMNET
    __ONLINE_buffer_load(@savesBuffer, "@notes");
    if(__ONLINE_buffer_read_u32(@savesBuffer) != 1313428292) return 0;
    if(__ONLINE_buffer_read_u8(@savesBuffer) != 1) return 0;
    @nplN = __ONLINE_buffer_read_u16(@savesBuffer);
#endif
if(@nplN < 0 || @nplN > 256) return 0;
for(@nplI = 0; @nplI < @nplN; @nplI += 1){
    #if not GMNET
        @nplKind = __ONLINE_buffer_read_uint8(@savesBuffer);
        @nplRoom = __ONLINE_buffer_read_int32(@savesBuffer);
        @nplX = __ONLINE_buffer_read_float32(@savesBuffer);
        @nplY = __ONLINE_buffer_read_float32(@savesBuffer);
        @nplIcon = __ONLINE_buffer_read_uint8(@savesBuffer);
        @nplTeam = __ONLINE_buffer_read_uint8(@savesBuffer);
        @nplSeq = __ONLINE_buffer_read_uint16(@savesBuffer);
    #endif
    #if GMNET
        @nplKind = __ONLINE_buffer_read_u8(@savesBuffer);
        @nplRoom = __ONLINE_buffer_read_i32(@savesBuffer);
        @nplX = __ONLINE_buffer_read_float(@savesBuffer);
        @nplY = __ONLINE_buffer_read_float(@savesBuffer);
        @nplIcon = __ONLINE_buffer_read_u8(@savesBuffer);
        @nplTeam = __ONLINE_buffer_read_u8(@savesBuffer);
        @nplSeq = __ONLINE_buffer_read_u16(@savesBuffer);
    #endif
    @nplName = __ONLINE_buffer_read_string(@savesBuffer);
    @noteStageText = "";
    if(@nplKind == 1 || @nplKind == 2){
        #if not GMNET
            @noteStageN = __ONLINE_buffer_read_uint16(@savesBuffer);
        #endif
        #if GMNET
            @noteStageN = __ONLINE_buffer_read_u16(@savesBuffer);
        #endif
        if(@noteStageN < 0 || @noteStageN > 480) return 0;
        for(@nplJ = 0; @nplJ < @noteStageN; @nplJ += 1){
            #if not GMNET
                @noteStageX[@nplJ] = __ONLINE_buffer_read_float32(@savesBuffer);
                @noteStageY[@nplJ] = __ONLINE_buffer_read_float32(@savesBuffer);
                @noteStageBrk[@nplJ] = __ONLINE_buffer_read_uint8(@savesBuffer);
            #endif
            #if GMNET
                @noteStageX[@nplJ] = __ONLINE_buffer_read_float(@savesBuffer);
                @noteStageY[@nplJ] = __ONLINE_buffer_read_float(@savesBuffer);
                @noteStageBrk[@nplJ] = __ONLINE_buffer_read_u8(@savesBuffer);
            #endif
        }
    }
    if(@nplKind == 3){
        @noteStageText = __ONLINE_buffer_read_string(@savesBuffer);
    }
    @nplSlot = @note_add(@nplKind, @nplRoom, @nplX, @nplY, @nplIcon, @selfID, @nplName, @nplTeam, @nplSeq);
    // restored entries are old news: past-toast, no arrival sound
    @noteT[@nplSlot] = current_time - 999999999;
}
return @nplN;

///// script @note_dup
// Content-based duplicate check for incoming notes (sync replays can collide
// with locally persisted notes; sender ids are per-connection and useless
// across sessions, so the match is on content: kind + room + anchor + icon/count
// + sender name). Returns 1 when a live slot already holds an equal note.
// args: 0 kind, 1 room, 2 x, 3 y, 4 aux (iconId / point count), 5 sender name
for(@ndI = 0; @ndI < @noteMax; @ndI += 1){
    if(@noteSeqArr[@ndI] < 0) continue;
    if(@noteKindArr[@ndI] != argument0) continue;
    if(@noteRoomArr[@ndI] != argument1) continue;
    if(@noteName[@ndI] != argument5) continue;
    if(abs(@noteX[@ndI] - argument2) >= 2) continue;
    if(abs(@noteY[@ndI] - argument3) >= 2) continue;
    if(argument0 == 0){
        if(@noteIcon[@ndI] != argument4) continue;
    }
    if(argument0 == 1 || argument0 == 2){
        if(@notePtsN[@ndI] != argument4) continue;
    }
    return 1;
}
return 0;
