/// ONLINE
// %arg0: world object name
// Proxy bullet Draw: draw the sender's skin bullet.png when that skin has
// one (state 6), otherwise the game's native bullet sprite. Rotation follows
// the synced direction. The whole draw is gated on the world's visibility
// (spectator/hidden mode hides remote bullets entirely - both the skin draw
// AND the native fallback, matching onlinePlayerDraw).
if(instance_exists(%arg0)){
    with(instance_find(%arg0, 0)){
        if(@vis <= 1){
            @bDrew = 0;
            if(other.@bSlot >= 0){
                @bDrew = @skin_draw(6, other.@bImg, other.x, other.y, 1, 1, other.@bAngle, other.image_alpha, other.@bSlot);
            }
            if(!@bDrew){
                if(global.@bulletSpr >= 0){
                    @bFrames = sprite_get_number(global.@bulletSpr);
                    if(@bFrames < 1){
                        @bFrames = 1;
                    }
                    draw_sprite_ext(global.@bulletSpr, other.@bImg mod @bFrames, other.x, other.y, 1, 1, other.@bAngle, c_white, other.image_alpha);
                }
            }
        }
    }
}
