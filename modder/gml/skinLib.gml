/// ONLINE
// ============================================================================
// Skin system script pack.
// The converter splits this file at the "///// script <name>" markers into
// standalone script assets (content before the first marker is dropped), so
// every section must be self-contained. No template argument placeholders.
//
// States: 0 idle, 1 run, 2 jump, 3 fall, 4 slide, 5 bow, 6 bullet.
// A skin is a subfolder of iwposkins\ holding info.ini plus one png per
// state (<state>.png: idle.png, run.png, jump.png, fall.png, slide.png,
// bow.png, bullet.png). info.ini sections: [skin] name/maker/source and one
// section per state with frames/framewidth/originx/originy.
//
// Calling context matters:
// - scan/parse/ensure_hash/select/clear/unload/prev_* run with self = the
//   world instance (they touch the world instance variables from
//   worldCreate.gml).
// - state_of/draw run with self = the player instance (injected Draw code),
//   so they may ONLY read the global mirror (global.__ONLINE_skin*).
// All scripts return an explicit value: GM8.0 errors when a caller uses the
// result of a script that never returns one.
// ============================================================================

///// script @skin_sec_names
// Fills @skSec[0..6] on the caller with the state names (ini sections and
// png file stems). Scripts share the caller's scope, so the caller sees the
// array after this returns.
@skSec[0] = "idle";
@skSec[1] = "run";
@skSec[2] = "jump";
@skSec[3] = "fall";
@skSec[4] = "slide";
@skSec[5] = "bow";
@skSec[6] = "bullet";
return 0;

///// script @skin_scan
// Enumerate iwposkins\ subfolders into @skinDir[] (lazy: info.ini is NOT
// parsed here). Rescans from scratch and fully initializes every slot it
// fills, so no create-time pre-initialization pass is needed (a fixed-cost
// pass over the 4096 slot cap would stall GM8 games that game_restart on
// every load). Every reader stays below @skinCount, and @skin_parse fills
// the per-state fields before they are read, so slots beyond the count are
// never touched uninitialized.
@skinCount = 0;
if(!directory_exists("iwposkins")){
    return 0;
}
@skBase = "iwposkins" + chr(92);
#if STUDIO
    // GMS: fa_directory lists files AND folders; keep only real folders.
    @skEntry = file_find_first(@skBase + "*", fa_directory);
    while(@skEntry != "" && @skinCount < 4096){
        if(@skEntry != "." && @skEntry != ".."){
            if(directory_exists(@skBase + @skEntry)){
                @skinDir[@skinCount] = @skEntry;
                @skinName[@skinCount] = "";
                @skinMaker[@skinCount] = "";
                @skinSource[@skinCount] = "";
                @skinHash[@skinCount] = "";
                @skinParsed[@skinCount] = 0;
                for(@skSt = 0; @skSt < 7; @skSt += 1){
                    @skinHas[@skinCount, @skSt] = 0;
                    @skinFrames[@skinCount, @skSt] = 0;
                    @skinFw[@skinCount, @skSt] = 32;
                    @skinOx[@skinCount, @skSt] = 17;
                    @skinOy[@skinCount, @skSt] = 23;
                }
                @skinCount += 1;
            }
        }
        @skEntry = file_find_next();
    }
    file_find_close();
#endif
#if not STUDIO
    // GM8: fa_directory lists folders only, no extra filter needed.
    @skEntry = file_find_first(@skBase + "*", fa_directory);
    while(@skEntry != "" && @skinCount < 4096){
        if(@skEntry != "." && @skEntry != ".."){
            @skinDir[@skinCount] = @skEntry;
            @skinName[@skinCount] = "";
            @skinMaker[@skinCount] = "";
            @skinSource[@skinCount] = "";
            @skinHash[@skinCount] = "";
            @skinParsed[@skinCount] = 0;
            for(@skSt = 0; @skSt < 7; @skSt += 1){
                @skinHas[@skinCount, @skSt] = 0;
                @skinFrames[@skinCount, @skSt] = 0;
                @skinFw[@skinCount, @skSt] = 32;
                @skinOx[@skinCount, @skSt] = 17;
                @skinOy[@skinCount, @skSt] = 23;
            }
            @skinCount += 1;
        }
        @skEntry = file_find_next();
    }
    file_find_close();
#endif
return @skinCount;

