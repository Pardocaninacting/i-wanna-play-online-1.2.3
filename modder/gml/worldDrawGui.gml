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
	// QoL fix: with views enabled but none visible (menu / title rooms) the old
	// guard (@hudFirst == -1) never matched view_current, so the whole HUD -
	// chat, notes and the O settings panel - silently vanished in those rooms.
	// Draw the single HUD pass in the current view instead.
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
if(@hudWinW < 1) @hudGuiOn = false;
if(@hudWinH < 1) @hudGuiOn = false;
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
	draw_set_halign(fa_center);
	draw_text(@clPanelX + @clPanelW / 2, @clPanelY + 3, "Chat Log");
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
		draw_set_halign(fa_center);
		draw_text(@clPanelX + @clPanelW / 2, @clPanelY + @clPanelH / 2 - 6, "No messages yet");
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
	draw_text(@plX+1, @plY, "Players Online:");
	draw_text(@plX, @plY+1, "Players Online:");
	draw_text(@plX-1, @plY, "Players Online:");
	draw_text(@plX, @plY-1, "Players Online:");
	draw_set_color(c_yellow);
	draw_text(@plX, @plY, "Players Online:");
	@plY += 18;
	@plSelf = @name + " (YOU)";
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
	// It must never be re-derived here: a hardcoded size once forked the two,
	// and the row table painted outside the panel.
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
	draw_set_blend_mode(bm_normal);
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
	@tabNames[0] = "Settings";
	@tabNames[1] = "Saves(" + string(@saveHistCount) + ")";
	@tabNames[2] = "Rating";
	@tabNames[3] = "Keys";
	@tabNames[4] = "Sync";
	@tabNames[5] = "Skins";
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
		draw_text(floor((@tX1 + @tX2) / 2), @tabY + 6, @tabNames[@tI]);
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

	// TAB 0: SETTINGS
	if(@settingsTab == 0){
		// QoL: one declarative table drives the layout (see gml/settingsLib.gml).
		@stg_build_rows(@contentY);
		// Scrollable viewport. It scrolls by ROW INDEX, not by pixels: the table is
		// drawn on its own grid below @stgTop, so a row can never be half visible and
		// the pointer/focus mapping can never drift by a row (that was the bug).
		@stgTop = @contentY;
		@stgBottom = @footerY - 6;
		@stgViewH = @stgBottom - @stgTop;
		if(@stgFirst < 0) @stgFirst = 0;
		if(@stgFirst >= global.__ONLINE_stgN) @stgFirst = global.__ONLINE_stgN - 1;
		if(@stgFirst < 0) @stgFirst = 0;
		@stgFit = @stg_fit_rows(@stgFirst, @stgTop + 2, @stgBottom);
		if(@stgFit < 1) @stgFit = 1;
		if(@kbFocus == 1){
			// Scroll by ONE row at a time. Aligning the focused row to the top edge
			// (the previous behaviour) made a single Down jump a whole page.
			if(@kbRow[0] < @stgFirst) @stgFirst = @kbRow[0];
			if(@kbRow[0] >= @stgFirst + @stgFit) @stgFirst += 1;
			// mixed row heights (18/24) make "fits" approximate, so walk forward
			// until the focused row is really inside the band
			@stgGuard = 0;
			while(@stgGuard < 64){
				@stgFit = @stg_fit_rows(@stgFirst, @stgTop + 2, @stgBottom);
				if(@stgFit < 1) @stgFit = 1;
				if(@kbRow[0] < @stgFirst + @stgFit) break;
				@stgFirst += 1;
				@stgGuard += 1;
			}
		}
		@stgMaxFirst = global.__ONLINE_stgN - @stgFit;
		if(@stgMaxFirst < 0) @stgMaxFirst = 0;
		if(@stgFirst > @stgMaxFirst) @stgFirst = @stgMaxFirst;
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
			if(@rowY + global.__ONLINE_stgRowH > @stgBottom) @rowVis = false;
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
					draw_set_color(make_color_rgb(48, 46, 30));
					draw_rectangle(@rowX - 6, @rowY - 1, @rowCX + @rowCW + 6, @rowY + global.__ONLINE_stgRowH - 3, false);
					draw_set_color(make_color_rgb(220, 200, 60));
					draw_rectangle(@rowX - 6, @rowY - 1, @rowCX + @rowCW + 6, @rowY + global.__ONLINE_stgRowH - 3, true);
				}else if(@rowHover == @rowI){
					draw_set_color(make_color_rgb(35, 35, 40));
					draw_rectangle(@rowX - 6, @rowY - 1, @rowCX + @rowCW + 6, @rowY + global.__ONLINE_stgRowH - 3, false);
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
				draw_set_color(make_color_rgb(150, 150, 150));
				draw_set_halign(fa_right);
				draw_text(@spX + @colW - 16, @rowY + 2 + @stgTextDY, "Server: " + @stg_server_text());
			}else{
				draw_set_color(c_white);
				draw_text(@rowX, @rowY + 4 + @stgTextDY, global.__ONLINE_stgLabel[@rowI]);
				@rowV = @stg_value(@rowI);
				@rowBY = @rowY + 2;
				@rowBH = global.__ONLINE_stgRowH - 6;
				if(@rowK == 5){
					// button: flat dark plate, brighter frame on hover/focus
					draw_set_color(make_color_rgb(45, 45, 52));
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, false);
					if(@rowSel || @rowHover == @rowI){
						draw_set_color(make_color_rgb(150, 160, 175));
					}else{
						draw_set_color(make_color_rgb(90, 95, 105));
					}
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, true);
					draw_set_color(c_white);
					draw_set_halign(fa_center);
					draw_text(@rowCX + floor(@rowCW / 2), @rowBY + 3 + @stgTextDY, @rowV);
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
					if(@rowV == "ON"){
						draw_set_color(make_color_rgb(50, 170, 80));
					}else{
						draw_set_color(make_color_rgb(90, 90, 90));
					}
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, false);
					draw_set_color(c_white);
					draw_set_halign(fa_center);
					draw_text(@rowCX + floor(@rowCW / 2), @rowBY + 3 + @stgTextDY, @rowV);
				}else{
					// text field (name / session key)
					draw_set_color(make_color_rgb(35, 35, 40));
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, false);
					draw_set_color(make_color_rgb(95, 95, 100));
					draw_rectangle(@rowCX, @rowBY, @rowCX + @rowCW, @rowBY + @rowBH, true);
					draw_set_color(c_white);
					draw_text(@rowCX + 6, @rowBY + 3, @rowV);
					if(@rowSty == 3){
						draw_set_color(make_color_rgb(150, 150, 150));
						draw_set_halign(fa_right);
						draw_text(@spX + @colW - 16, @rowBY + 3, @stg_source_text());
					}
				}
			}
			}
			@rowI += 1;
		}
		// side scrollbar (track + thumb) instead of the old "more" markers
		if(global.__ONLINE_stgN > @stgFit){
			@sbX = @spX + @colW - 7;
			draw_set_color(make_color_rgb(38, 38, 44));
			draw_rectangle(@sbX, @stgTop + 2, @sbX + 4, @stgBottom, false);
			@sbH = (@stgBottom - @stgTop - 2) * @stgFit / global.__ONLINE_stgN;
			if(@sbH < 16) @sbH = 16;
			@sbY = @stgTop + 2 + (@stgBottom - @stgTop - 2 - @sbH) * @stgFirst / max(1, @stgMaxFirst);
			draw_set_color(make_color_rgb(110, 110, 122));
			draw_rectangle(@sbX, @sbY, @sbX + 4, @sbY + @sbH, false);
		}
		draw_set_halign(fa_left);
		// footer: separator + hint + Close all live in the footer band (@footerY),
		// below the last row; the toast floats just above it and never overlaps
		// detail column (full layout only): what the list row cannot express
		if(@detW > 0) @stg_draw_detail(@kbRow[0]);

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
			draw_text(@spX + @colW - 16, @footerY - 18, global.__ONLINE_stgToastMsg);
			draw_set_halign(fa_left);
		}
		draw_set_color(make_color_rgb(70, 80, 95));
		draw_rectangle(@spX + 16, @footerY, @spX + @spW - 16, @footerY + 1, false);
		draw_set_color(make_color_rgb(160, 160, 160));
		if(@kbFocus == 1 && @kbRow[0] >= 0 && @kbRow[0] < global.__ONLINE_stgN){
			draw_text(@spX + 16, @footerY + 10, @stg_hint(@kbRow[0]));
		}else{
			draw_text(@spX + 16, @footerY + 10, "Up/Down rows   Left/Right tabs or values   Enter edit   F1 close");
		}
	}
	// TAB 1: SAVES
	if(@settingsTab == 1){
		draw_set_halign(fa_left);
		@shVisCount = 0;
		@shNow = date_current_datetime();
		for(@shI = @saveHistCount - 1; @shI >= 0; @shI -= 1){
			if(@saveHistFilter == 0 || @saveHistFav[@shI]){
				@shVisIdx[@shVisCount] = @shI;
				@shVisCount += 1;
			}
		}
		@shPageSize = 8;
		@shPages = floor((@shVisCount + @shPageSize - 1) / @shPageSize);
		if(@shPages < 1) @shPages = 1;
		if(@saveHistPage >= @shPages) @saveHistPage = @shPages - 1;
		if(@saveHistPage < 0) @saveHistPage = 0;
		@shStart = @saveHistPage * @shPageSize;
		@shEnd = @shStart + @shPageSize;
		if(@shEnd > @shVisCount) @shEnd = @shVisCount;
		@rowY = @contentY + 2;
		@btnPFX = @spX + 8;
		@btnPFY = @rowY - 2;
		@btnPFW = 20;
		@btnPFH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnPFX, @btnPFY, @btnPFX + @btnPFW, @btnPFY + @btnPFH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnPFX + @btnPFW/2, @rowY, "<<");
		@btnPLX = @spX + 32;
		@btnPLY = @rowY - 2;
		@btnPLW = 20;
		@btnPLH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnPLX, @btnPLY, @btnPLX + @btnPLW, @btnPLY + @btnPLH, false);
		draw_set_color(c_white);
		draw_text(@btnPLX + @btnPLW/2, @rowY, "<");
		draw_set_color(c_white);
		draw_text(@spX + 82, @rowY, string(@saveHistPage + 1) + "/" + string(@shPages));
		@btnPRX = @spX + 120;
		@btnPRY = @rowY - 2;
		@btnPRW = 20;
		@btnPRH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnPRX, @btnPRY, @btnPRX + @btnPRW, @btnPRY + @btnPRH, false);
		draw_set_color(c_white);
		draw_text(@btnPRX + @btnPRW/2, @rowY, ">");
		@btnPEX = @spX + 144;
		@btnPEY = @rowY - 2;
		@btnPEW = 20;
		@btnPEH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnPEX, @btnPEY, @btnPEX + @btnPEW, @btnPEY + @btnPEH, false);
		draw_set_color(c_white);
		draw_text(@btnPEX + @btnPEW/2, @rowY, ">>");
		@btnFltX = @spX + 174;
		@btnFltY = @rowY - 2;
		@btnFltW = 18;
		@btnFltH = 18;
		if(@saveHistFilter){
			draw_set_color(make_color_rgb(200, 160, 40));
		}else{
			draw_set_color(make_color_rgb(60, 60, 60));
		}
		draw_rectangle(@btnFltX, @btnFltY, @btnFltX + @btnFltW, @btnFltY + @btnFltH, false);
		draw_set_color(c_white);
		draw_text(@btnFltX + @btnFltW/2, @rowY, "*");
		@btnClrX = @spX + @colW - 72;
		@btnClrY = @rowY - 2;
		@btnClrW = 60;
		@btnClrH = 18;
		if(@saveHistCount > @saveHistFavCount){
			draw_set_color(make_color_rgb(140, 50, 50));
		}else{
			draw_set_color(make_color_rgb(40, 40, 40));
		}
		draw_rectangle(@btnClrX, @btnClrY, @btnClrX + @btnClrW, @btnClrY + @btnClrH, false);
		draw_set_color(c_white);
		draw_text(@btnClrX + @btnClrW/2, @rowY, "Clear");
		draw_set_halign(fa_left);
		for(@shVI = @shStart; @shVI < @shEnd; @shVI += 1){
			@shI = @shVisIdx[@shVI];
			@entIdx = @shVI - @shStart;
			@entY = @contentY + 28 + @entIdx * 38;
			draw_set_color(make_color_rgb(30, 30, 30));
			draw_rectangle(@spX + 8, @entY - 3, @spX + @colW - 8, @entY + 28, false);
			if(@kbFocus == 1 && @kbRow[1] == @shVI){
				draw_set_color(make_color_rgb(220, 200, 60));
				draw_rectangle(@spX + 4, @entY - 1, @spX + @colW - 4, @entY + 30, true);
			}
			@btnFavX = @spX + 10;
			@btnFavY = @entY + 5;
			@btnFavW = 16;
			@btnFavH = 16;
			if(@saveHistFav[@shI]){
				draw_set_color(make_color_rgb(200, 160, 40));
			}else{
				draw_set_color(make_color_rgb(50, 50, 50));
			}
			draw_rectangle(@btnFavX, @btnFavY, @btnFavX + @btnFavW, @btnFavY + @btnFavH, false);
			draw_set_color(c_white);
			draw_set_halign(fa_center);
			draw_text(@btnFavX + @btnFavW/2, @entY + 6, "*");
			@shHot = @saveHistHotkey[@shI];
			@btnHotX = @spX + 30;
			@btnHotY = @entY + 5;
			@btnHotW = 16;
			@btnHotH = 16;
			if(@shHot > 0){
				draw_set_color(make_color_rgb(60, 100, 170));
			}else{
				draw_set_color(make_color_rgb(45, 45, 45));
			}
			draw_rectangle(@btnHotX, @btnHotY, @btnHotX + @btnHotW, @btnHotY + @btnHotH, false);
			draw_set_color(c_white);
			if(@shHot > 0){
				draw_text(@btnHotX + @btnHotW/2, @entY + 5, string(@shHot));
			}else{
				draw_text(@btnHotX + @btnHotW/2, @entY + 5, "-");
			}
			draw_set_halign(fa_left);
			@shDispName = @saveHistName[@shI];
			#if GM80
			@shDispName = __ONLINE_gbk_trunc(@shDispName, 14, "..");
			#endif
			#if CJKTEXT
			@shDispName = __ONLINE_gbk_trunc(@shDispName, 14, "..");
			#endif
			#if not GM80
			#if not CJKTEXT
			if(string_length(@shDispName) > 14) @shDispName = string_copy(@shDispName, 1, 14) + "..";
			#endif
			#endif
			draw_set_color(c_lime);
			#if GM80
			fw_draw_set_halign(fa_left);
			fw_draw_set_valign(fa_top);
			__ONLINE_fw_use_font(@shDispName);
			fw_draw_text_ext(@spX + 54, @entY, @shDispName, 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 0;
			global.__ONLINE_cjkValign = 0;
			__ONLINE_cjk_draw_text(@spX + 54, @entY, @shDispName, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@spX + 54, @entY, @shDispName);
			#endif
			#endif
			@shDispRoom = @saveHistRoomName[@shI];
			if(string_length(@shDispRoom) > 14) @shDispRoom = string_copy(@shDispRoom, 1, 14) + "..";
			draw_set_color(c_aqua);
			draw_text(@spX + 204, @entY, @shDispRoom);
			if(@saveHistTime[@shI] <= 0){
				@shTimeDisp = "?";
			}else{
				@shAgeMins = (@shNow - @saveHistTime[@shI]) * 1440;
				if(@shAgeMins < 0) @shAgeMins = 0;
				if(@shAgeMins < 1){
					@shTimeDisp = "now";
				}else if(@shAgeMins < 60){
					@shTimeDisp = string(round(@shAgeMins)) + "m";
				}else if(@shAgeMins < 1440){
					@shTimeDisp = string(round(@shAgeMins / 60)) + "h";
				}else if(@shAgeMins < 10080){
					@shTimeDisp = string(round(@shAgeMins / 1440)) + "d";
				}else{
					@shTimeDisp = string(date_get_month(@saveHistTime[@shI])) + "/" + string(date_get_day(@saveHistTime[@shI]));
				}
			}
			draw_set_color(c_gray);
			draw_text(@spX + 320, @entY, @shTimeDisp);
			draw_set_color(make_color_rgb(160, 160, 160));
			draw_text(@spX + 54, @entY + 13, "x:" + string(@saveHistX[@shI]) + " y:" + string(round(@saveHistY[@shI])));
			@btnApX = @spX + @colW - 66;
			@btnApY = @entY + 5;
			@btnApW = 54;
			@btnApH = 18;
			draw_set_color(make_color_rgb(40, 100, 160));
			draw_rectangle(@btnApX, @btnApY, @btnApX + @btnApW, @btnApY + @btnApH, false);
			draw_set_color(c_white);
			draw_set_halign(fa_center);
			draw_text(@btnApX + @btnApW/2, @entY + 6, "Apply");
			draw_set_halign(fa_left);
		}
		if(@shVisCount == 0){
			draw_set_color(c_gray);
			draw_set_halign(fa_center);
			if(@saveHistFilter && @saveHistCount > 0){
				draw_text(@spX + @colW/2, @contentY + 120, "No favorites");
			}else{
				draw_text(@spX + @colW/2, @contentY + 120, "No saves yet");
			}
			draw_set_halign(fa_left);
		}
	}
	// TAB 2: RATING
	if(@settingsTab == 2){
		@rowY = @contentY + 4;
		if(@kbFocus == 1){
			if(@kbRow[2] == 0) @kbHi = @contentY + 24;
			if(@kbRow[2] == 1) @kbHi = @contentY + 54;
			if(@kbRow[2] == 2) @kbHi = @contentY + 101;
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@spX + 4, @kbHi, @spX + @colW - 4, @kbHi + 28, true);
		}
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		@gameLabel = "Game: " + @gameName;
		#if GM80
		__ONLINE_fw_use_font(@gameLabel);
		fw_draw_set_halign(fa_left);
		fw_draw_set_valign(fa_top);
		fw_draw_text_ext(@spX + 16, @rowY, @gameLabel, 9999);
		#endif
		#if CJKTEXT
		global.__ONLINE_cjkHalign = 0;
		global.__ONLINE_cjkValign = 0;
		__ONLINE_cjk_draw_text(@spX + 16, @rowY, @gameLabel, 9999);
		#endif
		#if not GM80
		#if not CJKTEXT
		draw_text(@spX + 16, @rowY, @gameLabel);
		#endif
		#endif
		@rowY += 26;
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Rating:");
		@starX = @spX + 100;
		@starY = @rowY - 2;
		@starW = 28;
		@starH = 22;
		for(@sI = 1; @sI <= 5; @sI += 1){
			@sX = @starX + (@sI - 1) * @starW;
			if(@sI <= @rStars){
				draw_set_color(make_color_rgb(255, 200, 40));
			}else{
				draw_set_color(make_color_rgb(60, 60, 60));
			}
			draw_rectangle(@sX, @starY, @sX + @starW - 2, @starY + @starH, false);
			draw_set_color(c_white);
			draw_set_halign(fa_center);
			draw_text(@sX + @starW/2 - 1, @rowY, string(@sI));
		}
		draw_set_halign(fa_left);
		@rowY += 30;
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Cleared:");
		@btnClrRX = @spX + 100;
		@btnClrRY = @rowY - 2;
		@btnClrRW = 50;
		@btnClrRH = 20;
		if(@rCleared){
			draw_set_color(make_color_rgb(40, 160, 40));
		}else{
			draw_set_color(make_color_rgb(50, 50, 50));
		}
		draw_rectangle(@btnClrRX, @btnClrRY, @btnClrRX + @btnClrRW, @btnClrRY + @btnClrRH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@rCleared){
			draw_text(@btnClrRX + @btnClrRW/2, @rowY, "Yes");
		}else{
			draw_text(@btnClrRX + @btnClrRW/2, @rowY, "No");
		}
		draw_set_halign(fa_left);
		draw_set_color(c_gray);
		draw_text(@spX + 160, @rowY, "(optional)");
		if(@rClearWarn > 0){
			@rowY += 24;
			draw_set_color(c_yellow);
			draw_text(@spX + 16, @rowY, "Game not cleared. Are you sure?");
			@rowY += 22;
		}else{
			@rowY += 46;
		}
		@btnSubX = @spX + @colW/2 - 55;
		@btnSubY = @rowY - 2;
		@btnSubW = 110;
		@btnSubH = 22;
		if(@ratingSubmitting){
			draw_set_color(make_color_rgb(60, 60, 60));
		}else if(@ratingCooldown > current_time){
			draw_set_color(make_color_rgb(80, 80, 40));
		}else if(@rStars == 0){
			draw_set_color(make_color_rgb(60, 60, 60));
		}else{
			draw_set_color(make_color_rgb(40, 100, 160));
		}
		draw_rectangle(@btnSubX, @btnSubY, @btnSubX + @btnSubW, @btnSubY + @btnSubH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@ratingSubmitting){
			draw_text(@btnSubX + @btnSubW/2, @rowY, "Sending...");
		}else if(@ratingCooldown > current_time){
			// QoL fix: the cooldown is stored in FRAMES (worldEndStep sets
			// room_speed * 10) but this used to divide by a hardcoded 30, so a
			// 60 fps game displayed 20 s and counted down at double speed.
			draw_text(@btnSubX + @btnSubW/2, @rowY, "Wait " + string(max(1, ceil((@ratingCooldown - current_time) / 1000))) + "s");
		}else{
			draw_text(@btnSubX + @btnSubW/2, @rowY, "Submit Rating");
		}
		if(@ratingResultTimer > current_time){
			@rowY += 30;
			if(@ratingResult == 1){
				draw_set_color(c_lime);
				draw_text(@spX + @colW/2, @rowY, "Rating submitted!");
			}else if(@ratingResult == 2){
				draw_set_color(c_yellow);
				draw_text(@spX + @colW/2, @rowY, "Submit failed (cooldown)");
			}
		}
		draw_set_halign(fa_left);
	}
	// TAB 3: KEYS
	if(@settingsTab == 3){
		@rowY = @contentY + 4;
		if(@kbFocus == 1 && @kbRow[3] < 11){
			@kbHi = @rowY - 4 + @kbRow[3] * 28;
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@spX + 4, @kbHi, @spX + @colW - 4, @kbHi + 27, true);
		}
		draw_set_halign(fa_left);
		@kbLabels[0] = "Visibility";
		@kbLabels[1] = "Toggle Save";
		@kbLabels[2] = "Spectate";
		@kbLabels[3] = "Chat Log";
		@kbLabels[4] = "Indicator";
		@kbLabels[5] = "Options";
		@kbLabels[6] = "Player List";
		@kbLabels[7] = "Chat";
		@kbLabels[8] = "Here";
		@kbLabels[9] = "Fast Load";
		@kbLabels[10] = "Canvas";
		@kbKeys[0] = @keyVis;
		@kbKeys[1] = @keySave;
		@kbKeys[2] = @keySpectate;
		@kbKeys[3] = @keyChatLog;
		@kbKeys[4] = @keyArrows;
		@kbKeys[5] = @keySettings;
		@kbKeys[6] = @keyPlayerList;
		@kbKeys[7] = @keyChat;
		@kbKeys[8] = @keyPing;
		@kbKeys[9] = @keyFastLoad;
		@kbKeys[10] = @keyCanvas;
		for(@kI = 0; @kI < 11; @kI += 1){
			@kbY = @rowY + @kI * 28;
			draw_set_color(c_white);
			draw_text(@spX + 16, @kbY, @kbLabels[@kI]);
			@btnKX = @spX + 140;
			@btnKY = @kbY - 2;
			@btnKW = 120;
			@btnKH = 20;
			if(@keybindEditing == @kI){
				draw_set_color(make_color_rgb(160, 120, 40));
			}else{
				draw_set_color(make_color_rgb(50, 50, 50));
			}
			draw_rectangle(@btnKX, @btnKY, @btnKX + @btnKW, @btnKY + @btnKH, false);
			draw_set_color(c_white);
			draw_set_halign(fa_center);
			if(@keybindEditing == @kI){
				draw_text(@btnKX + @btnKW/2, @kbY, "Press a key...");
			}else{
				if(@kbKeys[@kI] >= 33 && @kbKeys[@kI] <= 126){
					draw_text(@btnKX + @btnKW/2, @kbY, chr(@kbKeys[@kI]) + " (" + string(@kbKeys[@kI]) + ")");
				}else if(@kbKeys[@kI] == 32){
					draw_text(@btnKX + @btnKW/2, @kbY, "SPACE (32)");
				}else{
					draw_text(@btnKX + @btnKW/2, @kbY, "Key " + string(@kbKeys[@kI]));
				}
			}
			draw_set_halign(fa_left);
		}
		@btnRstX = @spX + @colW/2 - 55;
		@btnRstY = @rowY + 11 * 28 + 10;
		@btnRstW = 110;
		@btnRstH = 22;
		if(@kbFocus == 1 && @kbRow[3] == 11){
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@spX + 4, @btnRstY - 3, @spX + @colW - 4, @btnRstY + @btnRstH + 3, true);
		}
		draw_set_color(make_color_rgb(100, 50, 50));
		draw_rectangle(@btnRstX, @btnRstY, @btnRstX + @btnRstW, @btnRstY + @btnRstH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnRstX + @btnRstW/2, @btnRstY + 2, "Reset Keys");
		draw_set_halign(fa_left);
	}
	// TAB 4: SYNC
	if(@settingsTab == 4){
		@rowY = @contentY + 4;
		if(@kbFocus == 1){
			draw_set_color(make_color_rgb(220, 200, 60));
			draw_rectangle(@spX + 4, @rowY - 3, @spX + @colW - 4, @rowY + 25, true);
		}
		draw_set_color(c_white);
		draw_set_halign(fa_left);
		draw_text(@spX + 16, @rowY, "Sync Enabled:");
		@btnSyncX = @spX + 140;
		@btnSyncY = @rowY;
		@btnSyncW = 50;
		@btnSyncH = 18;
		if(@syncEnabled){
			draw_set_color(make_color_rgb(40, 160, 40));
		}else{
			draw_set_color(c_gray);
		}
		draw_rectangle(@btnSyncX, @btnSyncY, @btnSyncX + @btnSyncW, @btnSyncY + @btnSyncH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@syncEnabled){
			draw_text(@btnSyncX + @btnSyncW/2, @rowY + 2, "ON");
		}else{
			draw_text(@btnSyncX + @btnSyncW/2, @rowY + 2, "OFF");
		}
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		@rowY = @contentY + 32;
		draw_text(@spX + 16, @rowY, "Entries (" + string(@syncEntryCount) + "):");
		@rowY += 18;
		draw_set_color(make_color_rgb(180, 180, 180));
		draw_text(@spX + 16,  @rowY, "#");
		draw_text(@spX + 40,  @rowY, "Name");
		draw_text(@spX + 220, @rowY, "Count");
		draw_set_color(c_white);
		@rowY += 16;
		for(@scI = 0; @scI < @syncEntryCount; @scI += 1){
			if(@scI >= 10) break;
			draw_text(@spX + 16,  @rowY, string(@scI));
			draw_text(@spX + 40,  @rowY, @syncName[@scI]);
			draw_text(@spX + 220, @rowY, string(@syncCount[@scI]));
			@rowY += 16;
		}
		if(@syncEntryCount == 0){
			draw_set_color(make_color_rgb(150, 150, 150));
			draw_text(@spX + 16, @rowY, "(no entries configured)");
			draw_set_color(c_white);
		}
		draw_set_halign(fa_left);
	}
    // TAB 5: SKINS
    if(@settingsTab == 5){
        draw_set_halign(fa_left);
        // Paged list paradigm copied from the Saves tab (12 rows per page).
        @skPageSize = 12;
        @skPages = floor((@skinVisCount + @skPageSize - 1) / @skPageSize);
        if(@skPages < 1) @skPages = 1;
        if(@skinPage >= @skPages) @skinPage = @skPages - 1;
        if(@skinPage < 0) @skinPage = 0;
        @skStart = @skinPage * @skPageSize;
        @skEnd = @skStart + @skPageSize;
        if(@skEnd > @skinVisCount) @skEnd = @skinVisCount;
        @rowY = @contentY + 2;
        @btnSkPFX = @spX + 8;
        @btnSkPFY = @rowY - 2;
        @btnSkPFW = 20;
        @btnSkPFH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkPFX, @btnSkPFY, @btnSkPFX + @btnSkPFW, @btnSkPFY + @btnSkPFH, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(@btnSkPFX + @btnSkPFW/2, @rowY, "<<");
        @btnSkPLX = @spX + 32;
        @btnSkPLY = @rowY - 2;
        @btnSkPLW = 20;
        @btnSkPLH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkPLX, @btnSkPLY, @btnSkPLX + @btnSkPLW, @btnSkPLY + @btnSkPLH, false);
        draw_set_color(c_white);
        draw_text(@btnSkPLX + @btnSkPLW/2, @rowY, "<");
        draw_text(@spX + 82, @rowY, string(@skinPage + 1) + "/" + string(@skPages));
        @btnSkPRX = @spX + 120;
        @btnSkPRY = @rowY - 2;
        @btnSkPRW = 20;
        @btnSkPRH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkPRX, @btnSkPRY, @btnSkPRX + @btnSkPRW, @btnSkPRY + @btnSkPRH, false);
        draw_set_color(c_white);
        draw_text(@btnSkPRX + @btnSkPRW/2, @rowY, ">");
        @btnSkPEX = @spX + 144;
        @btnSkPEY = @rowY - 2;
        @btnSkPEW = 20;
        @btnSkPEH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkPEX, @btnSkPEY, @btnSkPEX + @btnSkPEW, @btnSkPEY + @btnSkPEH, false);
        draw_set_color(c_white);
        draw_text(@btnSkPEX + @btnSkPEW/2, @rowY, ">>");
        draw_set_halign(fa_left);
        draw_set_color(c_gray);
        draw_text(@spX + 180, @rowY, string(@skinVisCount) + " skin(s)");
        for(@skVI = @skStart; @skVI < @skEnd; @skVI += 1){
            @entIdx = @skVI - @skStart;
            @entY = @contentY + 28 + @entIdx * 22;
            if(!@skinParsed[@skVI]) @skin_parse(@skVI);
            if(@skVI == @skinSel){
                draw_set_color(make_color_rgb(30, 60, 30));
            }else{
                draw_set_color(make_color_rgb(30, 30, 30));
            }
            draw_rectangle(@spX + 8, @entY - 3, @spX + 268, @entY + 17, false);
            if(@kbFocus == 1 && @kbRow[5] == @skVI){
                draw_set_color(make_color_rgb(220, 200, 60));
                draw_rectangle(@spX + 4, @entY - 4, @spX + 272, @entY + 18, true);
            }
            draw_set_halign(fa_left);
            if(@skVI == @skinSel){
                draw_set_color(c_lime);
            }else{
                draw_set_color(c_white);
            }
            @skLabel = @skinName[@skVI];
            // A skin without idle.png breaks the whole fallback chain; flag it
            // in the list (still selectable, the draw falls back per-state).
            if(!@skinHas[@skVI, 0]) @skLabel = "[!] " + @skLabel;
            if(@skinMaker[@skVI] != "") @skLabel += " (" + @skinMaker[@skVI] + ")";
            if(string_length(@skLabel) > 30) @skLabel = string_copy(@skLabel, 1, 30) + "..";
            draw_text(@spX + 14, @entY, @skLabel);
            if(@skVI == @skinLoaded){
                draw_set_color(c_gray);
                draw_text(@spX + 246, @entY, "*");
            }
        }
        if(@skinVisCount == 0){
            draw_set_color(c_gray);
            draw_set_halign(fa_center);
            draw_text(@spX + @colW/2, @contentY + 120, "No skins found in iwposkins" + chr(92));
            draw_set_halign(fa_left);
        }
        // Row after the list: Auto-download toggle (keyboard row @skinVisCount).
        @rowY = @contentY + 28 + 12 * 22 + 4;
        if(@kbFocus == 1 && @kbRow[5] == @skinVisCount){
            draw_set_color(make_color_rgb(220, 200, 60));
            draw_rectangle(@spX + 4, @rowY - 3, @spX + 272, @rowY + 21, true);
        }
        draw_set_color(c_white);
        draw_set_halign(fa_left);
        draw_text(@spX + 16, @rowY, "Auto-download:");
        @btnSkAdLX = @spX + 150;
        @btnSkAdLY = @rowY;
        @btnSkAdLW = 20;
        @btnSkAdLH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkAdLX, @btnSkAdLY, @btnSkAdLX + @btnSkAdLW, @btnSkAdLY + @btnSkAdLH, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(@btnSkAdLX + @btnSkAdLW/2, @rowY, "<");
        if(@skinAutoDL){
            draw_set_color(make_color_rgb(40, 160, 40));
            draw_text(@spX + 205, @rowY, "On");
        }else{
            draw_set_color(c_gray);
            draw_text(@spX + 205, @rowY, "Off");
        }
        @btnSkAdRX = @spX + 240;
        @btnSkAdRY = @rowY;
        @btnSkAdRW = 20;
        @btnSkAdRH = 18;
        draw_set_color(c_gray);
        draw_rectangle(@btnSkAdRX, @btnSkAdRY, @btnSkAdRX + @btnSkAdRW, @btnSkAdRY + @btnSkAdRH, false);
        draw_set_color(c_white);
        draw_text(@btnSkAdRX + @btnSkAdRW/2, @rowY, ">");
        draw_set_halign(fa_left);
        // Last row: clear the current skin (keyboard row @skinVisCount + 1).
        @rowY += 26;
        if(@kbFocus == 1 && @kbRow[5] == @skinVisCount + 1){
            draw_set_color(make_color_rgb(220, 200, 60));
            draw_rectangle(@spX + 4, @rowY - 3, @spX + 272, @rowY + 21, true);
        }
        draw_set_color(c_white);
        draw_set_halign(fa_left);
        draw_text(@spX + 16, @rowY, "Skin:");
        @btnSkClrX = @spX + 150;
        @btnSkClrY = @rowY;
        @btnSkClrW = 56;
        @btnSkClrH = 18;
        draw_set_color(make_color_rgb(140, 50, 50));
        draw_rectangle(@btnSkClrX, @btnSkClrY, @btnSkClrX + @btnSkClrW, @btnSkClrY + @btnSkClrH, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(@btnSkClrX + @btnSkClrW/2, @rowY, "Clear");
        draw_set_halign(fa_left);
        // PREVIEW: dwell 15 frames on a skin row before loading it into the
        // preview slot (row changes reset the dwell and unload the slot), so
        // fast scrolling never thrashes sprite_add.
        @skPvRow = -1;
        if(@kbRow[5] >= 0 && @kbRow[5] < @skinVisCount) @skPvRow = @kbRow[5];
        if(@skPvRow != @skinPrevRow){
            @skinPrevRow = @skPvRow;
            @skinPrevTimer = 0;
            if(@skinPrevLoaded >= 0) @skin_prev_unload();
        }
        if(@skPvRow >= 0 && @skinPrevLoaded != @skPvRow){
            @skinPrevTimer += 1;
            if(@skinPrevTimer >= 15) @skin_prev_load(@skPvRow);
        }
        @pvBX = @spX + 288;
        @pvBY = @contentY + 28;
        @pvBW = 116;
        @pvBH = 150;
        draw_set_color(make_color_rgb(20, 20, 20));
        draw_rectangle(@pvBX, @pvBY, @pvBX + @pvBW, @pvBY + @pvBH, false);
        draw_set_color(make_color_rgb(60, 60, 60));
        draw_rectangle(@pvBX, @pvBY, @pvBX + @pvBW, @pvBY + @pvBH, true);
        if(@skinPrevLoaded >= 0 && @skinPrevSpr[0] >= 0){
            // Absolute per-frame pacing (same semantics as @skin_draw): one
            // strip frame per 100ms tick, no fast-forward on many-frame skins.
            @pvFrames = @skinFrames[@skinPrevLoaded, 0];
            if(@pvFrames < 1) @pvFrames = 1;
            @pvFrame = floor(current_time / 100) mod @pvFrames;
            draw_sprite_ext(@skinPrevSpr[0], @pvFrame, @pvBX + @pvBW/2, @pvBY + 90, 2, 2, 0, c_white, 1);
        }else{
            draw_set_color(make_color_rgb(50, 50, 50));
            draw_set_halign(fa_center);
            draw_text(@pvBX + @pvBW/2, @pvBY + 70, "preview");
            draw_set_halign(fa_left);
        }
        if(@skinPrevLoaded >= 0){
            draw_set_halign(fa_center);
            draw_set_color(c_white);
            @pvName = @skinName[@skinPrevLoaded];
            if(string_length(@pvName) > 14) @pvName = string_copy(@pvName, 1, 14) + "..";
            draw_text(@pvBX + @pvBW/2, @pvBY + @pvBH + 4, @pvName);
            if(@skinMaker[@skinPrevLoaded] != ""){
                draw_set_color(c_gray);
                @pvMaker = @skinMaker[@skinPrevLoaded];
                if(string_length(@pvMaker) > 14) @pvMaker = string_copy(@pvMaker, 1, 14) + "..";
                draw_text(@pvBX + @pvBW/2, @pvBY + @pvBH + 20, @pvMaker);
            }
            if(!@skinHas[@skinPrevLoaded, 0]){
                draw_set_color(make_color_rgb(255, 120, 120));
                @pvWarnY = @pvBY + @pvBH + 20;
                if(@skinMaker[@skinPrevLoaded] != "") @pvWarnY += 16;
                draw_text(@pvBX + @pvBW/2, @pvWarnY, "[!] no idle.png");
            }
            draw_set_halign(fa_left);
        }
    }
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
	draw_text(@btnCX + @btnCW/2, @btnCY + 4, "Close");
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
					@tabClicked = true;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 0){
			@kbFocus = 1;
			@stg_build_rows(@contentY);
			// (the wheel is handled in worldEndStep, once per frame - inside this
			// click branch it only worked while the button was held)
			// same coordinate space as the draw (@stgYOff) - using the table-space
			// hit test here is what made clicks land on the wrong row once scrolled
			@rowHit = @stg_hit_row_view(@mx, @my, @stgYOff);
			if(@rowHit >= 0){
				@kbRow[0] = @rowHit;
				@rowK = @stg_kind_of(@rowHit);
				@rowCX = global.__ONLINE_stgCX[@rowHit];
				@rowCW = global.__ONLINE_stgCW[@rowHit];
				if(@rowK == 3 && @mx >= @rowCX && @mx < @rowCX + 22){
					@stg_act_dir(@rowHit, -1);
				}else if(@rowK == 3 && @mx >= @rowCX + @rowCW - 22 && @mx <= @rowCX + @rowCW){
					@stg_act_dir(@rowHit, 1);
				}else{
					@stg_act(@rowHit);
				}
			}
		}
		if(!@tabClicked && @settingsTab == 1){
			@kbFocus = 1;
			if(@mx >= @btnPFX && @mx <= @btnPFX + @btnPFW && @my >= @btnPFY && @my <= @btnPFY + @btnPFH){
				@saveHistPage = 0;
			}
			if(@mx >= @btnPLX && @mx <= @btnPLX + @btnPLW && @my >= @btnPLY && @my <= @btnPLY + @btnPLH){
				if(@saveHistPage > 0) @saveHistPage -= 1;
			}
			if(@mx >= @btnPRX && @mx <= @btnPRX + @btnPRW && @my >= @btnPRY && @my <= @btnPRY + @btnPRH){
				if(@saveHistPage < @shPages - 1) @saveHistPage += 1;
			}
			if(@mx >= @btnPEX && @mx <= @btnPEX + @btnPEW && @my >= @btnPEY && @my <= @btnPEY + @btnPEH){
				@saveHistPage = @shPages - 1;
			}
			if(@mx >= @btnFltX && @mx <= @btnFltX + @btnFltW && @my >= @btnFltY && @my <= @btnFltY + @btnFltH){
				@saveHistFilter = 1 - @saveHistFilter;
				@saveHistPage = 0;
			}
			if(@mx >= @btnClrX && @mx <= @btnClrX + @btnClrW && @my >= @btnClrY && @my <= @btnClrY + @btnClrH){
				if(@saveHistCount > @saveHistFavCount){
					@saveHistClearFiles = true;
				}
			}
			for(@shVI = @shStart; @shVI < @shEnd; @shVI += 1){
				@shI = @shVisIdx[@shVI];
				@entIdx = @shVI - @shStart;
				@entY = @contentY + 28 + @entIdx * 38;
				@btnFavX = @spX + 10;
				@btnFavY = @entY + 5;
				@btnFavW = 16;
				@btnFavH = 16;
				if(@mx >= @btnFavX && @mx <= @btnFavX + @btnFavW && @my >= @btnFavY && @my <= @btnFavY + @btnFavH){
					if(@saveHistFav[@shI]){
						@saveHistFav[@shI] = 0;
						@saveHistFavCount -= 1;
					}else{
						if(@saveHistFavCount < @saveHistFavMax){
							@saveHistFav[@shI] = 1;
							@saveHistFavCount += 1;
						}
					}
					@shMutation += 1;
					if(!@saveHistDirty){
						@saveHistDirtyTimer = room_speed * 3;
					}
					@saveHistDirty = true;
				}
				@btnApX = @spX + @colW - 62;
				@btnApY = @entY + 5;
				@btnApW = 50;
				@btnApH = 18;
				if(@mx >= @btnApX && @mx <= @btnApX + @btnApW && @my >= @btnApY && @my <= @btnApY + @btnApH){
					@saveHistApply = @shI;
					@settingsOpen = false;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 2){
			@kbFocus = 1;
			for(@sI = 1; @sI <= 5; @sI += 1){
				@sX = @starX + (@sI - 1) * @starW;
				if(@mx >= @sX && @mx <= @sX + @starW - 2 && @my >= @starY && @my <= @starY + @starH){
					if(@rStars == @sI){
						@rStars = 0;
					}else{
						@rStars = @sI;
					}
				}
			}
			if(@mx >= @btnClrRX && @mx <= @btnClrRX + @btnClrRW && @my >= @btnClrRY && @my <= @btnClrRY + @btnClrRH){
				if(@rCleared){
					@rCleared = 0;
					@rClearWarn = 0;
				}else{
					@rCleared = 1;
					@rClearWarn = 0;
				}
			}
			if(!@ratingSubmitting && @ratingCooldown <= current_time && @rStars >= 1){
				if(@mx >= @btnSubX && @mx <= @btnSubX + @btnSubW && @my >= @btnSubY && @my <= @btnSubY + @btnSubH){
					@ratingSubmit = true;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 3){
			@kbFocus = 1;
			for(@kI = 0; @kI < 11; @kI += 1){
				@kbY = @rowY + @kI * 28;
				@btnKX = @spX + 140;
				@btnKY = @kbY - 2;
				@btnKW = 120;
				@btnKH = 20;
				if(@mx >= @btnKX && @mx <= @btnKX + @btnKW && @my >= @btnKY && @my <= @btnKY + @btnKH){
					if(@keybindEditing == @kI){
						@keybindEditing = -1;
					}else{
						@keybindEditing = @kI;
						@keybindArmTimer = 0;
					}
				}
			}
			if(@mx >= @btnRstX && @mx <= @btnRstX + @btnRstW && @my >= @btnRstY && @my <= @btnRstY + @btnRstH){
				@keyVis = 86;
				@keySave = 84;
				@keySpectate = 89;
				@keyChatLog = 85;
				@keyArrows = 73;
				@keySettings = 79;
				@keyPlayerList = 76;
				@keyChat = 32;
				@keyPing = 72;
				@keyFastLoad = 70;
				@keyCanvas = 78;
				@keybindEditing = -1;
				@keybindSave = true;
			}
		}
		if(!@tabClicked && @settingsTab == 4){
			@kbFocus = 1;
			if(@mx >= @btnSyncX && @mx <= @btnSyncX + @btnSyncW && @my >= @btnSyncY && @my <= @btnSyncY + @btnSyncH){
				@syncEnabled = !@syncEnabled;
				@syncEnabledChanged = true;
			}
		}
        if(!@tabClicked && @settingsTab == 5){
            @kbFocus = 1;
            if(@mx >= @btnSkPFX && @mx <= @btnSkPFX + @btnSkPFW && @my >= @btnSkPFY && @my <= @btnSkPFY + @btnSkPFH){
                @skinPage = 0;
            }
            if(@mx >= @btnSkPLX && @mx <= @btnSkPLX + @btnSkPLW && @my >= @btnSkPLY && @my <= @btnSkPLY + @btnSkPLH){
                if(@skinPage > 0) @skinPage -= 1;
            }
            if(@mx >= @btnSkPRX && @mx <= @btnSkPRX + @btnSkPRW && @my >= @btnSkPRY && @my <= @btnSkPRY + @btnSkPRH){
                if(@skinPage < @skPages - 1) @skinPage += 1;
            }
            if(@mx >= @btnSkPEX && @mx <= @btnSkPEX + @btnSkPEW && @my >= @btnSkPEY && @my <= @btnSkPEY + @btnSkPEH){
                @skinPage = @skPages - 1;
            }
            for(@skVI = @skStart; @skVI < @skEnd; @skVI += 1){
                @entY = @contentY + 28 + (@skVI - @skStart) * 22;
                if(@mx >= @spX + 8 && @mx <= @spX + 268 && @my >= @entY - 3 && @my <= @entY + 17){
                    @kbRow[5] = @skVI;
                    @skin_select(@skVI);
                }
            }
            if(@mx >= @btnSkAdLX && @mx <= @btnSkAdLX + @btnSkAdLW && @my >= @btnSkAdLY && @my <= @btnSkAdLY + @btnSkAdLH){
                @skinAutoDL = 1 - @skinAutoDL;
                @skinAutoDLChanged = true;
                @kbRow[5] = @skinVisCount;
            }
            if(@mx >= @btnSkAdRX && @mx <= @btnSkAdRX + @btnSkAdRW && @my >= @btnSkAdRY && @my <= @btnSkAdRY + @btnSkAdRH){
                @skinAutoDL = 1 - @skinAutoDL;
                @skinAutoDLChanged = true;
                @kbRow[5] = @skinVisCount;
            }
            if(@mx >= @btnSkClrX && @mx <= @btnSkClrX + @btnSkClrW && @my >= @btnSkClrY && @my <= @btnSkClrY + @btnSkClrH){
                @skin_clear();
                @kbRow[5] = @skinVisCount + 1;
            }
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
			draw_text(@barX + @barW / 2, @barY + @barH / 2, "Exiting...");
		}else{
			draw_text(@barX + @barW / 2, @barY + @barH / 2, "Spectating...");
		}
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
			draw_set_color(c_gray);
			draw_text(@hudX + @hudW/2 - string_width("  SPECTATING: " + @specTargetName + "  ")/2 - 8, @hudY + 4, "<");
			draw_text(@hudX + @hudW/2 + string_width("  SPECTATING: " + @specTargetName + "  ")/2 + 8, @hudY + 4, ">");
			draw_set_color(make_color_rgb(255, 220, 80));
			draw_text(@hudX + @hudW/2, @hudY + 4, @specTargetName);
			draw_set_halign(fa_right);
			draw_set_color(c_gray);
			draw_text(@hudX + @hudW - 6, @hudY + 4, string(@specTargetIdx + 1) + "/" + string(@specCount));
		}else{
			draw_set_color(c_gray);
			draw_text(@hudX + @hudW/2, @hudY + 4, "No players");
		}
		draw_set_halign(fa_right);
		draw_set_valign(fa_bottom);
		draw_set_alpha(0.5);
		draw_set_color(c_white);
		if(@specCamMode == 1){
			draw_text(@hudX + @hudW - 6, @hudY + @hudH - 4, "[Screen]");
		}else{
			draw_text(@hudX + @hudW - 6, @hudY + @hudH - 4, "[Follow]");
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
	draw_text(@pkX + 8, @pkY + 4, "Player objects:  L = add/remove");
	draw_text(@pkX + 8, @pkY + 22, "R = add first,  C = clear all");
	draw_text(@pkX + 8, @pkY + 40, "Enter = done");
	@pkYY = @pkY + 58;
	for(@pkI = 0; @pkI < ds_list_size(@obj_list); @pkI += 1){
		@pkObj = ds_list_find_value(@obj_list, @pkI);
		@pkTxt = object_get_name(@pkObj);
		if(@pkObj == @get_active_player()){
			@pkTxt += " (active)";
		}
		if(instance_exists(@pkObj)){
			@pkInst = instance_find(@pkObj, 0);
			@pkTxt += "  (" + string(@pkInst.x) + ", " + string(@pkInst.y) + ")";
		}else{
			@pkTxt += "  [no instance]";
		}
		draw_set_color(c_white);
		draw_text(@pkX + 16, @pkYY, @pkTxt);
		@pkYY += 18;
	}
	@pkTgt = instance_position(mouse_x, mouse_y, all);
	if(@pkTgt != noone){
		draw_set_color(c_yellow);
		if(ds_list_find_index(@obj_list, @pkTgt.object_index) >= 0){
			draw_text(@pkX + 8, @pkYY, "> " + object_get_name(@pkTgt.object_index) + ": L = remove");
		}else{
			draw_text(@pkX + 8, @pkYY, "> " + object_get_name(@pkTgt.object_index) + ": L = add, R = add first");
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
