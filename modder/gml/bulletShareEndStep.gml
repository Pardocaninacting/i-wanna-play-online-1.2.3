/// ONLINE
// %arg0: player object name, %arg1: player2 object name, %arg2: hit action,
// %arg3: PVP kill call (baked; empty when PVP is unavailable for this game)
// Proxy bullet EndStep: age out when fresh snapshots stop arriving, advance
// the animation phase, dead-reckon the position (uniform straight-line
// motion - snapshots re-anchor it on arrival, so jitter no longer freezes
// the bullet), then run the configured collision action against the local
// player.
// NOTE: the template engine has no #else support; use paired #if / #if not.
@bAlive -= 1;
if(@bAlive <= 0){
    if(instance_exists(@bWorld)){
        with(@bWorld){
            if(ds_map_exists(@bMap, other.@bKey)){
                ds_map_delete(@bMap, other.@bKey);
            }
        }
    }
    instance_destroy();
    exit;
}
if(@bSpd != 0){
    // Dead reckoning, wall-clamped: never extrapolate INTO a solid. A bullet
    // that dies on a wall on the sender side would otherwise visibly embed
    // itself for the 1-2 frames until the removal snapshot arrives (16 px per
    // frame at typical bullet speed). instance_place(..., all) + the solid
    // flag keeps this game-agnostic (players/proxies are not solid, blocks
    // are). A frozen proxy still gets re-anchored or removed by the next
    // snapshot, so a false positive (bullet that would have passed through)
    // self-corrects within a frame.
    @bNX = x + lengthdir_x(@bSpd, @bAngle);
    @bNY = y + lengthdir_y(@bSpd, @bAngle);
    @bWall = instance_place(@bNX, @bNY, all);
    if(@bWall == noone){
        x = @bNX;
        y = @bNY;
    }else{
        if(!@bWall.solid){
            x = @bNX;
            y = @bNY;
        }
    }
}
@bImg += 1;
#if PLAYER_LIST
    @bp = @get_active_player();
#endif
#if not PLAYER_LIST
    @bp = %arg0;
    #if PLAYER2
    if(!instance_exists(@bp)){
        @bp = %arg1;
    }
    #endif
#endif
if(instance_exists(@bp) && place_meeting(x, y, @bp)){
    %arg2
    // S5 (PVP): the kill call (%arg3, baked at convert time; empty = PVP
    // unavailable) fires only when the shooter's bullets can hurt the local
    // player under the victim-side rules matrix (Off/Team/FFA, see
    // @pvp_hostile in bulletShare.gml). The call is the game's own kill
    // script detected from its killer collision events, so death handling
    // (blood/sound/death counter/save) stays game-native.
    @bHurt = 0;
    if(instance_exists(@bWorld)){
        with(@bWorld){
            other.@bHurt = @pvp_hostile(other.@bOwner);
        }
    }
    if(@bHurt){
        %arg3
    }
}
