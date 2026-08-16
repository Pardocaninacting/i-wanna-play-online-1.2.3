// ONLINE bullet sharing (S4): remote players' bullets are rendered locally as
// the sender's skin bullet.png (or the game's native bullet sprite), with an
// optional per-game collision action (iwpo.bullet.hit). Reference: TheBiob
// lib/mods/shared_bullets (proxy object + per-frame state snapshots).
//
// The converter splits this file at the "///// script <name>" markers into
// __ONLINE_-prefixed script assets (same pattern as skinLib.gml). Every entry
// runs in the WORLD instance's context. The feature is inert when the
// converter could not resolve a bullet object (global.__ONLINE_bulletObj < 0).
//
// Design notes:
// - Snapshot semantics over TCP (ordered, no loss): every BULLET_NOTIFY is a
//   complete list of the sender's bullets. Receivers diff the proxy registry
//   against it (drop missing, update present, create new). No timestamps.
// - Senders only send while 1..8 bullets exist; proxies age out via @bAlive
//   (4 frames) so a silent sender (cleared bullets / quit / room switch)
//   cannot leave ghosts. A different GM room is filtered on receive.
// - Protocol: opcode 18 BULLET (C->S) / 19 BULLET_NOTIFY (S->C) - see
//   server/src/protocol.ts. Gated like skins (protocolVersion >= 3); clients
//   with an older protocol silently ignore opcode 19 (default: break).

///// script @bullet_init
// worldCreate: create the proxy registry map. The __ONLINE_bullet proxy
// object's sprite/depth/mask were copied from the game's bullet object at
// convert time (static), so this is all the runtime needs.
if(global.@bulletObj < 0){
    @bActive = 0;
    return 0;
}
@bMap = ds_map_create();
@bActive = 1;
return 1;

///// script @bullet_update
// worldEndStep: broadcast local bullet state once per frame while 1..8
// bullets exist. Full snapshot; receivers diff against it. The message is
// queued with __ONLINE_socket_write_message and flushed by the existing
// per-frame socket update.
if(@bActive && @connected && __ONLINE_socket_get_state(@socket) == 2){
    @bCount = instance_number(global.@bulletObj);
    if(@bCount >= 1 && @bCount <= 8){
        __ONLINE_buffer_clear(@buffer);
        #if not GMNET
            __ONLINE_buffer_write_uint8(@buffer, 18);
            __ONLINE_buffer_write_uint8(@buffer, @bCount);
            __ONLINE_buffer_write_uint16(@buffer, room);
        #endif
        #if GMNET
            __ONLINE_buffer_write_u8(@buffer, 18);
            __ONLINE_buffer_write_u8(@buffer, @bCount);
            __ONLINE_buffer_write_u16(@buffer, room);
        #endif
        with(global.@bulletObj){
            #if not GMNET
                __ONLINE_buffer_write_int32(other.@buffer, id);
                __ONLINE_buffer_write_int32(other.@buffer, x);
                __ONLINE_buffer_write_int32(other.@buffer, y);
                __ONLINE_buffer_write_float32(other.@buffer, direction);
                __ONLINE_buffer_write_float32(other.@buffer, speed);
            #endif
            #if GMNET
                __ONLINE_buffer_write_i32(other.@buffer, id);
                __ONLINE_buffer_write_i32(other.@buffer, x);
                __ONLINE_buffer_write_i32(other.@buffer, y);
                __ONLINE_buffer_write_float(other.@buffer, direction);
                __ONLINE_buffer_write_float(other.@buffer, speed);
            #endif
        }
        __ONLINE_socket_write_message(@socket, @buffer);
    }
}
return 0;

