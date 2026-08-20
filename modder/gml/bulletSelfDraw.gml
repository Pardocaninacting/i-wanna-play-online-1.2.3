/// ONLINE
// Local player bullet re-skin (S4, 2026-08-16): draw the selected skin's
// bullet.png (state 6) instead of the game's native bullet sprite. Injected
// into the bullet object's Draw event ONLY when that object had none (a Draw
// event suppresses the engine's automatic sprite draw, so the fallback below
// MUST redraw the native sprite when the skin has no bullet.png, skins are
// disabled, or the selected skin has no bullet strip). Collision masks and
// game logic are untouched - this changes display only. The skin slot -1
// reads the selected-skin global mirror (@skin_slot_spr), so a mid-game skin
// switch re-skins local bullets on the next frame.
// Facing: skin bullet strips face right. Games that flip via image_xscale
// carry the sign already; direction-neutral sprites (Domu: image_xscale is
// always 1, facing lives only in hspeed) get the flip from the travel
// direction. Keep this formula in sync with @bullet_update's @bFace.
if(global.@skinOn == 1){
    @bsFace = image_xscale;
    if(hspeed < 0){
        if(@bsFace > 0) @bsFace = -@bsFace;
    }
    if(hspeed > 0){
        if(@bsFace < 0) @bsFace = -@bsFace;
    }
    if(@skin_draw(6, image_index, x, y, @bsFace, image_yscale, image_angle, image_alpha, -1)){
        exit;
    }
}
if(sprite_exists(sprite_index)){
    draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, c_white, image_alpha);
}
