/// ONLINE
// %arg0: The ID of the game
// %arg1: The server
// %arg2: The TCP port
// %arg3: The UDP port
// %arg4: The game name
// %arg5: The version
// (7th arg: player object list init code, PLAYER_LIST only, already __ONLINE_-prefixed)
// (8th arg: built-in sprite count = base index for runtime sprite_add sweeps,
//  0 when skins are disabled)
// (9th/10th arg: S4 bullet-sharing constants - bullet object index and
//  bullet sprite index; -1 disables. Inlined HERE (before @bullet_init runs
//  later in this template) because addCreateCode appends the constant block
//  AFTER the template body, and GM8 reads an unassigned global as 0, which
//  would defeat the -1 disabled state.)
global.@bulletObj = %arg8;
global.@bulletSpr = %arg9;
if(!instance_exists(@userInterface)){
	instance_create(0, 0, @userInterface);
}
#if HTTPDLL_INIT
if (!file_exists("http_dll_2_3.dll"))
	show_message("http_dll_2_3.dll not found.#Please place it in the same folder as the exe.");
else{
	@httpdll_init();
	#if CJKTEXT
	__ONLINE_set_utf8_mode(1);
	#endif
}
#endif
@connected = false;
@buffer = __ONLINE_buffer_create();
// P6: dedicated buffer for the frame-sliced @saves serialization (the shared
// @buffer is cleared by every message read, so a multi-frame write cannot
// accumulate in it).
@savesBuffer = __ONLINE_buffer_create();
@selfID = "";
@name = "";
@selfGameID = "%arg0";
@server = "%arg1";
@tcpPort = %arg2;
@udpPort = %arg3;
@version = "%arg5";
@protocolVersion = 3;
@race = false;
@password = "";
@vis = 0;
@save_enabled = 1;
@udpReady = false;
@udpRetryCount = 0;
@udpGraceFrames = room_speed*3;
@reconnecting = false;
@manualReconnect = false;
@reconnectDelay = 0;
@reconnectTimer = 0;
@reconnectAttempts = 0;
@hbCounter = 0;
@listCounter = 0;
@lastRoom = room;
@pingPRoom = -1;
#if PLAYER_LIST
// MULTI-PLAYER OBJECT LIST (C1): tracked player objects in priority order.
// Persisted to __online_player_objects only after an in-game edit (pick mode);
// otherwise the converter-baked defaults below apply on every start.
@debug_pick_player = false;
@objListEdited = false;
@obj_list = ds_list_create();
@objListLoaded = false;
if(file_exists("__online_player_objects")){
	@f = file_text_open_read("__online_player_objects");
	while(!file_text_eof(@f)){
		@objline = file_text_read_string(@f);
		file_text_readln(@f); // read_* leaves the cursor on the same line; without this the loop never reaches eof
		if(@objline != ""){
			@obj_id = real(@objline) - 1; // stored +1: GM8 text files and 0 don't mix
			if(object_exists(@obj_id)){
				ds_list_add(@obj_list, @obj_id);
				@objListLoaded = true;
			}
		}
	}
	file_text_close(@f);
}
if(!@objListLoaded){
%arg6
}
#endif
// SETTINGS PANEL
@kbRow[0] = 0;
@kbRow[1] = 0;
@kbRow[2] = 0;
@kbRow[3] = 0;
@kbRow[4] = 0;
@kbRow[5] = 0;
@kbFocus = 1;
@kbDelay = 0;
@gameName = "%arg4";
@keyChat = 32;
@keyVis = 86;
@keySave = 84;
@keyPlayerList = 76;
@keyFastLoad = 70;
@showPlayerList = false;
@loadHotkeyConsumed = false;
@settingsOpen = false;
@keySettings = 79;
@lerpEnabled = true;
@fastLoadEnabled = true;
@teamChanged = false;
@visChanged = false;
@saveChanged = false;
@lerpChanged = false;
@fastLoadChanged = false;
@syncEnabledChanged = false;
@saveHistCount = 0;
@saveHistMax = 500;
@saveHistLastTime = 0;
@saveHistFavMax = 100;
@saveHistFavCount = 0;
@saveHistApply = -1;
@saveForceLoad = false;
@saveHistPending = false;
@saveHistPendingGrav = 0;
@saveHistPendingX = 0;
@saveHistPendingY = 0;
@saveHistPendingRoom = 0;
@settingsTab = 0;
@saveHistPage = 0;
@saveHistClearFiles = false;
@saveHistDirty = false;
@saveHistDirtyTimer = 0;
// P6: phased frame-sliced save-history write (0 idle, 1 thinning, 2 serializing).
@shWritePhase = 0;
@shWritePos = 0;
@shWriteStartCount = 0;
@shWriteStartMut = 0;
@shTrimActive = false;
@shMutation = 0;
@saveHistFilter = 0;
@keyChatLog = 85;
@ratingSubmitting = false;
@ratingSubmit = false;
@ratingResult = 0;
@ratingResultTimer = 0;
@ratingCooldown = 0;
@rStars = 0;
@rCleared = 0;
@rClearWarn = 0;
@keybindEditing = -1;
@keybindArmTimer = 0;
@keybindSave = false;
@team = 0;
@keySpectate = 89;
@keyArrows = 73;
@keyPing = 72;
@spectating = false;
@spectatingPrev = false;
@specX = 0;
@specY = 0;
@specRoom = 0;
@specGrav = 0;
@specObj = 0;
@specPending = false;
@specHoldFrames = 0;
@specTargetIdx = 0;
@specTargetID = "";
@specTargetName = "";
@specCamX = 0;
@specCamY = 0;
@showArrows = false;
@specGraceFrames = 0;
@specSnapCamera = true;
@specCamMode = 0;
@specProgress = 0;
@chatHistCount = 0;
@chatHistMax = 30;
@chatLogScroll = 0;
@chatLogOpen = false;
@chatHistName[0] = "";
@chatHistMsg[0] = "";
@chatHistTeam[0] = 0;
@saveHistFav[0] = 0;
@saveHistHotkey[0] = 0;
@saveHistGrav[0] = 0;
@saveHistX[0] = 0;
@saveHistY[0] = 0.0;
@saveHistRoom[0] = 0;
@saveHistName[0] = "";
@saveHistRoomName[0] = "";
@saveHistTime[0] = 0;
@teamColors[0] = c_white;
@teamColors[1] = make_color_rgb(255, 80, 80);
@teamColors[2] = make_color_rgb(80, 140, 255);
@teamColors[3] = make_color_rgb(255, 255, 80);
@teamColors[4] = make_color_rgb(200, 80, 255);
@teamColors[5] = make_color_rgb(80, 255, 80);
@teamColors[6] = make_color_rgb(255, 160, 40);
@teamColors[7] = make_color_rgb(80, 255, 255);
@teamMap = ds_map_create();
// PING
@pingWheelOpen = false;
@pingWheelCenterX = 0;
@pingWheelCenterY = 0;
@pingWheelHover = 4;
@pingWheelCanceled = false;
@pingHead = 0;
@pingMax = 16;
@pingLifeMs = 4000;
for(@i = 0; @i < @pingMax; @i += 1){
	@pingX[@i] = 0;
	@pingY[@i] = 0;
	@pingT[@i] = -99999;
	@pingType[@i] = 4;
	@pingName[@i] = "";
	@pingSenderIDArr[@i] = "";
	@pingTeamArr[@i] = 0;
}
@pingLabels[0] = "?";
@pingLabels[1] = "UP";
@pingLabels[2] = "SAFE";
@pingLabels[3] = "LEFT";
@pingLabels[4] = "HERE";
@pingLabels[5] = "RIGHT";
@pingLabels[6] = "WAIT";
@pingLabels[7] = "DOWN";
@pingLabels[8] = "!";
// SYNC
@syncEnabled = 1;
@syncEntryCount = 0;
for(@scI = 0; @scI < 16; @scI += 1){
	@syncName[@scI] = "";
	@syncCount[@scI] = 0;
}
// SKINS
@skinCount = 0;
@skinSel = -1;
@skinLoaded = -1;
@skinAutoDL = 1;
@skinSavedHash = "";
@skinSavedDir = "";
@skinAutoDLChanged = false;
@skinPage = 0;
@skinPrevLoaded = -1;
@skinPrevRow = -1;
@skinPrevTimer = 0;
@skinVisCount = 0;
@skinUnknown = -1;
// S2 network exchange: @skinNetDirty makes worldEndStep (re)send SKIN
// (opcode 12) once connected - covers initial join, menu changes and
// reconnects uniformly. Remote skins render through 8 fixed global slots
// (slot 0 reserved for the hidden "Unknown" fallback package); their
// sprites are covered by the restart sweep below on GM8 and by the mirrored
// cleanup on GMS.
@skinNetDirty = false;
@skinHashScan = 0;
@skinHintNext = 0;
for(@skH = 0; @skH < 8; @skH += 1){
    @skinHint[@skH] = "";
}
// S3 auto-download: one package at a time, driven per-step from worldEndStep
// (queue -> SKIN_GET manifest -> SKIN_FILE chunks -> hash verify -> library
// insert). @dlBuffer accumulates the current file's bytes and is flushed per
// file; on GMS the chunks stream straight to disk via file_bin_* instead (see
// the STUDIO branch in worldEndStep's SKIN_FILE case). @skinDlFile is that
// stream's handle (-1 = none). @skinDlTmp mirrors the in-flight directory
// name in the ini so a crash/game_restart mid-download can be wiped at the
// next boot.
@dlBuffer = __ONLINE_buffer_create();
@skinDlFile = -1;
@skinDlState = 0;
@skinDlWait = 0;
@skinDlHash = "";
@skinDlHint = "";
@skinDlDir = "";
@skinDlCount = 0;
@skinDlIdx = 0;
@skinDlPos = 0;
@skinDlQCount = 0;
@skinDlFailNext = 0;
@skinDlTmp = "";
for(@skI = 0; @skI < 8; @skI += 1){
    @skinDlQ[@skI] = "";
    @skinDlQHint[@skI] = "";
}
for(@skI = 0; @skI < 16; @skI += 1){
    @skinDlFail[@skI] = "";
}
for(@skI = 0; @skI < 32; @skI += 1){
    @skinDlName[@skI] = "";
    @skinDlFSize[@skI] = 0;
}
@skinMap = ds_map_create();
@skinMapHint = ds_map_create();
global.@rskCount = 0;
global.@rskUnknown = 0;
// 32 slots = 1 reserved Unknown + up to 31 distinct remote skins at once
// (players sharing a skin share a slot; released slots are recycled).
for(@rskI = 0; @rskI < 32; @rskI += 1){
    global.@rskHash[@rskI] = "";
    for(@rskSt = 0; @rskSt < 7; @rskSt += 1){
        global.@rskSpr[@rskI, @rskSt] = -1;
        global.@rskFrames[@rskI, @rskSt] = 0;
    }
}
global.@skinOn = 0;
// No create-time initialization of the skin slot arrays here: @skin_scan
// fully initializes every slot it fills and readers stay below @skinCount,
// so a fixed pass over the 4096 slot cap would be dead cost on every
// game_restart.
// game_restart keeps sprite_add resources alive, so the previously loaded skin
// sprites (selection, menu preview AND remote slots) must be freed before the
// mirror arrays below are reset. Only the sprites @skin_spr_save recorded are
// freed: a blind sweep over the whole dynamic-sprite range also deletes
// sprites the GAME created at runtime (yuuutu keeps a 1x1 pixel sprite right
// at the base index; deleting it made every draw that used it fail, which
// starved the draw phase and left the step loop spinning at ~2000 Hz).
// The record is id,width,height,frames per sprite and is only acted on when
// EVERY entry still matches - true after a game_restart, false on a fresh
// launch where the list is just a leftover from the previous process and the
// ids either do not exist yet or belong to unrelated game sprites (id alone
// is not enough: sprite_add hands out the same ids every run).
// Do NOT use variable_global_exists to detect the restart instead: on GM8.0
// it always returns true (verified on fish).
@skSprBase = %arg7;
// P4: reuse-armed state. @skReuseSpr[st] holds a sprite kept across
// game_restart (st = state 0-6, -1 = none); @skin_select consumes the set
// exactly once and re-checks the recorded hash before adopting it.
@skReuseArmed = 0;
@skReuseHash = "";
if(@skSprBase > 0){
    ini_open("@config.ini");
    @skSprList = ini_read_string("config", "skinSprIds", "");
    ini_write_string("config", "skinSprIds", "");
    @skSelRecRaw = ini_read_string("config", "skinSelSprites", "");
    ini_write_string("config", "skinSelSprites", "");
    @skSavedHashEarly = ini_read_string("config", "skin", "");
    ini_close();
    // P4: parse the selected-skin sprite record. Arm reuse only when every
    // entry validates AND the recorded hash equals the hash the config still
    // asks for - the kept sprites are then excluded from the deletion sweep
    // below. "hash;id,state,width,height,frames;..." state 0-6, no dups.
    for(@skSt = 0; @skSt < 7; @skSt += 1){
        @skReuseSpr[@skSt] = -1;
    }
    if(string_length(@skSelRecRaw) > 0){
        @skSelOk = 1;
        @skSelPos = string_pos(";", @skSelRecRaw);
        if(@skSelPos <= 0){
            @skSelOk = 0;
        }else{
            @skSelHash = string_copy(@skSelRecRaw, 1, @skSelPos - 1);
            @skSelRest = string_delete(@skSelRecRaw, 1, @skSelPos);
            if(@skSelHash == "" || @skSelHash != @skSavedHashEarly){
                @skSelOk = 0;
            }else{
                @skSelCnt = 0;
                while(string_length(@skSelRest) > 0 && @skSelOk){
                    @skSelPos = string_pos(";", @skSelRest);
                    if(@skSelPos <= 0){
                        // last record: no trailing separator
                        @skSelTok = @skSelRest;
                        @skSelRest = "";
                    }else{
                        @skSelTok = string_copy(@skSelRest, 1, @skSelPos - 1);
                        @skSelRest = string_delete(@skSelRest, 1, @skSelPos);
                    }
                    @skFldN = 0;
                    @skTokLeft = @skSelTok;
                    while(string_length(@skTokLeft) > 0){
                        @skComma = string_pos(",", @skTokLeft);
                        if(@skComma <= 0){
                            @skTok1 = @skTokLeft;
                            @skTokLeft = "";
                        }else{
                            @skTok1 = string_copy(@skTokLeft, 1, @skComma - 1);
                            @skTokLeft = string_delete(@skTokLeft, 1, @skComma);
                        }
                        // Digits guard (parity with the skinSprIds parser):
                        // GM8.0 real("abc") on a hand-edited/corrupt record is
                        // a hard error popup.
                        if(string_length(@skTok1) < 1 || string_digits(@skTok1) != @skTok1){
                            @skSelOk = 0;
                            @skFldN = 99;
                            break;
                        }
                        @skFVal[@skFldN] = real(@skTok1);
                        @skFldN += 1;
                    }
                    if(@skFldN != 5){
                        @skSelOk = 0;
                        break;
                    }
                    @skSelId = @skFVal[0];
                    @skSelSt = @skFVal[1];
                    if(@skSelId < @skSprBase || @skSelSt < 0 || @skSelSt > 6 || !sprite_exists(@skSelId)){
                        @skSelOk = 0;
                        break;
                    }
                    if(sprite_get_width(@skSelId) != @skFVal[2] || sprite_get_height(@skSelId) != @skFVal[3] || sprite_get_number(@skSelId) != @skFVal[4]){
                        @skSelOk = 0;
                        break;
                    }
                    if(@skReuseSpr[@skSelSt] >= 0){
                        @skSelOk = 0;
                        break;
                    }
                    @skReuseSpr[@skSelSt] = @skSelId;
                    @skSelCnt += 1;
                }
                if(@skSelCnt < 1){
                    @skSelOk = 0;
                }
            }
        }
        if(@skSelOk){
            @skReuseArmed = 1;
            @skReuseHash = @skSelHash;
        }
    }
    @skSprN = 0;
    @skSprFld = 0;
    @skSprOk = (string_length(@skSprList) > 0);
    while(string_length(@skSprList) > 0){
        @skSprPos = string_pos(",", @skSprList);
        if(@skSprPos <= 0){
            @skSprOk = false;
            break;
        }
        @skSprTok = string_copy(@skSprList, 1, @skSprPos - 1);
        @skSprList = string_delete(@skSprList, 1, @skSprPos);
        if(string_length(@skSprTok) <= 0 || string_digits(@skSprTok) != @skSprTok){
            @skSprOk = false;
            break;
        }
        @skSprVal[@skSprFld] = real(@skSprTok);
        @skSprFld += 1;
        if(@skSprFld >= 4){
            @skSprFld = 0;
            @skDel = @skSprVal[0];
            if(@skDel < @skSprBase || !sprite_exists(@skDel)){
                @skSprOk = false;
                break;
            }
            if(sprite_get_width(@skDel) != @skSprVal[1] || sprite_get_height(@skDel) != @skSprVal[2] || sprite_get_number(@skDel) != @skSprVal[3]){
                @skSprOk = false;
                break;
            }
            @skSprId[@skSprN] = @skDel;
            @skSprN += 1;
        }
    }
    if(@skSprFld != 0){
        @skSprOk = false;
    }
    if(@skSprOk){
        for(@skSprI = 0; @skSprI < @skSprN; @skSprI += 1){
            // P4: skip sprites the reuse set keeps.
            @skKeep = 0;
            if(@skReuseArmed){
                for(@skR = 0; @skR < 7; @skR += 1){
                    if(@skReuseSpr[@skR] == @skSprId[@skSprI]){
                        @skKeep = 1;
                        break;
                    }
                }
            }
            if(!@skKeep){
                sprite_delete(@skSprId[@skSprI]);
            }
        }
    }
}
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skinSpr[@skSt] = -1;
    @skinPrevSpr[@skSt] = -1;
    global.@skinSpr[@skSt] = -1;
    global.@skinPrevSpr[@skSt] = -1;
    global.@skinFrames[@skSt] = 0;
    global.@mapSpr[@skSt] = -1;
    global.@mapFrames[@skSt] = 0;
}
@cfgDir = program_directory;
if (string_char_at(@cfgDir, string_length(@cfgDir)) != chr(92)) @cfgDir += chr(92);
@cfgPath = @cfgDir + "@config.ini";
@serverPath = @cfgDir + "@server.txt";
@savesPath = "@saves";
// LAYERED CONFIG: layer 0 = default ini shipped beside the exe (read-only),
// layer 1 = user ini in the working directory (read-write). User keys override.
@cfgRead = false;
for (@cfgLayer = 0; @cfgLayer < 2; @cfgLayer += 1) {
	@cfgFile = "";
	if (@cfgLayer == 0) {
		#if not GM80
			if (file_exists(@cfgPath)) @cfgFile = @cfgPath;
		#endif
		// GM8.0: ini_open rejects absolute paths ("INI files must be located in the
		// same directory as the program"). For a compiled GM8.0 exe PD == WD anyway,
		// so the PD layer is covered by the user layer below.
	} else {
		if (file_exists("@config.ini")) @cfgFile = "@config.ini";
	}
	if (@cfgFile != "") {
		@cfgRead = true;
		ini_open(@cfgFile);
		@cfgVal = ini_read_string("config", "server", "");
		if(@cfgVal != "") @server = @cfgVal;
		@keyChat = ini_read_real("config", "key_chat", @keyChat);
		@keyVis = ini_read_real("config", "key_visibility", @keyVis);
		@keySave = ini_read_real("config", "key_save", @keySave);
		@keyPlayerList = ini_read_real("config", "key_playerlist", @keyPlayerList);
		@keySettings = ini_read_real("config", "key_settings", @keySettings);
		@keyChatLog = ini_read_real("config", "key_chatlog", @keyChatLog);
		@keySpectate = ini_read_real("config", "key_spectate", @keySpectate);
		@keyArrows = ini_read_real("config", "key_arrows", @keyArrows);
		@keyPing = ini_read_real("config", "key_ping", @keyPing);
		@keyFastLoad = ini_read_real("config", "key_fastload", @keyFastLoad);
		@pingLabels[0] = ini_read_string("ping", "label_0", @pingLabels[0]);
		@pingLabels[1] = ini_read_string("ping", "label_1", @pingLabels[1]);
		@pingLabels[2] = ini_read_string("ping", "label_2", @pingLabels[2]);
		@pingLabels[3] = ini_read_string("ping", "label_3", @pingLabels[3]);
		@pingLabels[4] = ini_read_string("ping", "label_4", @pingLabels[4]);
		@pingLabels[5] = ini_read_string("ping", "label_5", @pingLabels[5]);
		@pingLabels[6] = ini_read_string("ping", "label_6", @pingLabels[6]);
		@pingLabels[7] = ini_read_string("ping", "label_7", @pingLabels[7]);
		@pingLabels[8] = ini_read_string("ping", "label_8", @pingLabels[8]);
		@lerpEnabled = ini_read_real("config", "lerp", @lerpEnabled);
		@fastLoadEnabled = ini_read_real("config", "fast_load", @fastLoadEnabled);
		@team = ini_read_real("config", "team", @team);
		if(@team < 0 || @team > 7) @team = 0;
		@team = floor(@team);
		@skinAutoDL = ini_read_real("config", "skinAutoDL", 1);
		@skinSavedHash = ini_read_string("config", "skin", "");
		@skinSavedDir = ini_read_string("config", "skinDir", "");
		@skinDlTmp = ini_read_string("config", "skinDlTmp", "");
		@syncEnabled = ini_read_real("sync", "sync_enabled", @syncEnabled);
		@syncEntryCount = ini_read_real("sync", "entryCount", @syncEntryCount);
		if(@syncEntryCount < 0) @syncEntryCount = 0;
		if(@syncEntryCount > 16) @syncEntryCount = 16;
		for(@scI = 0; @scI < @syncEntryCount; @scI += 1){
			@syncName[@scI]      = ini_read_string("sync", "sync"+string(@scI)+"_name", @syncName[@scI]);
			@syncCount[@scI]     = ini_read_real  ("sync", "sync"+string(@scI)+"_count", @syncCount[@scI]);
			if(@syncCount[@scI] < 1) @syncCount[@scI] = 0;
			if(@syncCount[@scI] > 512) @syncCount[@scI] = 512;
			@syncSlotCount[@scI] = ceil(@syncCount[@scI] / 32);
			@syncDirty[@scI]     = true;
			@syncLastSig[@scI]   = "";
		}
		ini_close();
	}
}
// SKINS: wipe a stale half-downloaded package left by a crash/game_restart
// mid-download (the in-flight directory is recorded in the ini at download
// start and cleared once the finished package verifies). Must run before
// @skin_scan() so the partial folder never enters the library.
if(@skinDlTmp != ""){
	@skin_dl_wipe(@skinDlTmp);
	ini_open("@config.ini");
	ini_write_string("config", "skinDlTmp", "");
	ini_close();
	@skinDlTmp = "";
}
if (!@cfgRead && file_exists(@serverPath)) {
	@file = file_text_open_read(@serverPath);
	@line = file_text_read_string(@file);
	file_text_close(@file);
	if @line != "" {
		@server = @line;
	}
}
@lastTeamSent = @team;
@lastSpecSent = @spectating;
// LOAD SAVE HISTORY
if file_exists(@savesPath) {
	__ONLINE_buffer_clear(@buffer);
	#if not GMNET
		__ONLINE_buffer_read_from_file(@buffer, "@saves");
		@saveHistMagic = __ONLINE_buffer_read_uint16(@buffer);
	#endif
	#if GMNET
		__ONLINE_buffer_load(@buffer, "@saves");
		@saveHistMagic = __ONLINE_buffer_read_u16(@buffer);
	#endif
	if(@saveHistMagic == 65535){
		// VERSIONED FORMAT
		#if not GMNET
			@saveHistFormat = __ONLINE_buffer_read_uint8(@buffer);
			@saveHistCount = __ONLINE_buffer_read_uint16(@buffer);
		#endif
		#if GMNET
			@saveHistFormat = __ONLINE_buffer_read_u8(@buffer);
			@saveHistCount = __ONLINE_buffer_read_u16(@buffer);
		#endif
		if(@saveHistCount > @saveHistMax) @saveHistCount = @saveHistMax;
		for(@shI = 0; @shI < @saveHistCount; @shI += 1){
			#if not GMNET
				@saveHistFav[@shI] = __ONLINE_buffer_read_uint8(@buffer);
				if(@saveHistFormat >= 2){
					@saveHistHotkey[@shI] = __ONLINE_buffer_read_uint8(@buffer);
				}else{
					@saveHistHotkey[@shI] = 0;
				}
				@saveHistGrav[@shI] = __ONLINE_buffer_read_uint8(@buffer);
				@saveHistX[@shI] = __ONLINE_buffer_read_int32(@buffer);
				@saveHistY[@shI] = __ONLINE_buffer_read_float64(@buffer);
				@saveHistRoom[@shI] = __ONLINE_buffer_read_int16(@buffer);
				@saveHistTime[@shI] = __ONLINE_buffer_read_float64(@buffer);
				@saveHistName[@shI] = __ONLINE_buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = __ONLINE_buffer_read_string(@buffer);
			#endif
			#if GMNET
				@saveHistFav[@shI] = __ONLINE_buffer_read_u8(@buffer);
				if(@saveHistFormat >= 2){
					@saveHistHotkey[@shI] = __ONLINE_buffer_read_u8(@buffer);
				}else{
					@saveHistHotkey[@shI] = 0;
				}
				@saveHistGrav[@shI] = __ONLINE_buffer_read_u8(@buffer);
				@saveHistX[@shI] = __ONLINE_buffer_read_i32(@buffer);
				@saveHistY[@shI] = __ONLINE_buffer_read_double(@buffer);
				@saveHistRoom[@shI] = __ONLINE_buffer_read_i16(@buffer);
				@saveHistTime[@shI] = __ONLINE_buffer_read_double(@buffer);
				@saveHistName[@shI] = __ONLINE_buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = __ONLINE_buffer_read_string(@buffer);
			#endif
			if(@saveHistHotkey[@shI] < 1 || @saveHistHotkey[@shI] > 8) @saveHistHotkey[@shI] = 0;
			if(@saveHistHotkey[@shI] > 0){
				for(@shJ = 0; @shJ < @shI; @shJ += 1){
					if(@saveHistHotkey[@shJ] == @saveHistHotkey[@shI]) @saveHistHotkey[@shJ] = 0;
				}
			}
			if(@saveHistFav[@shI]) @saveHistFavCount += 1;
		}
	}else{
		// V1 FORMAT
		@saveHistCount = @saveHistMagic;
		if(@saveHistCount > @saveHistMax) @saveHistCount = @saveHistMax;
		@shMigrateNow = date_current_datetime();
		for(@shI = 0; @shI < @saveHistCount; @shI += 1){
			@saveHistFav[@shI] = 0;
			@saveHistHotkey[@shI] = 0;
			#if not GMNET
				@saveHistGrav[@shI] = __ONLINE_buffer_read_uint8(@buffer);
				@saveHistX[@shI] = __ONLINE_buffer_read_int32(@buffer);
				@saveHistY[@shI] = __ONLINE_buffer_read_float64(@buffer);
				@saveHistRoom[@shI] = __ONLINE_buffer_read_int16(@buffer);
				@saveHistName[@shI] = __ONLINE_buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = __ONLINE_buffer_read_string(@buffer);
				__ONLINE_buffer_read_string(@buffer);
			#endif
			#if GMNET
				@saveHistGrav[@shI] = __ONLINE_buffer_read_u8(@buffer);
				@saveHistX[@shI] = __ONLINE_buffer_read_i32(@buffer);
				@saveHistY[@shI] = __ONLINE_buffer_read_double(@buffer);
				@saveHistRoom[@shI] = __ONLINE_buffer_read_i16(@buffer);
				@saveHistName[@shI] = __ONLINE_buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = __ONLINE_buffer_read_string(@buffer);
				__ONLINE_buffer_read_string(@buffer);
			#endif
			@saveHistTime[@shI] = @shMigrateNow - (@saveHistCount - 1 - @shI) / 1440;
		}
		@saveHistDirty = true;
		@saveHistDirtyTimer = room_speed;
	}
}
#if TEMPFILE
	@restoredFromTemp = false;
	if(file_exists("tempOnline")){
		#if not GMNET
			__ONLINE_buffer_read_from_file(@buffer, "tempOnline");
			@socket = __ONLINE_buffer_read_uint16(@buffer);
			@udpsocket = __ONLINE_buffer_read_uint16(@buffer);
			@selfID = __ONLINE_buffer_read_string(@buffer);
			@name = __ONLINE_buffer_read_string(@buffer);
			@selfGameID = __ONLINE_buffer_read_string(@buffer);
			@password = "";
			if(string_length(@selfGameID) > string_length("%arg0")){
				@password = string_copy(@selfGameID, string_length("%arg0") + 1, string_length(@selfGameID) - string_length("%arg0"));
			}
			@race = __ONLINE_buffer_read_uint8(@buffer);
			@n = __ONLINE_buffer_read_uint16(@buffer);
			@vis = __ONLINE_buffer_read_uint16(@buffer);
			@save_enabled = __ONLINE_buffer_read_uint16(@buffer);
			@team = __ONLINE_buffer_read_uint8(@buffer);
			@lerpEnabled = __ONLINE_buffer_read_uint8(@buffer);
		#endif
		#if GMNET
			__ONLINE_buffer_load(@buffer, "tempOnline");
			@socket = __ONLINE_buffer_read_u16(@buffer);
			@udpsocket = __ONLINE_buffer_read_u16(@buffer);
			@selfID = __ONLINE_buffer_read_string(@buffer);
			@name = __ONLINE_buffer_read_string(@buffer);
			@selfGameID = __ONLINE_buffer_read_string(@buffer);
			@password = "";
			if(string_length(@selfGameID) > string_length("%arg0")){
				@password = string_copy(@selfGameID, string_length("%arg0") + 1, string_length(@selfGameID) - string_length("%arg0"));
			}
			@race = __ONLINE_buffer_read_u8(@buffer);
			@n = __ONLINE_buffer_read_u16(@buffer);
			@vis = __ONLINE_buffer_read_u16(@buffer);
			@save_enabled = __ONLINE_buffer_read_u16(@buffer);
			@team = __ONLINE_buffer_read_u8(@buffer);
			@lerpEnabled = __ONLINE_buffer_read_u8(@buffer);
		#endif
	if(!@save_enabled){
		// Restored with online saves disabled: discard any pending online save.
		if(file_exists("tempOnline2")){
			file_delete("tempOnline2");
		}
	}
	// VALIDATE SOCKET
	@tcpState = __ONLINE_socket_get_state(@socket);
	if(@tcpState == 2){
			#if not GMNET
				for(@i = 0; @i < @n; @i += 1){
					@oPlayer = instance_create(0, 0, @onlinePlayer);
					@oPlayer.@ID = __ONLINE_buffer_read_string(@buffer);
					@oPlayer.x = __ONLINE_buffer_read_int32(@buffer);
					@oPlayer.y = __ONLINE_buffer_read_int32(@buffer);
					@oPlayer.@targetX = @oPlayer.x;
					@oPlayer.@targetY = @oPlayer.y;
					@oPlayer.@lerpInit = true;
					@oPlayer.sprite_index = __ONLINE_buffer_read_int32(@buffer);
					@oPlayer.image_speed = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_xscale = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_yscale = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_angle = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.@oRoom = __ONLINE_buffer_read_uint16(@buffer);
					@oPlayer.@name = __ONLINE_buffer_read_string(@buffer);
					@oPlayer.@team = __ONLINE_buffer_read_uint8(@buffer);
				}
				@showPlayerList = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				for(@i = 0; @i < @n; @i += 1){
					@oPlayer = instance_create(0, 0, @onlinePlayer);
					@oPlayer.@ID = __ONLINE_buffer_read_string(@buffer);
					@oPlayer.x = __ONLINE_buffer_read_i32(@buffer);
					@oPlayer.y = __ONLINE_buffer_read_i32(@buffer);
					@oPlayer.@targetX = @oPlayer.x;
					@oPlayer.@targetY = @oPlayer.y;
					@oPlayer.@lerpInit = true;
					@oPlayer.sprite_index = __ONLINE_buffer_read_i32(@buffer);
					@oPlayer.image_speed = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_xscale = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_yscale = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_angle = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.@oRoom = __ONLINE_buffer_read_u16(@buffer);
					@oPlayer.@name = __ONLINE_buffer_read_string(@buffer);
					@oPlayer.@team = __ONLINE_buffer_read_u8(@buffer);
				}
				@showPlayerList = __ONLINE_buffer_read_u8(@buffer);
			#endif
			@restoredFromTemp = true;
			@connected = true;
			@hbCounter = room_speed * 5;
			@listCounter = room_speed * 15;
		}else{
			file_delete("tempOnline");
			if(file_exists("tempOnline2")){
				file_delete("tempOnline2");
			}
			if(file_exists("tempOnlineChat")){
				file_delete("tempOnlineChat");
			}
			__ONLINE_socket_destroy(@socket);
			@socket = __ONLINE_socket_create();
			__ONLINE_socket_connect(@socket, @server, @tcpPort);
			@udpsocket = __ONLINE_udpsocket_create();
			__ONLINE_udpsocket_start(@udpsocket, false, 0);
			__ONLINE_udpsocket_set_destination(@udpsocket, @server, @udpPort);
			@reconnecting = true;
			@reconnectTimer = room_speed;
			@reconnectAttempts = 0;
			@restoredFromTemp = true;
		}
	}
	// RESTORE CHAT HISTORY
	if(file_exists("tempOnlineChat")){
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_read_from_file(@buffer, "tempOnlineChat");
			@chatHistCount = __ONLINE_buffer_read_uint16(@buffer);
			if(@chatHistCount > @chatHistMax) @chatHistCount = @chatHistMax;
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				@chatHistName[@ci] = __ONLINE_buffer_read_string(@buffer);
				@chatHistMsg[@ci] = __ONLINE_buffer_read_string(@buffer);
				@chatHistTeam[@ci] = __ONLINE_buffer_read_uint8(@buffer);
			}
		#endif
		#if GMNET
			__ONLINE_buffer_load(@buffer, "tempOnlineChat");
			@chatHistCount = __ONLINE_buffer_read_u16(@buffer);
			if(@chatHistCount > @chatHistMax) @chatHistCount = @chatHistMax;
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				@chatHistName[@ci] = __ONLINE_buffer_read_string(@buffer);
				@chatHistMsg[@ci] = __ONLINE_buffer_read_string(@buffer);
				@chatHistTeam[@ci] = __ONLINE_buffer_read_u8(@buffer);
			}
		#endif
		file_delete("tempOnlineChat");
	}
	if(!@restoredFromTemp){
#endif
	@socket = __ONLINE_socket_create();
		@socketConnectResult = __ONLINE_socket_connect(@socket, @server, @tcpPort);
	#if STUDIO
		@name = get_string("Enter your name:", "");
	#endif
	#if not STUDIO
		#if CJKTEXT
		@name = __ONLINE_ansi_to_utf8(wd_input_box("Name", "Enter your name:", ""));
		#endif
		#if not CJKTEXT
		@name = wd_input_box("Name", "Enter your name:", "");
		#endif
	#endif
	if(@name == ""){
		@name = "Anonymous";
	}
	@name = string_replace_all(@name, "#", "\#");
	if(string_length(@name) > 20){
		@name = string_copy(@name, 0, 20);
	}
	#if STUDIO
		@password = get_string("Enter a password:", "");
	#endif
	#if not STUDIO
		#if CJKTEXT
		@password = __ONLINE_ansi_to_utf8(wd_input_box("Password", "Leave it empty for no password:", ""));
		#endif
		#if not CJKTEXT
		@password = wd_input_box("Password", "Leave it empty for no password:", "");
		#endif
	#endif
	if(string_length(@password) > 20){
		@password = string_copy(@password, 0, 20);
	}
	@selfGameID += @password;
	#if STUDIO
		@race = show_question("Do you want to enable RACE mod? (shared saves will be disabled)");
	#endif
	#if not STUDIO
		wd_message_set_text("Do you want to enable RACE mod? (shared saves will be disabled)");
		@race = wd_message_show(wd_mk_information, wd_mb_yes, wd_mb_no, 0) == wd_mb_yes;
	#endif
	__ONLINE_buffer_clear(@buffer);
	@hasPassword = 0;
	if(string_length(string(@password)) > 0) @hasPassword = 1;
	#if not GMNET
		__ONLINE_buffer_write_uint8(@buffer, 3);
		__ONLINE_buffer_write_string(@buffer, @name);
		__ONLINE_buffer_write_string(@buffer, @selfGameID);
		__ONLINE_buffer_write_string(@buffer, "%arg4");
		__ONLINE_buffer_write_string(@buffer, @version);
		__ONLINE_buffer_write_uint8(@buffer, @hasPassword);
		__ONLINE_buffer_write_uint8(@buffer, @protocolVersion);
		__ONLINE_socket_write_message(@socket, @buffer);
		@udpsocket = __ONLINE_udpsocket_create();
		__ONLINE_udpsocket_start(@udpsocket, false, 0);
		__ONLINE_udpsocket_set_destination(@udpsocket, @server, @udpPort);
		__ONLINE_buffer_clear(@buffer);
		__ONLINE_buffer_write_uint8(@buffer, 8);
		__ONLINE_buffer_write_uint8(@buffer, @team);
		__ONLINE_socket_write_message(@socket, @buffer);
		__ONLINE_buffer_clear(@buffer);
		__ONLINE_buffer_write_uint8(@buffer, 0);
	#endif
	#if GMNET
		__ONLINE_buffer_write_u8(@buffer, 3);
		__ONLINE_buffer_write_string(@buffer, @name);
		__ONLINE_buffer_write_string(@buffer, @selfGameID);
		__ONLINE_buffer_write_string(@buffer, "%arg4");
		__ONLINE_buffer_write_string(@buffer, @version);
		__ONLINE_buffer_write_u8(@buffer, @hasPassword);
		__ONLINE_buffer_write_u8(@buffer, @protocolVersion);
		__ONLINE_socket_write_message(@socket, @buffer);
		@udpsocket = __ONLINE_udpsocket_create();
		__ONLINE_udpsocket_start(@udpsocket, false, 0);
		__ONLINE_udpsocket_set_destination(@udpsocket, @server, @udpPort);
		__ONLINE_buffer_clear(@buffer);
		__ONLINE_buffer_write_u8(@buffer, 8);
		__ONLINE_buffer_write_u8(@buffer, @team);
		__ONLINE_socket_write_message(@socket, @buffer);
		__ONLINE_buffer_clear(@buffer);
		__ONLINE_buffer_write_u8(@buffer, 0);
	#endif
	__ONLINE_udpsocket_send(@udpsocket, @buffer);
#if TEMPFILE
	}
