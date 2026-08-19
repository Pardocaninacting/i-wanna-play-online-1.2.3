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
// - scan/parse/ensure_hash/select/clear/unload/prev_*/dl_* run with self =
//   the world instance (they touch the world instance variables from
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
// never touched uninitialized. Folders with no regular files are skipped:
// a wiped half-download leaves an empty folder behind (GM8.0 has no
// directory-delete), and it must never become a selectable entry.
// The reserved "Unknown" package (unknown-skin fallback for remote players)
// is moved to the LAST slot and excluded from @skinVisCount: the menu lists
// only [0, @skinVisCount), while hash matching and the fallback draw may use
// the full range.
@skinCount = 0;
@skinVisCount = 0;
@skinUnknown = -1;
@skHiddenDir = "";
@skListN = 0;
if(!directory_exists("iwposkins")){
    return 0;
}
@skBase = "iwposkins" + chr(92);
// Pass 1: collect subfolder names only. file_find has a single global search
// state on both engines, so the per-folder content check below cannot run
// inside this loop (it would clobber the enumeration).
#if STUDIO
    // GMS: fa_directory lists files AND folders; keep only real folders.
    @skEntry = file_find_first(@skBase + "*", fa_directory);
    while(@skEntry != "" && @skListN < 4096){
        if(@skEntry != "." && @skEntry != ".."){
            if(directory_exists(@skBase + @skEntry)){
                @skList[@skListN] = @skEntry;
                @skListN += 1;
            }
        }
        @skEntry = file_find_next();
    }
    file_find_close();
#endif
#if not STUDIO
    // GM8: fa_directory lists folders only, no extra filter needed.
    @skEntry = file_find_first(@skBase + "*", fa_directory);
    while(@skEntry != "" && @skListN < 4096){
        if(@skEntry != "." && @skEntry != ".."){
            @skList[@skListN] = @skEntry;
            @skListN += 1;
        }
        @skEntry = file_find_next();
    }
    file_find_close();
