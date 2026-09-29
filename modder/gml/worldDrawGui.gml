/// ONLINE
// SCREEN-SPACE HUD (chat log, player list, settings panel, spectator bar,
// pick-mode panel). Research: _workspace/RESEARCH_GM8_3D_HUD.md.
// GM8.0/8.1: injected into the UI object's regular Draw event AFTER
// worldDraw.gml; we force a view-port ortho projection (survives weird views,
// window scaling and letterboxed fullscreen) and restore the view projection
// at the end of the event - the runner only re-applies it at the next view.
// d3d_set_depth(-15999) parks our primitives on the near plane.
// GM8.2 (GM8GUI): attached to the native Draw GUI event (group 11, the old
// trigger group GM8.2 repurposed) instead,
// which runs once per frame after ALL regular draws. Regular-Draw output is
// silently invisible in d3d-started rooms (TUNNEL VISION E1 probe: group-8
// text never rasterizes there, group-11 does). The GUI pass projection is
// Y-flipped once a game has entered d3d mode, so we always set our own
// view-port ortho - the same pattern the game's own 2D overlays use
// (objHubTransIn:
// d3d_set_hidden(false) -> d3d_set_projection_ortho -> draw -> hidden(true)).
// GAME_D3D games (converter-detected d3d usage): z-testing may be live, so the
// HUD draw is wrapped in d3d_set_hidden(false)/(true); 2D-only games keep the
// untouched-state path. Projection needs no restore here: the GUI pass is the
// frame's last draw and the runner re-applies the view projection at the next
// view/frame, and per-instance depth is re-applied before every other
// instance's draw.
// GMS: attached to the Draw GUI event instead, which is already screen-space
// (runs once per frame, no view guard needed).
#if not STUDIO
	#if not GM8GUI
@hudGuiOn = false;
@hudFirst = 0;
if(view_enabled){
	// Draw events run once per visible view; draw the HUD only on the first
	// one (GM8.0 has no break, hence the guard style).
	@hudFirst = -1;
	for(@hudVi = 0; @hudVi < 8; @hudVi += 1){
		if(@hudFirst < 0){
			if(view_visible[@hudVi]) @hudFirst = @hudVi;
		}
	}
}
if(@hudFirst < 0 || view_current == @hudFirst){
	// QoL: with views enabled but none visible (menu / title rooms) @hudFirst
	// stays -1 and never matches view_current; draw the single HUD pass in the
	// current view instead, or the whole HUD (chat, notes, settings panel)
	// silently vanishes in those rooms.
	// Draw in view-port space (not window space): the D3D viewport follows the
	// port, so this stays correct under window scaling / letterboxed
	// fullscreen, and the HUD scales together with the game image. The
	// projection is restored at the end of this event - the runner only
	// re-applies the view projection at the START of the next view, anything
	// drawn after us in THIS view (foreground backgrounds, cursor) would
	// otherwise inherit our ortho.
	if(view_enabled){
		@hudView = view_current;
		@hudWinW = view_wport[view_current];
		@hudWinH = view_hport[view_current];
	}else{
		@hudView = -1;
		@hudWinW = room_width;
		@hudWinH = room_height;
	}
	if(@hudWinW >= 1){
		if(@hudWinH >= 1){
			d3d_set_projection_ortho(0, 0, @hudWinW, @hudWinH, 0);
			d3d_set_depth(-15999);
			#if GAME_D3D
				// 3D game: z-testing may be live; drop it for the HUD (restored
				// at the end of this block so the game's next frame is intact).
				d3d_set_hidden(false);
			#endif
			@hudGuiOn = true;
		}
	}
}
	#endif
#endif
#if GM8GUI
	@hudGuiOn = false;
	// Same view-port space as the group-8 path (see above); the GUI pass has no
	// per-view context, so anchor on view 0. No projection restore needed here:
	// the GUI pass is the last draw of the frame and the runner re-applies the
	// view projection at the next view/frame.
	if(view_enabled){
		if(view_visible[0]){
			@hudView = 0;
			@hudWinW = view_wport[0];
			@hudWinH = view_hport[0];
		}else{
			@hudView = -1;
			@hudWinW = room_width;
			@hudWinH = room_height;
		}
	}else{
		@hudView = -1;
		@hudWinW = room_width;
		@hudWinH = room_height;
	}
	if(@hudWinW >= 1){
		if(@hudWinH >= 1){
			d3d_set_projection_ortho(0, 0, @hudWinW, @hudWinH, 0);
			#if GAME_D3D
				d3d_set_hidden(false);
			#endif
			@hudGuiOn = true;
		}
	}