#endif
@pExists = false;
@pX = 0;
@pY = 0;
@t = 0;
@stoppedFrames = 0;
@sGravity = 0;
@sX = 0;
@sY = 0;
@sRoom = 0;
@sSaved = false;
#if GMSND
sound_add_included("__ONLINE_sndChatbox.wav", 0, 1)
sound_add_included("__ONLINE_sndSaved.wav", 0, 1)
globalvar @sndChatbox, @sndSaved;
@sndChatbox = "__ONLINE_sndChatbox"
@sndSaved = "__ONLINE_sndSaved"
#endif

#if CJKTEXT
__ONLINE_cjk_init();
#endif

#if GM80
globalvar @fwBerlin, @fwCjk;
@fwAsciiPath = "__ONLINE_ascii.ttf";
if(!file_exists(@fwAsciiPath) && file_exists(working_directory + "__ONLINE_ascii.ttf")){
	@fwAsciiPath = working_directory + "__ONLINE_ascii.ttf";
}
@fwBerlin = -1;
if(file_exists(@fwAsciiPath)){
	@fwBerlin = fw_add_font_from_file(@fwAsciiPath, 9, false, false, false);
}
if(@fwBerlin < 0) @fwBerlin = fw_add_font('Berlin Sans FB Demi', 9, false, false, false);
if(@fwBerlin < 0) @fwBerlin = fw_add_font('Tahoma', 9, false, false, false);
if(@fwBerlin < 0) @fwBerlin = fw_add_font('Arial', 9, false, false, false);
@fwCjk = fw_add_font('Microsoft Yahei', 9, false, false, false);
if(@fwCjk < 0) @fwCjk = fw_add_font('SimSun', 9, false, false, false);
if(@fwCjk >= 0) fw_set_font_offset(@fwCjk, -1, -4);
if(@fwBerlin >= 0){
	fw_draw_set_font(@fwBerlin);
}else if(@fwCjk >= 0){
	fw_draw_set_font(@fwCjk);
}
#endif