#endif
// Pass 2: keep only folders holding at least one regular file. A wiped
// half-download leaves an EMPTY folder behind (GM8.0 has no directory
// delete), and it must never be listed as a selectable skin.
for(@skI = 0; @skI < @skListN; @skI += 1){
    @skEntry = @skList[@skI];
    @skHasFile = false;
    @skE2 = file_find_first(@skBase + @skEntry + chr(92) + "*.*", 0);
    while(@skE2 != ""){
        if(!directory_exists(@skBase + @skEntry + chr(92) + @skE2)){
            @skHasFile = true;
            break;
        }
        @skE2 = file_find_next();
    }
    file_find_close();
    if(!@skHasFile){
        // empty folder: skip (an empty "unknown" is ignored too)
    }else if(string_lower(@skEntry) == "unknown"){
        @skHiddenDir = @skEntry;
    }else if(@skinCount < 4096){
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
// Reserved fallback package: last slot, hidden from the selectable list.
@skinVisCount = @skinCount;
if(@skHiddenDir != "" && @skinCount < 4096){
    @skinDir[@skinCount] = @skHiddenDir;
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
    @skinUnknown = @skinCount;
    @skinCount += 1;
}
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

///// script @skin_cache_load
// P0/P3: load the on-disk hash cache (iwposkins/skincache.txt) into memory
// once per world Create. Format: 3 lines per entry - dirname, hash (32 hex),
// fingerprint. The reverse hash->dirname lookup scans the in-memory table
// (the table is small); no second on-disk index is needed. A plain text file
// instead of ini: GM8.0 has NO ini_key_first/next (GM8.1+ only), and the
// file_text_* family exists on every supported engine. Reading 196 entries
// costs one open/read/close (~1-3ms) ONCE per game_restart; it replaces up to
// 196 x 25ms of pure-GML MD5. An unreadable/absent cache simply leaves the
// table empty (lookups fall back to hashing).
@skinCacheN = 0;
@skinCacheChanged = 0;
if(!file_exists("iwposkins" + chr(92) + "skincache.txt")){
    return 0;
}
@skcF = file_text_open_read("iwposkins" + chr(92) + "skincache.txt");
if(@skcF == -1){
    return 0;
}
while(!file_text_eof(@skcF) && @skinCacheN < 4096){
    @skcD = file_text_read_string(@skcF);
    file_text_readln(@skcF);
    @skcH = file_text_read_string(@skcF);
    file_text_readln(@skcF);
    @skcP = file_text_read_string(@skcF);
    file_text_readln(@skcF);
    // Sanity: a hash must be exactly 32 hex chars; anything else means the
    // file is truncated/corrupt, skip the entry (trailing blank lines read
    // back as empty strings and fail this too).
    if(string_length(@skcD) > 0 && string_length(@skcH) == 32){
        @skinCacheDir[@skinCacheN] = @skcD;
        @skinCacheHash[@skinCacheN] = @skcH;
        @skinCacheFp[@skinCacheN] = @skcP;
        @skinCacheN += 1;
    }
}
file_text_close(@skcF);
return @skinCacheN;

///// script @skin_cache_fp
// argument0: skin index. Computes the cheap fingerprint of the folder:
// "<fileCount>|<name>:<size>;..." over direct regular files. File sizes are
// read with file_size (no open); the list is sorted by the engine's string
// order for LOCAL determinism (the cache is per-machine, no cross-engine
// byte equality needed - the hash itself stays cross-engine). A changed
// file name/count/size changes the fingerprint and forces a re-hash; a
// content change that keeps every size identical is accepted as a miss
// (acceptable collision; selecting a skin re-hashes anyway).
@skcI = argument0;
if(@skcI < 0 || @skcI >= @skinCount){
    return "";
}
@skcPath = "iwposkins" + chr(92) + @skinDir[@skcI] + chr(92);
@skcN = 0;
@skcName = file_find_first(@skcPath + "*.*", 0);
while(@skcName != "" && @skcN < 64){
    if(!directory_exists(@skcPath + @skcName)){
        @skcNames[@skcN] = @skcName;
        @skcN += 1;
    }
    @skcName = file_find_next();
}
file_find_close();
// insertion sort by the engine's string order (local determinism only)
for(@skcI2 = 1; @skcI2 < @skcN; @skcI2 += 1){
    @skcTmp = @skcNames[@skcI2];
    @skcJ = @skcI2;
    while(@skcJ > 0 && @skcNames[@skcJ - 1] > @skcTmp){
        @skcNames[@skcJ] = @skcNames[@skcJ - 1];
        @skcJ -= 1;
    }
    @skcNames[@skcJ] = @skcTmp;
}
@skcFp = string(@skcN) + "|";
for(@skcI2 = 0; @skcI2 < @skcN; @skcI2 += 1){
    // GM8.0 has no file_size (8.1+); file_bin_open+file_bin_size is the
    // proven-8.0 way (md5.gml already reads files through file_bin_*).
    @skcSize = -1;
    @skcFull = @skcPath + @skcNames[@skcI2];
    if(file_exists(@skcFull)){
        @skcFs = file_bin_open(@skcFull, 0);
        if(@skcFs >= 0){
            @skcSize = file_bin_size(@skcFs);
            file_bin_close(@skcFs);
        }
    }
    @skcFp += @skcNames[@skcI2] + ":" + string(@skcSize) + ";";
}
return @skcFp;

///// script @skin_cache_lookup
// argument0: skin index. Returns the cached hash when the fingerprint still
// matches, "" otherwise (caller falls back to the real hashing).
@skcI = argument0;
@skcFp = @skin_cache_fp(@skcI);
if(@skcFp == ""){
    return "";
}
for(@skcI2 = 0; @skcI2 < @skinCacheN; @skcI2 += 1){
    if(@skinCacheDir[@skcI2] == @skinDir[@skcI]){
        if(@skinCacheFp[@skcI2] == @skcFp){
            return @skinCacheHash[@skcI2];
        }
        return "";
    }
}
return "";

///// script @skin_cache_add
// argument0: skin index (hash already computed into @skinHash[i]).
// Adds/updates both cache tables in memory and marks the cache changed; the
// on-disk flush happens once in @skin_cache_flush (world Game End).
@skcI = argument0;
@skcFp = @skin_cache_fp(@skcI);
if(@skcFp == ""){
    return 0;
}
@skcFound = 0;
for(@skcI2 = 0; @skcI2 < @skinCacheN; @skcI2 += 1){
    if(@skinCacheDir[@skcI2] == @skinDir[@skcI]){
        @skinCacheHash[@skcI2] = @skinHash[@skcI];
        @skinCacheFp[@skcI2] = @skcFp;
        @skcFound = 1;
        break;
    }
}
if(!@skcFound && @skinCacheN < 4096){
    @skinCacheDir[@skinCacheN] = @skinDir[@skcI];
    @skinCacheHash[@skinCacheN] = @skinHash[@skcI];
    @skinCacheFp[@skinCacheN] = @skcFp;
    @skinCacheN += 1;
}
@skinCacheChanged = 1;
return 1;

///// script @skin_cache_flush
// world Game End: persist the in-memory tables when anything changed
// (3-line records, see @skin_cache_load). A full rewrite (~196 records)
// takes ~1-5ms, which is invisible during the game_restart load that
// triggers this event.
if(!@skinCacheChanged){
    return 0;
}
@skinCacheChanged = 0;
@skcF = file_text_open_write("iwposkins" + chr(92) + "skincache.txt");
if(@skcF == -1){
    return 0;
}
for(@skcI2 = 0; @skcI2 < @skinCacheN; @skcI2 += 1){
    file_text_write_string(@skcF, @skinCacheDir[@skcI2]);
    file_text_writeln(@skcF);
    file_text_write_string(@skcF, @skinCacheHash[@skcI2]);
    file_text_writeln(@skcF);
    file_text_write_string(@skcF, @skinCacheFp[@skcI2]);
    file_text_writeln(@skcF);
}
file_text_close(@skcF);
return 1;

///// script @skin_ensure_hash
// argument0: skin index. Computes @skinHash[i] on first use (folder md5 via
// the md5 pack). Hashing is expensive; callers should only ask when needed.
// P0/P3: a matching on-disk cache entry (same dirname + file fingerprint)
// short-circuits the MD5 entirely - the per-death game_restart cost goes
// from N x 25ms to one ini parse.
@skI = argument0;
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
if(@skinHash[@skI] == ""){
    @skcHit = @skin_cache_lookup(@skI);
    if(@skcHit != ""){
        @skinHash[@skI] = @skcHit;
    }else{
        @skinHash[@skI] = @skin_hash_dir("iwposkins" + chr(92) + @skinDir[@skI] + chr(92));
        if(@skinHash[@skI] != ""){
            @skin_cache_add(@skI);
        }
    }
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
// P4: adopt sprites kept across game_restart when their recorded content hash
// still equals the hash of the skin being restored; otherwise free them and
// load normally. The kept set is consumed exactly once (the boot restore is
// the first select of a world lifetime).
@skReuseOk = 0;
if(@skReuseArmed){
    if(@skReuseHash == @skinHash[@skI]){
        @skReuseOk = 1;
    }else{
        for(@skR = 0; @skR < 7; @skR += 1){
            if(@skReuseSpr[@skR] >= 0){
                if(sprite_exists(@skReuseSpr[@skR])){
                    sprite_delete(@skReuseSpr[@skR]);
                }
            }
        }
    }
    @skReuseArmed = 0;
    @skReuseHash = "";
}
@skBase = "iwposkins" + chr(92) + @skinDir[@skI] + chr(92);
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skinSpr[@skSt] = -1;
    if(@skReuseOk){
        @skinSpr[@skSt] = @skReuseSpr[@skSt];
        if(@skinSpr[@skSt] >= 0){
            if(!sprite_exists(@skinSpr[@skSt])){
                @skinSpr[@skSt] = -1;
            }
        }
        if(@skinSpr[@skSt] < 0 && @skinHas[@skI, @skSt]){
            @skPath = @skBase + @skSec[@skSt] + ".png";
            @skinSpr[@skSt] = sprite_add(@skPath, @skinFrames[@skI, @skSt], 0, 0, @skinOx[@skI, @skSt], @skinOy[@skI, @skSt]);
        }
    }else if(@skinHas[@skI, @skSt]){
        @skPath = @skBase + @skSec[@skSt] + ".png";
        // 6-arg form on BOTH engines: GM8.0 rejects the 8-arg (preload) form,
        // same as TheBiob's skin_selector. PNG alpha loads fine either way.
        @skinSpr[@skSt] = sprite_add(@skPath, @skinFrames[@skI, @skSt], 0, 0, @skinOx[@skI, @skSt], @skinOy[@skI, @skSt]);
    }
}
@skinSel = @skI;
@skinLoaded = @skI;
@skin_mirror();
@skin_spr_save();
@skinNetDirty = true;
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
@skin_spr_save();
@skinNetDirty = true;
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

///// script @skin_spr_save
// Persists every sprite this process created with sprite_add as
// id,width,height,frames, so the next world Create can free exactly those
// after a game_restart instead of sweeping the whole dynamic-sprite range
// (which also hits sprites the GAME created at runtime). The extra fields let
// the reader reject a leftover list from a previous process: sprite_add hands
// out the same ids every run, so id alone would false-positive on a fresh
// launch. Call after any batch that adds or frees skin sprites; world
// context, own variable names so callers' loops survive.
@skSvList = "";
for(@skSvSt = 0; @skSvSt < 7; @skSvSt += 1){
    if(@skinSpr[@skSvSt] >= 0) @skSvList += @skin_spr_rec(@skinSpr[@skSvSt]);
    if(@skinPrevSpr[@skSvSt] >= 0) @skSvList += @skin_spr_rec(@skinPrevSpr[@skSvSt]);
}
for(@skSvSlot = 0; @skSvSlot < global.@rskCount; @skSvSlot += 1){
    for(@skSvSt = 0; @skSvSt < 7; @skSvSt += 1){
        if(global.@rskSpr[@skSvSlot, @skSvSt] >= 0) @skSvList += @skin_spr_rec(global.@rskSpr[@skSvSlot, @skSvSt]);
    }
}
// P4: the selected-skin sprites are recorded WITH their content hash so the
// next world Create can keep them across game_restart instead of paying
// 7x sprite_delete + 7x sprite_add (~6-7ms) on every death. Record shape:
// "hash;id,state,width,height,frames;..." (state 0-6). Validation on the
// read side re-checks id/width/height/frames, and @skin_select re-checks the
// hash against the skin being restored, so a stale record can never adopt a
// wrong sprite.
@skSelRec = "";
// GM8.0 does NOT short-circuit boolean && - nesting the guards is required so
// @skinHash[@skinSel] is never evaluated with @skinSel < 0 (no skin selected
// -> Negative array index crash on menu preview open / boot with skin= empty).
if(@skinSel >= 0){
    if(@skinSel < @skinCount){
        if(@skinHash[@skinSel] != ""){
            @skSelRec = @skinHash[@skinSel];
            for(@skSvSt = 0; @skSvSt < 7; @skSvSt += 1){
                if(@skinSpr[@skSvSt] >= 0){
                    if(sprite_exists(@skinSpr[@skSvSt])){
                        @skSelRec += ";" + string(@skinSpr[@skSvSt]) + "," + string(@skSvSt) + "," + string(sprite_get_width(@skinSpr[@skSvSt])) + "," + string(sprite_get_height(@skinSpr[@skSvSt])) + "," + string(sprite_get_number(@skinSpr[@skSvSt]));
                    }
                }
            }
        }
    }
}
ini_open("@config.ini");
ini_write_string("config", "skinSprIds", @skSvList);
ini_write_string("config", "skinSelSprites", @skSelRec);
ini_close();
return 0;

///// script @skin_spr_rec
// argument0: a sprite id. Returns its "id,width,height,frames," record, or ""
// when the sprite is gone.
if(!sprite_exists(argument0)){
    return "";
}
return string(argument0) + "," + string(sprite_get_width(argument0)) + "," + string(sprite_get_height(argument0)) + "," + string(sprite_get_number(argument0)) + ",";

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
// argument7: alpha, argument8: source slot (-1 = the selected-skin global
// mirror, 0-31 = a remote-player slot). Caller context reads only globals.
// Missing states fall back slide -> fall -> idle (the kid slides DOWN vines,
// so the upward jump pose is wrong; a state counts as missing when its
// mirrored sprite slot is empty, i.e. the skin has no such png or it failed
// to load). bow and bullet are optional states with NO fallback: when the
// slot is empty this returns 0 — a bow caller must draw nothing (a skin
// without bow.png is a character with no bow), a bullet caller must keep
// the game's original sprite. Returns 1 when something was drawn, 0
// otherwise.
//
// Frame pacing keeps the ORIGINAL per-frame duration no matter how many
// frames the skin strip has (TheBiob skin_selector and IWSAP semantics: a
// 20-frame idle plays all 20 frames at the game's own image_speed instead of
// fast-forwarding the whole strip inside one original cycle). The
// accumulator lives on the CALLER instance (player or onlinePlayer), so
// every instance paces independently.
@skSlot = floor(argument8);
@skEff = argument0;
if(@skin_slot_spr(@skSlot, @skEff) < 0){
    if(@skEff == 4) @skEff = 3;
}
if(@skin_slot_spr(@skSlot, @skEff) < 0){
    if(argument0 >= 5) return 0;
    @skEff = 0;
}
@skSprId = @skin_slot_spr(@skSlot, @skEff);
if(@skSprId < 0){
    return 0;
}
// Defense in depth: a mirrored id that no longer exists must degrade to the
// caller's fallback/original draw, not raise a hard sprite error.
if(!sprite_exists(@skSprId)){
    return 0;
}
if(@skSlot < 0){
    @skFrames = floor(global.@skinFrames[@skEff]);
}else{
    @skFrames = floor(global.@rskFrames[@skSlot, @skEff]);
}
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
draw_sprite_ext(@skSprId, @skFrame, argument2, argument3, argument4, argument5, argument6, c_white, argument7);
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
@skin_spr_save();
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
@skin_spr_save();
return 0;

///// script @skin_slot_spr
// argument0: source slot (-1 = selected-skin global mirror, 0-31 = remote
// slot), argument1: state. Returns the mirrored sprite id (or -1).
if(argument0 < 0){
    return global.@skinSpr[argument1];
}
return global.@rskSpr[argument0, argument1];

///// script @skin_resolve
// argument0: hash hex. Returns the local skin index among ALREADY-COMPUTED
// hashes only (never hashes here); -1 when not yet known. P3: the in-memory
// cache table answers hash->dirname in O(1)-ish; a hit fills @skinHash[i]
// WITHOUT hashing (the cached hash came from a verified computation), so a
// peer with a renamed folder (hint miss) resolves instantly instead of
// queueing a 25ms MD5 scan.
for(@skcI2 = 0; @skcI2 < @skinCacheN; @skcI2 += 1){
    if(@skinCacheHash[@skcI2] == argument0){
        for(@skI = 0; @skI < @skinCount; @skI += 1){
            if(@skinDir[@skI] == @skinCacheDir[@skcI2]){
                @skinHash[@skI] = argument0;
                return @skI;
            }
        }
        return -1;
    }
}
for(@skI = 0; @skI < @skinCount; @skI += 1){
    if(@skinHash[@skI] != ""){
        if(@skinHash[@skI] == argument0){
            return @skI;
        }
    }
}
return -1;

///// script @skin_slot_load
// argument0: remote slot (0-31), argument1: local skin index. Loads every
// state the skin ships into the global remote slot (6-arg sprite_add on both
// engines, same as @skin_select). Returns 1 on success, 0 on bad args.
@skSlot = floor(argument0);
@skI = floor(argument1);
if(@skSlot < 0 || @skSlot >= 32){
    return 0;
}
if(@skI < 0 || @skI >= @skinCount){
    return 0;
}
@skin_parse(@skI);
@skin_sec_names();
@skBase = "iwposkins" + chr(92) + @skinDir[@skI] + chr(92);
for(@skSt = 0; @skSt < 7; @skSt += 1){
    global.@rskSpr[@skSlot, @skSt] = -1;
    global.@rskFrames[@skSlot, @skSt] = 0;
    if(@skinHas[@skI, @skSt]){
        global.@rskSpr[@skSlot, @skSt] = sprite_add(@skBase + @skSec[@skSt] + ".png", @skinFrames[@skI, @skSt], 0, 0, @skinOx[@skI, @skSt], @skinOy[@skI, @skSt]);
        global.@rskFrames[@skSlot, @skSt] = @skinFrames[@skI, @skSt];
    }
}
@skin_spr_save();
return 1;

///// script @skin_slot_acquire
// argument0: local skin index, argument1: hash hex. Returns the remote slot
// holding that skin's sprites (loading on first use), or -1 when all slots
// are taken. Slot 0 is the reserved "Unknown" fallback and never recycled.
// Released slots (empty hash) are reused before growing: a peer cycling
// through skins must not exhaust the fixed slot pool.
for(@skSlot = 1; @skSlot < global.@rskCount; @skSlot += 1){
    if(global.@rskHash[@skSlot] == argument1){
        return @skSlot;
    }
}
@skHole = 0;
for(@skSlot = 1; @skSlot < global.@rskCount; @skSlot += 1){
    if(global.@rskHash[@skSlot] == ""){
        @skHole = @skSlot;
        break;
    }
}
if(@skHole > 0){
    @skSlot = @skHole;
}else{
    if(global.@rskCount >= 32){
        return -1;
    }
    @skSlot = global.@rskCount;
    global.@rskCount += 1;
}
if(!@skin_slot_load(@skSlot, argument0)){
    return -1;
}
global.@rskHash[@skSlot] = argument1;
return @skSlot;

///// script @skin_slot_release
// argument0: an onlinePlayer instance, argument1: the remote slot it is
// giving up. Frees the slot's sprites when no OTHER onlinePlayer still uses
// that slot, so a peer cycling through skins (or leaving) cannot exhaust
// the fixed pool. Slot 0 (the Unknown fallback) is never freed. World
// context.
@skP = argument0;
@skSlot = floor(argument1);
if(@skSlot <= 0){
    return 0;
}
for(@skI = 0; @skI < instance_number(@onlinePlayer); @skI += 1){
    @skQ = instance_find(@onlinePlayer, @skI);
    if(@skQ != @skP){
        if(@skQ.@skinSlot == @skSlot){
            return 0;
        }
    }
}
for(@skSt = 0; @skSt < 7; @skSt += 1){
    if(global.@rskSpr[@skSlot, @skSt] >= 0){
        if(sprite_exists(global.@rskSpr[@skSlot, @skSt])){
            sprite_delete(global.@rskSpr[@skSlot, @skSt]);
        }
    }
    global.@rskSpr[@skSlot, @skSt] = -1;
    global.@rskFrames[@skSlot, @skSt] = 0;
}
global.@rskHash[@skSlot] = "";
@skin_spr_save();
return 1;

///// script @skin_remote_unknown
// argument0: an onlinePlayer instance whose hash failed local resolution.
// Marks it explicitly-missing. With auto-download on, the hash is queued for
// a server fetch instead of an immediate chat notice (a notice is pushed only
// when the download later fails or cannot be queued); with auto-download off,
// a one-per-hash local chat notice is pushed right away.
// World context (touches the chat history arrays).
@skP = argument0;
@skP.@skinState = 3;
@skP.@skinSlot = -1;
@skHash = @skP.@skinHash;
for(@skH = 0; @skH < 8; @skH += 1){
    if(@skinHint[@skH] == @skHash){
        return 0;
    }
}
@skinHint[@skinHintNext] = @skHash;
@skinHintNext = (@skinHintNext + 1) mod 8;
if(@skinAutoDL){
    @skHint2 = "";
    if(ds_map_exists(@skinMapHint, @skP.@ID)){
        @skHint2 = ds_map_find_value(@skinMapHint, @skP.@ID);
    }
    if(@skin_dl_enqueue(@skHash, @skHint2) > 0){
        return 1;
    }
    // Queue full or already failed this session: fall through to the notice.
}
@skMsg = "Skin missing for " + @skP.@name + " (" + string_copy(@skHash, 1, 8) + ")";
if(@chatHistCount < @chatHistMax){
    @chatHistName[@chatHistCount] = "SKIN";
    @chatHistMsg[@chatHistCount] = @skMsg;
    @chatHistTeam[@chatHistCount] = @skP.@team;
    @chatHistCount += 1;
}else{
    for(@ci = 0; @ci < @chatHistMax - 1; @ci += 1){
        @chatHistName[@ci] = @chatHistName[@ci + 1];
        @chatHistMsg[@ci] = @chatHistMsg[@ci + 1];
        @chatHistTeam[@ci] = @chatHistTeam[@ci + 1];
    }
    @chatHistName[@chatHistMax - 1] = "SKIN";
    @chatHistMsg[@chatHistMax - 1] = @skMsg;
    @chatHistTeam[@chatHistMax - 1] = @skP.@team;
}
return 1;

///// script @skin_apply_remote
// argument0: an onlinePlayer instance. Re-evaluates that player's remote
// skin from @skinMap (playerId -> hash hex). Call right after the instance's
// @ID is (re)assigned and from the SKIN_NOTIFY handler. World context.
// The slot the player used before is released whenever the re-evaluation
// moves it to a different slot (or none), keeping the pool recyclable.
@skP = argument0;
@skOldSlot = @skP.@skinSlot;
@skP.@skinSlot = -1;
if(!ds_map_exists(@skinMap, @skP.@ID)){
    @skP.@skinHash = "";
    @skP.@skinState = 0;
    if(@skOldSlot > 0){
        @skin_slot_release(@skP, @skOldSlot);
    }
    return 0;
}
@skP.@skinHash = ds_map_find_value(@skinMap, @skP.@ID);
// Fast path: the sender's directory name hint usually hits the identical
// bundled package - verify with a single hash computation.
@skNIdx = -1;
if(ds_map_exists(@skinMapHint, @skP.@ID)){
    @skNHint = ds_map_find_value(@skinMapHint, @skP.@ID);
    for(@skI = 0; @skI < @skinCount; @skI += 1){
        if(@skinDir[@skI] == @skNHint){
            @skin_ensure_hash(@skI);
            if(@skinHash[@skI] == @skP.@skinHash){
                @skNIdx = @skI;
            }
            break;
        }
    }
}
if(@skNIdx < 0){
    @skNIdx = @skin_resolve(@skP.@skinHash);
}
if(@skNIdx >= 0){
    @skP.@skinSlot = @skin_slot_acquire(@skNIdx, @skP.@skinHash);
    if(@skP.@skinSlot < 0){
        @skP.@skinState = 3; // remote slots exhausted: explicit missing
    }else{
        @skP.@skinState = 2;
    }
}else if(@skinHashScan >= @skinCount){
    @skin_remote_unknown(@skP);
}else{
    @skP.@skinState = 1; // pending the background hash scan
}
if(@skOldSlot > 0){
    if(@skP.@skinSlot != @skOldSlot){
        @skin_slot_release(@skP, @skOldSlot);
    }
}
return 1;

///// script @skin_net_send
// Writes SKIN (opcode 12: 16-byte hash + directory-name hint; all-zero hash
// = no skin) into @buffer and sends it. World context; the caller
// (worldEndStep) guarantees the socket is connected.
__ONLINE_buffer_clear(@buffer);
#if not GMNET
    __ONLINE_buffer_write_uint8(@buffer, 12);
#endif
#if GMNET
    __ONLINE_buffer_write_u8(@buffer, 12);
#endif
@skHex = "";
@skHint = "";
if(@skinSel >= 0){
    @skHex = string_lower(@skinHash[@skinSel]);
    @skHint = @skinDir[@skinSel];
}
for(@skB = 0; @skB < 16; @skB += 1){
    @skByte = 0;
    if(@skHex != ""){
        @skByte = (string_pos(string_char_at(@skHex, @skB * 2 + 1), "0123456789abcdef") - 1) * 16 + string_pos(string_char_at(@skHex, @skB * 2 + 2), "0123456789abcdef") - 1;
    }
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, @skByte);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, @skByte);
    #endif
}
__ONLINE_buffer_write_string(@buffer, @skHint);
__ONLINE_socket_write_message(@socket, @buffer);
return 0;

