/// ONLINE
// ============================================================================
// Player Draw injection pack.
// The converter splits this file at the "///// mode <name>" markers and picks
// one section per player object:
//   replace: the object has no Draw event - this section becomes the whole
//            event, so it must reproduce the engine default draw when no
//            skin applies (otherwise the player would turn invisible).
//   preempt: the object has a Draw event - the skin draws INSTEAD of the
//            game's own draw. GMS prepends this section plus an
//            `if(<pre>skPre) { exit; }` line (GMS `exit` leaves the whole
//            event); GM8 (where `exit` would only leave the current code
//            action) textually wraps the event's single code action in
//            `if(!<pre>skPre){ ... }`. This is the DEFAULT for objects with
//            a Draw event: stacking the skin over the original sprite looks
//            broken. Fallbacks to overlay: multi-action Draw events on GM8,
//            or iwpo.skins.overlay=1 on either engine.
//   overlay: appended after the game's own draw code, painting the skin on
//            top and never suppressing the original draw. Kept as an opt-in
//            (iwpo.skins.overlay) for games whose Draw event renders more
//            than the player sprite (HUD, effects) and must keep running
//            while a skin is active.
// All run with self = the player instance: only built-in instance variables
// and the global skin mirror may be touched. No var keyword, matching the
// template convention (scratch values are @-prefixed instance variables).
// No template argument placeholders.
// NOTE: the facing/gravity multiplier block is shared verbatim by preempt
// and overlay - keep the two copies in sync.
// ============================================================================

///// mode replace
@st = -1;
if(global.@skinOn){
    @st = @skin_state_of(sprite_index);
}
if(@st >= 0){
    @f = image_index;
    if(!@skin_draw(@st, @f, x, y, image_xscale, image_yscale, image_angle, image_alpha, -1, c_white, 0)){
        @st = -1;
    }
}
if(@st < 0){
    // The engine's default draw silently draws NOTHING when the instance has
    // no sprite (some engines set sprite_index = -1 in special states);
    // draw_sprite_ext would raise "Trying to draw non-existing sprite", so
    // this guard is part of reproducing the default draw, not optional.
    if(sprite_exists(sprite_index)){
        draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, image_blend, image_alpha);
    }
}

///// mode preempt
@st = -1;
if(global.@skinOn){
    @st = @skin_state_of(sprite_index);
}
@skPre = 0;
if(@st >= 0){
    @f = image_index;
    // Facing/gravity multipliers mirror the broadcast matrix (worldEndStep.gml):
    // engines that draw the player with a custom facing variable (detected at
    // conversion time from the player Create event) need the same multiplier
    // here, otherwise the skin would not follow the game's own flip.
    // self = the player instance, so instance variables are referenced bare.
    #if GM8YY
        @xs = image_xscale*xScale;
        @ys = image_yscale*global.grav;
    #endif
    #if not GM8YY
        #if GLOBAL_PLAYER_XSCALE
            @xs = image_xscale*global.player_xscale;
        #endif
        #if not GLOBAL_PLAYER_XSCALE
            #if PLAYER_XSCALE
                @xs = image_xscale*xScale;
            #endif
            #if not PLAYER_XSCALE
                #if PLAYER_XSCALE_LOWER
                    @xs = image_xscale*xscale;
                #endif
                #if not PLAYER_XSCALE_LOWER
                    #if PLAYER_FACING
                        @xs = image_xscale*facing;
                    #endif
                    #if not PLAYER_FACING
                        @xs = image_xscale;
                    #endif
                #endif
            #endif
        #endif
        #if STUDIO
            #if GRAVITY
                @ys = image_yscale*global.grav;
            #endif
            #if not GRAVITY
                @ys = image_yscale;
            #endif
        #endif
        #if not STUDIO
            @ys = image_yscale;
        #endif
    #endif
    @skPre = @skin_draw(@st, @f, x, y, @xs, @ys, image_angle, image_alpha, -1, c_white, 0);
}

///// mode overlay
@st = -1;
if(global.@skinOn){
    @st = @skin_state_of(sprite_index);
}
if(@st >= 0){
    @f = image_index;
    // Facing/gravity multipliers mirror the broadcast matrix (worldEndStep.gml):
    // engines that draw the player with a custom facing variable (detected at
    // conversion time from the player Create event) need the same multiplier
    // here, otherwise the overlay would not follow the game's own flip.
    // self = the player instance, so instance variables are referenced bare.
    #if GM8YY
        @xs = image_xscale*xScale;
        @ys = image_yscale*global.grav;
    #endif
    #if not GM8YY
        #if GLOBAL_PLAYER_XSCALE
            @xs = image_xscale*global.player_xscale;
        #endif
        #if not GLOBAL_PLAYER_XSCALE
            #if PLAYER_XSCALE
                @xs = image_xscale*xScale;
            #endif
            #if not PLAYER_XSCALE
                #if PLAYER_XSCALE_LOWER
                    @xs = image_xscale*xscale;
                #endif
                #if not PLAYER_XSCALE_LOWER
                    #if PLAYER_FACING
                        @xs = image_xscale*facing;
                    #endif
                    #if not PLAYER_FACING
                        @xs = image_xscale;
                    #endif
                #endif
            #endif
        #endif
        #if STUDIO
            #if GRAVITY
                @ys = image_yscale*global.grav;
            #endif
            #if not GRAVITY
                @ys = image_yscale;
            #endif
        #endif
        #if not STUDIO
            @ys = image_yscale;
        #endif
    #endif
    @skin_draw(@st, @f, x, y, @xs, @ys, image_angle, image_alpha, -1, c_white, 0);
}