// SKINS: scan the skins folder, then restore the persisted selection. The
// saved directory name locates the skin instantly; if the folder was renamed
// or deleted (or the config predates skinDir), fall back to a one-time hash
// scan that stops at the first match. The hash scan re-hashes folders until
// the hit, so it must NOT run on the normal path: with ~200 skins installed
// it cost seconds on every game_restart (fish restarts on every load).
@skin_scan();
// P0/P3: hash cache - one txt-cache read replaces up to 196 x 25ms of MD5
// per game_restart (per death in games that restart on load).
@skin_cache_load();
@skinFound = -1;
if(@skinSavedDir != ""){
    for(@skI = 0; @skI < @skinCount; @skI += 1){
        if(@skinDir[@skI] == @skinSavedDir){
            @skinFound = @skI;
            break;
        }
    }
}
if(@skinFound < 0 && @skinSavedHash != ""){
    // Renamed folder or pre-skinDir config: one-shot hash-scan fallback.
    for(@skI = 0; @skI < @skinCount; @skI += 1){
        if(@skinFound < 0){
            @skin_ensure_hash(@skI);
            if(@skinHash[@skI] == @skinSavedHash){
                @skinFound = @skI;
            }
        }
    }
}
if(@skinFound >= 0){
    @skin_select(@skinFound);
}else if(@skinSavedHash != "" || @skinSavedDir != ""){
    // The saved skin no longer exists: forget it on disk as well.
    // P4: the reuse-armed sprites are consumed only by @skin_select - this
    // branch never reaches it, so free the kept set explicitly (otherwise
    // the 7 sprites leak forever; the next @skin_spr_save no longer lists
    // them and they can never be reclaimed).
    if(@skReuseArmed){
        for(@skR = 0; @skR < 7; @skR += 1){
            if(@skReuseSpr[@skR] >= 0){
                if(sprite_exists(@skReuseSpr[@skR])){
                    sprite_delete(@skReuseSpr[@skR]);
                }
            }
        }
        @skReuseArmed = 0;
        @skReuseHash = "";
    }
    @skinSavedHash = "";
    @skinSavedDir = "";
    ini_open("@config.ini");
    ini_write_string("config", "skin", "");
    ini_write_string("config", "skinDir", "");
    ini_close();
}
// S2: the hidden "Unknown" fallback package occupies remote slot 0.
if(@skinUnknown >= 0){
    if(@skin_slot_load(0, @skinUnknown)){
        global.@rskHash[0] = "<unknown>";
        global.@rskCount = 1;
        global.@rskUnknown = 1;
        // @skin_slot_load already saved, but @rskCount was still 0 back then
        // so slot 0 was skipped: re-save now that the slot counts.
        @skin_spr_save();
    }
}
// S2: (re)apply remote skins to players restored from tempOnline above (the
// library did not exist yet when those instances were created).
for(@skI = 0; @skI < instance_number(@onlinePlayer); @skI += 1){
    @skin_apply_remote(instance_find(@onlinePlayer, @skI));
}
// S4: bullet sharing init (no-op when the converter could not resolve a
// bullet object; @bActive stays 0 and every entry is inert).
@bActive = 0;
@bullet_init();
