/// ONLINE
// %arg0: The ID of the game
// %arg1: The server
// %arg2: The TCP port
// %arg3: The UDP port
// %arg4: The game name
// %arg5: The version
// %arg6: Whether shared save hooks are enabled for this game
// %arg7: The font index for online UI
// Player object list init code follows (PLAYER_LIST only, already
// __ONLINE_-prefixed). It is multi-line, so nothing may trail it on a
// comment line (the remainder would land at column 0 and fail the GMS
// compile); also never write the literal arg token inside any comment:
// %arg8
if(!instance_exists(@userInterface)){
	#if GMS2
		instance_create_depth(0, 0, -2147483648, @userInterface);
	#endif
	#if not GMS2
		instance_create(0, 0, @userInterface);
	#endif
}
@connected = false;
set_utf8_mode(1);
@buffer = buffer_create();
// P6: dedicated buffer for the frame-sliced @saves serialization (the shared
// @buffer is cleared by every message read, so a multi-frame write cannot
// accumulate in it).
@savesBuffer = buffer_create();
@selfID = "";
@name = "";
@selfGameID = "%arg0";
// QoL: keep the base game id; @account_apply rebuilds @selfGameID as base + session key.
@accBaseGameID = @selfGameID;
@server = "%arg1";
@tcpPort = %arg2;
@udpPort = %arg3;
@version = "%arg5";
@protocolVersion = 5;
// QoL: prime the settings row table / toast state (see gml/settingsLib.gml).
@stg_init();
@password = "";
@vis = 0;
@save_enabled = %arg6;
@onlinePlayerDepth = -10;
@chatboxDepth = -11;
@playerSavedDepth = -10;
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
// SETTINGS PANEL
@kbRow[0] = 0;
@kbRow[1] = 0;
@kbRow[2] = 0;
@kbRow[3] = 0;
@kbRow[4] = 0;
@kbRow[5] = 0;
@kbFocus = 1;
@kbDelay = 0;
@kbRepeatKey = 0;   // menu key repeat state (see @kb_repeat) - without
@kbRepeatWait = 0;  // this the panel aborts on GMS in End Step
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
@reconnectQuitOnFail = 0;
@reconnectQuitChanged = false;
@serverChanged = false;
@saveHistMaxChanged = false;
@chatHistMaxChanged = false;
@showArrowsChanged = false;
@specCamChanged = false;
@showPlayerListChanged = false;
@noteCanvasModeChanged = false;
@noteHideChanged = false;
@menuModePrefChanged = false;
@lerpChanged = false;
@lerpFactor = 0.5;
@lerpMode = -1;   // resolved in the config loop below (legacy key fallback there)
@fastLoadChanged = false;
@syncEnabledChanged = false;
// S5 (PVP): mode 0=Off/1=Team/2=FFA; bullets visible by default and forced
// visible while PVP is on. @pvpAvail is baked by the converter (PVPKILL).
@pvpMode = 0;
@bulletShow = 1;
@pvpChanged = false;
@bulletShowChanged = false;
#if PVPKILL
    @pvpAvail = 1;
#endif
#if not PVPKILL
    @pvpAvail = 0;
