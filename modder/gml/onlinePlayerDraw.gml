/// ONLINE
// %arg0: The name of the world object
if(@oRoom != room){
	exit;
}
@oWorld = noone;
if(instance_exists(%arg0)){
	@oWorld = instance_find(%arg0, 0);
}
if(@oWorld != noone && @oWorld.@vis <= 1){
	if(sprite_exists(sprite_index)){
		@_drawAlpha = image_alpha;
		@_drewSkin = 0;
		if(@skinState >= 1){
			// Remote skin: resolved players draw from their slot; pending and
			// explicitly-missing players draw the "Unknown" fallback package
			// (slot 0) when it is installed.
			@_st = @skin_state_of(sprite_index);
			if(@_st >= 0){
				@_slot = -1;
				if(@skinState == 2){
					@_slot = @skinSlot;
				}else if(global.@rskUnknown == 1){
					@_slot = 0;
				}
				if(@_slot >= 0){
					@_drewSkin = @skin_draw(@_st, image_index, x, y, image_xscale, image_yscale, image_angle, @_drawAlpha, @_slot);
				}
			}
		}
		if(!@_drewSkin){
			draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, c_white, @_drawAlpha);
		}
		if(@oWorld.@vis == 0){
			@_alpha = draw_get_alpha();
			@_color = draw_get_color();
			draw_set_alpha(@_drawAlpha);
			#if STUDIO
				if(global.@ftOnline >= 0){
					draw_set_font(global.@ftOnline);
				}
			#endif
			#if not STUDIO
				draw_set_font(@ftOnlinePlayerName);
			#endif
			draw_set_valign(fa_center);
			draw_set_halign(fa_center);
			draw_set_color(c_black);
			@border = 2;
			@padding = 30;
			@xx = round(x);
			@yy = round(y-@padding);
			if(@spectating){
				@specLabel = "[SPEC]";
				@specY = @yy - 14;
				@specDrawX = @xx;
				@specDrawY = @specY;
				#if CJKTEXT
				@specDrawW = __ONLINE_cjk_string_width_ext(@specLabel, -1, 9999);
				@specDrawH = __ONLINE_cjk_string_height_ext(@specLabel, -1, 9999);
				@specDrawX = round(@xx - @specDrawW * 0.5);
				@specDrawY = round(@specY - @specDrawH * 0.5);
				#endif
				#if not GM80
				#if not CJKTEXT
				@specDrawW = string_width(@specLabel);
				@specDrawH = string_height(@specLabel);
				@specDrawX = round(@xx - @specDrawW * 0.5);
				@specDrawY = round(@specY - @specDrawH * 0.5);
				draw_set_halign(fa_left);
				draw_set_valign(fa_top);
				#endif
				#endif
				draw_set_alpha(@_drawAlpha);
				draw_set_color(c_black);
				#if GM80
				fw_draw_set_halign(fa_center);
				fw_draw_set_valign(fa_center);
				__ONLINE_fw_use_font(@specLabel);
				fw_draw_text_ext(@xx+@border, @specY, @specLabel, 9999);
				fw_draw_text_ext(@xx, @specY+@border, @specLabel, 9999);
				fw_draw_text_ext(@xx-@border, @specY, @specLabel, 9999);
				fw_draw_text_ext(@xx, @specY-@border, @specLabel, 9999);
				draw_set_color(make_color_rgb(160, 220, 255));
				fw_draw_text_ext(@xx, @specY, @specLabel, 9999);
				#endif
				#if CJKTEXT
				global.__ONLINE_cjkHalign = 0;
				global.__ONLINE_cjkValign = 0;
				__ONLINE_cjk_draw_text(@specDrawX+@border, @specDrawY, @specLabel, 9999);
				__ONLINE_cjk_draw_text(@specDrawX, @specDrawY+@border, @specLabel, 9999);
				__ONLINE_cjk_draw_text(@specDrawX-@border, @specDrawY, @specLabel, 9999);
				__ONLINE_cjk_draw_text(@specDrawX, @specDrawY-@border, @specLabel, 9999);
				draw_set_color(make_color_rgb(160, 220, 255));
				__ONLINE_cjk_draw_text(@specDrawX, @specDrawY, @specLabel, 9999);
				#endif
				#if not GM80
				#if not CJKTEXT
				draw_text(@specDrawX+@border, @specDrawY, @specLabel);
				draw_text(@specDrawX, @specDrawY+@border, @specLabel);
				draw_text(@specDrawX-@border, @specDrawY, @specLabel);
				draw_text(@specDrawX, @specDrawY-@border, @specLabel);
				draw_set_color(make_color_rgb(160, 220, 255));
				draw_text(@specDrawX, @specDrawY, @specLabel);
				#endif
				#endif
			}
			// PLAYER NAME
			// PLAYER NAME (explicit-missing remote skins get a [?] marker)
			@nameShown = @name;
			if(@skinState == 3){
				@nameShown = @name + " [?]";
			}
			@nameDrawX = @xx;
			@nameDrawY = @yy;
			#if CJKTEXT
			@nameDrawW = __ONLINE_cjk_string_width_ext(@nameShown, -1, 9999);
			@nameDrawH = __ONLINE_cjk_string_height_ext(@nameShown, -1, 9999);
			@nameDrawX = round(@xx - @nameDrawW * 0.5);
			@nameDrawY = round(@yy - @nameDrawH * 0.5);
			#endif
			#if not GM80
			#if not CJKTEXT
			@nameDrawW = string_width(@nameShown);
			@nameDrawH = string_height(@nameShown);
			@nameDrawX = round(@xx - @nameDrawW * 0.5);
			@nameDrawY = round(@yy - @nameDrawH * 0.5);
			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			#endif
			#endif
			draw_set_alpha(@_drawAlpha);
			draw_set_color(c_black);
			#if GM80
			fw_draw_set_halign(fa_center);
			fw_draw_set_valign(fa_center);
			__ONLINE_fw_use_font(@nameShown);
			fw_draw_text_ext(@xx+@border, @yy, @nameShown, 9999);
			fw_draw_text_ext(@xx, @yy+@border, @nameShown, 9999);
			fw_draw_text_ext(@xx-@border, @yy, @nameShown, 9999);
			fw_draw_text_ext(@xx, @yy-@border, @nameShown, 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 0;
			global.__ONLINE_cjkValign = 0;
			__ONLINE_cjk_draw_text(@nameDrawX+@border, @nameDrawY, @nameShown, 9999);
			__ONLINE_cjk_draw_text(@nameDrawX, @nameDrawY+@border, @nameShown, 9999);
			__ONLINE_cjk_draw_text(@nameDrawX-@border, @nameDrawY, @nameShown, 9999);
			__ONLINE_cjk_draw_text(@nameDrawX, @nameDrawY-@border, @nameShown, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@nameDrawX+@border, @nameDrawY, @nameShown);
			draw_text(@nameDrawX, @nameDrawY+@border, @nameShown);
			draw_text(@nameDrawX-@border, @nameDrawY, @nameShown);
			draw_text(@nameDrawX, @nameDrawY-@border, @nameShown);
			#endif
			#endif
			@_tc = c_white;
			with(@oWorld){
				other.@_tc = @teamColors[other.@team];
			}
			draw_set_color(@_tc);
			draw_set_alpha(@_drawAlpha);
			#if GM80
			fw_draw_text_ext(@xx, @yy, @nameShown, 9999);
			#endif
			#if CJKTEXT
			__ONLINE_cjk_draw_text(@nameDrawX, @nameDrawY, @nameShown, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@nameDrawX, @nameDrawY, @nameShown);
			#endif
			#endif
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
	}
}