///// script @skin_parse
// argument0: skin index. Reads iwposkins\<dir>\info.ini once per skin
// (guarded by @skinParsed[]). Relative paths only: GM8.0 ini_open rejects
// absolute paths. Defaults: frames idle/run 4, jump/fall/slide 2, bow/bullet
// 1, framewidth 32, origin (17, 23); name falls back to the folder name.
@skI = argument0;
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
if(@skinParsed[@skI]){
    return 1;
}
@skinParsed[@skI] = 1;
@skin_sec_names();
@skBase = "iwposkins" + chr(92) + @skinDir[@skI] + chr(92);
@skinName[@skI] = @skinDir[@skI];
@skinMaker[@skI] = "";
@skinSource[@skI] = "";
@skHasIni = file_exists(@skBase + "info.ini");
if(@skHasIni){
#if STUDIO
    ini_open(@skBase + "info.ini");
#endif
#if not STUDIO
    // GM8 ini_open only accepts a flat file name in the working directory
    // (TheBiob skin_selector precedent), so bounce through a temp copy.
    file_copy(@skBase + "info.ini", "@skin_temp.ini");
    ini_open("@skin_temp.ini");
#endif
    @skinName[@skI] = ini_read_string("skin", "name", @skinDir[@skI]);
    @skinMaker[@skI] = ini_read_string("skin", "maker", "");
    @skinSource[@skI] = ini_read_string("skin", "source", "");
}
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skDef = 1;
    if(@skSt <= 1){
        @skDef = 4;
    }
    if(@skSt > 1 && @skSt <= 4){
        @skDef = 2;
    }
    if(@skHasIni){
        @skinFrames[@skI, @skSt] = floor(ini_read_real(@skSec[@skSt], "frames", @skDef));
        @skinFw[@skI, @skSt] = floor(ini_read_real(@skSec[@skSt], "framewidth", 32));
        @skinOx[@skI, @skSt] = floor(ini_read_real(@skSec[@skSt], "originx", 17));
        @skinOy[@skI, @skSt] = floor(ini_read_real(@skSec[@skSt], "originy", 23));
    }else{
        @skinFrames[@skI, @skSt] = @skDef;
        @skinFw[@skI, @skSt] = 32;
        @skinOx[@skI, @skSt] = 17;
        @skinOy[@skI, @skSt] = 23;
    }
    if(@skinFrames[@skI, @skSt] < 1) @skinFrames[@skI, @skSt] = 1;
    if(@skinFw[@skI, @skSt] < 1) @skinFw[@skI, @skSt] = 32;
    @skinHas[@skI, @skSt] = file_exists(@skBase + @skSec[@skSt] + ".png");
}
if(@skHasIni){
    ini_close();
#if not STUDIO
    file_delete("@skin_temp.ini");
#endif
}
return 1;

///// script @skin_ensure_hash
// argument0: skin index. Computes @skinHash[i] on first use (folder md5 via
// the md5 pack). Hashing is expensive; callers should only ask when needed.
@skI = argument0;
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
if(@skinHash[@skI] == ""){
    @skinHash[@skI] = @skin_hash_dir("iwposkins" + chr(92) + @skinDir[@skI] + chr(92));
}
return 1;

///// script @skin_select
// argument0: skin index. Unloads the current skin, loads every state the new
// skin ships (sprite_add in the 6-arg form both engines accept), mirrors to
// the global draw state and persists the selection by hash AND directory
// name; the dir name lets the next boot restore instantly (hash matching
// would re-hash every folder).
@skI = argument0;
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
@skin_unload();
@skin_parse(@skI);
@skin_ensure_hash(@skI);
@skin_sec_names();
@skBase = "iwposkins" + chr(92) + @skinDir[@skI] + chr(92);
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skinSpr[@skSt] = -1;
    if(@skinHas[@skI, @skSt]){
        @skPath = @skBase + @skSec[@skSt] + ".png";
        // 6-arg form on BOTH engines: GM8.0 rejects the 8-arg (preload) form,
        // same as TheBiob's skin_selector. PNG alpha loads fine either way.
        @skinSpr[@skSt] = sprite_add(@skPath, @skinFrames[@skI, @skSt], 0, 0, @skinOx[@skI, @skSt], @skinOy[@skI, @skSt]);
    }
}
@skinSel = @skI;
@skinLoaded = @skI;
@skin_mirror();
ini_open("@config.ini");
ini_write_string("config", "skin", @skinHash[@skI]);
ini_write_string("config", "skinDir", @skinDir[@skI]);
ini_close();
return 1;

///// script @skin_clear
// Drops the current skin selection and forgets it on disk.
@skin_unload();
@skinSel = -1;
@skinLoaded = -1;
@skin_mirror();
ini_open("@config.ini");
ini_write_string("config", "skin", "");
ini_write_string("config", "skinDir", "");
ini_close();
return 0;

///// script @skin_unload
// Frees every loaded sprite of the current selection and resets the slots.
for(@skSt = 0; @skSt < 7; @skSt += 1){
    if(@skinSpr[@skSt] >= 0){
        sprite_delete(@skinSpr[@skSt]);
        @skinSpr[@skSt] = -1;
    }
}
@skinLoaded = -1;
return 0;

///// script @skin_mirror
// Cheap per-frame sync of the selected skin into the global draw state that
// the injected player Draw code reads (player context cannot see the world
// instance variables). Early-out when no skin is selected.
global.@skinOn = 0;
if(@skinSel < 0){
    return 0;
}
global.@skinOn = 1;
for(@skSt = 0; @skSt < 7; @skSt += 1){
    global.@skinSpr[@skSt] = @skinSpr[@skSt];
    global.@skinFrames[@skSt] = @skinFrames[@skinSel, @skSt];
}
return 1;