///// script @skin_dl_sanitize
// argument0: a directory-name hint (from the remote player's SKIN_NOTIFY).
// Returns a name safe to create inside iwposkins\: whitelist [A-Za-z0-9._-],
// max 48 chars, no pure-dot names, no ".." sequences, and never the reserved
// "unknown" (that folder is the hidden fallback package). "" = unusable.
@skS = "";
@skNonDot = 0;
for(@skI = 1; @skI <= string_length(argument0); @skI += 1){
    @skO = ord(string_char_at(argument0, @skI));
    if((@skO >= 65 && @skO <= 90) || (@skO >= 97 && @skO <= 122) || (@skO >= 48 && @skO <= 57) || @skO == 95 || @skO == 45 || @skO == 46){
        @skS += string_char_at(argument0, @skI);
        if(@skO != 46) @skNonDot += 1;
    }
    if(string_length(@skS) >= 48) break;
}
if(@skNonDot < 1) return "";
if(string_pos("..", @skS) > 0) return "";
if(string_lower(@skS) == "unknown") return "";
return @skS;

///// script @skin_dl_name_ok
// argument0: a file name from a SKIN_MANIFEST reply. Whitelist
// [A-Za-z0-9._-], length 1-64, no "."/".." names and no ".." anywhere:
// downloaded files must stay flat inside the package directory.
@skNL = string_length(argument0);
if(@skNL < 1 || @skNL > 64) return 0;
if(argument0 == ".") return 0;
if(string_pos("..", argument0) > 0) return 0;
for(@skI = 1; @skI <= @skNL; @skI += 1){
    @skO = ord(string_char_at(argument0, @skI));
    if((@skO >= 65 && @skO <= 90) || (@skO >= 97 && @skO <= 122) || (@skO >= 48 && @skO <= 57) || @skO == 95 || @skO == 45 || @skO == 46){
        // allowed
    }else{
        return 0;
    }
}
return 1;