#endif
#if STUDIO
@hudGuiOn = true;
@hudWinW = display_get_gui_width();
@hudWinH = display_get_gui_height();
// A Studio 2 game with no GUI layer configured reports 0 here; switching the
// overlay off then hides the panel while its Step logic keeps working. Fall
// back to the window size: with no GUI layer the Draw GUI surface is the
// window. The GM8 branch above falls back the same way (view_wport ->
// room_width).
if(@hudWinW < 1) @hudWinW = window_get_width();
if(@hudWinH < 1) @hudWinH = window_get_height();
if(@hudWinW < 1) @hudGuiOn = false;
if(@hudWinH < 1) @hudGuiOn = false;
#endif
#if PROBE
#if STUDIO   // needs the GUI-size API
// iwpo.probe (see DEVNOTES.md): one line per second into iwpo_probe.txt, written
// from before the guard so a suppressed overlay explains itself. Only variables
// worldCreate/@stg_init own are read: anything the panel assigns later would abort
// this event on the first frame.
if(current_time - global.__ONLINE_probeLast >= 1000){
  global.__ONLINE_probeLast = current_time;
  @probeLine = "save=" + string(game_save_id);
  @probeLine += " fps=" + string(fps);
  @probeLine += " gui=" + string(display_get_gui_width()) + "x" + string(display_get_gui_height());
  @probeLine += " win=" + string(window_get_width()) + "x" + string(window_get_height());
  @probeLine += " room=" + string(room_width) + "x" + string(room_height);
  @probeLine += " alpha=" + string(draw_get_alpha()) + " color=" + string(draw_get_color());
  @probeLine += " hudOn=" + string(@hudGuiOn) + " hudW=" + string(@hudWinW) + " hudH=" + string(@hudWinH);
  @probeLine += " open=" + string(@settingsOpen) + " tab=" + string(@settingsTab);
  @probeLine += " sp=" + string(@spX) + "," + string(@spY) + "," + string(@spW) + "," + string(@spH);
  @probeLine += " stgN=" + string(global.__ONLINE_stgN) + " first=" + string(@stgFirst);
  @probeF = file_text_open_append("iwpo_probe.txt");
  if(@probeF >= 0){
    file_text_write_string(@probeF, @probeLine);
    file_text_writeln(@probeF);
    file_text_close(@probeF);
  }
}
#endif
#if not STUDIO
// GM8 variant: no display_get_gui_width here - the fps figure is the point of
// the measurement (the i18n atlas spike), plus which menu page was open.
if(current_time - global.__ONLINE_probeLast >= 1000){
  global.__ONLINE_probeLast = current_time;
  @probeF = file_text_open_append("iwpo_probe.txt");
  if(@probeF >= 0){
    file_text_write_string(@probeF, "fps=" + string(fps) + " open=" + string(@settingsOpen) + " tab=" + string(@settingsTab) + " stgN=" + string(global.__ONLINE_stgN));
    file_text_writeln(@probeF);
    file_text_close(@probeF);
  }
}
#endif
#endif

