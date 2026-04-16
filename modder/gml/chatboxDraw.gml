/// ONLINE
if(@timer > 0 && @scale > 0){
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	#if not STUDIO
		draw_set_font(@ftOnlinePlayerName);
	#endif
	#if GM80
		__ONLINE_fw_use_font(@wrappedMsg);
		@textH = fw_string_height_ext(@wrappedMsg, -1, @bubbleMaxW);
		@textW = fw_string_width_ext(@wrappedMsg, -1, @bubbleMaxW);
	#endif
	#if CJKTEXT
		@textH = __ONLINE_cjk_string_height_ext(@wrappedMsg, -1, @bubbleMaxW);
		@textW = __ONLINE_cjk_string_width_ext(@wrappedMsg, -1, @bubbleMaxW);
	#endif
	#if not GM80
	#if not CJKTEXT
		@textH = string_height_ext(@wrappedMsg, -1, @bubbleMaxW);
		@textW = string_width_ext(@wrappedMsg, -1, @bubbleMaxW);
	#endif
	#endif
	if(@textW > @bubbleMaxW) @textW = @bubbleMaxW;
	@bPad = 7;
	@fullW = @textW + @bPad * 2;
	@fullH = @textH + @bPad * 2;
	@clampedSquash = @squash;
	if(@clampedSquash < -0.1) @clampedSquash = -0.1;
	if(@clampedSquash > 0.25) @clampedSquash = 0.25;
	@dW = @fullW * @scale * (1 + @clampedSquash);
	@dH = @fullH * @scale * (1 - @clampedSquash);
	@bobOff = sin(@bobTime * 0.06) * 1.5;
	@xx = @c2x;
	@yy = @c2y + @bobOff;
	@left = 0;
	@right = room_width;
	@top = 0;
	@bottom = room_height;
	if(view_enabled && view_visible[0]){
		@left = view_xview[0];
		@right = @left + view_wview[0];
		@top = view_yview[0];
		@bottom = @top + view_hview[0];
	}
	@xx = min(max(@xx, @left + @dW/2 + 4), @right - @dW/2 - 4);
	@yy = min(max(@yy - @dH - 8, @top + 4), @bottom - @dH - 20);
	@yy = @yy + @dH / 2;
	@drawX = @xx;
	@drawY = @yy;
	@fAlpha = @fadeAlpha * @drawAlpha;
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	@breathe = sin(@bobTime * 0.06);
	@tailR1 = (2.5 + @breathe * 0.3) * @scale;
	@tailR2 = (4 + @breathe * 0.5) * @scale;
	@tailR3 = (5.5 + @breathe * 0.7) * @scale;
	@tailS1 = @tailPop / 0.24;
	if(@tailS1 < 0) @tailS1 = 0;
	if(@tailS1 > 1) @tailS1 = 1;
	@tailS1 = @tailS1 * @tailS1 * (3 - 2 * @tailS1);
	@tailS2 = (@tailPop - 0.1) / 0.24;
	if(@tailS2 < 0) @tailS2 = 0;
	if(@tailS2 > 1) @tailS2 = 1;
	@tailS2 = @tailS2 * @tailS2 * (3 - 2 * @tailS2);
	@tailS3 = (@tailPop - 0.2) / 0.24;
	if(@tailS3 < 0) @tailS3 = 0;
	if(@tailS3 > 1) @tailS3 = 1;
	@tailS3 = @tailS3 * @tailS3 * (3 - 2 * @tailS3);
	draw_set_alpha(@fAlpha * 0.88);
	draw_set_color(c_white);
	draw_roundrect(@drawX - @dW/2, @drawY - @dH/2, @drawX + @dW/2, @drawY + @dH/2, false);
	if(@tailS3 > 0){
		draw_set_alpha(@fAlpha * 0.76);
		draw_circle(@c2x, @c2y, @tailR3 * @tailS3, false);
	}
	if(@tailS2 > 0){
		draw_set_alpha(@fAlpha * 0.63);
		draw_circle(@c1x, @c1y, @tailR2 * @tailS2, false);
	}
	if(@tailS1 > 0){
		draw_set_alpha(@fAlpha * 0.50);
		draw_circle(@c0x, @c0y, @tailR1 * @tailS1, false);
	}
	draw_set_color(make_color_rgb(70, 70, 70));
	draw_set_alpha(@fAlpha * 0.88);
	draw_roundrect(@drawX - @dW/2, @drawY - @dH/2, @drawX + @dW/2, @drawY + @dH/2, true);
	if(@tailS3 > 0){
		draw_set_alpha(@fAlpha * 0.76);
		draw_circle(@c2x, @c2y, @tailR3 * @tailS3, true);
	}
	if(@tailS2 > 0){
		draw_set_alpha(@fAlpha * 0.63);
		draw_circle(@c1x, @c1y, @tailR2 * @tailS2, true);
	}
	if(@tailS1 > 0){
		draw_set_alpha(@fAlpha * 0.50);
		draw_circle(@c0x, @c0y, @tailR1 * @tailS1, true);
	}
	if(@showText){
		draw_set_alpha(@fAlpha * @textAlpha);
		draw_set_color(c_black);
		draw_set_valign(fa_center);
		draw_set_halign(fa_center);
		#if GM80
			fw_draw_set_valign(fa_center);
			fw_draw_set_halign(fa_center);
			fw_draw_set_line_spacing(-1);
			fw_draw_text_ext(@drawX, @drawY, @wrappedMsg, @bubbleMaxW);
		#endif
		#if CJKTEXT
			global.__ONLINE_cjkValign = 1;
			global.__ONLINE_cjkHalign = 1;
			__ONLINE_cjk_draw_text(@drawX, @drawY, @wrappedMsg, @bubbleMaxW);
		#endif
		#if not GM80
		#if not CJKTEXT
			draw_text_ext(@drawX, @drawY, @wrappedMsg, -1, @bubbleMaxW);
		#endif
		#endif
	}
	draw_set_alpha(@_alpha);
	draw_set_color(@_color);
	if(font_exists(0)){
		draw_set_font(0);
	}
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	#if GM80
		fw_draw_set_valign(fa_top);
		fw_draw_set_halign(fa_left);
	#endif
	#if CJKTEXT
		global.__ONLINE_cjkValign = 0;
		global.__ONLINE_cjkHalign = 0;
	#endif
}