///// script @skin_dl_notice
// argument0: message. Pushes a local "SKIN" chat-history entry (same ring
// logic as the notice half of @skin_remote_unknown, without a player).
if(@chatHistCount < @chatHistMax){
    @chatHistName[@chatHistCount] = "SKIN";
    @chatHistMsg[@chatHistCount] = argument0;
    @chatHistTeam[@chatHistCount] = 0;
    @chatHistCount += 1;
}else{
    for(@ci = 0; @ci < @chatHistMax - 1; @ci += 1){
        @chatHistName[@ci] = @chatHistName[@ci + 1];
        @chatHistMsg[@ci] = @chatHistMsg[@ci + 1];
        @chatHistTeam[@ci] = @chatHistTeam[@ci + 1];
    }
    @chatHistName[@chatHistMax - 1] = "SKIN";
    @chatHistMsg[@chatHistMax - 1] = argument0;
    @chatHistTeam[@chatHistMax - 1] = 0;
}
return 1;

///// script @skin_dl_wipe
// argument0: a directory name inside iwposkins\. Deletes every regular file
// in it. The (now empty) directory itself stays behind: GM8.0 has no
// directory-delete function, and @skin_scan skips empty folders anyway, so
// the leftover is invisible. Missing directories are fine. Names with path
// separators or ".." are refused (the name normally comes from
// @skin_dl_sanitize or the "dl_<hex>" fallback, but the boot-time stale
// cleanup passes a value read back from the ini).
if(argument0 == "") return 0;
if(string_pos("/", argument0) > 0) return 0;
if(string_pos(chr(92), argument0) > 0) return 0;
if(string_pos("..", argument0) > 0) return 0;
@skWBase = "iwposkins" + chr(92) + argument0;
if(!directory_exists(@skWBase)) return 0;
@skWBase += chr(92);
@skWE = file_find_first(@skWBase + "*.*", 0);
while(@skWE != ""){
    if(!directory_exists(@skWBase + @skWE)){
        file_delete(@skWBase + @skWE);
    }
    @skWE = file_find_next();
}
file_find_close();
// The empty folder itself stays behind (see the header comment).
return 1;

