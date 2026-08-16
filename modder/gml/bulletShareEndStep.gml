/// ONLINE
// %arg0: player object name, %arg1: player2 object name, %arg2: hit action
// Proxy bullet EndStep: age out when fresh snapshots stop arriving, advance
// the animation phase, then run the configured collision action against the
// local player. Position is driven entirely by incoming snapshots - the
// proxy never moves itself (same model as TheBiob's shared_bullets).
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
}
