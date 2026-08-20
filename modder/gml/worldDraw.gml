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
	@pdSelfOnly = false;
	if(@vis != 0) @pdSelfOnly = true;
	for(@i = 0; @i < @pingMax; @i += 1){
		@pAge = current_time - @pingT[@i];
		if(@pAge < 0 || @pAge >= @pingLifeMs) continue;
		if(@pdSelfOnly && @pingSenderIDArr[@i] != @selfID) continue;
		@pT = @pAge / @pingLifeMs;
		@pOuterAlpha = 0;
		@pOuterR = 0;
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
		@pX = round(@pingX[@i]);
		@pY = round(@pingY[@i]);
		if(!@spectating && @pExists){
			@pA *= min(1, point_distance(@X, @Y, @pX, @pY) / 100);
		}
		if(@pA < 0) @pA = 0;
		if(@pA <= 0) continue;
		@pType = @pingType[@i];
		if(@pType < 0 || @pType > 8) @pType = 4;
		@pNT = @pingTeamArr[@i];
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
		if(@pType == 0){
			@pQBob = round(sin(@pAge * 0.010) * @pScale);
			@pQR = 8 * @pScale + sin(@pAge * 0.008) * 1.2 * @pScale;
			draw_set_color(make_color_rgb(88, 118, 150));
			draw_circle(@pX, @pY, @pQR, true);
			draw_set_color(c_black);
			draw_text(@pX - 1, @pY + @pQBob, "?");
			draw_text(@pX + 1, @pY + @pQBob, "?");
			draw_text(@pX, @pY - 1 + @pQBob, "?");
			draw_text(@pX, @pY + 1 + @pQBob, "?");
			draw_set_color(c_white);
			draw_text(@pX, @pY + @pQBob, "?");
		}
		if(@pType == 1 || @pType == 3 || @pType == 5 || @pType == 7){
			@pArrowLen = (6 + sin(@pAge * 0.014) * 1.5) * @pScale;
			@pArrowTail = 2 * @pScale;
			draw_set_color(c_white);
			if(@pType == 1){
				draw_triangle(@pX - 5 * @pScale, @pY, @pX + 5 * @pScale, @pY, @pX, @pY - @pArrowLen, false);
				draw_rectangle(@pX - @pArrowTail, @pY, @pX + @pArrowTail, @pY + @pArrowLen, false);
			}
			if(@pType == 3){
				draw_triangle(@pX, @pY - 5 * @pScale, @pX, @pY + 5 * @pScale, @pX - @pArrowLen, @pY, false);
				draw_rectangle(@pX, @pY - @pArrowTail, @pX + @pArrowLen, @pY + @pArrowTail, false);
			}
			if(@pType == 5){
				draw_triangle(@pX, @pY - 5 * @pScale, @pX, @pY + 5 * @pScale, @pX + @pArrowLen, @pY, false);
				draw_rectangle(@pX - @pArrowLen, @pY - @pArrowTail, @pX, @pY + @pArrowTail, false);
			}
			if(@pType == 7){
				draw_triangle(@pX - 5 * @pScale, @pY, @pX + 5 * @pScale, @pY, @pX, @pY + @pArrowLen, false);
				draw_rectangle(@pX - @pArrowTail, @pY - @pArrowLen, @pX + @pArrowTail, @pY, false);
			}
		}
		if(@pType == 2){
			@pSafeR = (8 + sin(@pAge * 0.010) * 1.3) * @pScale;
			draw_set_alpha(@pA * 0.24);
			draw_set_color(make_color_rgb(74, 222, 128));
			draw_circle(@pX, @pY, @pSafeR, false);
			draw_set_alpha(@pA);
			draw_circle(@pX, @pY, 8 * @pScale, true);
			draw_set_color(c_black);
			draw_line_width(@pX - 5 * @pScale, @pY + 1 * @pScale, @pX - 1 * @pScale, @pY + 5 * @pScale, 3);
			draw_line_width(@pX - 1 * @pScale, @pY + 5 * @pScale, @pX + 6 * @pScale, @pY - 4 * @pScale, 3);
			draw_set_color(c_white);
			draw_line_width(@pX - 5 * @pScale, @pY, @pX - 1 * @pScale, @pY + 4 * @pScale, 2);
			draw_line_width(@pX - 1 * @pScale, @pY + 4 * @pScale, @pX + 6 * @pScale, @pY - 5 * @pScale, 2);
		}
		if(@pType == 4){
			@pInner = 3 * @pScale;
			if(@pT >= 0.053 && @pT < 0.833 && ((@pAge div 200) mod 2) == 0) @pInner = 5 * @pScale;
			draw_set_color(c_white);
			draw_circle(@pX, @pY, 7 * @pScale, true);
			draw_circle(@pX, @pY, @pInner, true);
			draw_line_width(@pX - 11 * @pScale, @pY, @pX - 6 * @pScale, @pY, 2);
			draw_line_width(@pX + 6 * @pScale, @pY, @pX + 11 * @pScale, @pY, 2);
			draw_line_width(@pX, @pY - 11 * @pScale, @pX, @pY - 6 * @pScale, 2);
			draw_line_width(@pX, @pY + 6 * @pScale, @pX, @pY + 11 * @pScale, 2);
			draw_circle(@pX, @pY, 1, false);
		}
		if(@pType == 6){
			@pWaitR = 8 * @pScale + sin(@pAge * 0.008) * 0.8 * @pScale;
			@pWaitH = 6 * @pScale + sin(@pAge * 0.010) * 1.0 * @pScale;
			@pWaitGap = 4 * @pScale + sin(@pAge * 0.008) * 0.7 * @pScale;
			draw_set_color(make_color_rgb(88, 106, 122));
			draw_circle(@pX, @pY, @pWaitR, true);
			draw_set_color(c_white);
			draw_rectangle(@pX - @pWaitGap - 2, @pY - @pWaitH, @pX - @pWaitGap + 2, @pY + @pWaitH, false);
			draw_rectangle(@pX + @pWaitGap - 2, @pY - @pWaitH, @pX + @pWaitGap + 2, @pY + @pWaitH, false);
		}
		if(@pType == 8){
			@pWarnCol = make_color_rgb(250, 204, 21);
			if(@pT >= 0.053 && @pT < 0.833 && ((@pAge div 100) mod 2) == 0) @pWarnCol = make_color_rgb(251, 191, 36);
			draw_set_color(@pWarnCol);
			draw_triangle(@pX - 10 * @pScale, @pY + 8 * @pScale, @pX + 10 * @pScale, @pY + 8 * @pScale, @pX, @pY - 10 * @pScale, false);
			draw_set_color(c_black);
			draw_text(@pX, @pY + 1 * @pScale, "!");
		}
		draw_set_alpha(@pA);
		if(@pingName[@i] != ""){
			@pNameDrawX = @pX;
			@pNameDrawY = @pY - 22;
			#if CJKTEXT
			@pNameDrawW = __ONLINE_cjk_string_width_ext(@pingName[@i], -1, 9999);
			@pNameDrawH = __ONLINE_cjk_string_height_ext(@pingName[@i], -1, 9999);
			@pNameDrawX = round(@pX - @pNameDrawW * 0.5);
			@pNameDrawY = round((@pY - 22) - @pNameDrawH * 0.5);
			#endif
			#if not GM80
			#if not CJKTEXT
			@pNameDrawW = string_width(@pingName[@i]);
			@pNameDrawH = string_height(@pingName[@i]);
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
			__ONLINE_fw_use_font(@pingName[@i]);
			fw_draw_text_ext(@pX - 1, @pY - 22, @pingName[@i], 9999);
			fw_draw_text_ext(@pX + 1, @pY - 22, @pingName[@i], 9999);
			fw_draw_text_ext(@pX, @pY - 23, @pingName[@i], 9999);
			fw_draw_text_ext(@pX, @pY - 21, @pingName[@i], 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 0;
			global.__ONLINE_cjkValign = 0;
			__ONLINE_cjk_draw_text(@pNameDrawX - 1, @pNameDrawY, @pingName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX + 1, @pNameDrawY, @pingName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY - 1, @pingName[@i], 9999);
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY + 1, @pingName[@i], 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@pNameDrawX - 1, @pNameDrawY, @pingName[@i]);
			draw_text(@pNameDrawX + 1, @pNameDrawY, @pingName[@i]);
			draw_text(@pNameDrawX, @pNameDrawY - 1, @pingName[@i]);
			draw_text(@pNameDrawX, @pNameDrawY + 1, @pingName[@i]);
			#endif
			#endif
			draw_set_color(@pNC);
			#if GM80
			fw_draw_text_ext(@pX, @pY - 22, @pingName[@i], 9999);
			#endif
			#if CJKTEXT
			__ONLINE_cjk_draw_text(@pNameDrawX, @pNameDrawY, @pingName[@i], 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@pNameDrawX, @pNameDrawY, @pingName[@i]);
			draw_set_halign(fa_center);
			draw_set_valign(fa_middle);
			#endif
			#endif
		}
	}
	if(@pingWheelOpen){
		@wcx = @pingWheelCenterX;
		@wcy = @pingWheelCenterY;
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
				if(@cellIdx == @pingWheelHover){
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
				draw_set_alpha(1);
				if(@cellIdx == 0){
					draw_set_color(make_color_rgb(88, 118, 150));
					draw_circle(@cx, @cy, 6, true);
					draw_set_color(c_black);
					draw_text(@cx - 1, @cy, "?");
					draw_text(@cx + 1, @cy, "?");
					draw_text(@cx, @cy - 1, "?");
					draw_text(@cx, @cy + 1, "?");
					draw_set_color(c_white);
					draw_text(@cx, @cy, "?");
				}
				if(@cellIdx == 1 || @cellIdx == 3 || @cellIdx == 5 || @cellIdx == 7){
					@wArrowLen = 5;
					@wArrowTail = 1;
					draw_set_color(c_white);
					if(@cellIdx == 1){
						draw_triangle(@cx - 4, @cy, @cx + 4, @cy, @cx, @cy - @wArrowLen, false);
						draw_rectangle(@cx - @wArrowTail, @cy, @cx + @wArrowTail, @cy + @wArrowLen, false);
					}
					if(@cellIdx == 3){
						draw_triangle(@cx, @cy - 4, @cx, @cy + 4, @cx - @wArrowLen, @cy, false);
						draw_rectangle(@cx, @cy - @wArrowTail, @cx + @wArrowLen, @cy + @wArrowTail, false);
					}
					if(@cellIdx == 5){
						draw_triangle(@cx, @cy - 4, @cx, @cy + 4, @cx + @wArrowLen, @cy, false);
						draw_rectangle(@cx - @wArrowLen, @cy - @wArrowTail, @cx, @cy + @wArrowTail, false);
					}
					if(@cellIdx == 7){
						draw_triangle(@cx - 4, @cy, @cx + 4, @cy, @cx, @cy + @wArrowLen, false);
						draw_rectangle(@cx - @wArrowTail, @cy - @wArrowLen, @cx + @wArrowTail, @cy, false);
					}
				}
				if(@cellIdx == 2){
					draw_set_color(make_color_rgb(74, 222, 128));
					draw_circle(@cx, @cy, 6, true);
					draw_set_color(c_black);
					draw_line_width(@cx - 4, @cy, @cx - 1, @cy + 3, 3);
					draw_line_width(@cx - 1, @cy + 3, @cx + 5, @cy - 4, 3);
					draw_set_color(c_white);
					draw_line_width(@cx - 4, @cy - 1, @cx - 1, @cy + 2, 2);
					draw_line_width(@cx - 1, @cy + 2, @cx + 5, @cy - 5, 2);
				}
				if(@cellIdx == 4){
					draw_set_color(c_white);
					draw_circle(@cx, @cy, 5, true);
					draw_circle(@cx, @cy, 2, true);
					draw_line_width(@cx - 8, @cy, @cx - 5, @cy, 2);
					draw_line_width(@cx + 5, @cy, @cx + 8, @cy, 2);
					draw_line_width(@cx, @cy - 8, @cx, @cy - 5, 2);
					draw_line_width(@cx, @cy + 5, @cx, @cy + 8, 2);
					draw_circle(@cx, @cy, 1, false);
				}
				if(@cellIdx == 6){
					draw_set_color(make_color_rgb(88, 106, 122));
					draw_circle(@cx, @cy, 6, true);
					draw_set_color(c_white);
					draw_rectangle(@cx - 4, @cy - 5, @cx - 2, @cy + 5, false);
					draw_rectangle(@cx + 2, @cy - 5, @cx + 4, @cy + 5, false);
				}
				if(@cellIdx == 8){
					draw_set_color(make_color_rgb(250, 204, 21));
					draw_triangle(@cx - 9, @cy + 7, @cx + 9, @cy + 7, @cx, @cy - 9, false);
					draw_set_color(c_black);
					draw_text(@cx, @cy + 1, "!");
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