#endif
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
global.@ftOnline = %arg7;
@team = 0;
@keySpectate = 89;
@keyArrows = 73;
@keyPing = 72;
@keyCanvas = 78;
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
// NOTES (opcode 20; supersedes the PING marker arrays - legacy clients'
// opcode 11 pings are folded into this same store on receive)
@noteMode = 0;             // 0 idle, 2 wheel, 3 icon palette
@noteNoClick = 0;          // input gate: set while wheel/palette is open
@noteCanvasMode = 0;       // N key cycles: 0 transient (toast only), 1 canvas (all notes, no names), 2 off
@noteAnchorX = 0;          // where the note lands (H press position)
@noteAnchorY = 0;
@noteCX = 0;               // clamped wheel/palette center (render + hover)
@noteCY = 0;
@noteWarped = 0;           // cursor captured into a clamped wheel center
@noteMouseWX = 0;          // OS cursor pos to restore on close
@noteMouseWY = 0;
@noteWheelHover = 4;
@notePaletteHover = -1;
@notePalettePage = 0;
@notePaletteLast = 4;
@noteLastIcon = 4;         // center quick icon (ini persisted)
@noteLastIconLoaded = 4;
@noteHideOthers = 0;       // ini [notes] hide_others
@noteHideAll = 0;          // ini [notes] hide_all
@noteMax = 64;
@notePerCap = 8;           // per-sender-per-kind FIFO cap
@noteToastMs = 4000;       // full-alpha period; notes then persist dimmed
@noteHead = 0;
@noteSeq = 0;
for(@i = 0; @i < @noteMax; @i += 1){
	@noteKindArr[@i] = 0;
	@noteRoomArr[@i] = 0;
	@noteX[@i] = 0;
	@noteY[@i] = 0;
	@noteIcon[@i] = 4;
	@noteSenderArr[@i] = "";
	@noteName[@i] = "";
	@noteTeamArr[@i] = 0;
	@noteT[@i] = -99999;
	@noteSeqArr[@i] = -1;
	@noteWireArr[@i] = -1;
	@notePtsN[@i] = 0;
	@noteText[@i] = "";
}
@noteStageN = 0;           // in-progress polyline/stroke staging (also used by receive)
@noteStageText = "";
@noteAtlasSpr = -1;
@noteSeqSend = 0;         // sender-side note id counter (wire seq)
@notePrevRoom = -1;         // room-change detector drives NOTE_SYNC pulls
@noteSyncLastMs = 0;
@noteDirty = 0;             // notes store needs a persist flush
@noteFlushMs = 0;
// cached save rides tempOnline2 into the first normal loadGame (no auto-teleport)
@noteDrawing = 0;          // brush mode: LMB stroke in progress
@noteDrawRunStart = 0;     // brush mode: current sub-path start index
@noteStrokeSeq = 0;        // sender-side stroke id counter
for(@i = 0; @i < 8; @i += 1){
	@noteStrokeOwner[@i] = "";
	@noteStrokeSid[@i] = -1;
	@noteStrokeN[@i] = 0;
	@noteStrokeT[@i] = 0;
}
// SYNC
@syncEnabled = 1;
@syncEntryCount = 0;
for(@scI = 0; @scI < 16; @scI += 1){
	@syncName[@scI] = "";
	@syncCount[@scI] = 0;
}
// SKINS (on the GMS side the converter prepends the generated sprite-state
// map before this template, so the global sprite-map arrays must NOT be
// defaulted here - that would clobber the converter-provided values).
@skinCount = 0;
@skinSel = -1;
// P4: sprite-slot reuse across game_restart is a GM8-only optimization; GMS
// keeps these unarmed so @skin_select's shared code path loads normally.
@skReuseArmed = 0;
@skReuseHash = "";
@skinLoaded = -1;
@skinAutoDL = 1;
@skinSavedHash = "";
@skinSavedDir = "";
@skinAutoDLChanged = false;
@skinPage = 0;
@skinPrevLoaded = -1;
@skinPrevRow = -1;
@skinPrevState = 0;
@skinFilter = "";
@skinFilterParsed = "";
@skinPrevTimer = 0;
@skinVisCount = 0;
@skinUnknown = -1;
// Early GMS1 runners lack variable_instance_exists, so @skin_draw tracks
// initialized caller instances in this map (GMS2 uses the function instead).
// Created unconditionally: variable_global_exists hard-errors on early GMS1
// ("trying to index a variable which is not an array") for any name that is
// registered in the variable table, so it cannot guard the recreate; a map
// abandoned by a game_restart is just a few KB of dead entries.
#if not GMS2
global.@skinAnMap = ds_map_create();
#endif
// S2 network exchange (see worldCreate.gml for the full commentary).
@skinNetDirty = false;
@skinHashScan = 0;
@skinHintNext = 0;
for(@skH = 0; @skH < 8; @skH += 1){
    @skinHint[@skH] = "";
}
// S3 auto-download (see worldCreate.gml for the full commentary).
@dlBuffer = buffer_create();
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
// game_restart keeps sprite_add resources alive; free the previously mirrored
// skin sprites (selection, menu preview AND remote slots) before dropping
// their ids below. The restart record travels through the config ini exactly
// like the GM8 path (see worldCreate.gml): variable_global_exists cannot
// detect the restart because on early GMS1 runners (bytecode 15) it
// hard-errors ("trying to index a variable which is not an array") for any
// compile-time-registered global name. Validation is all-or-nothing on
// id,width,height,frames (this template receives no sprite-base arg, so the
// GM8 base-index check is the only one dropped).
ini_open("@config.ini");
@skSprList = ini_read_string("config", "skinSprIds", "");
ini_write_string("config", "skinSprIds", "");
// P4 reuse records are a GM8-only optimization; consume the key so a stale
// record never lingers across runs.
ini_write_string("config", "skinSelSprites", "");
ini_close();
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
    // Digits guard (parity with GM8): real("abc") on a corrupt record is a
    // hard error popup on the classic runners.
    if(string_length(@skSprTok) <= 0 || string_digits(@skSprTok) != @skSprTok){
        @skSprOk = false;
        break;
    }
    @skSprVal[@skSprFld] = real(@skSprTok);
    @skSprFld += 1;
    if(@skSprFld >= 4){
        @skSprFld = 0;
        @skDel = @skSprVal[0];
        if(!sprite_exists(@skDel)){
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
        // re-check at delete time: a duplicated/stale record must never
        // fatal (a second delete of the same id crashes)
        if(sprite_exists(@skSprId[@skSprI])){
            sprite_delete(@skSprId[@skSprI]);
        }
    }
}
for(@skSt = 0; @skSt < 7; @skSt += 1){
    @skinSpr[@skSt] = -1;
    @skinPrevSpr[@skSt] = -1;
    global.@skinSpr[@skSt] = -1;
    global.@skinPrevSpr[@skSt] = -1;
    global.@skinFrames[@skSt] = 0;
}
@cfgDir = program_directory;
if (string_char_at(@cfgDir, string_length(@cfgDir)) != chr(92)) @cfgDir += chr(92);
@cfgPath = @cfgDir + "@config.ini";
@serverPath = @cfgDir + "@server.txt";
@savesPath = "@saves";
#if PLAYER_LIST
// MULTI-PLAYER OBJECT LIST (C1, GMS port): tracked player objects in
// priority order. Same semantics as the GM8 template, but the persistence
// file lives in program_directory (the GMS sandbox would dump a bare
// relative path into AppData). Persisted only after an in-game edit (pick
// mode); otherwise the converter-baked defaults below apply on every start.
@debug_pick_player = false;
@objListEdited = false;
@poDir = @cfgDir;
@poFile = @cfgDir + "__online_player_objects";
@obj_list = ds_list_create();
@objListLoaded = false;
if(file_exists(@poFile)){
	@poF = file_text_open_read(@poFile);
	while(!file_text_eof(@poF)){
		@objline = file_text_read_string(@poF);
		file_text_readln(@poF); // read_* leaves the cursor on the same line; without this the loop never reaches eof
		// Digits-only normalize: legacy files may carry write_real's leading
		// space padding, and real() on non-digits is a hard error.
		@objline = string_digits(@objline);
		if(@objline != ""){
			@obj_id = real(@objline) - 1; // stored +1: text files and 0 don't mix
			if(object_exists(@obj_id)){
				ds_list_add(@obj_list, @obj_id);
				@objListLoaded = true;
			}
		}
	}
	file_text_close(@poF);
}
if(!@objListLoaded){
%arg8
}
#endif
// LAYERED CONFIG: layer 0 = default ini shipped beside the exe (read-only),
// layer 1 = user ini in the working directory (read-write). User keys override.
@cfgRead = false;
for (@cfgLayer = 0; @cfgLayer < 2; @cfgLayer += 1) {
	@cfgFile = "";
	if (@cfgLayer == 0) {
		if (file_exists(@cfgPath)) @cfgFile = @cfgPath;
	} else {
		if (file_exists("@config.ini")) @cfgFile = "@config.ini";
	}
	if (@cfgFile != "") {
		@cfgRead = true;
		ini_open(@cfgFile);
		@cfgVal = ini_read_string("config", "server", "");
		if(@cfgVal != "") @server = @cfgVal;
		// menu layout: 0 = auto (full when the view port is wide enough), 1 = the
		// shipped narrow layout, 2 = force the full layout with the detail pane.
		@menuModePref = ini_read_real("config", "menu_mode", 0);
		if(@menuModePref < 0 || @menuModePref > 2) @menuModePref = 0;
		@keyChat = ini_read_real("config", "key_chat", @keyChat);
		@keyVis = ini_read_real("config", "key_visibility", @keyVis);
		@keySave = ini_read_real("config", "key_save", @keySave);
		@keyPlayerList = ini_read_real("config", "key_playerlist", @keyPlayerList);
		@keySettings = ini_read_real("config", "key_settings", @keySettings);
		@keyChatLog = ini_read_real("config", "key_chatlog", @keyChatLog);
		@keySpectate = ini_read_real("config", "key_spectate", @keySpectate);
		@keyArrows = ini_read_real("config", "key_arrows", @keyArrows);
		@keyPing = ini_read_real("config", "key_ping", @keyPing);
		@keyCanvas = ini_read_real("config", "key_canvas", @keyCanvas);
		@keyFastLoad = ini_read_real("config", "key_fastload", @keyFastLoad);
		@noteLastIcon = ini_read_real("ping", "last_icon", @noteLastIcon);
		if(@noteLastIcon < 0 || (@noteLastIcon > 9 && @noteLastIcon < 16) || @noteLastIcon > 47) @noteLastIcon = 4;
		@noteLastIcon = floor(@noteLastIcon);
		@noteLastIconLoaded = @noteLastIcon;
		@noteHideOthers = ini_read_real("notes", "hide_others", 0);
		if(@noteHideOthers != 0) @noteHideOthers = 1;
		@noteHideAll = ini_read_real("notes", "hide_all", 0);
		if(@noteHideAll != 0) @noteHideAll = 1;
		@lerpEnabled = ini_read_real("config", "lerp", @lerpEnabled);
		@fastLoadEnabled = ini_read_real("config", "fast_load", @fastLoadEnabled);
		@pvpMode = ini_read_real("config", "pvp_mode", @pvpMode);
		if(@pvpMode < 0 || @pvpMode > 2) @pvpMode = 0;
		@pvpMode = floor(@pvpMode);
		@bulletShow = ini_read_real("config", "bullet_show", @bulletShow);
		if(@bulletShow != 0) @bulletShow = 1;
		// A PVP player must never hide the bullets that can kill them.
		if(@pvpMode != 0) @bulletShow = 1;
		@team = ini_read_real("config", "team", @team);
		@vis = ini_read_real("config", "vis", @vis);
		@lerpMode = ini_read_real("config", "lerp_mode", -1);
		if(@lerpMode < 0){
			// legacy bool key: on -> Standard, off -> OFF
			@lerpMode = 2;
			if(!@lerpEnabled) @lerpMode = 0;
		}
		if(@lerpMode > 3) @lerpMode = 2;
		@stg_lerp_apply();
		if(@vis < 0 || @vis > 2) @vis = 0;
		@showArrows = ini_read_real("config", "indicator", @showArrows);
		@specCamMode = ini_read_real("config", "spec_cam", @specCamMode);
		@showPlayerList = ini_read_real("config", "player_list", @showPlayerList);
		@noteCanvasMode = ini_read_real("notes", "canvas_mode", @noteCanvasMode);
		@reconnectQuitOnFail = ini_read_real("config", "reconnect_quit", @reconnectQuitOnFail);
		@tcpPort = ini_read_real("config", "tcp_port", @tcpPort);
		@udpPort = ini_read_real("config", "udp_port", @udpPort);
		@saveHistMax = ini_read_real("config", "save_hist_max", @saveHistMax);
		if(@saveHistMax < 100) @saveHistMax = 100;
		if(@saveHistMax > 2000) @saveHistMax = 2000;
		@chatHistMax = ini_read_real("config", "chat_hist_max", @chatHistMax);
		if(@chatHistMax < 10) @chatHistMax = 10;
		if(@chatHistMax > 300) @chatHistMax = 300;
		if(@noteCanvasMode < 0 || @noteCanvasMode > 2) @noteCanvasMode = 0;
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
// SKINS: wipe a stale half-downloaded package (see worldCreate.gml).
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
	if(@line != ""){
		@server = @line;
	}
}
@lastTeamSent = @team;
@lastSpecSent = @spectating;
// LOAD SAVE HISTORY
if file_exists(@savesPath) {
	buffer_clear(@buffer);
	#if not GMNET
		buffer_read_from_file(@buffer, "@saves");
		@saveHistMagic = buffer_read_uint16(@buffer);
	#endif
	#if GMNET
		buffer_load(@buffer, "@saves");
		@saveHistMagic = buffer_read_u16(@buffer);
	#endif
	if(@saveHistMagic == 65535){
		// VERSIONED FORMAT
		#if not GMNET
			@saveHistFormat = buffer_read_uint8(@buffer);
			@saveHistCount = buffer_read_uint16(@buffer);
		#endif
		#if GMNET
			@saveHistFormat = buffer_read_u8(@buffer);
			@saveHistCount = buffer_read_u16(@buffer);
		#endif
		if(@saveHistCount > @saveHistMax) @saveHistCount = @saveHistMax;
		for(@shI = 0; @shI < @saveHistCount; @shI += 1){
			#if not GMNET
				@saveHistFav[@shI] = buffer_read_uint8(@buffer);
				if(@saveHistFormat >= 2){
					@saveHistHotkey[@shI] = buffer_read_uint8(@buffer);
				}else{
					@saveHistHotkey[@shI] = 0;
				}
				@saveHistGrav[@shI] = buffer_read_uint8(@buffer);
				@saveHistX[@shI] = buffer_read_int32(@buffer);
				@saveHistY[@shI] = buffer_read_float64(@buffer);
				@saveHistRoom[@shI] = buffer_read_int16(@buffer);
				@saveHistTime[@shI] = buffer_read_float64(@buffer);
				@saveHistName[@shI] = buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = buffer_read_string(@buffer);
			#endif
			#if GMNET
				@saveHistFav[@shI] = buffer_read_u8(@buffer);
				if(@saveHistFormat >= 2){
					@saveHistHotkey[@shI] = buffer_read_u8(@buffer);
				}else{
					@saveHistHotkey[@shI] = 0;
				}
				@saveHistGrav[@shI] = buffer_read_u8(@buffer);
				@saveHistX[@shI] = buffer_read_i32(@buffer);
				@saveHistY[@shI] = buffer_read_double(@buffer);
				@saveHistRoom[@shI] = buffer_read_i16(@buffer);
				@saveHistTime[@shI] = buffer_read_double(@buffer);
				@saveHistName[@shI] = buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = buffer_read_string(@buffer);
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
				@saveHistGrav[@shI] = buffer_read_uint8(@buffer);
				@saveHistX[@shI] = buffer_read_int32(@buffer);
				@saveHistY[@shI] = buffer_read_float64(@buffer);
				@saveHistRoom[@shI] = buffer_read_int16(@buffer);
				@saveHistName[@shI] = buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = buffer_read_string(@buffer);
				buffer_read_string(@buffer);
			#endif
			#if GMNET
				@saveHistGrav[@shI] = buffer_read_u8(@buffer);
				@saveHistX[@shI] = buffer_read_i32(@buffer);
				@saveHistY[@shI] = buffer_read_double(@buffer);
				@saveHistRoom[@shI] = buffer_read_i16(@buffer);
				@saveHistName[@shI] = buffer_read_string(@buffer);
				@saveHistRoomName[@shI] = buffer_read_string(@buffer);
				buffer_read_string(@buffer);
			#endif
			@saveHistTime[@shI] = @shMigrateNow - (@saveHistCount - 1 - @shI) / 1440;
		}
		@saveHistDirty = true;
		@saveHistDirtyTimer = room_speed;
	}
}
// QoL: read the account store UNCONDITIONALLY, before the #if TEMPFILE
// region: engines without tempOnline strip that whole region, and a
// tempOnline restore (game_restart) takes the "if(!@restoredFromTemp)"
// branch below - placing this call after the region's #endif still left it
// inside that runtime block, so every restart wiped the menu back to
// "(not set)" while the file on disk kept the values.
@accLoaded = @account_load();

#if TEMPFILE
	@restoredFromTemp = false;
	if(file_exists("tempOnline")){
		#if not GMNET
			buffer_read_from_file(@buffer, "tempOnline");
			@socket = buffer_read_uint16(@buffer);
			@udpsocket = buffer_read_uint16(@buffer);
			@selfID = buffer_read_string(@buffer);
			@name = buffer_read_string(@buffer);
			@selfGameID = buffer_read_string(@buffer);
			@password = "";
			if(string_length(@selfGameID) > string_length("%arg0")){
				@password = string_copy(@selfGameID, string_length("%arg0") + 1, string_length(@selfGameID) - string_length("%arg0"));
			}
			@n = buffer_read_uint16(@buffer);
			@vis = buffer_read_uint16(@buffer);
			@save_enabled = buffer_read_uint16(@buffer);
			@team = buffer_read_uint8(@buffer);
			@lerpEnabled = buffer_read_uint8(@buffer);
		#endif

		#if GMNET
			buffer_load(@buffer, "tempOnline");
			@socket = buffer_read_u16(@buffer);
			@udpsocket = buffer_read_u16(@buffer);
			@selfID = buffer_read_string(@buffer);
			@name = buffer_read_string(@buffer);
			@selfGameID = buffer_read_string(@buffer);
			@password = "";
			if(string_length(@selfGameID) > string_length("%arg0")){
				@password = string_copy(@selfGameID, string_length("%arg0") + 1, string_length(@selfGameID) - string_length("%arg0"));
			}
			@n = buffer_read_u16(@buffer);
			@vis = buffer_read_u16(@buffer);
			@save_enabled = buffer_read_u16(@buffer);
			@team = buffer_read_u8(@buffer);
			@lerpEnabled = buffer_read_u8(@buffer);
		#endif
		if(!@save_enabled){
			// Restored with online saves disabled: discard any pending online save.
			if(file_exists("tempOnline2")){
				file_delete("tempOnline2");
			}
		}
		@tcpState = socket_get_state(@socket);
		if(@tcpState == 2){
			#if not GMNET
				for(@i = 0; @i < @n; @i += 1){
					#if GMS2
						@oPlayer = instance_create_depth(0, 0, @onlinePlayerDepth, @onlinePlayer);
					#endif
					#if not GMS2
						@oPlayer = instance_create(0, 0, @onlinePlayer);
					#endif
					@oPlayer.@ID = buffer_read_string(@buffer);
					@oPlayer.x = buffer_read_int32(@buffer);
					@oPlayer.y = buffer_read_int32(@buffer);
					@oPlayer.@targetX = @oPlayer.x;
					@oPlayer.@targetY = @oPlayer.y;
					@oPlayer.@lerpInit = true;
					@oPlayer.sprite_index = buffer_read_int32(@buffer);
					@oPlayer.image_speed = buffer_read_float32(@buffer);
					@oPlayer.image_xscale = buffer_read_float32(@buffer);
					@oPlayer.image_yscale = buffer_read_float32(@buffer);
					@oPlayer.image_angle = buffer_read_float32(@buffer);
					@oPlayer.@oRoom = buffer_read_uint16(@buffer);
					@oPlayer.@name = buffer_read_string(@buffer);
					@oPlayer.@team = buffer_read_uint8(@buffer);
				}
				@showPlayerList = buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				for(@i = 0; @i < @n; @i += 1){
					#if GMS2
						@oPlayer = instance_create_depth(0, 0, @onlinePlayerDepth, @onlinePlayer);
					#endif
					#if not GMS2
						@oPlayer = instance_create(0, 0, @onlinePlayer);
					#endif
					@oPlayer.@ID = buffer_read_string(@buffer);
					@oPlayer.x = buffer_read_i32(@buffer);
					@oPlayer.y = buffer_read_i32(@buffer);
					@oPlayer.@targetX = @oPlayer.x;
					@oPlayer.@targetY = @oPlayer.y;
					@oPlayer.@lerpInit = true;
					@oPlayer.sprite_index = buffer_read_i32(@buffer);
					@oPlayer.image_speed = buffer_read_float(@buffer);
					@oPlayer.image_xscale = buffer_read_float(@buffer);
					@oPlayer.image_yscale = buffer_read_float(@buffer);
					@oPlayer.image_angle = buffer_read_float(@buffer);
					@oPlayer.@oRoom = buffer_read_u16(@buffer);
					@oPlayer.@name = buffer_read_string(@buffer);
					@oPlayer.@team = buffer_read_u8(@buffer);
				}
				@showPlayerList = buffer_read_u8(@buffer);
			#endif
			@restoredFromTemp = true;
			@connected = true;
			@hbCounter = room_speed * 5;
			@listCounter = room_speed * 15;
		}else{
			file_delete("tempOnline");
			if(file_exists("tempOnline2")) file_delete("tempOnline2");
			if(file_exists("tempOnlineChat")) file_delete("tempOnlineChat");
			socket_destroy(@socket);
			@socket = socket_create();
			socket_connect(@socket, @server, @tcpPort);
			@udpsocket = udpsocket_create();
			udpsocket_start(@udpsocket, false, 0);
			udpsocket_set_destination(@udpsocket, @server, @udpPort);
			@reconnecting = true;
			@reconnectTimer = room_speed;
			@reconnectAttempts = 0;
			@restoredFromTemp = true;
		}
	}
	// RESTORE CHAT HISTORY
	if(file_exists("tempOnlineChat")){
		buffer_clear(@buffer);
		#if not GMNET
			buffer_read_from_file(@buffer, "tempOnlineChat");
			@chatHistCount = buffer_read_uint16(@buffer);
			if(@chatHistCount > @chatHistMax) @chatHistCount = @chatHistMax;
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				@chatHistName[@ci] = buffer_read_string(@buffer);
				@chatHistMsg[@ci] = buffer_read_string(@buffer);
				@chatHistTeam[@ci] = buffer_read_uint8(@buffer);
			}
		#endif
		#if GMNET
			buffer_load(@buffer, "tempOnlineChat");
			@chatHistCount = buffer_read_u16(@buffer);
			if(@chatHistCount > @chatHistMax) @chatHistCount = @chatHistMax;
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				@chatHistName[@ci] = buffer_read_string(@buffer);
				@chatHistMsg[@ci] = buffer_read_string(@buffer);
				@chatHistTeam[@ci] = buffer_read_u8(@buffer);
			}
		#endif
		file_delete("tempOnlineChat");
	}
	if(!@restoredFromTemp){
#endif
	@socket = socket_create();
	socket_connect(@socket, @server, @tcpPort);
	// QoL: credentials come from the account store - env (P1) -> this folder (P2)
	// -> global %APPDATA%\iwpo\account.ini (P3). The dialogs only run on the very
	// first launch (@accLoaded == 0). RACE was removed (team system + T-key save
	// toggle cover it). The socket layer queues writes until the handshake
	// completes, so NAME below can be queued right away.
	if(!@accLoaded){
		#if STUDIO
			global.__ONLINE_accName = get_string("Enter your name:", "");
		#endif
		#if not STUDIO
			global.__ONLINE_accName = wd_input_box("Name", "Enter your name:", "");
		#endif
		global.__ONLINE_accName = @account_trim(global.__ONLINE_accName);
		if(global.__ONLINE_accName == "") global.__ONLINE_accName = "Anonymous";
		#if STUDIO
			global.__ONLINE_accPassword = get_string("Leave it empty for no password:", "");
		#endif
		#if not STUDIO
			global.__ONLINE_accPassword = wd_input_box("Password", "Leave it empty for no password:", "");
		#endif
		global.__ONLINE_accPassword = @account_trim(global.__ONLINE_accPassword);
		global.__ONLINE_accStore = 0;
		@account_save();
	}
	@account_apply();
	buffer_clear(@buffer);
	#if not GMNET
		buffer_write_uint8(@buffer, 3);
		buffer_write_string(@buffer, @name);
		buffer_write_string(@buffer, @selfGameID);
		buffer_write_string(@buffer, "%arg4");
		buffer_write_string(@buffer, @version);
		buffer_write_uint8(@buffer, @hasPassword);
		buffer_write_uint8(@buffer, @protocolVersion);
		socket_write_message(@socket, @buffer);
		@udpsocket = udpsocket_create();
		udpsocket_start(@udpsocket, false, 0);
		udpsocket_set_destination(@udpsocket, @server, @udpPort);
		buffer_clear(@buffer);
		buffer_write_uint8(@buffer, 8);
		buffer_write_uint8(@buffer, @team);
		socket_write_message(@socket, @buffer);
		buffer_clear(@buffer);
		buffer_write_uint8(@buffer, 0);
	#endif
	#if GMNET
		buffer_write_u8(@buffer, 3);
		buffer_write_string(@buffer, @name);
		buffer_write_string(@buffer, @selfGameID);
		buffer_write_string(@buffer, "%arg4");
		buffer_write_string(@buffer, @version);
		buffer_write_u8(@buffer, @hasPassword);
		buffer_write_u8(@buffer, @protocolVersion);
		socket_write_message(@socket, @buffer);
		@udpsocket = udpsocket_create();
		udpsocket_start(@udpsocket, false, 0);
		udpsocket_set_destination(@udpsocket, @server, @udpPort);
		buffer_clear(@buffer);
		buffer_write_u8(@buffer, 8);
		buffer_write_u8(@buffer, @team);
		socket_write_message(@socket, @buffer);
		buffer_clear(@buffer);
		buffer_write_u8(@buffer, 0);
	#endif
	udpsocket_send(@udpsocket, @buffer);
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
@sndChatboxId = asset_get_index("__ONLINE_sndChatbox");
@sndSavedId = asset_get_index("__ONLINE_sndSaved");
#endif

#if CJKTEXT
__ONLINE_cjk_init();
#endif

// SKINS: scan the skins folder, then restore the persisted selection. The
// saved directory name locates the skin instantly; if the folder was renamed
// or deleted (or the config predates skinDir), fall back to a one-time hash
// scan that stops at the first match. The hash scan re-hashes folders until
// the hit, so it must NOT run on the normal path: with ~200 skins installed
// it cost seconds on every game_restart.
@skin_scan();
// P0/P3: hash cache - one ini parse replaces up to 196 x 25ms of MD5 per
// game_restart (per death in games that restart on load).
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
// S2: (re)apply remote skins to any pre-existing player instances.
for(@skI = 0; @skI < instance_number(@onlinePlayer); @skI += 1){
    @skin_apply_remote(instance_find(@onlinePlayer, @skI));
}
// S4: bullet sharing init (no-op when the converter could not resolve a
// bullet object; @bActive stays 0 and every entry is inert).
@bActive = 0;
@bullet_init();

// N3: built-in notes icon atlas (iwponotes/icons.png). Loads AFTER the skin
// sprite sweep so the fresh id lands in the bookkeeper record (game_restart
// frees exactly this id next time). -1 = atlas missing; iconId 16-31 then
// render as the vector HERE fallback.
@note_atlas_load();
// N4: restore the notes store from the previous session (past-toast)
@note_persist_load();