///// script @skin_dl_enqueue
// argument0: hash hex, argument1: directory-name hint. Queues the package for
// download from the server skin library. Returns 1 when newly queued, 2 when
// already pending (queued or in flight), 0 when rejected (download of this
// hash already failed this session, or the 8-slot queue is full - the caller
// should surface the plain missing-notice then).
if(@skinDlHash == argument0) return 2;
for(@skI = 0; @skI < @skinDlQCount; @skI += 1){
    if(@skinDlQ[@skI] == argument0) return 2;
}
for(@skI = 0; @skI < 16; @skI += 1){
    if(@skinDlFail[@skI] == argument0) return 0;
}
if(@skinDlQCount >= 8) return 0;
@skinDlQ[@skinDlQCount] = argument0;
@skinDlQHint[@skinDlQCount] = argument1;
@skinDlQCount += 1;
return 1;

///// script @skin_dl_send_req
// Writes SKIN_GET (opcode 14) or SKIN_FILE_REQ (16) into @buffer and sends
// it. argument0: opcode, argument1: hash hex, argument2: file name (""
// omits the name field - SKIN_GET carries none). World context; the caller
// guarantees the socket is connected. Safe to call from inside the message
// read loop: @buffer is reloaded by the next read_message (case 5 precedent).
__ONLINE_buffer_clear(@buffer);
#if not GMNET
    __ONLINE_buffer_write_uint8(@buffer, argument0);
