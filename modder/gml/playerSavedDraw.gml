/// ONLINE
// Screen-space toasts. GM8.0: regular Draw event under a forced window-pixel
// ortho projection (see _workspace/RESEARCH_GM8_3D_HUD.md). GM8.2 (GM8GUI):
// native Draw GUI event instead (group 11, repurposed trigger group; GM8.0/8.1
// runners treat group 11 as never-drawn triggers and keep the GM8.0 path) - regular Draw output is silently invisible
// in d3d-started rooms (TUNNEL VISION E1 probe), and the GUI pass projection
// is Y-flipped there, so we always set our own window ortho. GAME_D3D builds
// additionally wrap the draw in d3d_set_hidden(false)/(true) because a live
// z-buffer eats our primitives. GMS: this event is attached to Draw GUI,
// already screen-space.
#if not STUDIO
	#if not GM8GUI
@psFirst = 0;
if(view_enabled){
	@psFirst = -1;
	for(@psVi = 0; @psVi < 8; @psVi += 1){
		if(@psFirst < 0){
			if(view_visible[@psVi]) @psFirst = @psVi;
		}
	}
}
if(view_current != @psFirst) exit;
d3d_set_projection_ortho(0, 0, window_get_width(), window_get_height(), 0);
d3d_set_depth(-15999);
#if GAME_D3D
d3d_set_hidden(false);
#endif
	#endif
#endif
#if GM8GUI
d3d_set_projection_ortho(0, 0, window_get_width(), window_get_height(), 0);
#if GAME_D3D
d3d_set_hidden(false);
#endif
#endif
@xx = 20;
@yy = 20 + @msgSlot * 20;
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
#if CJKTEXT
global.__ONLINE_cjkHalign = 0;
global.__ONLINE_cjkValign = 0;
__ONLINE_cjk_draw_text(@xx+1, @yy, @text, 9999);
__ONLINE_cjk_draw_text(@xx, @yy+1, @text, 9999);
__ONLINE_cjk_draw_text(@xx-1, @yy, @text, 9999);
__ONLINE_cjk_draw_text(@xx, @yy-1, @text, 9999);
draw_set_color(@useTeamColor);
__ONLINE_cjk_draw_text(@xx, @yy, @text, 9999);
#endif
#if not GM80
#if not CJKTEXT
draw_text(@xx+1, @yy, @text);
draw_text(@xx, @yy+1, @text);
draw_text(@xx-1, @yy, @text);
draw_text(@xx, @yy-1, @text);
draw_set_color(@useTeamColor);
draw_text(@xx, @yy, @text);
#endif
#endif
draw_set_alpha(@_alpha);
draw_set_color(@_color);
if(font_exists(0)){
	draw_set_font(0);
}
draw_set_valign(fa_top);
draw_set_halign(fa_left);
#if GAME_D3D
#if not STUDIO
d3d_set_hidden(true);
#endif
#endif
