/// ONLINE
// %arg0: world object name
// Proxy bullet Draw: draw the sender's skin bullet.png when that skin has
// one (state 6), otherwise the game's native bullet sprite. Flip/rotation
// follow the sender's image_xscale/image_angle (synced in the v2 wire
// format; v1 senders yield xscale 1 + movement-direction rotation). The
// whole draw is gated on the world's visibility (spectator/hidden mode
// hides remote bullets entirely - both the skin draw AND the native
// fallback, matching onlinePlayerDraw).
// The visibility check reads the world through a with() block, but the
// @skin_draw call itself runs in THIS proxy's context: its per-frame pacing
// accumulator (@skinAnPos etc.) lives on the caller instance, so every
// proxy animates independently (a shared world-side accumulator would lock
// all multi-frame bullet strips to the same phase).
@bVis = 0;
if(instance_exists(%arg0)){
    with(instance_find(%arg0, 0)){
        if(@vis <= 1){
            other.@bVis = 1;
        }
    }
}
if(@bVis){
    @bDrew = 0;
    if(@bSlot >= 0){
        @bDrew = @skin_draw(6, @bImg, x, y, @bXS, 1, @bAA, image_alpha, @bSlot, c_white, 0);
    }
    if(!@bDrew){
        if(global.@bulletSpr >= 0){
            @bFrames = sprite_get_number(global.@bulletSpr);
            if(@bFrames < 1){
                @bFrames = 1;
            }
            draw_sprite_ext(global.@bulletSpr, @bImg mod @bFrames, x, y, @bXS, 1, @bAA, c_white, image_alpha);
        }
    }
}