if(@hudGuiOn){
#if GM8GUI
	// N3: world-anchored notes + off-screen arrows render in this GUI pass
	// under the view-rect projection (room coords work unchanged), then port
	// space is restored for the screen-space HUD below.
	if(@hudView >= 0){
		d3d_set_projection_ortho(view_xview[@hudView], view_yview[@hudView], view_wview[@hudView], view_hview[@hudView], view_angle[@hudView]);
	}else{
		d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
	}
	@note_render_all();
	d3d_set_projection_ortho(0, 0, @hudWinW, @hudWinH, 0);
#endif

if(@chatLogOpen){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@clLeft = 8;
	@clBottom = @hudWinH - 40;
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	// CHAT LOG
	@clPanelW = 300;
	@clPanelH = 240;
	@clPanelX = @clLeft;
	@clPanelY = @clBottom - @clPanelH;
	@clContentY = @clPanelY + 20;
	@clContentH = @clPanelH - 24;
	@clWrapW = @clPanelW - 16;
	#if GM80
		@clLH = fw_string_height_ext("A", -1, 9999);
	#endif
	#if CJKTEXT
		@clLH = __ONLINE_cjk_string_height_ext("A", -1, 9999);
	#endif
	#if not GM80
	#if not CJKTEXT
		@clLH = string_height("A");
	#endif
	#endif
	@clStep = @clLH + 2;
	@clTotalLines = 0;
	for(@clI = 0; @clI < @chatHistCount; @clI += 1){
		@clDispName = @chatHistName[@clI];
		#if GM80
		@clDispName = __ONLINE_gbk_trunc(@clDispName, 12, "..");
		#endif
		#if CJKTEXT
		@clDispName = __ONLINE_gbk_trunc(@clDispName, 12, "..");
		#endif
		#if not GM80
		#if not CJKTEXT
		if(string_length(@clDispName) > 12) @clDispName = string_copy(@clDispName, 1, 12) + "..";
		#endif
		#endif
		@clSrc = @clDispName + ": " + @chatHistMsg[@clI];
		@clCurLine = "";
		@clCurWord = "";
		@clLineW = 0;
		@clWordW = 0;
		for(@clC = 1; @clC <= string_length(@clSrc); @clC += 1){
			@clCh = string_copy(@clSrc, @clC, 1);
			#if GM80
					if(ord(@clCh) >= $81 && @clC < string_length(@clSrc)){
					@clCh = string_copy(@clSrc, @clC, 2);
					@clC += 1;
				}
				@clChW = fw_string_width(@clCh);
			#endif
			#if CJKTEXT
					if(ord(@clCh) >= $81 && @clC < string_length(@clSrc)){
					@clCh = string_copy(@clSrc, @clC, 2);
					@clC += 1;
				}
				@clChW = __ONLINE_cjk_string_width(@clCh);
			#endif
			#if not GM80
			#if not CJKTEXT
				@clChW = string_width(@clCh);
			#endif
			#endif
			if(@clCh == " "){
				if(@clLineW + @clWordW > @clWrapW && @clLineW > 0){
					@clAllLines[@clTotalLines] = @clCurLine;
					@clTotalLines += 1;
					@clCurLine = @clCurWord + " ";
					@clLineW = @clWordW + @clChW;
				}else{
					@clCurLine = @clCurLine + @clCurWord + " ";
					@clLineW += @clWordW + @clChW;
				}
				@clCurWord = "";
				@clWordW = 0;
			}else{
				if(@clWordW + @clChW > @clWrapW){
					if(@clLineW > 0){
						@clAllLines[@clTotalLines] = @clCurLine;
						@clTotalLines += 1;
						@clCurLine = "";
						@clLineW = 0;
					}
					if(string_length(@clCurWord) > 0){
						@clAllLines[@clTotalLines] = @clCurWord;
						@clTotalLines += 1;
					}
					@clCurWord = @clCh;
					@clWordW = @clChW;
				}else{
					@clCurWord = @clCurWord + @clCh;
					@clWordW += @clChW;
				}
			}
		}
		if(@clLineW + @clWordW > @clWrapW && @clLineW > 0){
			@clAllLines[@clTotalLines] = @clCurLine;
			@clTotalLines += 1;
			@clCurLine = @clCurWord;
		}else{
			@clCurLine = @clCurLine + @clCurWord;
		}
		if(string_length(@clCurLine) > 0){
			@clAllLines[@clTotalLines] = @clCurLine;
			@clTotalLines += 1;
		}
	}
	@clTotalH = @clTotalLines * @clStep;
	if(mouse_wheel_up()) @chatLogScroll += 20;
	if(mouse_wheel_down()) @chatLogScroll -= 20;
	@clMaxScroll = max(0, @clTotalH - @clContentH);
	if(@chatLogScroll > @clMaxScroll) @chatLogScroll = @clMaxScroll;
	if(@chatLogScroll < 0) @chatLogScroll = 0;
	draw_set_alpha(0.75);
	draw_set_color(c_black);
	draw_rectangle(@clPanelX, @clPanelY, @clPanelX + @clPanelW, @clPanelY + @clPanelH, false);
	draw_set_alpha(1);
	draw_set_color(c_white);
	draw_rectangle(@clPanelX, @clPanelY, @clPanelX + @clPanelW, @clPanelY + @clPanelH, true);
	draw_set_color(c_gray);
	@stg_text_cjk(@clPanelX + @clPanelW / 2, @clPanelY + 3, @L(global.__ONLINE_LK_HUD_CHAT_LOG, "Chat Log"), 1);
	draw_set_halign(fa_left);
	@clDrawY = @clContentY + @clContentH - @clTotalH + @chatLogScroll;
	draw_set_color(c_white);
	#if GM80
	fw_draw_set_halign(fa_left);
	fw_draw_set_valign(fa_top);
	#endif
	#if CJKTEXT
	global.__ONLINE_cjkHalign = 0;
	global.__ONLINE_cjkValign = 0;
	#endif
	for(@clL = 0; @clL < @clTotalLines; @clL += 1){
		if(@clDrawY >= @clContentY && @clDrawY + @clLH <= @clContentY + @clContentH){
			#if GM80
				__ONLINE_fw_use_font(@clAllLines[@clL]);
				fw_draw_text_ext(@clPanelX + 8, @clDrawY, @clAllLines[@clL], @clWrapW);
			#endif
			#if CJKTEXT
				__ONLINE_cjk_draw_text(@clPanelX + 8, @clDrawY, @clAllLines[@clL], @clWrapW);
			#endif
			#if not GM80
			#if not CJKTEXT
				draw_text(@clPanelX + 8, @clDrawY, @clAllLines[@clL]);
			#endif
			#endif
		}
		@clDrawY += @clStep;
	}
	if(@chatHistCount == 0){
		draw_set_color(c_gray);
		@stg_text_cjk(@clPanelX + @clPanelW / 2, @clPanelY + @clPanelH / 2 - 6, @L(global.__ONLINE_LK_HUD_NO_MESSAGES, "No messages yet"), 1);
		draw_set_halign(fa_left);
	}
	if(@clTotalH > @clContentH){
		@clBarH = max(20, @clContentH * @clContentH / @clTotalH);
		@clBarY = @clContentY + (@clContentH - @clBarH) * (1 - @chatLogScroll / @clMaxScroll);
		draw_set_alpha(0.4);
		draw_set_color(c_white);
		draw_rectangle(@clPanelX + @clPanelW - 5, @clBarY, @clPanelX + @clPanelW - 2, @clBarY + @clBarH, false);
	}
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
}
if(@showPlayerList){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@plX = @hudWinW - 10;
	@plY = 10;
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	draw_set_valign(fa_top);
	draw_set_halign(fa_right);
	draw_set_alpha(0.8);
	// PLAYER LIST
	draw_set_color(c_black);
	@stg_text_cjk(@plX+1, @plY, @L(global.__ONLINE_LK_HUD_PLAYERS_ONLINE, "Players Online:"), 2);
	@stg_text_cjk(@plX, @plY+1, @L(global.__ONLINE_LK_HUD_PLAYERS_ONLINE, "Players Online:"), 2);
	@stg_text_cjk(@plX-1, @plY, @L(global.__ONLINE_LK_HUD_PLAYERS_ONLINE, "Players Online:"), 2);
	@stg_text_cjk(@plX, @plY-1, @L(global.__ONLINE_LK_HUD_PLAYERS_ONLINE, "Players Online:"), 2);
	draw_set_color(c_yellow);
	@stg_text_cjk(@plX, @plY, @L(global.__ONLINE_LK_HUD_PLAYERS_ONLINE, "Players Online:"), 2);
	@plY += 18;
	@plSelf = @name + @L(global.__ONLINE_LK_HUD_YOU, " (YOU)");
	draw_set_halign(fa_right);   // stg_text_cjk resets to fa_left; the plain-draw name path below still wants right
	draw_set_color(c_black);
	#if GM80
	fw_draw_set_halign(fa_right);
	fw_draw_set_valign(fa_top);
	__ONLINE_fw_use_font(@plSelf);
	fw_draw_text_ext(@plX+1, @plY, @plSelf, 9999);
	fw_draw_text_ext(@plX, @plY+1, @plSelf, 9999);
	fw_draw_text_ext(@plX-1, @plY, @plSelf, 9999);
	fw_draw_text_ext(@plX, @plY-1, @plSelf, 9999);
	draw_set_color(@teamColors[@team]);
	fw_draw_text_ext(@plX, @plY, @plSelf, 9999);
	#endif
	#if CJKTEXT
	global.__ONLINE_cjkHalign = 2;
	global.__ONLINE_cjkValign = 0;
	__ONLINE_cjk_draw_text(@plX+1, @plY, @plSelf, 9999);
	__ONLINE_cjk_draw_text(@plX, @plY+1, @plSelf, 9999);
	__ONLINE_cjk_draw_text(@plX-1, @plY, @plSelf, 9999);
	__ONLINE_cjk_draw_text(@plX, @plY-1, @plSelf, 9999);
	draw_set_color(@teamColors[@team]);
	__ONLINE_cjk_draw_text(@plX, @plY, @plSelf, 9999);
	#endif
	#if not GM80
	#if not CJKTEXT
	draw_text(@plX+1, @plY, @plSelf);
	draw_text(@plX, @plY+1, @plSelf);
	draw_text(@plX-1, @plY, @plSelf);
	draw_text(@plX, @plY-1, @plSelf);
	draw_set_color(@teamColors[@team]);
	draw_text(@plX, @plY, @plSelf);
	#endif
	#endif
	@plY += 16;
	for(@plI = 0; @plI < instance_number(@onlinePlayer); @plI += 1){
		@plObj = instance_find(@onlinePlayer, @plI);
		if(@plObj.@name != ""){
			draw_set_color(c_black);
			#if GM80
			__ONLINE_fw_use_font(@plObj.@name);
			fw_draw_text_ext(@plX+1, @plY, @plObj.@name, 9999);
			fw_draw_text_ext(@plX, @plY+1, @plObj.@name, 9999);
			fw_draw_text_ext(@plX-1, @plY, @plObj.@name, 9999);
			fw_draw_text_ext(@plX, @plY-1, @plObj.@name, 9999);
			draw_set_color(@teamColors[@plObj.@team]);
			fw_draw_text_ext(@plX, @plY, @plObj.@name, 9999);
			#endif
			#if CJKTEXT
			__ONLINE_cjk_draw_text(@plX+1, @plY, @plObj.@name, 9999);
			__ONLINE_cjk_draw_text(@plX, @plY+1, @plObj.@name, 9999);
			__ONLINE_cjk_draw_text(@plX-1, @plY, @plObj.@name, 9999);
			__ONLINE_cjk_draw_text(@plX, @plY-1, @plObj.@name, 9999);
			draw_set_color(@teamColors[@plObj.@team]);
			__ONLINE_cjk_draw_text(@plX, @plY, @plObj.@name, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@plX+1, @plY, @plObj.@name);
			draw_text(@plX, @plY+1, @plObj.@name);
			draw_text(@plX-1, @plY, @plObj.@name);
			draw_text(@plX, @plY-1, @plObj.@name);
			draw_set_color(@teamColors[@plObj.@team]);
			draw_text(@plX, @plY, @plObj.@name);
			#endif
			#endif
			@plY += 16;
		}
	}
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	#if GM80
	fw_draw_set_halign(fa_left);
	fw_draw_set_valign(fa_top);
	#endif
	#if CJKTEXT
	global.__ONLINE_cjkHalign = 0;
	global.__ONLINE_cjkValign = 0;
	#endif
}
// SKINS: never leak preview sprites once the menu is closed or another tab
// is showing (the tab 5 block below only runs while it is visible).
if(@skinPrevLoaded >= 0){
    if(!@settingsOpen || @settingsTab != 5){
        @skin_prev_unload();
        @skinPrevRow = -1;
        @skinPrevTimer = 0;
    }
}
// SETTINGS PANEL
if(@settingsOpen){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	// Geometry (@spX/@spY/@spW/@spH/@tabH) is owned by @stg_init (worldCreate).
	// Never re-derive it here: a forked hardcoded size paints the row table
	// outside the panel.
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	// The game's own draw state leaks into this event (e.g. fish's title glow
	// uses bm_add, under which a black panel plate adds zero and vanishes);
	// always draw the chrome under the normal blend mode.
	// GMS2 renamed the blend functions to gpu_set_blendmode (the legacy
	// draw_set_blend_mode only exists in UTMT's !gms2 builtin table - on a GMS2
	// game it compiles into an unresolvable variable read)
	#if GMS2
	gpu_set_blendmode(bm_normal);
	#endif
	#if not GMS2
	draw_set_blend_mode(bm_normal);
	#endif
	// panel: flat dark plate + thin frame
	draw_set_alpha(0.90);
	draw_set_color(c_black);
	draw_rectangle(@spX, @spY, @spX + @spW, @spY + @spH, false);
	draw_set_alpha(1);
	draw_set_color(make_color_rgb(70, 80, 95));
	draw_rectangle(@spX, @spY, @spX + @spW, @spY + @spH, true);
	// tab strip: the active tab blends into the panel with an accent underline,
	// inactive tabs sit darker with muted text
	@tabCount = 6;
	@tabW = floor(@spW / @tabCount);
	@tabY = @spY;
	// tab names and Close are localized: they go through @L and the CJK draw path
	@tabNames[0] = @L(global.__ONLINE_LK_TAB_SETTINGS, "Settings");
	@tabNames[1] = @str_fmt(@L(global.__ONLINE_LK_TAB_SAVES, "Saves(%1)"), @saveHistCount, 0, 0);
	@tabNames[2] = @L(global.__ONLINE_LK_TAB_RATING, "Rating");
	@tabNames[3] = @L(global.__ONLINE_LK_TAB_KEYS, "Keys");
	@tabNames[4] = @L(global.__ONLINE_LK_TAB_SYNC, "Sync");
	@tabNames[5] = @L(global.__ONLINE_LK_TAB_SKINS, "Skins");
	for(@tI = 0; @tI < @tabCount; @tI += 1){
		@tX1 = @spX + @tI * @tabW;
		@tX2 = @tX1 + @tabW;
		if(@tI == @tabCount - 1) @tX2 = @spX + @spW;
		if(@settingsTab == @tI){
			draw_set_color(c_black);
		}else{
			draw_set_color(make_color_rgb(28, 28, 34));
		}
		draw_rectangle(@tX1, @tabY, @tX2, @tabY + @tabH, false);
		draw_set_color(make_color_rgb(55, 60, 70));
		draw_rectangle(@tX1, @tabY + @tabH - 1, @tX2, @tabY + @tabH, false);
		draw_set_halign(fa_center);
		if(@settingsTab == @tI){
			draw_set_color(c_white);
		}else{
			draw_set_color(make_color_rgb(150, 150, 155));
		}
		@stg_text_cjk(floor((@tX1 + @tX2) / 2), @tabY + 6, @tabNames[@tI], 1);
		if(@settingsTab == @tI){
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@tX1 + 8, @tabY + @tabH - 2, @tX2 - 8, @tabY + @tabH - 1, false);
		}
		if(@kbFocus == 0 && @settingsTab == @tI){
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@tX1 + 1, @tabY + 1, @tX2 - 1, @tabY + @tabH - 1, true);
		}
	}
	draw_set_halign(fa_left);
	// QoL: keep the panel geometry in step with the current view-port (full vs
	// narrow layout); @stg_layout is a handful of comparisons.
	@stg_layout();
	@contentY = @tabY + @tabH + 8;

	#if STUDIO
	@mx = device_mouse_x_to_gui(0);
	@my = device_mouse_y_to_gui(0);
	#endif
	#if not STUDIO
	// Convert the authoritative room-space mouse into the same view-port space
	// the prelude established (@hudView < 0 means room space). window_mouse_get
	// would include letterbox offsets under scaling/fullscreen and disagree
	// with the HUD rectangles. The runner rotates the view about its center and
	// its mouse_x/y are rotation-aware, so the forward transform must be too
	// (nezumi probe: at angle==0 this reduces exactly to translate+scale).
	if(@hudView >= 0){
		@mA = degtorad(view_angle[@hudView]);
		@mDX = mouse_x - view_xview[@hudView] - view_wview[@hudView] / 2;
		@mDY = mouse_y - view_yview[@hudView] - view_hview[@hudView] / 2;
		@mCos = cos(@mA);
		@mSin = sin(@mA);
		@mx = view_wport[@hudView] / 2 + (@mDX * @mCos + @mDY * @mSin) * view_wport[@hudView] / view_wview[@hudView];
		@my = view_hport[@hudView] / 2 + (@mDY * @mCos - @mDX * @mSin) * view_hport[@hudView] / view_hview[@hudView];
	}else{
		@mx = mouse_x;
		@my = mouse_y;
	}
	#endif

	// Every tab is table-driven: the builder fills the row table for the
	// active tab, the shared renderer draws list + scrollbar + detail + footer.
	@stg_build_tab(@settingsTab);
	@stg_draw_table();

	// Close lives in the footer band, right-aligned (matches the tab-0 footer;
	// other tabs keep their content above @footerY)
	@btnCW = 70;
	@btnCH = 22;
	@btnCX = @spX + @spW - @btnCW - 16;
	@btnCY = @footerY + 6;
	draw_set_color(make_color_rgb(45, 45, 52));
	draw_rectangle(@btnCX, @btnCY, @btnCX + @btnCW, @btnCY + @btnCH, false);
	draw_set_color(make_color_rgb(90, 95, 105));
	draw_rectangle(@btnCX, @btnCY, @btnCX + @btnCW, @btnCY + @btnCH, true);
	draw_set_color(c_white);
	draw_set_halign(fa_center);
	@stg_text_cjk(@btnCX + @btnCW/2, @btnCY + 4, @L(global.__ONLINE_LK_CLOSE, "Close"), 1);
	if(mouse_check_button_pressed(mb_left)){
		@tabClicked = false;
		if(@my >= @tabY && @my <= @tabY + @tabH){
			for(@tI = 0; @tI < @tabCount; @tI += 1){
				@tX1 = @spX + @tI * @tabW;
				@tX2 = @tX1 + @tabW;
				if(@tI == @tabCount - 1) @tX2 = @spX + @spW;
				if(@mx >= @tX1 && @mx <= @tX2){
					@settingsTab = @tI;
					@kbFocus = 0;
					@keybindEditing = -1;
					@kbRow[0] = -1;   // same reset as the keyboard tab switch
					@stgFirst = 0;
					@tabClicked = true;
				}
			}
		}
		// scrollbar: grab the thumb to drag (stg_draw_table tracks it while the
		// button is held), click the track to page up/down
		if(!@tabClicked && @sbShow){
			if(@mx >= @sbX - 3 && @mx <= @sbX + 8 && @my >= @stgTop + 2 && @my <= @stgBottom){
				@tabClicked = true;
				if(@my >= @sbY && @my <= @sbY + @sbH){
					@stgSbDrag = true;
					@stgSbGrab = @my - @sbY;
				}else{
					if(@my < @sbY) @stgFirst -= @stgFit; else @stgFirst += @stgFit;
					if(@stgFirst < 0) @stgFirst = 0;
					if(@stgFirst > @stgMaxFirst) @stgFirst = @stgMaxFirst;
				}
			}
		}
		// rating stars: the detail pane's star boxes are directly clickable
		// (fixed slot @stgTop + 24, see @stg_draw_detail); clicking the active
		// star toggles it off
		if(!@tabClicked && @settingsTab == 2 && @detW > 0 && global.__ONLINE_stgAct[@stgPrevRow] == 31){
			for(@rI = 1; @rI <= 5; @rI += 1){
				@rSX = @spX + @colW + 12 + (@rI - 1) * 30;
				if(@mx >= @rSX && @mx <= @rSX + 26 && @my >= @stgTop + 24 && @my <= @stgTop + 46){
					if(@rStars == @rI) @rStars = 0; else @rStars = @rI;
					@tabClicked = true;
				}
			}
		}
		// skin preview state cycler (detail pane, fixed slot: box @stgTop+24,
		// strip @stgTop+146 - see @stg_skin_preview)
		if(!@tabClicked && @settingsTab == 5 && @detW > 0 && global.__ONLINE_stgAct[@stgPrevRow] == 55){
			if(@my >= @stgTop + 146 && @my <= @stgTop + 166){
				if(@mx >= @spX + @colW + 12 && @mx < @spX + @colW + 34){
					@stg_skin_prev_state_dir(-1); @tabClicked = true;
				}
				if(@mx >= @spX + @colW + 106 && @mx < @spX + @colW + 128){
					@stg_skin_prev_state_dir(1); @tabClicked = true;
				}
			}
		}
		if(!@tabClicked){
			@stg_build_tab(@settingsTab);
			// (the wheel is handled in worldEndStep, once per frame - inside this
			// click branch it only fires while the button is held)
			// same coordinate space as the draw (@stgYOff) - the table-space hit
			// test lands clicks on the wrong row once scrolled
			@rowHit = @stg_hit_row_view(@mx, @my, @stgYOff);
			if(@rowHit >= 0) @stg_click_row(@rowHit);
		}

		if(@mx >= @btnCX && @mx <= @btnCX + @btnCW && @my >= @btnCY && @my <= @btnCY + @btnCH){
			@settingsOpen = false;
		}
	}
	draw_set_halign(fa_left);
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
}
// SPECTATOR HUD
if(@spectating || @specProgress > 0){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@hudX = 0;
	@hudY = 0;
	@hudW = @hudWinW;
	@hudH = @hudWinH;
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	if(@specProgress > 0 && @specProgress < 1){
		@barW = 160;
		@barH = 18;
		@barX = @hudX + @hudW / 2 - @barW / 2;
		@barY = @hudY + @hudH / 2 - @barH / 2;
		draw_set_alpha(0.7);
		draw_set_color(c_black);
		draw_rectangle(@barX - 2, @barY - 2, @barX + @barW + 2, @barY + @barH + 2, false);
		draw_set_alpha(0.9);
		draw_set_color(make_color_rgb(255, 200, 60));
		draw_rectangle(@barX, @barY, @barX + @barW * @specProgress, @barY + @barH, false);
		draw_set_alpha(1);
		draw_set_color(c_white);
		draw_rectangle(@barX - 2, @barY - 2, @barX + @barW + 2, @barY + @barH + 2, true);
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
		draw_set_color(c_white);
		if(@spectating){
			@barTxt = @L(global.__ONLINE_LK_HUD_EXITING, "Exiting...");
		}else{
			@barTxt = @L(global.__ONLINE_LK_HUD_SPECTATING, "Spectating...");
		}
		// vertically centred in the bar: @stg_text_cjk is top-only, so this one
		// string hand-rolls the three paths with the middle valign (chatboxDraw
		// precedent). A top-valign draw here sat ~8px low on GM8.
		#if GM80
		__ONLINE_fw_use_font(@barTxt);
		fw_draw_set_halign(fa_center);
		fw_draw_set_valign(fa_middle);
		fw_draw_text_ext(@barX + @barW / 2, @barY + @barH / 2, @barTxt, 9999);
		fw_draw_set_valign(fa_top);
		fw_draw_set_halign(fa_left);
		#endif
		#if CJKTEXT
		global.__ONLINE_cjkHalign = 1;
		global.__ONLINE_cjkValign = 1;
		__ONLINE_cjk_draw_text(@barX + @barW / 2, @barY + @barH / 2, @barTxt, 9999);
		global.__ONLINE_cjkHalign = 0;
		global.__ONLINE_cjkValign = 0;
		#endif
		#if not GM80
		#if not CJKTEXT
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
		draw_text(@barX + @barW / 2, @barY + @barH / 2, @barTxt);
		#endif
		#endif
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
	}
	if(@spectating){
		draw_set_alpha(0.55);
		draw_set_color(c_black);
		draw_rectangle(@hudX, @hudY, @hudX + @hudW, @hudY + 22, false);
		draw_set_alpha(0.2);
		draw_rectangle(@hudX, @hudY + 22, @hudX + @hudW, @hudY + 24, false);
		draw_set_alpha(1);
		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		@specCount = instance_number(@onlinePlayer);
		if(@specTargetID != ""){
			// the prefix is measured but never drawn: the arrows bracket where the
			// full "SPECTATING: name" would sit. Measure on the CJK-aware path so a
			// Chinese target name does not scatter the arrows.
			@specFull = @L(global.__ONLINE_LK_HUD_SPECTATING_PREFIX, "  SPECTATING: ") + @specTargetName + "  ";
			draw_set_color(c_gray);
			draw_text(@hudX + @hudW/2 - @stg_text_width(@specFull)/2 - 8, @hudY + 4, "<");
			draw_text(@hudX + @hudW/2 + @stg_text_width(@specFull)/2 + 8, @hudY + 4, ">");
			draw_set_color(make_color_rgb(255, 220, 80));
			@stg_text_cjk(@hudX + @hudW/2, @hudY + 4, @specTargetName, 1);
			draw_set_color(c_gray);
			@stg_text_cjk(@hudX + @hudW - 6, @hudY + 4, string(@specTargetIdx + 1) + "/" + string(@specCount), 2);
		}else{
			draw_set_color(c_gray);
			@stg_text_cjk(@hudX + @hudW/2, @hudY + 4, @L(global.__ONLINE_LK_HUD_NO_PLAYERS, "No players"), 1);
		}
		draw_set_valign(fa_bottom);
		draw_set_alpha(0.5);
		draw_set_color(c_white);
		if(@specCamMode == 1){
			@stg_text_cjk(@hudX + @hudW - 6, @hudY + @hudH - 4, @L(global.__ONLINE_LK_HUD_SCREEN, "[Screen]"), 2);
		}else{
			@stg_text_cjk(@hudX + @hudW - 6, @hudY + @hudH - 4, @L(global.__ONLINE_LK_HUD_FOLLOW, "[Follow]"), 2);
		}
	}
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
}
#if PLAYER_LIST
// PLAYER OBJECT PICK MODE HUD (paired with the input block in worldEndStep)
if(@debug_pick_player){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	@pkX = 8;
	@pkY = 8;
	@pkLines = ds_list_size(@obj_list) + 5;
	draw_set_alpha(0.85);
	draw_set_color(c_black);
	draw_rectangle(@pkX, @pkY, @pkX + 400, @pkY + @pkLines * 18 + 10, false);
	draw_set_alpha(1);
	draw_set_color(c_white);
	@stg_text_cjk(@pkX + 8, @pkY + 4, @L(global.__ONLINE_LK_HUD_PICK_TITLE, "Player objects:  L = add/remove"), 0);
	@stg_text_cjk(@pkX + 8, @pkY + 22, @L(global.__ONLINE_LK_HUD_PICK_LINE2, "R = add first,  C = clear all"), 0);
	@stg_text_cjk(@pkX + 8, @pkY + 40, @L(global.__ONLINE_LK_HUD_PICK_DONE, "Enter = done"), 0);
	@pkYY = @pkY + 58;
	for(@pkI = 0; @pkI < ds_list_size(@obj_list); @pkI += 1){
		@pkObj = ds_list_find_value(@obj_list, @pkI);
		@pkTxt = object_get_name(@pkObj);
		if(@pkObj == @get_active_player()){
			@pkTxt += @L(global.__ONLINE_LK_HUD_PICK_ACTIVE, " (active)");
		}
		if(instance_exists(@pkObj)){
			@pkInst = instance_find(@pkObj, 0);
			@pkTxt += "  (" + string(@pkInst.x) + ", " + string(@pkInst.y) + ")";
		}else{
			@pkTxt += @L(global.__ONLINE_LK_HUD_PICK_NO_INSTANCE, "  [no instance]");
		}
		draw_set_color(c_white);
		@stg_text_cjk(@pkX + 16, @pkYY, @pkTxt, 0);
		@pkYY += 18;
	}
	@pkTgt = instance_position(mouse_x, mouse_y, all);
	if(@pkTgt != noone){
		draw_set_color(c_yellow);
		if(ds_list_find_index(@obj_list, @pkTgt.object_index) >= 0){
			@stg_text_cjk(@pkX + 8, @pkYY, @str_fmt(@L(global.__ONLINE_LK_HUD_PICK_REMOVE, "> %1: L = remove"), object_get_name(@pkTgt.object_index), 0, 0), 0);
		}else{
			@stg_text_cjk(@pkX + 8, @pkYY, @str_fmt(@L(global.__ONLINE_LK_HUD_PICK_CURRENT, "> %1: L = add, R = add first"), object_get_name(@pkTgt.object_index), 0, 0), 0);
		}
	}
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
}
#endif
#if GAME_D3D
	#if not STUDIO
		d3d_set_hidden(true);
	#endif
#endif
#if not STUDIO
	#if not GM8GUI
	// Projection restore (group-8 path only): the runner re-applies the view
	// projection only at the start of the next view, so anything drawn after
	// us in this view would otherwise inherit the HUD ortho.
	if(view_enabled){
		d3d_set_projection_ortho(view_xview[view_current], view_yview[view_current], view_wview[view_current], view_hview[view_current], view_angle[view_current]);
	}else{
		d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
	}
	#endif
#endif
}
