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
	#if not GM80
		@textH = string_height_ext(@wrappedMsg, -1, @bubbleMaxW);
		@textW = string_width_ext(@wrappedMsg, -1, @bubbleMaxW);
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
	@xx = x;
	@yy = y - 30 + @bobOff;
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
	@fAlpha = @fadeAlpha * @drawAlpha;
	@_alpha = draw_get_alpha();
	@_color = draw_get_color();
	draw_set_alpha(@fAlpha * 0.88);
	draw_set_color(c_white);
	draw_roundrect(@xx - @dW/2, @yy - @dH/2, @xx + @dW/2, @yy + @dH/2, false);
	@tailW = min(5 * @scale, 5);
	@tailH = min(6 * @scale, 6);
	@tailBaseY = @yy + @dH / 2;
	draw_triangle(@xx - @tailW, @tailBaseY - 1, @xx + @tailW, @tailBaseY - 1, @xx, @tailBaseY + @tailH, false);
	draw_set_color(make_color_rgb(70, 70, 70));
	draw_roundrect(@xx - @dW/2, @yy - @dH/2, @xx + @dW/2, @yy + @dH/2, true);
	draw_set_color(c_white);
	draw_rectangle(@xx - @tailW + 1, @tailBaseY - 1, @xx + @tailW - 1, @tailBaseY, false);
	draw_set_color(make_color_rgb(70, 70, 70));
	draw_line(@xx - @tailW, @tailBaseY, @xx, @tailBaseY + @tailH);
	draw_line(@xx + @tailW, @tailBaseY, @xx, @tailBaseY + @tailH);
	if(@showText){
		draw_set_alpha(@fAlpha * @textAlpha);
		draw_set_color(c_black);
		draw_set_valign(fa_center);
		draw_set_halign(fa_center);
		#if GM80
			fw_draw_set_valign(fa_center);
			fw_draw_set_halign(fa_center);
			fw_draw_set_line_spacing(-1);
			fw_draw_text_ext(@xx, @yy, @wrappedMsg, @bubbleMaxW);
		#endif
		#if not GM80
			draw_text_ext(@xx, @yy, @wrappedMsg, -1, @bubbleMaxW);
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
}