#endif
#if GMNET
    __ONLINE_buffer_write_u8(@buffer, argument0);
#endif
for(@skB = 0; @skB < 16; @skB += 1){
    @skByte = (string_pos(string_char_at(argument1, @skB * 2 + 1), "0123456789abcdef") - 1) * 16 + string_pos(string_char_at(argument1, @skB * 2 + 2), "0123456789abcdef") - 1;
    #if not GMNET
        __ONLINE_buffer_write_uint8(@buffer, @skByte);
    #endif
    #if GMNET
        __ONLINE_buffer_write_u8(@buffer, @skByte);
    #endif
}
if(argument2 != ""){
    __ONLINE_buffer_write_string(@buffer, argument2);
}
__ONLINE_socket_write_message(@socket, @buffer);
return 0;

///// script @skin_dl_begin
// Pops the download queue head and requests its manifest from the server.
// Returns 1 when a SKIN_GET was sent, 0 when staying idle (queue empty or
// socket not connected). The in-flight directory is recorded in the ini
// (skinDlTmp) so a crash or game_restart mid-download can be cleaned up at
// the next boot - a half-written package must never enter the library.
if(@skinDlState != 0) return 0;
if(@skinDlQCount < 1) return 0;
if(!@connected) return 0;
if(__ONLINE_socket_get_state(@socket) != 2) return 0;
@skinDlHash = @skinDlQ[0];
@skinDlHint = @skinDlQHint[0];
for(@skI = 1; @skI < @skinDlQCount; @skI += 1){
    @skinDlQ[@skI - 1] = @skinDlQ[@skI];
    @skinDlQHint[@skI - 1] = @skinDlQHint[@skI];
}
@skinDlQCount -= 1;
@skinDlQ[@skinDlQCount] = "";
@skinDlQHint[@skinDlQCount] = "";
// Target directory: the sanitized hint, unless that folder already exists
// (same-named different package - identical content would have resolved
// locally and never queued); the hash-derived name is the fallback.
@skinDlDir = @skin_dl_sanitize(@skinDlHint);
if(@skinDlDir == ""){
    @skinDlDir = "dl_" + string_copy(@skinDlHash, 1, 16);
}
if(directory_exists("iwposkins" + chr(92) + @skinDlDir)){
    @skinDlDir = "dl_" + string_copy(@skinDlHash, 1, 16);
}
// Wipe a stale partial of a previous attempt, then (re)create the folder.
@skin_dl_wipe(@skinDlDir);
if(!directory_exists("iwposkins")){
    directory_create("iwposkins");
}
directory_create("iwposkins" + chr(92) + @skinDlDir);
ini_open("@config.ini");
ini_write_string("config", "skinDlTmp", @skinDlDir);
ini_close();
__ONLINE_buffer_clear(@dlBuffer);
@skinDlCount = 0;
@skinDlIdx = 0;
@skinDlPos = 0;
@skinDlFile = -1;
@skin_dl_send_req(14, @skinDlHash, "");
@skinDlState = 1;
@skinDlWait = room_speed * 30;
return 1;

