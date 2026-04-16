/// ONLINE
// %arg0: The name of the world object
@oWorld = noone;
if(instance_exists(%arg0)){
	@oWorld = instance_find(%arg0, 0);
}
if(@oWorld != noone && @oWorld.@vis <= 1){
	if(sprite_exists(sprite_index)){
		draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, c_white, image_alpha);
		if(@oWorld.@vis == 0){
			@_alpha = draw_get_alpha();
			@_color = draw_get_color();
			draw_set_alpha(image_alpha);
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
			@xx = x;
			@yy = y-@padding;
			// PLAYER NAME
			draw_set_alpha(1);
			draw_set_color(c_black);
			#if GM80
			fw_draw_set_halign(fa_center);
			fw_draw_set_valign(fa_center);
			__ONLINE_fw_use_font(@name);
			fw_draw_text_ext(@xx+@border, @yy, @name, 9999);
			fw_draw_text_ext(@xx, @yy+@border, @name, 9999);
			fw_draw_text_ext(@xx-@border, @yy, @name, 9999);
			fw_draw_text_ext(@xx, @yy-@border, @name, 9999);
			#endif
			#if CJKTEXT
			global.__ONLINE_cjkHalign = 1;
			global.__ONLINE_cjkValign = 1;
			__ONLINE_cjk_draw_text(@xx+@border, @yy, @name, 9999);
			__ONLINE_cjk_draw_text(@xx, @yy+@border, @name, 9999);
			__ONLINE_cjk_draw_text(@xx-@border, @yy, @name, 9999);
			__ONLINE_cjk_draw_text(@xx, @yy-@border, @name, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@xx+@border, @yy, @name);
			draw_text(@xx, @yy+@border, @name);
			draw_text(@xx-@border, @yy, @name);
			draw_text(@xx, @yy-@border, @name);
			#endif
			#endif
			@_tc = c_white;
			with(@oWorld){
				other.@_tc = @teamColors[other.@team];
			}
			draw_set_color(@_tc);
			#if GM80
			fw_draw_text_ext(@xx, @yy, @name, 9999);
			#endif
			#if CJKTEXT
			__ONLINE_cjk_draw_text(@xx, @yy, @name, 9999);
			#endif
			#if not GM80
			#if not CJKTEXT
			draw_text(@xx, @yy, @name);
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
