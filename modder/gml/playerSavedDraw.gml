/// ONLINE
// Screen-space toasts. GM8.0/8.1: regular Draw event under a forced view-port
// ortho projection, restored at the end of the event (the runner re-applies
// the view projection only at the next view; see
// _workspace/RESEARCH_GM8_3D_HUD.md). GM8.2 (GM8GUI):
// native Draw GUI event instead (group 11, repurposed trigger group; GM8.0/8.1
// runners treat group 11 as never-drawn triggers and keep the GM8.0 path) - regular Draw output is silently invisible
// in d3d-started rooms (TUNNEL VISION E1 probe), and the GUI pass projection
// is Y-flipped there, so we always set our own view-port ortho. GAME_D3D builds
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
// View-port space (not window space): survives window scaling / letterboxed
// fullscreen and scales with the game image. Projection is restored at the
// end of this event; the runner only re-applies it at the next view, and this
// object's draws leak to every instance with a lower depth.
if(view_enabled){
	d3d_set_projection_ortho(0, 0, view_wport[view_current], view_hport[view_current], 0);
}else{
	d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
}
d3d_set_depth(-15999);
#if GAME_D3D
d3d_set_hidden(false);
#endif
	#endif
#endif
#if GM8GUI
// Same view-port space as the group-8 path; GUI pass has no per-view context,
// anchor on view 0. No projection restore needed (GUI pass is frame-last).
if(view_enabled){
	if(view_visible[0]){
		d3d_set_projection_ortho(0, 0, view_wport[0], view_hport[0], 0);
	}else{
		d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
	}
}else{
	d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
}
#if GAME_D3D
d3d_set_hidden(false);
#endif
#endif
@xx = 20;
@yy = 20 + @msgSlot * 20;
@text = "";
// live states only: -2 = custom message in @name, -1 = "<name> saved!",
// 0-2 = player visual mode, 3/4 = online save off/on. (5-10 were smooth/
// indicator/camera announcements, retired with the hotkeys.)
if(@state == 4) @text = @L(global.__ONLINE_LK_NOTIFY_SAVE_ON, "Online save enabled!");
else if(@state == 3) @text = @L(global.__ONLINE_LK_NOTIFY_SAVE_OFF, "Online save disabled!");
else if(@state >= 0) @text = @str_fmt(@L(global.__ONLINE_LK_NOTIFY_VISUAL_MODE, "player visual mode: %1"), @state, 0, 0);
else if(@state == -2) @text = @name;
else @text = @str_fmt(@L(global.__ONLINE_LK_NOTIFY_SAVED, "%1 saved!"), @name, 0, 0);
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
#if not STUDIO
	#if not GM8GUI
// Projection restore (group-8 path only): anything drawn after this object in
// the same view would otherwise inherit the toast ortho.
if(view_enabled){
	d3d_set_projection_ortho(view_xview[view_current], view_yview[view_current], view_wview[view_current], view_hview[view_current], view_angle[view_current]);
}else{
	d3d_set_projection_ortho(0, 0, room_width, room_height, 0);
}
	#endif
#endif
#if GAME_D3D
#if not STUDIO
d3d_set_hidden(true);
#endif
#endif