///// script @skin_dl_requeue
// The connection was (re)established while a download was in flight: the
// in-flight request died with the old socket, so put the package back at the
// queue tail (silently - this is not a failure) and reset the transfer
// state. The partial directory is wiped; the restarted download re-creates
// it. Called from worldEndStep's (re)connect path.
if(@skinDlState == 0) return 0;
if(@skinDlFile >= 0){
    file_bin_close(@skinDlFile);
    @skinDlFile = -1;
}
@skin_dl_wipe(@skinDlDir);
ini_open("@config.ini");
ini_write_string("config", "skinDlTmp", "");
ini_close();
if(@skinDlQCount < 8){
    @skinDlQ[@skinDlQCount] = @skinDlHash;
    @skinDlQHint[@skinDlQCount] = @skinDlHint;
    @skinDlQCount += 1;
}
@skinDlState = 0;
@skinDlHash = "";
@skinDlHint = "";
@skinDlDir = "";
@skinDlCount = 0;
@skinDlIdx = 0;
@skinDlPos = 0;
__ONLINE_buffer_clear(@dlBuffer);
return 1;

///// script @skin_dl_fail
// argument0: chat notice text ("" = silent). Wipes the partial directory,
// remembers the hash in the 16-entry failure ring (no automatic retries this
// session) and resets the transfer state.
if(@skinDlFile >= 0){
    file_bin_close(@skinDlFile);
    @skinDlFile = -1;
}
@skin_dl_wipe(@skinDlDir);
ini_open("@config.ini");
ini_write_string("config", "skinDlTmp", "");
ini_close();
@skinDlDir = "";
if(@skinDlHash != ""){
    @skKnown = false;
    for(@skI = 0; @skI < 16; @skI += 1){
        if(@skinDlFail[@skI] == @skinDlHash) @skKnown = true;
    }
    if(!@skKnown){
        @skinDlFail[@skinDlFailNext] = @skinDlHash;
        @skinDlFailNext = (@skinDlFailNext + 1) mod 16;
    }
    if(argument0 != ""){
        @skin_dl_notice(argument0);
    }
}
@skinDlState = 0;
@skinDlHash = "";
@skinDlHint = "";
@skinDlCount = 0;
@skinDlIdx = 0;
@skinDlPos = 0;
__ONLINE_buffer_clear(@dlBuffer);
return 0;