///// script @bullet_recv
// case 19 (BULLET_NOTIFY) handler: read the per-bullet state into the shared
// arrays (@bRI/@bRX/@bRY/@bRD/@bRS), then diff the proxy registry.
// argument0: sender playerId, argument1: bullet count.
@bOwner = argument0;
@bCount = argument1;
if(!@bActive){
    return 0;
}
for(@bi = 0; @bi < @bCount; @bi += 1){
    #if not GMNET
        @bRI[@bi] = __ONLINE_buffer_read_int32(@buffer);
        @bRX[@bi] = __ONLINE_buffer_read_int32(@buffer);
        @bRY[@bi] = __ONLINE_buffer_read_int32(@buffer);
        @bRD[@bi] = __ONLINE_buffer_read_float32(@buffer);
        @bRS[@bi] = __ONLINE_buffer_read_float32(@buffer);
    #endif
    #if GMNET
        @bRI[@bi] = __ONLINE_buffer_read_i32(@buffer);
        @bRX[@bi] = __ONLINE_buffer_read_i32(@buffer);
        @bRY[@bi] = __ONLINE_buffer_read_i32(@buffer);
        @bRD[@bi] = __ONLINE_buffer_read_float(@buffer);
        @bRS[@bi] = __ONLINE_buffer_read_float(@buffer);
    #endif
}
@bullet_apply(@bOwner, @bCount);
return 1;

///// script @bullet_apply
// argument0: sender playerId, argument1: bullet count (already read into
// @bRI/@bRX/@bRY/@bRD/@bRS). Snapshot diff: drop proxies whose bullet is no
// longer in the snapshot, update the survivors, create the missing ones
// (registry capped at 64 proxies to protect GM8 instance counts).
@bOwner = argument0;
@bCount = argument1;
if(!@bActive){
    return 0;
}
// Sender's skin slot: resolved remote skins render their bullet.png; pending/
// missing (or skinless) senders draw the game's native bullet sprite.
@bP = noone;
for(@bi = 0; @bi < instance_number(@onlinePlayer); @bi += 1){
    @bT = instance_find(@onlinePlayer, @bi);
    if(@bT.@ID == @bOwner){
        @bP = @bT;
        break;
    }
}
@bSlot = -1;
if(@bP != noone){
    if(@bP.@skinState == 2){
        @bSlot = @bP.@skinSlot;
    }
}
// 1) Drop proxies whose bullet is no longer in the snapshot.
with(@bullet){
    if(@bOwner == other.@bOwner){
        @bIn = 0;
        for(@bi = 0; @bi < other.@bCount; @bi += 1){
            if(@bKey == other.@bOwner + "|" + string(other.@bRI[@bi])){
                @bIn = 1;
                break;
            }
        }
        if(!@bIn){
            // Remove the registry entry via the world context directly
            // (other = the @bullet_apply caller) - more reliable than the
            // proxy's own @bWorld reference.
            if(ds_map_exists(other.@bMap, @bKey)){
                ds_map_delete(other.@bMap, @bKey);
            }
            instance_destroy();
        }
    }
}
// 2) Update existing proxies / create missing ones. A map entry whose
// instance is gone is STALE (the proxy died through a path that could not
// reach the map, e.g. its @bWorld reference was invalid): GM instance ids
// get reused, so a stale key would make a brand-new bullet with the same id
// invisible forever. Drop the stale entry and fall through to creation.
for(@bi = 0; @bi < @bCount; @bi += 1){
    @bkey = @bOwner + "|" + string(@bRI[@bi]);
    @bid = -1;
    if(ds_map_exists(@bMap, @bkey)){
        @bid = ds_map_find_value(@bMap, @bkey);
        if(!instance_exists(@bid)){
            ds_map_delete(@bMap, @bkey);
            @bid = -1;
        }
    }
    if(@bid >= 0){
        with(@bid){
            x = other.@bRX[other.@bi];
            y = other.@bRY[other.@bi];
            @bAngle = other.@bRD[other.@bi];
            @bAlive = 4;
            @bSlot = other.@bSlot;
        }
    }else{
        if(ds_map_size(@bMap) < 64){
            @bid = instance_create(@bRX[@bi], @bRY[@bi], @bullet);
            if(instance_exists(@bid)){
                with(@bid){
                    @bOwner = other.@bOwner;
                    @bKey = other.@bkey;
                    @bAngle = other.@bRD[other.@bi];
                    @bAlive = 4;
                    @bSlot = other.@bSlot;
                    @bWorld = other.id;
                    @bImg = 0;
                }
                ds_map_add(@bMap, @bkey, @bid);
            }
        }
    }
}
return 1;

///// script @bullet_cleanup
// worldGameEnd: destroy every proxy and the registry map.
if(!@bActive){
    return 0;
}
with(@bullet){
    instance_destroy();
}
ds_map_destroy(@bMap);
@bActive = 0;
return 1;
