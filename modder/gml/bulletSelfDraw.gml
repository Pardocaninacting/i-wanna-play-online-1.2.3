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
if(global.@skinOn == 1){
    if(@skin_draw(6, image_index, x, y, image_xscale, image_yscale, image_angle, image_alpha, -1)){
        exit;
    }
}
if(sprite_exists(sprite_index)){
    draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, c_white, image_alpha);
}
