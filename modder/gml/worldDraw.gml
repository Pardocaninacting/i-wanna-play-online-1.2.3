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
		@pOuterAlpha = 0;
		@pOuterR = 0;
		if(@pAge < @noteToastMs){
			@pT = @pAge / @noteToastMs;
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
			@pAge = @noteToastMs;
		}
		@pX = round(@noteX[@i]);
		@pY = round(@noteY[@i]);
		if(!@spectating && @pExists){
			@pA *= min(1, point_distance(@X, @Y, @pX, @pY) / 100);
		}
		if(@pA < 0) @pA = 0;
		if(@pA <= 0) continue;
		@pNT = @noteTeamArr[@i];
		if(@pNT < 0 || @pNT > 7) @pNT = 0;
		@pNC = @teamColors[@pNT];
		draw_set_alpha(@pA);
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
	// anchor crosshair while the wheel/palette is active (所见即所发: the
	// note lands here even when the wheel itself is edge-clamped away)
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
				// N/E/S edges = tools that land in N2/N3 (drawn disabled)
				@cellIcon = -1;
				if(@cellIdx == 0) @cellIcon = 8;
				if(@cellIdx == 2) @cellIcon = 0;
				if(@cellIdx == 6) @cellIcon = 9;
				if(@cellIdx == 8) @cellIcon = 2;
				if(@cellIdx == 4) @cellIcon = @noteLastIcon;
				@cellDisabled = 0;
				if(@cellIdx == 1 || @cellIdx == 5 || @cellIdx == 7) @cellDisabled = 1;
				draw_set_alpha(0.22);
				draw_set_color(c_black);
				draw_circle(@cx, @cy, 14, false);
				if(@cellIdx == @noteWheelHover){
					draw_set_alpha(0.62);
					if(@cellDisabled) draw_set_alpha(0.22);
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
					// arrow tool (N2)
					draw_set_alpha(0.25);
					draw_set_color(c_gray);
					draw_line_width(@cx - 5, @cy + 5, @cx + 3, @cy - 3, 2);
					draw_triangle(@cx + 1, @cy - 7, @cx + 7, @cy - 1, @cx + 6, @cy - 6, false);
				}else if(@cellIdx == 5){
					// brush tool (N3)
					draw_set_alpha(0.25);
					draw_set_color(c_gray);
					draw_line_width(@cx - 5, @cy + 5, @cx + 3, @cy - 3, 3);
					draw_triangle(@cx + 2, @cy - 2, @cx + 7, @cy - 7, @cx + 6, @cy - 1, false);
				}else if(@cellIdx == 7){
					// text tool (N2)
					draw_set_alpha(0.25);
					draw_set_color(c_gray);
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
	// icon palette (mode 3): modal 3x3 grid, page 1 = the legacy 9-icon
	// layout (cell index == icon id, muscle memory preserved)
	if(@noteMode == 3){
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
				draw_set_alpha(0.22);
				draw_set_color(c_black);
				draw_circle(@cx, @cy, 14, false);
				if(@cellIdx == @notePaletteHover){
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
				@note_draw_icon(@cellIdx, @cx, @cy, 0.8, 1, current_time);
				if(@cellIdx == @notePaletteLast){
					draw_set_alpha(1);
					draw_set_color(@teamColors[@wTeam]);
					draw_circle(@cx, @cy + 18, 2, false);
				}
			}
		}
	}
	draw_set_alpha(@pdAlpha);
	draw_set_color(@pdColor);
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	if(font_exists(0)){
		draw_set_font(0);
	}
}
