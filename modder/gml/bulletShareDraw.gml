/// ONLINE
// %arg0: world object name
// Proxy bullet Draw: draw the sender's skin bullet.png when that skin has
// one (state 6), otherwise the game's native bullet sprite. Rotation follows
// the synced direction. Only drawn while the world is not in spectator /
// hidden mode (same visibility rule as onlinePlayerDraw).
@bDrew = 0;
if(instance_exists(%arg0)){
    with(instance_find(%arg0, 0)){
        if(@vis <= 1){
            if(other.@bSlot >= 0){
                other.@bDrew = @skin_draw(6, other.@bImg, other.x, other.y, 1, 1, other.@bAngle, other.image_alpha, other.@bSlot);
            }
        }
    }
}
if(!@bDrew){
    if(global.@bulletSpr >= 0){
        @bFrames = sprite_get_number(global.@bulletSpr);
        if(@bFrames < 1){
            @bFrames = 1;
        }
        draw_sprite_ext(global.@bulletSpr, @bImg mod @bFrames, x, y, 1, 1, @bAngle, c_white, image_alpha);
    }
}
