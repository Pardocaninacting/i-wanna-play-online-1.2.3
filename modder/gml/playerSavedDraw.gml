/// ONLINE
@xx = 20;
@yy = 20 + @msgSlot * 20;
if(view_enabled && view_visible[0]){
	@xx += view_xview[0];
	@yy += view_yview[0];
}
@text = "";
if(@state == 4) @text = "Online save enabled!";
else if(@state == 3) @text = "Online save disabled!";
else if(@state == 5) @text = "player smooth movement: on";
else if(@state == 6) @text = "player smooth movement: off";
else if(@state == 7) @text = "Indicator: on";
else if(@state == 8) @text = "Indicator: off";
else if(@state == 9) @text = "Camera: Follow";
else if(@state == 10) @text = "Camera: Screen";
else if(@state >= 0) @text = "player visual mode: "+string(@state);
else if(@state == -2) @text = @name;
else @text = @name+" saved!";
@_alpha = draw_get_alpha();
@_color = draw_get_color();
draw_set_valign(fa_top);
draw_set_halign(fa_left);
draw_set_alpha(image_alpha);
#if STUDIO
	if(global.@ftOnline >= 0){
		draw_set_font(global.@ftOnline);
	}
#endif
#if not STUDIO
	draw_set_font(@ftOnlinePlayerName);
#endif
if(@state == -2){
	@useTeamColor = @teamColor;
}else{
	@useTeamColor = c_white;
}
draw_set_color(c_black);
#if GM80
fw_draw_set_halign(fa_left);
fw_draw_set_valign(fa_top);
__ONLINE_fw_use_font(@text);
fw_draw_text_ext(@xx+1, @yy, @text, 9999);
fw_draw_text_ext(@xx, @yy+1, @text, 9999);
fw_draw_text_ext(@xx-1, @yy, @text, 9999);
fw_draw_text_ext(@xx, @yy-1, @text, 9999);
draw_set_color(@useTeamColor);
fw_draw_text_ext(@xx, @yy, @text, 9999);
#endif
#if not GM80
draw_text(@xx+1, @yy, @text);
draw_text(@xx, @yy+1, @text);
draw_text(@xx-1, @yy, @text);
draw_text(@xx, @yy-1, @text);
draw_set_color(@useTeamColor);
draw_text(@xx, @yy, @text);
#endif
draw_set_alpha(@_alpha);
draw_set_color(@_color);
if(font_exists(0)){
	draw_set_font(0);
}
draw_set_valign(fa_top);
draw_set_halign(fa_left);