///// script @skin_dl_finish
// All files received: re-hash the assembled directory and compare against
// the requested hash (integrity check - a mismatch wipes the package and
// reports failure). On success the skin is registered into the library,
// inserted before the hidden "Unknown" slot so it becomes menu-visible, and
// every remote player waiting on this hash is re-evaluated.
@skFHash = @skin_hash_dir("iwposkins" + chr(92) + @skinDlDir + chr(92));
if(@skFHash != @skinDlHash){
    @skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
    return 0;
}
// Verified on disk: no longer a partial, so clear the crash-cleanup marker
// BEFORE registering (a crash after this point leaves a complete package).
ini_open("@config.ini");
ini_write_string("config", "skinDlTmp", "");
ini_close();
// Make room right before the hidden Unknown slot (kept last) or append.
@skFIdx = @skinCount;
if(@skinUnknown >= 0){
    @skFIdx = @skinUnknown;
    @skinDir[@skinCount] = @skinDir[@skFIdx];
    @skinName[@skinCount] = @skinName[@skFIdx];
    @skinMaker[@skinCount] = @skinMaker[@skFIdx];
    @skinSource[@skinCount] = @skinSource[@skFIdx];
    @skinHash[@skinCount] = @skinHash[@skFIdx];
    @skinParsed[@skinCount] = @skinParsed[@skFIdx];
    for(@skSt = 0; @skSt < 7; @skSt += 1){
        @skinHas[@skinCount, @skSt] = @skinHas[@skFIdx, @skSt];
        @skinFrames[@skinCount, @skSt] = @skinFrames[@skFIdx, @skSt];
        @skinFw[@skinCount, @skSt] = @skinFw[@skFIdx, @skSt];
        @skinOx[@skinCount, @skSt] = @skinOx[@skFIdx, @skSt];
        @skinOy[@skinCount, @skSt] = @skinOy[@skFIdx, @skSt];
    }
    @skinUnknown = @skinCount;
}
// Initialize the new visible slot (field set mirrors @skin_scan; the hash is
// pre-filled so @skin_ensure_hash never recomputes it).
@skinDir[@skFIdx] = @skinDlDir;
@skinName[@skFIdx] = "";
@skinMaker[@skFIdx] = "";
@skinSource[@skFIdx] = "";
@skinHash[@skFIdx] = @skinDlHash;
@skinParsed[@skFIdx] = 0;
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skinHas[@skFIdx, @skSt] = 0;
    @skinFrames[@skFIdx, @skSt] = 0;
    @skinFw[@skFIdx, @skSt] = 32;
    @skinOx[@skFIdx, @skSt] = 17;
    @skinOy[@skFIdx, @skSt] = 23;
}
@skin_parse(@skFIdx);
@skinVisCount += 1;
@skinCount += 1;
// Re-apply to every remote player waiting on this hash (state 1 = pending
// the hash scan, 3 = explicitly missing). NOTE: scripts share the caller's
// scope, and @skin_apply_remote writes @skI/@skP - this loop must use
// variables no called script touches.
for(@dlK = 0; @dlK < instance_number(@onlinePlayer); @dlK += 1){
    @dlP = instance_find(@onlinePlayer, @dlK);
    if(@dlP.@skinHash == @skinDlHash){
        if(@dlP.@skinState == 1 || @dlP.@skinState == 3){
            @skin_apply_remote(@dlP);
        }
    }
}
@skin_dl_notice("Skin downloaded: " + @skinName[@skFIdx]);
@skinDlState = 0;
@skinDlHash = "";
@skinDlHint = "";
@skinDlDir = "";
@skinDlCount = 0;
@skinDlIdx = 0;
@skinDlPos = 0;
__ONLINE_buffer_clear(@dlBuffer);
return 1;

///// script @skin_dl_step
// Per-step driver, called from worldEndStep after the reconnect early-exit
// (the wait timer therefore never ticks while the socket is being
// re-established; the (re)connect path requeues any in-flight transfer).
if(@skinDlState == 0){
    @skin_dl_begin();
    return 0;
}
@skinDlWait -= 1;
if(@skinDlWait <= 0){
    // The server went silent (rate-limiter drop or connection trouble).
    @skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
    return 0;
}
return 1;