///// script @skin_state_of
// argument0: game sprite index (the player's sprite_index). Returns the
// animation state 0-6 or -1 when the sprite is not mapped. Exact match
// against global.@mapSpr[0..6], unmapped slots (-1) are skipped.
for(@skSt = 0; @skSt < 7; @skSt += 1){
    if(global.@mapSpr[@skSt] >= 0){
        if(argument0 == global.@mapSpr[@skSt]){
            return @skSt;
        }
    }
}
return -1;

///// script @skin_draw
// Draws one skin frame. argument0: state, argument1: image_index,
// argument2/3: x/y, argument4/5: xscale/yscale, argument6: angle,
// argument7: alpha. Player context: reads only globals. Missing states
// fall back slide -> fall -> idle (the kid slides DOWN vines, so the upward
// jump pose is wrong; a state counts as missing when its mirrored sprite
// slot is empty, i.e. the skin has no such png or it failed to load).
// bow and bullet are optional states with NO fallback: when the slot is
// empty this returns 0 — a bow caller must draw nothing (a skin without
// bow.png is a character with no bow), a bullet caller must keep the game's
// original sprite. Returns 1 when something was drawn, 0 otherwise.
//
// Frame pacing keeps the ORIGINAL per-frame duration no matter how many
// frames the skin strip has (TheBiob skin_selector and IWSAP semantics: a
// 20-frame idle plays all 20 frames at the game's own image_speed instead of
// fast-forwarding the whole strip inside one original cycle). self is the
// player instance, so the accumulator naturally lives per player instance.
@skEff = argument0;
if(global.@skinSpr[@skEff] < 0){
    if(@skEff == 4) @skEff = 3;
}
if(global.@skinSpr[@skEff] < 0){
    if(argument0 >= 5) return 0;
    @skEff = 0;
}
if(global.@skinSpr[@skEff] < 0){
    return 0;
}
// Defense in depth: a mirrored id that no longer exists must degrade to the
// caller's fallback/original draw, not raise a hard sprite error.
if(!sprite_exists(global.@skinSpr[@skEff])){
    return 0;
}
@skFrames = floor(global.@skinFrames[@skEff]);
if(@skFrames < 1) @skFrames = 1;
// Per-frame-duration pacing accumulator (see header). GMS errors on reading
// an undefined instance variable, so initialize on first use (GMS1 removed
// the classic variable_exists, hence the engine split).
#if STUDIO
if(!variable_instance_exists(id, "@skinAnPos")){
#endif
#if not STUDIO
if(!variable_local_exists("@skinAnPos")){
#endif
    @skinAnPos = 0;
    @skinAnPrevImg = 0;
    @skinAnState = -1;
}
@skMap = floor(global.@mapFrames[argument0]);
if(@skMap < 1) @skMap = 1;
if(@skinAnState != argument0){
    // State change: enter the new strip at the proportional phase.
    @skinAnPos = argument1 * @skFrames / @skMap;
}else{
    @skDelta = argument1 - @skinAnPrevImg;
    if(@skDelta < 0) @skDelta += @skMap; // native image_index wrap
    if(@skDelta < 0 || @skDelta > @skMap){
        // The game set image_index by hand: resync proportionally.
        @skinAnPos = argument1 * @skFrames / @skMap;
    }else{
        @skinAnPos += @skDelta;
    }
}
@skinAnPrevImg = argument1;
@skinAnState = argument0;
@skFrame = floor(@skinAnPos) mod @skFrames;
draw_sprite_ext(global.@skinSpr[@skEff], @skFrame, argument2, argument3, argument4, argument5, argument6, c_white, argument7);
return 1;

///// script @skin_prev_load
// argument0: skin index. Loads the idle state of a skin into the menu
// preview slot (any previous preview content is dropped first).
@skI = argument0;
@skin_prev_unload();
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
@skin_parse(@skI);
if(@skinHas[@skI, 0]){
    @skPath = "iwposkins" + chr(92) + @skinDir[@skI] + chr(92) + "idle.png";
    // 6-arg form on both engines (see @skin_select).
    @skinPrevSpr[0] = sprite_add(@skPath, @skinFrames[@skI, 0], 0, 0, @skinOx[@skI, 0], @skinOy[@skI, 0]);
    // Mirror to a global so the world-Create restart cleanup can free the
    // sprite even after the world instance (and its variables) is gone
    // (GMS path; the GM8 cleanup sweeps the dynamic-sprite range instead).
    global.@skinPrevSpr[0] = @skinPrevSpr[0];
}
@skinPrevLoaded = @skI;
return 1;

///// script @skin_prev_unload
// Frees the menu preview slot (row change, tab switch or menu close).
for(@skSt = 0; @skSt < 7; @skSt += 1){
    if(@skinPrevSpr[@skSt] >= 0){
        sprite_delete(@skinPrevSpr[@skSt]);
        @skinPrevSpr[@skSt] = -1;
        global.@skinPrevSpr[@skSt] = -1;
    }
}
@skinPrevLoaded = -1;
return 0;
