/// ONLINE
if(@chatLogOpen){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@clLeft = 8;
	@clBottom = -40;
	if(view_enabled && view_visible[0]){
		@clLeft += view_xview[0];
		@clBottom += view_yview[0] + view_hview[0];
	}else{
		@clBottom += room_height;
	}
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
	@plX = -10;
	@plY = 10;
	if(view_enabled && view_visible[0]){
		@plX += view_xview[0] + view_wview[0];
		@plY += view_yview[0];
	}else{
		@plX += room_width;
	}
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
		if(@plObj.@oRoom == room){
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
// SETTINGS PANEL
if(@settingsOpen){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@spW = 340;
	@spH = 400;
	@spX = 0;
	@spY = 0;
	if(view_enabled && view_visible[0]){
		@spX = view_xview[0] + floor((view_wview[0] - @spW) / 2);
		@spY = view_yview[0] + floor((view_hview[0] - @spH) / 2);
	}else{
		@spX = floor((room_width - @spW) / 2);
		@spY = floor((room_height - @spH) / 2);
	}
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
	draw_set_alpha(0.88);
	draw_set_color(c_black);
	draw_rectangle(@spX, @spY, @spX + @spW, @spY + @spH, false);
	draw_set_alpha(1);
	draw_set_color(c_white);
	draw_rectangle(@spX, @spY, @spX + @spW, @spY + @spH, true);
	@tabCount = 4;
	@tabW = floor(@spW / @tabCount);
	@tabH = 22;
	@tabY = @spY;
	@tabNames[0] = "Settings";
	@tabNames[1] = "Saves(" + string(@saveHistCount) + ")";
	@tabNames[2] = "Rating";
	@tabNames[3] = "Keys";
	for(@tI = 0; @tI < @tabCount; @tI += 1){
		@tX1 = @spX + @tI * @tabW;
		@tX2 = @tX1 + @tabW;
		if(@tI == @tabCount - 1) @tX2 = @spX + @spW;
		if(@settingsTab == @tI){
			draw_set_color(make_color_rgb(50, 50, 50));
		}else{
			draw_set_color(make_color_rgb(25, 25, 25));
		}
		draw_rectangle(@tX1, @tabY, @tX2, @tabY + @tabH, false);
		draw_set_color(c_white);
		draw_rectangle(@tX1, @tabY, @tX2, @tabY + @tabH, true);
		draw_set_halign(fa_center);
		if(@settingsTab == @tI){
			draw_set_color(c_yellow);
		}else{
			draw_set_color(c_gray);
		}
		draw_text(floor((@tX1 + @tX2) / 2), @tabY + 3, @tabNames[@tI]);
	}
	@contentY = @tabY + @tabH + 6;
	draw_set_halign(fa_left);
	// TAB 0: SETTINGS
	if(@settingsTab == 0){
		@rowY = @contentY + 4;
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Team:");
		@btnLX = @spX + 100;
		@btnLY = @rowY - 2;
		@btnLW = 20;
		@btnLH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnLX, @btnLY, @btnLX + @btnLW, @btnLY + @btnLH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnLX + @btnLW/2, @rowY, "<");
		@teamNames[0] = "None";
		@teamNames[1] = "Red";
		@teamNames[2] = "Blue";
		@teamNames[3] = "Yellow";
		@teamNames[4] = "Purple";
		@teamNames[5] = "Green";
		@teamNames[6] = "Orange";
		@teamNames[7] = "Cyan";
		draw_set_color(@teamColors[@team]);
		draw_text(@spX + 200, @rowY, string(@team) + " " + @teamNames[@team]);
		@btnRX = @spX + 280;
		@btnRY = @rowY - 2;
		@btnRW = 20;
		@btnRH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnRX, @btnRY, @btnRX + @btnRW, @btnRY + @btnRH, false);
		draw_set_color(c_white);
		draw_text(@btnRX + @btnRW/2, @rowY, ">");
		@rowY = @contentY + 32;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Lerp:");
		@btnLerpX = @spX + 100;
		@btnLerpY = @rowY - 2;
		@btnLerpW = 40;
		@btnLerpH = 18;
		if(@lerpEnabled){
			draw_set_color(make_color_rgb(40, 160, 40));
		}else{
			draw_set_color(c_gray);
		}
		draw_rectangle(@btnLerpX, @btnLerpY, @btnLerpX + @btnLerpW, @btnLerpY + @btnLerpH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@lerpEnabled){
			draw_text(@btnLerpX + @btnLerpW/2, @rowY, "ON");
		}else{
			draw_text(@btnLerpX + @btnLerpW/2, @rowY, "OFF");
		}
		@rowY = @contentY + 60;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Save:");
		@btnSaveX = @spX + 100;
		@btnSaveY = @rowY - 2;
		@btnSaveW = 40;
		@btnSaveH = 18;
		if(@save_enabled){
			draw_set_color(make_color_rgb(40, 160, 40));
		}else{
			draw_set_color(c_gray);
		}
		draw_rectangle(@btnSaveX, @btnSaveY, @btnSaveX + @btnSaveW, @btnSaveY + @btnSaveH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@save_enabled){
			draw_text(@btnSaveX + @btnSaveW/2, @rowY, "ON");
		}else{
			draw_text(@btnSaveX + @btnSaveW/2, @rowY, "OFF");
		}
		@rowY = @contentY + 88;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Visual:");
		@btnVLX = @spX + 100;
		@btnVLY = @rowY - 2;
		@btnVLW = 20;
		@btnVLH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnVLX, @btnVLY, @btnVLX + @btnVLW, @btnVLY + @btnVLH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnVLX + @btnVLW/2, @rowY, "<");
		@visNames[0] = "All";
		@visNames[1] = "No Names";
		@visNames[2] = "Hidden";
		draw_set_color(c_white);
		draw_text(@spX + 200, @rowY, @visNames[@vis]);
		@btnVRX = @spX + 280;
		@btnVRY = @rowY - 2;
		@btnVRW = 20;
		@btnVRH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnVRX, @btnVRY, @btnVRX + @btnVRW, @btnVRY + @btnVRH, false);
		draw_set_color(c_white);
		draw_text(@btnVRX + @btnVRW/2, @rowY, ">");
		@rowY = @contentY + 116;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Indicator:");
		@btnIndX = @spX + 100;
		@btnIndY = @rowY - 2;
		@btnIndW = 40;
		@btnIndH = 18;
		if(@showArrows){
			draw_set_color(make_color_rgb(40, 160, 40));
		}else{
			draw_set_color(c_gray);
		}
		draw_rectangle(@btnIndX, @btnIndY, @btnIndX + @btnIndW, @btnIndY + @btnIndH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		if(@showArrows){
			draw_text(@btnIndX + @btnIndW/2, @rowY, "ON");
		}else{
			draw_text(@btnIndX + @btnIndW/2, @rowY, "OFF");
		}
		@rowY = @contentY + 144;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Spec Cam:");
		@btnCamLX = @spX + 100;
		@btnCamLY = @rowY - 2;
		@btnCamLW = 20;
		@btnCamLH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnCamLX, @btnCamLY, @btnCamLX + @btnCamLW, @btnCamLY + @btnCamLH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnCamLX + @btnCamLW/2, @rowY, "<");
		@camModeNames[0] = "Follow";
		@camModeNames[1] = "Screen";
		draw_set_color(c_white);
		draw_text(@spX + 200, @rowY, @camModeNames[@specCamMode]);
		@btnCamRX = @spX + 280;
		@btnCamRY = @rowY - 2;
		@btnCamRW = 20;
		@btnCamRH = 18;
		draw_set_color(c_gray);
		draw_rectangle(@btnCamRX, @btnCamRY, @btnCamRX + @btnCamRW, @btnCamRY + @btnCamRH, false);
		draw_set_color(c_white);
		draw_text(@btnCamRX + @btnCamRW/2, @rowY, ">");
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
		@btnClrX = @spX + @spW - 72;
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
			@entY = @contentY + 26 + @entIdx * 38;
			draw_set_color(make_color_rgb(30, 30, 30));
			draw_rectangle(@spX + 8, @entY - 2, @spX + @spW - 8, @entY + 26, false);
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
			draw_set_halign(fa_left);
			@shDispName = @saveHistName[@shI];
			#if GM80
			@shDispName = __ONLINE_gbk_trunc(@shDispName, 10, "..");
			#endif
			#if CJKTEXT
			@shDispName = __ONLINE_gbk_trunc(@shDispName, 10, "..");
			#endif
			#if not GM80
			#if not CJKTEXT
			if(string_length(@shDispName) > 10) @shDispName = string_copy(@shDispName, 1, 10) + "..";
			#endif
			#endif
			draw_set_color(c_lime);
			#if GM80
			fw_draw_set_halign(fa_left);
			fw_draw_set_valign(fa_top);
			__ONLINE_fw_use_font(@shDispName);
			fw_draw_text_ext(@spX + 30, @entY, @shDispName, 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 0;
			global.__ONLINE_cjkValign = 0;
			__ONLINE_cjk_draw_text(@spX + 30, @entY, @shDispName, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@spX + 30, @entY, @shDispName);
			#endif
			#endif
			@shDispRoom = @saveHistRoomName[@shI];
			if(string_length(@shDispRoom) > 12) @shDispRoom = string_copy(@shDispRoom, 1, 12) + "..";
			draw_set_color(c_aqua);
			draw_text(@spX + 130, @entY, @shDispRoom);
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
			draw_text(@spX + 240, @entY, @shTimeDisp);
			draw_set_color(make_color_rgb(160, 160, 160));
			draw_text(@spX + 30, @entY + 13, "x:" + string(@saveHistX[@shI]) + " y:" + string(round(@saveHistY[@shI])));
			@btnApX = @spX + @spW - 62;
			@btnApY = @entY + 6;
			@btnApW = 50;
			@btnApH = 18;
			draw_set_color(make_color_rgb(40, 100, 160));
			draw_rectangle(@btnApX, @btnApY, @btnApX + @btnApW, @btnApY + @btnApH, false);
			draw_set_color(c_white);
			draw_set_halign(fa_center);
			draw_text(@btnApX + @btnApW/2, @entY + 7, "Apply");
			draw_set_halign(fa_left);
		}
		if(@shVisCount == 0){
			draw_set_color(c_gray);
			draw_set_halign(fa_center);
			if(@saveHistFilter && @saveHistCount > 0){
				draw_text(@spX + @spW/2, @contentY + 120, "No favorites");
			}else{
				draw_text(@spX + @spW/2, @contentY + 120, "No saves yet");
			}
			draw_set_halign(fa_left);
		}
	}
	// TAB 2: RATING
	if(@settingsTab == 2){
		@rowY = @contentY + 4;
		draw_set_halign(fa_left);
		draw_set_color(c_white);
		draw_text(@spX + 16, @rowY, "Game: " + @gameName);
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
		@btnSubX = @spX + @spW/2 - 55;
		@btnSubY = @rowY - 2;
		@btnSubW = 110;
		@btnSubH = 22;
		if(@ratingSubmitting){
			draw_set_color(make_color_rgb(60, 60, 60));
		}else if(@ratingCooldown > 0){
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
		}else if(@ratingCooldown > 0){
			draw_text(@btnSubX + @btnSubW/2, @rowY, "Wait " + string(ceil(@ratingCooldown / 30)) + "s");
		}else{
			draw_text(@btnSubX + @btnSubW/2, @rowY, "Submit Rating");
		}
		if(@ratingResultTimer > 0){
			@rowY += 30;
			if(@ratingResult == 1){
				draw_set_color(c_lime);
				draw_text(@spX + @spW/2, @rowY, "Rating submitted!");
			}else if(@ratingResult == 2){
				draw_set_color(c_yellow);
				draw_text(@spX + @spW/2, @rowY, "Submit failed (cooldown)");
			}
		}
		draw_set_halign(fa_left);
	}
	// TAB 3: KEYS
	if(@settingsTab == 3){
		@rowY = @contentY + 4;
		draw_set_halign(fa_left);
		@kbLabels[0] = "Visibility";
		@kbLabels[1] = "Toggle Save";
		@kbLabels[2] = "Spectate";
		@kbLabels[3] = "Chat Log";
		@kbLabels[4] = "Indicator";
		@kbLabels[5] = "Options";
		@kbLabels[6] = "Player List";
		@kbLabels[7] = "Chat";
		@kbKeys[0] = @keyVis;
		@kbKeys[1] = @keySave;
		@kbKeys[2] = @keySpectate;
		@kbKeys[3] = @keyChatLog;
		@kbKeys[4] = @keyArrows;
		@kbKeys[5] = @keySettings;
		@kbKeys[6] = @keyPlayerList;
		@kbKeys[7] = @keyChat;
		for(@kI = 0; @kI < 8; @kI += 1){
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
		@btnRstX = @spX + @spW/2 - 55;
		@btnRstY = @rowY + 8 * 28 + 10;
		@btnRstW = 110;
		@btnRstH = 22;
		draw_set_color(make_color_rgb(100, 50, 50));
		draw_rectangle(@btnRstX, @btnRstY, @btnRstX + @btnRstW, @btnRstY + @btnRstH, false);
		draw_set_color(c_white);
		draw_set_halign(fa_center);
		draw_text(@btnRstX + @btnRstW/2, @btnRstY + 2, "Reset Keys");
		draw_set_halign(fa_left);
	}
	@btnCX = @spX + @spW/2 - 35;
	@btnCY = @spY + @spH - 28;
	@btnCW = 70;
	@btnCH = 22;
	draw_set_color(c_gray);
	draw_rectangle(@btnCX, @btnCY, @btnCX + @btnCW, @btnCY + @btnCH, false);
	draw_set_color(c_white);
	draw_set_halign(fa_center);
	draw_text(@btnCX + @btnCW/2, @btnCY + 2, "Close");
	@mx = mouse_x;
	@my = mouse_y;
	if(mouse_check_button_pressed(mb_left)){
		@tabClicked = false;
		if(@my >= @tabY && @my <= @tabY + @tabH){
			for(@tI = 0; @tI < @tabCount; @tI += 1){
				@tX1 = @spX + @tI * @tabW;
				@tX2 = @tX1 + @tabW;
				if(@tI == @tabCount - 1) @tX2 = @spX + @spW;
				if(@mx >= @tX1 && @mx <= @tX2){
					@settingsTab = @tI;
					@keybindEditing = -1;
					@tabClicked = true;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 0){
			if(@mx >= @btnLX && @mx <= @btnLX + @btnLW && @my >= @btnLY && @my <= @btnLY + @btnLH){
				@team -= 1;
				if(@team < 0) @team = 7;
				@teamChanged = true;
			}
			if(@mx >= @btnRX && @mx <= @btnRX + @btnRW && @my >= @btnRY && @my <= @btnRY + @btnRH){
				@team += 1;
				if(@team > 7) @team = 0;
				@teamChanged = true;
			}
			if(@mx >= @btnLerpX && @mx <= @btnLerpX + @btnLerpW && @my >= @btnLerpY && @my <= @btnLerpY + @btnLerpH){
				@lerpEnabled = !@lerpEnabled;
				@lerpChanged = true;
			}
			if(@mx >= @btnSaveX && @mx <= @btnSaveX + @btnSaveW && @my >= @btnSaveY && @my <= @btnSaveY + @btnSaveH){
				@save_enabled = 1 - @save_enabled;
				@saveChanged = true;
			}
			if(@mx >= @btnVLX && @mx <= @btnVLX + @btnVLW && @my >= @btnVLY && @my <= @btnVLY + @btnVLH){
				@vis -= 1;
				if(@vis < 0) @vis = 2;
				@visChanged = true;
			}
			if(@mx >= @btnVRX && @mx <= @btnVRX + @btnVRW && @my >= @btnVRY && @my <= @btnVRY + @btnVRH){
				@vis += 1;
				if(@vis > 2) @vis = 0;
				@visChanged = true;
			}
			if(@mx >= @btnIndX && @mx <= @btnIndX + @btnIndW && @my >= @btnIndY && @my <= @btnIndY + @btnIndH){
				@showArrows = !@showArrows;
				#if GMS2
					@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
				#endif
				#if not GMS2
					@a = instance_create(0, 0, @playerSaved);
				#endif
				if(@showArrows){
					@a.@name = "Indicator: on";
				}else{
					@a.@name = "Indicator: off";
				}
				@a.@state = -2;
			}
			if(@mx >= @btnCamLX && @mx <= @btnCamLX + @btnCamLW && @my >= @btnCamLY && @my <= @btnCamLY + @btnCamLH){
				@specCamMode = 1 - @specCamMode;
				#if GMS2
					@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
				#endif
				#if not GMS2
					@a = instance_create(0, 0, @playerSaved);
				#endif
				if(@specCamMode == 0){
					@a.@name = "Cam: Follow";
				}else{
					@a.@name = "Cam: Screen";
				}
				@a.@state = -2;
			}
			if(@mx >= @btnCamRX && @mx <= @btnCamRX + @btnCamRW && @my >= @btnCamRY && @my <= @btnCamRY + @btnCamRH){
				@specCamMode = 1 - @specCamMode;
				#if GMS2
					@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
				#endif
				#if not GMS2
					@a = instance_create(0, 0, @playerSaved);
				#endif
				if(@specCamMode == 0){
					@a.@name = "Cam: Follow";
				}else{
					@a.@name = "Cam: Screen";
				}
				@a.@state = -2;
			}
		}
		if(!@tabClicked && @settingsTab == 1){
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
				@entY = @contentY + 26 + @entIdx * 38;
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
					if(!@saveHistDirty){
						@saveHistDirtyTimer = room_speed * 3;
					}
					@saveHistDirty = true;
				}
				@btnApX = @spX + @spW - 62;
				@btnApY = @entY + 6;
				@btnApW = 50;
				@btnApH = 18;
				if(@mx >= @btnApX && @mx <= @btnApX + @btnApW && @my >= @btnApY && @my <= @btnApY + @btnApH){
					@saveHistApply = @shI;
					@settingsOpen = false;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 2){
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
					if(!variable_global_exists("clear") || !variable_global_get("clear")){
						@rClearWarn = room_speed * 5;
					}
				}
			}
			if(!@ratingSubmitting && @ratingCooldown <= 0 && @rStars >= 1){
				if(@mx >= @btnSubX && @mx <= @btnSubX + @btnSubW && @my >= @btnSubY && @my <= @btnSubY + @btnSubH){
					@ratingSubmit = true;
				}
			}
		}
		if(!@tabClicked && @settingsTab == 3){
			for(@kI = 0; @kI < 8; @kI += 1){
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
				@keybindEditing = -1;
				@keybindSave = true;
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
	@hudW = 0;
	@hudH = 0;
	if(view_enabled && view_visible[0]){
		@hudX = view_xview[0];
		@hudY = view_yview[0];
		@hudW = view_wview[0];
		@hudH = view_hview[0];
	}else{
		@hudW = room_width;
		@hudH = room_height;
	}
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
// OFF-SCREEN ARROWS
if(@showArrows || @spectating){
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@arVX = 0;
	@arVY = 0;
	@arVW = room_width;
	@arVH = room_height;
	if(view_enabled && view_visible[0]){
		@arVX = view_xview[0];
		@arVY = view_yview[0];
		@arVW = view_wview[0];
		@arVH = view_hview[0];
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
	#if GM80
	fw_draw_set_halign(fa_left);
	fw_draw_set_valign(fa_top);
	#endif
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
