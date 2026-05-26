/// ONLINE
// %arg0: The ID of the game
// %arg1: The server
// %arg2: The TCP port
// %arg3: The UDP port
// %arg4: The game name
// %arg5: The version
if(!instance_exists(@userInterface)){
	instance_create(0, 0, @userInterface);
}
#if HTTPDLL_INIT
if (!file_exists("http_dll_2_3.dll"))
	show_message("http_dll_2_3.dll not found.#Please place it in the same folder as the exe.");
else{
	@httpdll_init();
	#if CJKTEXT
	set_utf8_mode(1);
	#endif
}
#endif
@connected = false;
@buffer = buffer_create();
@selfID = "";
@name = "";
@selfGameID = "%arg0";
@server = "%arg1";
@tcpPort = %arg2;
@udpPort = %arg3;
@version = "%arg5";
@protocolVersion = 2;
@race = false;
@password = "";
@vis = 0;
@save_enabled = 1;
@udpReady = false;
@udpRetryCount = 0;
@udpGraceFrames = room_speed*3;
@reconnecting = false;
@reconnectDelay = 0;
@reconnectTimer = 0;
@reconnectAttempts = 0;
@customSlot = 0;
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
@kbFocus = 1;
@kbDelay = 0;
@customSlotPrev = -1;
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
@rClearAutoSet = false;
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
@cfgDir = program_directory;
@cfgPath = @cfgDir + "\@config.ini";
@serverPath = @cfgDir + "\@server.txt";
@savesPath = "@saves";
if file_exists(@cfgPath) {
	ini_open("@config.ini");
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
	@lerpEnabled = ini_read_real("config", "lerp", 1);
	@fastLoadEnabled = ini_read_real("config", "fast_load", 1);
	@team = ini_read_real("config", "team", @team);
	if(@team < 0 || @team > 7) @team = 0;
	@team = floor(@team);
	@syncEnabled = ini_read_real("sync", "sync_enabled", 1);
	@syncEntryCount = ini_read_real("sync", "entryCount", 0);
	if(@syncEntryCount < 0) @syncEntryCount = 0;
	if(@syncEntryCount > 16) @syncEntryCount = 16;
	for(@scI = 0; @scI < @syncEntryCount; @scI += 1){
		@syncName[@scI]      = ini_read_string("sync", "sync"+string(@scI)+"_name", "");
		@syncCount[@scI]     = ini_read_real  ("sync", "sync"+string(@scI)+"_count", 0);
		if(@syncCount[@scI] < 1) @syncCount[@scI] = 0;
		if(@syncCount[@scI] > 512) @syncCount[@scI] = 512;
		@syncSlotCount[@scI] = ceil(@syncCount[@scI] / 32);
		@syncDirty[@scI]     = true;
		@syncLastSig[@scI]   = "";
	}
	ini_close();
} else if file_exists(@serverPath) {
	@file = file_text_open_read(@serverPath);
	@line = file_text_read_string(@file);
	file_text_close(@file);
	if @line != "" {
		@server = @line;
	}
}
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
			@race = buffer_read_uint8(@buffer);
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
			@race = buffer_read_u8(@buffer);
			@n = buffer_read_u16(@buffer);
			@vis = buffer_read_u16(@buffer);
			@save_enabled = buffer_read_u16(@buffer);
			@team = buffer_read_u8(@buffer);
			@lerpEnabled = buffer_read_u8(@buffer);
		#endif
	// VALIDATE SOCKET
	@tcpState = socket_get_state(@socket);
	if(@tcpState == 2){
			#if not GMNET
				for(@i = 0; @i < @n; @i += 1){
					@oPlayer = instance_create(0, 0, @onlinePlayer);
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
					@oPlayer = instance_create(0, 0, @onlinePlayer);
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
			if(file_exists("tempOnline2")){
				file_delete("tempOnline2");
			}
			if(file_exists("tempOnlineChat")){
				file_delete("tempOnlineChat");
			}
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
		@socketConnectResult = socket_connect(@socket, @server, @tcpPort);
	#if STUDIO
		@name = get_string("Enter your name:", "");
	#endif
	#if not STUDIO
		#if CJKTEXT
		@name = ansi_to_utf8(wd_input_box("Name", "Enter your name:", ""));
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
		@password = ansi_to_utf8(wd_input_box("Password", "Leave it empty for no password:", ""));
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
	buffer_clear(@buffer);
	@hasPassword = 0;
	if(string_length(string(@password)) > 0) @hasPassword = 1;
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
@heartbeat = 0;
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
