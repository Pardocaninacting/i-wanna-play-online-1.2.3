/// ONLINE
// %arg0: The name of the player object
// %arg1: The name of the player2 object if it exists
instance_activate_object(@userInterface);
instance_activate_object(@onlinePlayer);
instance_activate_object(@chatbox);
instance_activate_object(@playerSaved);
if(!instance_exists(@userInterface)){
	#if GMS2
		instance_create_depth(0, 0, -2147483648, @userInterface);
	#endif
	#if not GMS2
		instance_create(0, 0, @userInterface);
	#endif
}
// POSITION ROLLBACK
if(@saveHistPending){
	@_rp = %arg0;
	#if PLAYER2
		@_gravSwapped = 0;
		#if not STUDIO
			if(@saveHistPendingGrav == 1){
				if(instance_exists(%arg0)){
					instance_create(0, 0, %arg1);
					with(%arg0){ instance_destroy(); }
					@_gravSwapped = 1;
				}
				@_rp = %arg1;
			}else{
				if(instance_exists(%arg1) && !instance_exists(%arg0)){
					instance_create(0, 0, %arg0);
					with(%arg1){ instance_destroy(); }
					@_gravSwapped = -1;
				}
			}
		#endif
		#if STUDIO
			if(!instance_exists(@_rp)) @_rp = %arg1;
		#endif
	#endif
	if(instance_exists(@_rp) && room == @saveHistPendingRoom){
		#if STUDIO
			#if GRAVITY
			if(global.grav != @saveHistPendingGrav){
				#if SCR_FLIP_GRAV
					scrFlipGrav();
				#endif
				#if not SCR_FLIP_GRAV
					with(@_rp){
						event_user(0);
					}
				#endif
			}
			#endif
		#endif
		#if not STUDIO
			global.grav = @saveHistPendingGrav;
		#endif
		@_rp.x = @saveHistPendingX;
		@_rp.y = @saveHistPendingY;
		@saveHistPending = false;
	}
}
// SPECTATOR RESTORE
if(@specPending){
	if(room == @specRoom){
		@p = %arg0;
		#if PLAYER2
			if(@specGrav == 1){
				if(instance_exists(%arg0)){
					@specDepth = instance_find(%arg0, 0).depth;
					#if GMS2
						instance_create_depth(0, 0, @specDepth, %arg1);
					#endif
					#if not GMS2
						instance_create(0, 0, %arg1);
					#endif
					with(%arg0){
						instance_destroy();
					}
				}
				@p = %arg1;
			}else{
				if(instance_exists(%arg1) && !instance_exists(%arg0)){
					@specDepth = instance_find(%arg1, 0).depth;
					#if GMS2
						instance_create_depth(0, 0, @specDepth, %arg0);
					#endif
					#if not GMS2
						instance_create(0, 0, %arg0);
					#endif
					with(%arg1){
						instance_destroy();
					}
				}
			}
		#endif
		if(instance_exists(@p)){
			@p = instance_find(@p, 0);
			@p.x = @specX;
			@p.y = @specY;
		}else{
			#if GMS2
				@p = instance_create_depth(@specX, @specY, 0, @specObj);
			#endif
			#if not GMS2
				@p = instance_create(@specX, @specY, @specObj);
			#endif
		}
		#if STUDIO
			#if GRAVITY
			if(global.grav != @specGrav){
				#if SCR_FLIP_GRAV
					scrFlipGrav();
				#endif
				#if not SCR_FLIP_GRAV
					with(@p){
						event_user(0);
					}
				#endif
			}
			#endif
		#endif
		#if not STUDIO
			global.grav = @specGrav;
		#endif
		if(view_enabled && view_visible[0]){
			view_object[0] = @p;
		}
		@spectating = false;
		@specPending = false;
	}
}
// TCP SOCKETS
#if not GMNET
__ONLINE_socket_update_read(@socket);
#endif
#if GMNET
__ONLINE_socket_receive(@socket);
#endif
while(__ONLINE_socket_read_message(@socket, @buffer)){
	#if not GMNET
		@opcode = __ONLINE_buffer_read_uint8(@buffer);
	#endif
	#if GMNET
		@opcode = __ONLINE_buffer_read_u8(@buffer);
	#endif
	switch(@opcode){
		case 0:
			// CREATED
			@ID = __ONLINE_buffer_read_string(@buffer);
			@createdName = __ONLINE_buffer_read_string(@buffer);
			@found = false;
			@oPlayer = noone;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@found = true;
				}
			}
			if(!@found){
				#if GMS2
					@oPlayer = instance_create_depth(0, 0, @onlinePlayerDepth, @onlinePlayer);
				#endif
				#if not GMS2
					@oPlayer = instance_create(0, 0, @onlinePlayer);
				#endif
				@oPlayer.@ID = @ID;
				if(ds_map_exists(@teamMap, @ID)){
					@oPlayer.@team = ds_map_find_value(@teamMap, @ID);
				}
			}
			@oPlayer.@name = @createdName;
			@skin_apply_remote(@oPlayer);
			break;
		case 1:
			// DESTROYED
			@ID = __ONLINE_buffer_read_string(@buffer);
			@found = false;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@oPlayer.@avatarAlive = false;
					@oPlayer.@targetX = @oPlayer.x;
					@oPlayer.@targetY = @oPlayer.y;
					@oPlayer.visible = false;
					@found = true;
				}
			}
			break;
		case 2:
			// INCOMPATIBLE VERSION
			@lastVersion = __ONLINE_buffer_read_string(@buffer);
			@errorMessage = "Your tool uses the version "+@version+" but the oldest compatible version is "+@lastVersion+". Please update your tool.";
			#if STUDIO
				show_message(@errorMessage);
			#endif
			#if not STUDIO
				wd_message_simple(@errorMessage);
			#endif
			game_end();
			exit;
			break;
		case 4:
			// CHAT MESSAGE
			@ID = __ONLINE_buffer_read_string(@buffer);
			@found = false;
			@oPlayer = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@found = true;
				}
			}
			if(@found){
				@message = __ONLINE_buffer_read_string(@buffer);
				#if STUDIO
				@message = strip_non_bmp(@message);
				#endif
					@bubbleMsg = @message;
				#if GM80
				@bubbleMsg = __ONLINE_gbk_trunc(@bubbleMsg, 77, "...");
				#endif
				#if CJKTEXT
				@bubbleMsg = __ONLINE_gbk_trunc(@bubbleMsg, 77, "...");
				#endif
				#if not GM80
				#if not CJKTEXT
				if(string_length(@bubbleMsg) > 80){
					@bubbleMsg = string_copy(@bubbleMsg, 1, 77) + "...";
				}
				#endif
				#endif
				#if GMS2
					@oCb = instance_create_depth(0, 0, @chatboxDepth, @chatbox);
				#endif
				#if not GMS2
					@oCb = instance_create(0, 0, @chatbox);
				#endif
				@oCb.@message = @bubbleMsg;
				@oCb.@follower = @oPlayer;
				if(@chatHistCount < @chatHistMax){
					@chatHistName[@chatHistCount] = @oPlayer.@name;
					@chatHistMsg[@chatHistCount] = @message;
					@chatHistTeam[@chatHistCount] = @oPlayer.@team;
					@chatHistCount += 1;
				}else{
						for(@ci = 0; @ci < @chatHistMax - 1; @ci += 1){
						@chatHistName[@ci] = @chatHistName[@ci + 1];
						@chatHistMsg[@ci] = @chatHistMsg[@ci + 1];
						@chatHistTeam[@ci] = @chatHistTeam[@ci + 1];
					}
					@chatHistName[@chatHistMax - 1] = @oPlayer.@name;
					@chatHistMsg[@chatHistMax - 1] = @message;
					@chatHistTeam[@chatHistMax - 1] = @oPlayer.@team;
				}
				if(@oPlayer.visible){
					#if STUDIO
						audio_play_sound(@sndChatbox, 0, false);
					#endif
					#if not STUDIO
						sound_play(@sndChatbox);
					#endif
				}
			}
			break;
		case 5:
			// SOMEONE SAVED
			if(!@race){
				#if not GMNET
					@sGravity = __ONLINE_buffer_read_uint8(@buffer);
					@sName = __ONLINE_buffer_read_string(@buffer);
					@sX = __ONLINE_buffer_read_int32(@buffer);
					@sY = __ONLINE_buffer_read_float64(@buffer);
					@sRoom = __ONLINE_buffer_read_int16(@buffer);
				#endif
				#if GMNET
					@sGravity = __ONLINE_buffer_read_u8(@buffer);
					@sName = __ONLINE_buffer_read_string(@buffer);
					@sX = __ONLINE_buffer_read_i32(@buffer);
					@sY = __ONLINE_buffer_read_double(@buffer);
					@sRoom = __ONLINE_buffer_read_i16(@buffer);
				#endif
				#if GMS2
					@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
				#endif
				#if not GMS2
					@a = instance_create(0, 0, @playerSaved);
				#endif
				@a.@name = @sName;
				@a.@state = -1;
				if(@save_enabled){
				@shIdx = @saveHistCount;
				@saveHistCount += 1;
				@shMutation += 1;
				@saveHistFav[@shIdx] = 0;
				@saveHistHotkey[@shIdx] = 0;
				@saveHistGrav[@shIdx] = @sGravity;
				@saveHistX[@shIdx] = @sX;
				@saveHistY[@shIdx] = @sY;
				@saveHistRoom[@shIdx] = @sRoom;
				@saveHistName[@shIdx] = @sName;
				@saveHistRoomName[@shIdx] = room_get_name(@sRoom);
				@saveHistTime[@shIdx] = date_current_datetime();
				if(!@saveHistDirty){
					@saveHistDirtyTimer = room_speed * 3;
				}
				@saveHistDirty = true;
				}
				if(@save_enabled){
					@sSaved = true;
					#if TEMPFILE
						__ONLINE_buffer_clear(@buffer);
						#if not GMNET
							__ONLINE_buffer_write_uint8(@buffer, @sGravity);
							__ONLINE_buffer_write_int32(@buffer, @sX);
							__ONLINE_buffer_write_float64(@buffer, @sY);
							__ONLINE_buffer_write_int16(@buffer, @sRoom);
							__ONLINE_buffer_write_to_file(@buffer, "tempOnline2");
						#endif
						#if GMNET
							__ONLINE_buffer_write_u8(@buffer, @sGravity);
							__ONLINE_buffer_write_i32(@buffer, @sX);
							__ONLINE_buffer_write_double(@buffer, @sY);
							__ONLINE_buffer_write_i16(@buffer, @sRoom);
							__ONLINE_buffer_save(@buffer, "tempOnline2");
						#endif
					#endif
				}
				#if STUDIO
					audio_play_sound(@sndSaved, 0, false);
				#endif
				#if not STUDIO
					sound_play(@sndSaved);
				#endif
			}
			break;
		case 6:
			// SELF ID
			@selfID = __ONLINE_buffer_read_string(@buffer);
			@listCounter = room_speed * 15;
			break;
		case 7:
			// CUSTOM DATA
			#if not GMNET
				@cs_v2flag = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@cs_v2flag = __ONLINE_buffer_read_u8(@buffer);
			#endif
			if(@cs_v2flag != 1){
				break;
			}
			@cs_owner = __ONLINE_buffer_read_string(@buffer);
			#if not GMNET
				@cs_entryN = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@cs_entryN = __ONLINE_buffer_read_u8(@buffer);
			#endif
			if(@cs_entryN > 16){ break; }
			for(@cs_k = 0; @cs_k < @cs_entryN; @cs_k += 1){
				@cs_rname = __ONLINE_buffer_read_string(@buffer);
				#if not GMNET
					@cs_rcount    = __ONLINE_buffer_read_uint16(@buffer);
					@cs_rslotCnt  = __ONLINE_buffer_read_uint16(@buffer);
				#endif
				#if GMNET
					@cs_rcount    = __ONLINE_buffer_read_u16(@buffer);
					@cs_rslotCnt  = __ONLINE_buffer_read_u16(@buffer);
				#endif
				if(@cs_rcount > 512 || @cs_rslotCnt > 16){ break; }
				for(@cs_s = 0; @cs_s < @cs_rslotCnt; @cs_s += 1){
					#if not GMNET
						@cs_recvSlot[@cs_s] = __ONLINE_buffer_read_uint32(@buffer);
					#endif
					#if GMNET
						@cs_recvSlot[@cs_s] = __ONLINE_buffer_read_u32(@buffer);
					#endif
				}
				@cs_matchIdx = -1;
				for(@cs_i = 0; @cs_i < @syncEntryCount; @cs_i += 1){
					if(@syncName[@cs_i] == @cs_rname){ @cs_matchIdx = @cs_i; break; }
				}
				if(@cs_matchIdx == -1) continue;
				if(!@syncEnabled) continue;
				if(!variable_global_exists(@cs_rname)) continue;
				@cs_applyCount = min(@cs_rcount, @syncCount[@cs_matchIdx]);
				for(@cs_s = 0; @cs_s < @cs_rslotCnt; @cs_s += 1){
					@cs_v = @cs_recvSlot[@cs_s];
					if(@cs_v == 0) continue;
					for(@cs_b = 0; @cs_b < 32; @cs_b += 1){
						@cs_idx = @cs_s * 32 + @cs_b + 1;
						if(@cs_idx > @cs_applyCount) break;
						if(((@cs_v >> @cs_b) & 1) == 0) continue;
						#if not STUDIO
							execute_string("global." + @cs_rname + "[" + string(@cs_idx) + "] = 1;");
						#endif
						#if STUDIO
							@cs_arr = variable_global_get(@cs_rname);
							if(is_array(@cs_arr) && array_length_1d(@cs_arr) > @cs_idx){
								@cs_arr[@cs_idx] = 1;
								variable_global_set(@cs_rname, @cs_arr);
							}
						#endif
					}
				}
				@syncLastSig[@cs_matchIdx] = "";
			}
			break;
		case 8:
			// TEAM
			@ID = __ONLINE_buffer_read_string(@buffer);
			#if not GMNET
				@receivedTeam = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@receivedTeam = __ONLINE_buffer_read_u8(@buffer);
			#endif
			@found = false;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					if(@receivedTeam == 254){
						@oPlayer.@spectating = true;
					}else{
						@oPlayer.@spectating = false;
						if(@receivedTeam < 8) @oPlayer.@team = @receivedTeam;
					}
					@found = true;
				}
			}
			if(@receivedTeam < 8){
				if(ds_map_exists(@teamMap, @ID)){
					ds_map_replace(@teamMap, @ID, @receivedTeam);
				}else{
					ds_map_add(@teamMap, @ID, @receivedTeam);
				}
			}
			break;
		case 9:
			// RATING
			#if not GMNET
				@ratingReply = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@ratingReply = __ONLINE_buffer_read_u8(@buffer);
			#endif
			@ratingSubmitting = false;
			if(@ratingReply == 1){
				@ratingResult = 1;
			}else{
				@ratingResult = 2;
			}
			@ratingResultTimer = room_speed * 3;
			@ratingCooldown = room_speed * 10;
			break;
		case 10:
			// LIST RECONCILE
			#if not GMNET
				@listCount = __ONLINE_buffer_read_uint16(@buffer);
			#endif
			#if GMNET
				@listCount = __ONLINE_buffer_read_u16(@buffer);
			#endif
			@listSeen = ds_map_create();
			for(@li = 0; @li < @listCount; @li += 1){
				@listID = __ONLINE_buffer_read_string(@buffer);
				@listName = __ONLINE_buffer_read_string(@buffer);
				#if not GMNET
					@listTeam = __ONLINE_buffer_read_uint8(@buffer);
				#endif
				#if GMNET
					@listTeam = __ONLINE_buffer_read_u8(@buffer);
				#endif
				ds_map_add(@listSeen, @listID, 1);
				if(@listTeam < 8){
					if(ds_map_exists(@teamMap, @listID)){
						ds_map_replace(@teamMap, @listID, @listTeam);
					}else{
						ds_map_add(@teamMap, @listID, @listTeam);
					}
				}
				@found = false;
				for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
					@oPlayer = instance_find(@onlinePlayer, @i);
					if(@oPlayer.@ID == @listID){
						@oPlayer.@name = @listName;
						if(@listTeam == 254){
							@oPlayer.@spectating = true;
						}else{
							@oPlayer.@spectating = false;
							if(@listTeam < 8) @oPlayer.@team = @listTeam;
						}
						@found = true;
					}
				}
				if(!@found){
					#if GMS2
						@oPlayer = instance_create_depth(0, 0, @onlinePlayerDepth, @onlinePlayer);
					#endif
					#if not GMS2
						@oPlayer = instance_create(0, 0, @onlinePlayer);
					#endif
					@oPlayer.@ID = @listID;
					@oPlayer.@name = @listName;
					if(@listTeam == 254){
						@oPlayer.@spectating = true;
					}else{
						@oPlayer.@spectating = false;
						if(@listTeam < 8) @oPlayer.@team = @listTeam;
					}
					@skin_apply_remote(@oPlayer);
				}
			}
			for(@i = instance_number(@onlinePlayer) - 1; @i >= 0; @i -= 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(!ds_map_exists(@listSeen, @oPlayer.@ID)){
					// Leaving player: give the remote-skin slot back to the pool.
					@skin_slot_release(@oPlayer, @oPlayer.@skinSlot);
					with(@oPlayer){
						instance_destroy();
					}
				}
			}
			ds_map_destroy(@listSeen);
			break;
		case 11:
			// PING
			@pingSenderID = __ONLINE_buffer_read_string(@buffer);
			#if not GMNET
				@pingPRoom = __ONLINE_buffer_read_int32(@buffer);
				@pingPx = __ONLINE_buffer_read_float32(@buffer);
				@pingPy = __ONLINE_buffer_read_float32(@buffer);
				@pingPtype = __ONLINE_buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@pingPRoom = __ONLINE_buffer_read_i32(@buffer);
				@pingPx = __ONLINE_buffer_read_float(@buffer);
				@pingPy = __ONLINE_buffer_read_float(@buffer);
				@pingPtype = __ONLINE_buffer_read_u8(@buffer);
			#endif
			if(@pingPRoom != room) break;
			@pingSenderName = "?";
			@pingSenderTeam = -1;
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @pingSenderID){
					@pingSenderName = @oPlayer.@name;
					@pingSenderTeam = @oPlayer.@team;
					break;
				}
			}
			@pingX[@pingHead] = @pingPx;
			@pingY[@pingHead] = @pingPy;
			@pingT[@pingHead] = current_time;
			@pingType[@pingHead] = @pingPtype;
			@pingName[@pingHead] = @pingSenderName;
			@pingSenderIDArr[@pingHead] = @pingSenderID;
			if(@pingSenderTeam >= 0 && @pingSenderTeam < 8){
				@pingTeamArr[@pingHead] = @pingSenderTeam;
			}else if(ds_map_exists(@teamMap, @pingSenderID)){
				@pingTeamArr[@pingHead] = ds_map_find_value(@teamMap, @pingSenderID);
			}else{
				@pingTeamArr[@pingHead] = 0;
			}
			if(@vis == 0 && @pingSenderID != @selfID){
				#if STUDIO
					audio_play_sound(@sndChatbox, 0, false);
				#endif
				#if not STUDIO
					sound_play(@sndChatbox);
				#endif
			}
			@pingHead = (@pingHead + 1) mod @pingMax;
			break;
		case 13:
			// SKIN NOTIFY: stringNT playerId, 16-byte hash, stringNT dir hint.
			// Zero hash = the player has no skin selected.
			@skNID = __ONLINE_buffer_read_string(@buffer);
			@skNHex = "";
			@skNZero = 0;
			for(@skB = 0; @skB < 16; @skB += 1){
				#if not GMNET
					@skByte = __ONLINE_buffer_read_uint8(@buffer);
				#endif
				#if GMNET
					@skByte = __ONLINE_buffer_read_u8(@buffer);
				#endif
				@skNZero = @skNZero | @skByte;
				@skNHex += string_char_at("0123456789abcdef", (@skByte div 16) + 1) + string_char_at("0123456789abcdef", (@skByte mod 16) + 1);
			}
			@skNHint = __ONLINE_buffer_read_string(@buffer);
			if(@skNZero == 0){
				ds_map_delete(@skinMap, @skNID);
				ds_map_delete(@skinMapHint, @skNID);
			}else{
				// GM8.0 ds_map_replace only replaces EXISTING keys (it never
				// adds), so a fresh playerId needs the exists/add form.
				if(ds_map_exists(@skinMap, @skNID)){
					ds_map_replace(@skinMap, @skNID, @skNHex);
				}else{
					ds_map_add(@skinMap, @skNID, @skNHex);
				}
				if(ds_map_exists(@skinMapHint, @skNID)){
					ds_map_replace(@skinMapHint, @skNID, @skNHint);
				}else{
					ds_map_add(@skinMapHint, @skNID, @skNHint);
				}
			}
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @skNID){
					@skin_apply_remote(@oPlayer);
					break;
				}
			}
			break;
		case 15:
			// SKIN MANIFEST (auto-download): 16-byte hash echo, u8 status
			// (0 ok / 1 not found), then u8 fileCount + [stringNT name,
			// u32 size] x count. Stray replies are dropped unread.
			if(@skinDlState == 1){
				@skMHex = "";
				for(@skB = 0; @skB < 16; @skB += 1){
					#if not GMNET
						@skByte = __ONLINE_buffer_read_uint8(@buffer);
					#endif
					#if GMNET
						@skByte = __ONLINE_buffer_read_u8(@buffer);
					#endif
					@skMHex += string_char_at("0123456789abcdef", (@skByte div 16) + 1) + string_char_at("0123456789abcdef", (@skByte mod 16) + 1);
				}
				#if not GMNET
					@skMStatus = __ONLINE_buffer_read_uint8(@buffer);
				#endif
				#if GMNET
					@skMStatus = __ONLINE_buffer_read_u8(@buffer);
				#endif
				if(@skMHex != @skinDlHash){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				if(@skMStatus != 0){
					// Not in the server library (e.g. a private skin).
					@skin_dl_fail("Skin not on server (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				#if not GMNET
					@skinDlCount = __ONLINE_buffer_read_uint8(@buffer);
				#endif
				#if GMNET
					@skinDlCount = __ONLINE_buffer_read_u8(@buffer);
				#endif
				if(@skinDlCount < 1 || @skinDlCount > 32){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				@skMOk = true;
				@skMTotal = 0;
				for(@i = 0; @i < @skinDlCount; @i += 1){
					@skinDlName[@i] = __ONLINE_buffer_read_string(@buffer);
					#if not GMNET
						@skinDlFSize[@i] = __ONLINE_buffer_read_uint32(@buffer);
					#endif
					#if GMNET
						@skinDlFSize[@i] = __ONLINE_buffer_read_u32(@buffer);
					#endif
					if(!@skin_dl_name_ok(@skinDlName[@i])) @skMOk = false;
					if(@skinDlFSize[@i] > 1048576) @skMOk = false;
					@skMTotal += @skinDlFSize[@i];
				}
				if(!@skMOk || @skMTotal > 4194304){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				@skinDlIdx = 0;
				@skinDlPos = 0;
				__ONLINE_buffer_clear(@dlBuffer);
				@skin_dl_send_req(16, @skinDlHash, @skinDlName[0]);
				@skinDlState = 2;
				@skinDlWait = room_speed * 15;
			}
			break;
		case 17:
			// SKIN FILE (auto-download): 16-byte hash echo, stringNT name,
			// u8 status, u32 totalSize, u32 offset, u16 chunkLen, raw bytes.
			// Chunks arrive in order; the file is flushed to disk when its
			// byte count is complete, then the next file is requested.
			if(@skinDlState == 2){
				@skFHex = "";
				for(@skB = 0; @skB < 16; @skB += 1){
					#if not GMNET
						@skByte = __ONLINE_buffer_read_uint8(@buffer);
					#endif
					#if GMNET
						@skByte = __ONLINE_buffer_read_u8(@buffer);
					#endif
					@skFHex += string_char_at("0123456789abcdef", (@skByte div 16) + 1) + string_char_at("0123456789abcdef", (@skByte mod 16) + 1);
				}
				@skFName = __ONLINE_buffer_read_string(@buffer);
				#if not GMNET
					@skFStatus = __ONLINE_buffer_read_uint8(@buffer);
				#endif
				#if GMNET
					@skFStatus = __ONLINE_buffer_read_u8(@buffer);
				#endif
				if(@skFHex != @skinDlHash || @skFStatus != 0 || @skFName != @skinDlName[@skinDlIdx]){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				#if not GMNET
					@skFTotal = __ONLINE_buffer_read_uint32(@buffer);
					@skFOff = __ONLINE_buffer_read_uint32(@buffer);
					@skFLen = __ONLINE_buffer_read_uint16(@buffer);
				#endif
				#if GMNET
					@skFTotal = __ONLINE_buffer_read_u32(@buffer);
					@skFOff = __ONLINE_buffer_read_u32(@buffer);
					@skFLen = __ONLINE_buffer_read_u16(@buffer);
				#endif
				if(@skFTotal != @skinDlFSize[@skinDlIdx] || @skFOff != @skinDlPos || @skFLen > 16384){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				if(@skFOff + @skFLen > @skFTotal){
					@skin_dl_fail("Skin download failed (" + string_copy(@skinDlHash, 1, 8) + ")");
					break;
				}
				#if STUDIO
					// GMS: stream the file straight to disk with file_bin_* instead of
					// flushing @dlBuffer through the DLL. The DLL write resolves relative
					// paths against the process CWD (the exe dir), while directory_create
					// is sandboxed into the per-user writable area - the dir the DLL sees
					// does not exist, so the write silently fails. file_bin_* share the
					// directory_create sandbox, and the readers (file_find/sprite_add)
					// check the writable area, so writer and readers agree.
					if(@skFOff == 0){
						@skinDlFile = file_bin_open("iwposkins" + chr(92) + @skinDlDir + chr(92) + @skFName, 1);
					}
				#endif
				for(@skB = 0; @skB < @skFLen; @skB += 1){
					#if not GMNET
						@skByte = __ONLINE_buffer_read_uint8(@buffer);
					#endif
					#if GMNET
						@skByte = __ONLINE_buffer_read_u8(@buffer);
					#endif
					#if STUDIO
						file_bin_write_byte(@skinDlFile, @skByte);
					#endif
					#if not STUDIO
						#if not GMNET
							__ONLINE_buffer_write_uint8(@dlBuffer, @skByte);
						#endif
						#if GMNET
							__ONLINE_buffer_write_u8(@dlBuffer, @skByte);
						#endif
					#endif
				}
				@skinDlPos += @skFLen;
				@skinDlWait = room_speed * 15;
				if(@skinDlPos >= @skFTotal){
					#if STUDIO
						file_bin_close(@skinDlFile);
						@skinDlFile = -1;
					#endif
					#if not STUDIO
						#if not GMNET
							__ONLINE_buffer_write_to_file(@dlBuffer, "iwposkins" + chr(92) + @skinDlDir + chr(92) + @skFName);
						#endif
						#if GMNET
							__ONLINE_buffer_save(@dlBuffer, "iwposkins" + chr(92) + @skinDlDir + chr(92) + @skFName);
						#endif
					#endif
					__ONLINE_buffer_clear(@dlBuffer);
					@skinDlIdx += 1;
					@skinDlPos = 0;
					if(@skinDlIdx >= @skinDlCount){
						@skin_dl_finish();
					}else{
						@skin_dl_send_req(16, @skinDlHash, @skinDlName[@skinDlIdx]);
					}
				}
			}
			break;
		case 19:
			// BULLET NOTIFY (S4 bullet sharing): stringNT senderId, u8 count,
			// u16 room, then per-bullet entries. Wire format v2: the count
			// byte carries a 0x80 flag; flagged entries are 28 bytes (id, x,
			// y, direction, speed, image_xscale, image_angle), unflagged are
			// the v1 20 bytes (no flip/rotation data). Full snapshot of the
			// sender's bullets; only applied in the same GM room. Stray
			// replies (inactive sharing, other room, bad count) are dropped
			// unread.
			if(@bActive){
				@bOwner = __ONLINE_buffer_read_string(@buffer);
				#if not GMNET
					@bCount = __ONLINE_buffer_read_uint8(@buffer);
					@bPRoom = __ONLINE_buffer_read_uint16(@buffer);
				#endif
				#if GMNET
					@bCount = __ONLINE_buffer_read_u8(@buffer);
					@bPRoom = __ONLINE_buffer_read_u16(@buffer);
				#endif
				@bV2 = 0;
				if(@bCount >= 128){
					@bV2 = 1;
					@bCount -= 128;
				}
				if(@bCount >= 1 && @bCount <= 8){
					if(@bPRoom == room){
						@bullet_recv(@bOwner, @bCount, @bV2);
					}
				}
			}
			break;
		default:
			break;
	}
}
@mustQuit = false;
if(@manualReconnect){
	@manualReconnect = false;
	// MANUAL RECONNECT (settings menu "Reconnect: Now"): reset the socket and let the
	// reconnect state machine below do the rest. Resetting the attempt counter also
	// escapes the max-attempts quit path.
	__ONLINE_socket_destroy(@socket);
	@socket = __ONLINE_socket_create();
	@reconnecting = true;
	@connected = false;
	@reconnectTimer = room_speed;
	@reconnectAttempts = 0;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "Reconnecting...";
	@a.@state = -2;
}
if(@reconnecting){
	@reconnectTimer -= 1;
	if(@reconnectTimer <= 0){
		@reconnectAttempts += 1;
		if(@reconnectAttempts > 10){
			#if STUDIO
				show_message("Failed to reconnect after multiple attempts.");
			#endif
			#if not STUDIO
				wd_message_simple("Failed to reconnect after multiple attempts.");
			#endif
			@mustQuit = true;
		}else{
			__ONLINE_socket_destroy(@socket);
			@socket = __ONLINE_socket_create();
			__ONLINE_socket_connect(@socket, @server, @tcpPort);
			@reconnectDelay = min(@reconnectAttempts * 2, 10) * room_speed;
			@reconnectTimer = @reconnectDelay;
		}
	}
}
@socketState = __ONLINE_socket_get_state(@socket);
switch(@socketState){
	case 2:
		if(!@connected || @reconnecting){
			if(@reconnecting){
				// RECONNECT
				@reconnecting = false;
				@reconnectAttempts = 0;
				@listCounter = room_speed * 15;
				@skinNetDirty = true;
				__ONLINE_buffer_clear(@buffer);
				#if not GMNET
					__ONLINE_buffer_write_uint8(@buffer, 3);
					__ONLINE_buffer_write_string(@buffer, @name);
					__ONLINE_buffer_write_string(@buffer, @selfGameID);
					__ONLINE_buffer_write_string(@buffer, @gameName);
					__ONLINE_buffer_write_string(@buffer, @version);
					@hasPassword = 0;
					if(string_length(string(@password)) > 0) @hasPassword = 1;
					__ONLINE_buffer_write_uint8(@buffer, @hasPassword);
					__ONLINE_buffer_write_uint8(@buffer, @protocolVersion);
					__ONLINE_socket_write_message(@socket, @buffer);
				#endif
				#if GMNET
					__ONLINE_buffer_write_u8(@buffer, 3);
					__ONLINE_buffer_write_string(@buffer, @name);
					__ONLINE_buffer_write_string(@buffer, @selfGameID);
					__ONLINE_buffer_write_string(@buffer, @gameName);
					__ONLINE_buffer_write_string(@buffer, @version);
					@hasPassword = 0;
					if(string_length(string(@password)) > 0) @hasPassword = 1;
					__ONLINE_buffer_write_u8(@buffer, @hasPassword);
					__ONLINE_buffer_write_u8(@buffer, @protocolVersion);
					__ONLINE_socket_write_message(@socket, @buffer);
				#endif
				__ONLINE_buffer_clear(@buffer);
				#if not GMNET
					__ONLINE_buffer_write_uint8(@buffer, 8);
					__ONLINE_buffer_write_uint8(@buffer, @team);
				#endif
				#if GMNET
					__ONLINE_buffer_write_u8(@buffer, 8);
					__ONLINE_buffer_write_u8(@buffer, @team);
				#endif
				__ONLINE_socket_write_message(@socket, @buffer);
				@spectatingPrev = false;
				if(@spectating){
					__ONLINE_buffer_clear(@buffer);
					#if not GMNET
						__ONLINE_buffer_write_uint8(@buffer, 8);
						__ONLINE_buffer_write_uint8(@buffer, 254);
					#endif
					#if GMNET
						__ONLINE_buffer_write_u8(@buffer, 8);
						__ONLINE_buffer_write_u8(@buffer, 254);
					#endif
					__ONLINE_socket_write_message(@socket, @buffer);
					@spectatingPrev = true;
				}
				if(__ONLINE_udpsocket_exists(@udpsocket)){
					__ONLINE_udpsocket_destroy(@udpsocket);
				}
				@udpsocket = __ONLINE_udpsocket_create();
				__ONLINE_udpsocket_start(@udpsocket, false, 0);
				__ONLINE_udpsocket_set_destination(@udpsocket, @server, @udpPort);
				__ONLINE_buffer_clear(@buffer);
				#if not GMNET
					__ONLINE_buffer_write_uint8(@buffer, 0);
				#endif
				#if GMNET
					__ONLINE_buffer_write_u8(@buffer, 0);
				#endif
				__ONLINE_udpsocket_send(@udpsocket, @buffer);
				@udpReady = false;
				@udpRetryCount = 0;
				@udpGraceFrames = room_speed*3;
			}
			// SKINS: a fresh connection invalidates any in-flight skin download
			// (its request died with the old socket) - requeue it silently.
			if(@skinDlState != 0){
				@skin_dl_requeue();
			}
			@connected = true;
		}
		break;
	case 4:
	case 5:
		if(!@reconnecting){
			@reconnecting = true;
			@connected = false;
			@reconnectTimer = room_speed;
			@reconnectAttempts = 0;
				#if GMS2
				@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
			#endif
			#if not GMS2
				@a = instance_create(0, 0, @playerSaved);
			#endif
			@a.@name = "Reconnecting...";
			@a.@state = -2;
		}
		break;
}
if(@mustQuit){
	#if TEMPFILE
		if(file_exists("temp")){
			file_delete("temp");
		}
	#endif
	game_end();
	exit;
}
if(@reconnecting){
	exit;
}
// SKINS: (re)announce the local selection once connected - the dirty flag is
// set by skin select/clear, the boot-time restore and the reconnect path.
if(@skinNetDirty){
	if(@connected && __ONLINE_socket_get_state(@socket) == 2){
		@skinNetDirty = false;
		@skin_net_send();
	}
}
// SKINS: background hash resolution, budgeted per frame. Only while a remote
// player is waiting (state 1) do we hash: with the native md5_dir fast path a
// single frame can chew through several skins; with the pure-GML fallback the
// deadline admits at most one 25ms hash per frame and skips hashing entirely
// on frames that are already late. Once the library is fully scanned,
// whatever is still pending is genuinely missing locally.
if(@skinHashScan < @skinCount){
	@skAnyPending = false;
	for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
		@oPlayer = instance_find(@onlinePlayer, @i);
		if(@oPlayer.@skinState == 1){
			@skAnyPending = true;
			break;
		}
	}
	if(@skAnyPending){
		// P1: wall-clock deadline (ms) + hard per-frame iteration cap. GM8's
		// current_time is GetTickCount-based (~15.6ms granularity), so the
		// deadline alone can let one frame chew several ticks; the cap keeps
		// the frame cost bounded regardless of clock granularity.
		@skDeadline = current_time + 6;
		@skScanCap = 0;
		while(@skinHashScan < @skinCount && current_time < @skDeadline && @skScanCap < 24){
			@skin_ensure_hash(@skinHashScan);
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@skinState == 1 && @oPlayer.@skinHash == @skinHash[@skinHashScan]){
					@oPlayer.@skinSlot = @skin_slot_acquire(@skinHashScan, @oPlayer.@skinHash);
					if(@oPlayer.@skinSlot < 0){
						@oPlayer.@skinState = 3;
					}else{
						@oPlayer.@skinState = 2;
					}
				}
			}
			@skinHashScan += 1;
			@skScanCap += 1;
		}
		if(@skinHashScan >= @skinCount){
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@skinState == 1){
					@skin_remote_unknown(@oPlayer);
				}
			}
		}
	}
}
// SKINS: auto-download driver (unknown remote skin -> fetch manifest and
// file chunks from the server library, verify the hash, then register).
@skin_dl_step();
// S4: bullet sharing broadcast (one BULLET message per frame while 1..8
// local bullets exist; the message is queued and flushed with the socket
// update below, so no extra flush is needed here).
@bullet_update();
// PERIODIC HEARTBEAT
@hbCounter += 1;
if(@hbCounter >= room_speed * 5){
	@hbCounter = 0;
	if(@connected && __ONLINE_socket_get_state(@socket) == 2){
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, 2);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, 2);
		#endif
		__ONLINE_socket_write_message(@socket, @buffer);
		// TEAM resend only on change since last sent (reconnect path sends separately)
		if(@team != @lastTeamSent || @spectating != @lastSpecSent){
			@lastTeamSent = @team;
			@lastSpecSent = @spectating;
			__ONLINE_buffer_clear(@buffer);
			#if not GMNET
				__ONLINE_buffer_write_uint8(@buffer, 8);
				if(@spectating){
					__ONLINE_buffer_write_uint8(@buffer, 254);
				}else{
					__ONLINE_buffer_write_uint8(@buffer, @team);
				}
			#endif
			#if GMNET
				__ONLINE_buffer_write_u8(@buffer, 8);
				if(@spectating){
					__ONLINE_buffer_write_u8(@buffer, 254);
				}else{
					__ONLINE_buffer_write_u8(@buffer, @team);
				}
			#endif
			__ONLINE_socket_write_message(@socket, @buffer);
		}
	}
}
// PERIODIC LIST RECONCILE
@listCounter += 1;
if(@lastRoom != room){
	@lastRoom = room;
	@listCounter = room_speed * 15;
}
if(@listCounter >= room_speed * 15){
	@listCounter = 0;
	if(@connected && __ONLINE_socket_get_state(@socket) == 2){
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, 10);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, 10);
		#endif
		if(@selfID != ""){
			__ONLINE_buffer_write_string(@buffer, @selfID);
		}
		__ONLINE_socket_write_message(@socket, @buffer);
	}
}
if(!@spectating){
#if PLAYER_LIST
@p = @get_active_player();
#endif
#if not PLAYER_LIST
@p = %arg0;
#if PLAYER2
	if(!instance_exists(@p)){
		@p = %arg1;
	}
#endif
#endif
@exists = instance_exists(@p);
@X = @pX;
@Y = @pY;
@loadHotkeyConsumed = false;
if(@exists){
	@p = instance_find(@p, 0);
	if(@exists != @pExists){
		// SEND PLAYER CREATE
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, 0);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, 0);
		#endif
		__ONLINE_socket_write_message(@socket, @buffer);
	}
	@X = @p.x;
	@Y = @p.y;
#if CUSTOM_WORLD_OBJ
	// With a custom world object we move it to the player's position to hopefully avoid most cases where certain camera code would disable this instance (TheBiob heritage).
	x = @X;
	y = @Y;
#endif
	@stoppedFrames += 1;
	if(@pX != @X || @pY != @Y || keyboard_check_released(vk_anykey) || keyboard_check_pressed(vk_anykey)){
		@stoppedFrames = 0;
	}
	if(@stoppedFrames < 5 || @t < 3 || @stoppedFrames mod 60 == 0){
		if(@t >= 3){
			@t = 0;
		}
		// SEND PLAYER MOVED
		if(@selfID != ""){
			__ONLINE_buffer_clear(@buffer);
			#if not GMNET
				__ONLINE_buffer_write_uint8(@buffer, 1);
				__ONLINE_buffer_write_string(@buffer, @selfID);
				__ONLINE_buffer_write_string(@buffer, @selfGameID);
				__ONLINE_buffer_write_uint16(@buffer, room);
				__ONLINE_buffer_write_uint64(@buffer, current_time);
				__ONLINE_buffer_write_int32(@buffer, @X);
				__ONLINE_buffer_write_int32(@buffer, @Y);
				__ONLINE_buffer_write_int32(@buffer, @p.sprite_index);
				__ONLINE_buffer_write_float32(@buffer, @p.image_speed);
				#if GM8YY
					__ONLINE_buffer_write_float32(@buffer, @p.image_xscale*@p.xScale);
				#endif
				#if GLOBAL_PLAYER_XSCALE
					__ONLINE_buffer_write_float32(@buffer, @p.image_xscale*global.player_xscale);
				#endif
				#if not GLOBAL_PLAYER_XSCALE
					#if not GM8YY
						#if PLAYER_XSCALE
							__ONLINE_buffer_write_float32(@buffer, @p.image_xscale*@p.xScale);
						#endif
						#if not PLAYER_XSCALE
							#if PLAYER_XSCALE_LOWER
								__ONLINE_buffer_write_float32(@buffer, @p.image_xscale*@p.xscale);
							#endif
							#if not PLAYER_XSCALE_LOWER
								#if PLAYER_FACING
									__ONLINE_buffer_write_float32(@buffer, @p.image_xscale*@p.facing);
								#endif
								#if not PLAYER_FACING
									__ONLINE_buffer_write_float32(@buffer, @p.image_xscale);
								#endif
							#endif
						#endif
					#endif
				#endif
				#if STUDIO
					#if GRAVITY
					__ONLINE_buffer_write_float32(@buffer, @p.image_yscale*global.grav);
					#endif
					#if not GRAVITY
					__ONLINE_buffer_write_float32(@buffer, @p.image_yscale);
					#endif
				#endif
				#if GM8YY
					__ONLINE_buffer_write_float32(@buffer, @p.image_yscale*global.grav);
				#endif
				#if not STUDIO
					#if not GM8YY
						__ONLINE_buffer_write_float32(@buffer, @p.image_yscale);
					#endif
				#endif
				__ONLINE_buffer_write_float32(@buffer, @p.image_angle);
				__ONLINE_buffer_write_string(@buffer, @name);
			#endif
			#if GMNET
				__ONLINE_buffer_write_u8(@buffer, 1);
				__ONLINE_buffer_write_string(@buffer, @selfID);
				__ONLINE_buffer_write_string(@buffer, @selfGameID);
				__ONLINE_buffer_write_u16(@buffer, room);
				__ONLINE_buffer_write_u64(@buffer, current_time);
				__ONLINE_buffer_write_i32(@buffer, @X);
				__ONLINE_buffer_write_i32(@buffer, @Y);
				__ONLINE_buffer_write_i32(@buffer, @p.sprite_index);
				__ONLINE_buffer_write_float(@buffer, @p.image_speed);
				#if not RENEX
					#if GLOBAL_PLAYER_XSCALE
						__ONLINE_buffer_write_float(@buffer, @p.image_xscale*global.player_xscale);
					#endif
					#if GM8YY
						__ONLINE_buffer_write_float(@buffer, @p.image_xscale*@p.xScale);
					#endif
					#if not GLOBAL_PLAYER_XSCALE
						#if not GM8YY
							#if PLAYER_XSCALE
								__ONLINE_buffer_write_float(@buffer, @p.image_xscale*@p.xScale);
							#endif
							#if not PLAYER_XSCALE
								#if PLAYER_XSCALE_LOWER
									__ONLINE_buffer_write_float(@buffer, @p.image_xscale*@p.xscale);
								#endif
								#if not PLAYER_XSCALE_LOWER
									#if PLAYER_FACING
										__ONLINE_buffer_write_float(@buffer, @p.image_xscale*@p.facing);
									#endif
									#if not PLAYER_FACING
										__ONLINE_buffer_write_float(@buffer, @p.image_xscale);
									#endif
								#endif
							#endif
						#endif
					#endif
					#if STUDIO
						#if GRAVITY
						__ONLINE_buffer_write_float(@buffer, @p.image_yscale*global.grav);
						#endif
						#if not GRAVITY
						__ONLINE_buffer_write_float(@buffer, @p.image_yscale);
						#endif
					#endif
					#if GM8YY
						__ONLINE_buffer_write_float(@buffer, @p.image_yscale*global.grav);
					#endif
					#if not STUDIO
						#if not GM8YY
							__ONLINE_buffer_write_float(@buffer, @p.image_yscale);
						#endif
					#endif
				#endif
				#if RENEX
					__ONLINE_buffer_write_float(@buffer, @p.image_xscale*@p.x_scale);
					__ONLINE_buffer_write_float(@buffer, @p.image_yscale*global.grav);
				#endif
				__ONLINE_buffer_write_float(@buffer, @p.image_angle);
				__ONLINE_buffer_write_string(@buffer, @name);
			#endif
			__ONLINE_udpsocket_send(@udpsocket, @buffer);
		}
	}
	@t += 1;
	if(!@loadHotkeyConsumed && !@settingsOpen && @saveHistCount > 0){
		if(@fastLoadEnabled && keyboard_check_pressed(@keyFastLoad)){
			@saveHistApply = @saveHistCount - 1;
			@loadHotkeyConsumed = true;
		}else{
			@loadHotkey = 0;
			for(@hkI = 1; @hkI <= 8 && @loadHotkey == 0; @hkI += 1){
				if(keyboard_check_pressed(48 + @hkI)) @loadHotkey = @hkI;
			}
			if(@loadHotkey > 0){
				for(@hkI = @saveHistCount - 1; @hkI >= 0; @hkI -= 1){
					if(@saveHistHotkey[@hkI] == @loadHotkey){
						@saveHistApply = @hkI;
						@loadHotkeyConsumed = true;
						@hkI = -1;
					}
				}
			}
		}
	}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keyChat) && !@settingsOpen){
		#if STUDIO
			@message = get_string("Say something:", "");
		#endif
		#if not STUDIO
			#if GM80
			@message = wd_input_box("Chat", "Say something:", "");
			#endif
			#if CJKTEXT
			@message = __ONLINE_ansi_to_utf8(wd_input_box("Chat", "Say something:", ""));
			#endif
			#if not GM80
			#if not CJKTEXT
			@message = wd_input_box("Chat", "Say something:", "");
			#endif
			#endif
		#endif
		@message = string_replace_all(@message, "#", "\\#");
		#if STUDIO
		@message = strip_non_bmp(@message);
		#endif
		@message_length = string_length(@message);
		if(@message_length > 0){
			@message_max_length = 300;
			#if GM80
			if(@message_length > @message_max_length){
				@message = __ONLINE_gbk_trunc(@message, @message_max_length, "");
			}
			#endif
			#if CJKTEXT
			if(@message_length > @message_max_length){
				@message = __ONLINE_gbk_trunc(@message, @message_max_length, "");
			}
			#endif
			#if not GM80
			#if not CJKTEXT
			if(@message_length > @message_max_length){
				@message = string_copy(@message, 0, @message_max_length);
			}
			#endif
			#endif
			__ONLINE_buffer_clear(@buffer);
			#if not GMNET
				__ONLINE_buffer_write_uint8(@buffer, 4);
			#endif
			#if GMNET
				__ONLINE_buffer_write_u8(@buffer, 4);
			#endif
			__ONLINE_buffer_write_string(@buffer, @message);
			__ONLINE_socket_write_message(@socket, @buffer);
			@selfChatBubble = @message;
			#if GM80
			@selfChatBubble = __ONLINE_gbk_trunc(@selfChatBubble, 77, "...");
			#endif
			#if CJKTEXT
			@selfChatBubble = __ONLINE_gbk_trunc(@selfChatBubble, 77, "...");
			#endif
			#if not GM80
			#if not CJKTEXT
			if(string_length(@selfChatBubble) > 80){
				@selfChatBubble = string_copy(@selfChatBubble, 1, 77) + "...";
			}
			#endif
			#endif
			#if GMS2
				@oCb = instance_create_depth(0, 0, @chatboxDepth, @chatbox);
			#endif
			#if not GMS2
				@oCb = instance_create(0, 0, @chatbox);
			#endif
			@oCb.@message = @selfChatBubble;
			@oCb.@follower = @p;
			if(@chatHistCount < @chatHistMax){
				@chatHistName[@chatHistCount] = @name;
				@chatHistMsg[@chatHistCount] = @message;
				@chatHistTeam[@chatHistCount] = @team;
				@chatHistCount += 1;
			}else{
				for(@ci = 0; @ci < @chatHistMax - 1; @ci += 1){
					@chatHistName[@ci] = @chatHistName[@ci + 1];
					@chatHistMsg[@ci] = @chatHistMsg[@ci + 1];
					@chatHistTeam[@ci] = @chatHistTeam[@ci + 1];
				}
				@chatHistName[@chatHistMax - 1] = @name;
				@chatHistMsg[@chatHistMax - 1] = @message;
				@chatHistTeam[@chatHistMax - 1] = @team;
			}
			#if STUDIO
				audio_play_sound(@sndChatbox, 0, false);
			#endif
			#if not STUDIO
				sound_play(@sndChatbox);
			#endif
		}
	}
}
if(@exists != @pExists){
	// SEND PLAYER DESTROYED
	__ONLINE_buffer_clear(@buffer);
	#if not GMNET
		__ONLINE_buffer_write_uint8(@buffer, 1);
	#endif
	#if GMNET
		__ONLINE_buffer_write_u8(@buffer, 1);
	#endif
	__ONLINE_socket_write_message(@socket, @buffer);
}
@pExists = @exists;
@pX = @X;
@pY = @Y;
}
// SKINS: keep the global draw-state mirror in sync every frame (the function
// early-outs when no skin is selected).
@skin_mirror();
#if not GMNET
__ONLINE_socket_update_write(@socket);
#endif
#if GMNET
__ONLINE_socket_send(@socket);
#endif
// UDP SOCKETS
while(__ONLINE_udpsocket_receive(@udpsocket, @buffer)){
	#if not GMNET
		switch(__ONLINE_buffer_read_uint8(@buffer)){
	#endif
	#if GMNET
		switch(__ONLINE_buffer_read_u8(@buffer)){
	#endif
		case 1:
			// RECEIVED MOVED
			@ID = __ONLINE_buffer_read_string(@buffer);
			@gameID = __ONLINE_buffer_read_string(@buffer);
			@found = false;
			@oPlayer = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@found = true;
				}
			}
			if(!@found){
				#if GMS2
					@oPlayer = instance_create_depth(0, 0, @onlinePlayerDepth, @onlinePlayer);
				#endif
				#if not GMS2
					@oPlayer = instance_create(0, 0, @onlinePlayer);
				#endif
				@oPlayer.@ID = @ID;
				if(ds_map_exists(@teamMap, @ID)){
					@oPlayer.@team = ds_map_find_value(@teamMap, @ID);
				}
			}
			@oPlayer.@avatarAlive = true;
			#if not GMNET
				@oPlayer.@oRoom = __ONLINE_buffer_read_uint16(@buffer);
				@syncTime = __ONLINE_buffer_read_uint64(@buffer);
				if(@oPlayer.@syncTime < @syncTime){
					@oPlayer.@syncTime = @syncTime;
					@oPlayer.@targetX = __ONLINE_buffer_read_int32(@buffer);
					@oPlayer.@targetY = __ONLINE_buffer_read_int32(@buffer);
					if(!@oPlayer.@lerpInit){
						@oPlayer.x = @oPlayer.@targetX;
						@oPlayer.y = @oPlayer.@targetY;
						@oPlayer.@lerpInit = true;
					}
					@oPlayer.sprite_index = __ONLINE_buffer_read_int32(@buffer);
					@oPlayer.image_speed = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_xscale = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_yscale = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.image_angle = __ONLINE_buffer_read_float32(@buffer);
					@oPlayer.@name = __ONLINE_buffer_read_string(@buffer);
			#endif
			#if GMNET
				@oPlayer.@oRoom = __ONLINE_buffer_read_u16(@buffer);
				@syncTime = __ONLINE_buffer_read_u64(@buffer);
				if(@oPlayer.@syncTime < @syncTime){
					@oPlayer.@syncTime = @syncTime;
					@oPlayer.@targetX = __ONLINE_buffer_read_i32(@buffer);
					@oPlayer.@targetY = __ONLINE_buffer_read_i32(@buffer);
					if(!@oPlayer.@lerpInit){
						@oPlayer.x = @oPlayer.@targetX;
						@oPlayer.y = @oPlayer.@targetY;
						@oPlayer.@lerpInit = true;
					}
					@oPlayer.sprite_index = __ONLINE_buffer_read_i32(@buffer);
					@oPlayer.image_speed = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_xscale = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_yscale = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.image_angle = __ONLINE_buffer_read_float(@buffer);
					@oPlayer.@name = __ONLINE_buffer_read_string(@buffer);
			#endif
			}
			break;
		default:
			break;
	}
}
@udpState = __ONLINE_udpsocket_get_state(@udpsocket);
if(@udpState == 1){
	@udpReady = true;
	@udpGraceFrames = room_speed*3;
}else{
	if(!@udpReady && @udpGraceFrames > 0){
		@udpGraceFrames -= 1;
	}else if(!@udpReady && @udpRetryCount < 3){
		@udpRetryCount += 1;
		if(__ONLINE_udpsocket_exists(@udpsocket)){
			__ONLINE_udpsocket_destroy(@udpsocket);
		}
		@udpsocket = __ONLINE_udpsocket_create();
		__ONLINE_udpsocket_start(@udpsocket, false, 0);
		__ONLINE_udpsocket_set_destination(@udpsocket, @server, @udpPort);
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, 0);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, 0);
		#endif
		__ONLINE_udpsocket_send(@udpsocket, @buffer);
		@udpGraceFrames = room_speed*3;
	}else if(!@udpReady){
		if(!@reconnecting){
			@reconnecting = true;
			@connected = false;
			@reconnectTimer = room_speed;
			@reconnectAttempts = 0;
			#if GMS2
				@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
			#endif
			#if not GMS2
				@a = instance_create(0, 0, @playerSaved);
			#endif
			@a.@name = "Reconnecting...";
			@a.@state = -2;
		}
	}
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keyVis) && !@settingsOpen){
	if(@vis == 0) @vis = 1;
	else if(@vis == 1) @vis = 2;
	else if(@vis == 2) @vis = 0;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	@a.@state = @vis;
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keySave) && !@settingsOpen){
	@save_enabled = 1 - @save_enabled;
	if(!@save_enabled){
		// Toggling online saves off discards any pending online save.
		#if TEMPFILE
			if(file_exists("tempOnline2")){
				file_delete("tempOnline2");
			}
		#endif
		@sSaved = false;
	}
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	@a.@state = @save_enabled + 3;
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keyPlayerList) && !@settingsOpen){
	@showPlayerList = !@showPlayerList;
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keySettings)){
		@settingsOpen = !@settingsOpen;
		if(@settingsOpen){
			@kbFocus = 1;
			@keybindEditing = -1;
		}else{
			@keybindEditing = -1;
		}
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keyChatLog) && !@settingsOpen){
	@chatLogOpen = !@chatLogOpen;
	@chatLogScroll = 0;
}
	if(!@loadHotkeyConsumed && keyboard_check_pressed(@keyArrows) && !@settingsOpen){
	@showArrows = !@showArrows;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	if(@showArrows){
		@a.@name = "Indicator: on";
	}else{
		@a.@name = "Indicator: off";
	}
	@a.@state = -2;
}
// PING RADIAL MENU
	if(@socket != -1 && !@settingsOpen && !@chatLogOpen && @keybindEditing < 0 && !@loadHotkeyConsumed){
	if(keyboard_check_pressed(@keyPing) && !@pingWheelOpen){
		@pingWheelOpen = true;
		@pingWheelCanceled = false;
		@pingWheelCenterX = mouse_x;
		@pingWheelCenterY = mouse_y;
		@pingWheelHover = 4;
	}
	if(@pingWheelOpen){
		@pwDx = mouse_x - @pingWheelCenterX;
		@pwDy = mouse_y - @pingWheelCenterY;
		if(@pwDx*@pwDx + @pwDy*@pwDy < 19*19){
			@pingWheelHover = 4;
		}else{
			@pwDir = point_direction(0, 0, @pwDx, @pwDy);
			if(@pwDir >= 337.5 || @pwDir < 22.5) @pingWheelHover = 5;
			else if(@pwDir < 67.5) @pingWheelHover = 2;
			else if(@pwDir < 112.5) @pingWheelHover = 1;
			else if(@pwDir < 157.5) @pingWheelHover = 0;
			else if(@pwDir < 202.5) @pingWheelHover = 3;
			else if(@pwDir < 247.5) @pingWheelHover = 6;
			else if(@pwDir < 292.5) @pingWheelHover = 7;
			else @pingWheelHover = 8;
		}
		if(mouse_check_button_pressed(mb_right)){
			@pingWheelOpen = false;
			@pingWheelCanceled = true;
		}
		if(!keyboard_check(@keyPing)){
			@pingWheelOpen = false;
			if(!@pingWheelCanceled){
				__ONLINE_buffer_clear(@buffer);
				#if not GMNET
					__ONLINE_buffer_write_uint8(@buffer, 11);
					__ONLINE_buffer_write_int32(@buffer, room);
					__ONLINE_buffer_write_float32(@buffer, @pingWheelCenterX);
					__ONLINE_buffer_write_float32(@buffer, @pingWheelCenterY);
					__ONLINE_buffer_write_uint8(@buffer, @pingWheelHover);
				#endif
				#if GMNET
					__ONLINE_buffer_write_u8(@buffer, 11);
					__ONLINE_buffer_write_i32(@buffer, room);
					__ONLINE_buffer_write_float(@buffer, @pingWheelCenterX);
					__ONLINE_buffer_write_float(@buffer, @pingWheelCenterY);
					__ONLINE_buffer_write_u8(@buffer, @pingWheelHover);
				#endif
				__ONLINE_socket_write_message(@socket, @buffer);
				@pingX[@pingHead] = @pingWheelCenterX;
				@pingY[@pingHead] = @pingWheelCenterY;
				@pingT[@pingHead] = current_time;
				@pingType[@pingHead] = @pingWheelHover;
				@pingName[@pingHead] = @name;
				@pingSenderIDArr[@pingHead] = @selfID;
				@pingTeamArr[@pingHead] = @team;
				#if STUDIO
					audio_play_sound(@sndChatbox, 0, false);
				#endif
				#if not STUDIO
					sound_play(@sndChatbox);
				#endif
				@pingHead = (@pingHead + 1) mod @pingMax;
			}
			@pingWheelCanceled = false;
		}
	}
}else{
	@pingWheelOpen = false;
	@pingWheelCanceled = false;
}
// SPECTATOR MODE
	if(@loadHotkeyConsumed || !keyboard_check(@keySpectate) || @settingsOpen){
	@specHoldFrames = 0;
	@specProgress -= 3 / room_speed;
	if(@specProgress < 0) @specProgress = 0;
}else{
	if(@specHoldFrames >= 0){
		@specHoldFrames += 1;
		@specProgress += 1 / room_speed;
		if(@specProgress > 1) @specProgress = 1;
	}
}
if(@spectating){
	if(keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_down)){
		@specCamMode = 1 - @specCamMode;
	}
}
if(@specProgress >= 1){
	@specProgress = 0;
	@specHoldFrames = -1;
	if(!@spectating){
		// ENTER SPECTATOR
		#if PLAYER_LIST
			@p = @get_active_player();
		#endif
		#if not PLAYER_LIST
			@p = %arg0;
			#if PLAYER2
				if(!instance_exists(@p)) @p = %arg1;
			#endif
		#endif
		if(instance_exists(@p)){
			@p = instance_find(@p, 0);
			@specX = @p.x;
			@specY = @p.y;
			@specRoom = room;
			@specObj = @p.object_index;
			#if STUDIO
				#if GRAVITY
					@specGrav = global.grav;
				#endif
				#if not GRAVITY
					@specGrav = 1;
				#endif
			#endif
			#if GM8YY
				@specGrav = (global.grav + 1) / 2;
			#endif
			#if not STUDIO
				#if not GM8YY
					#if RENEX
						@specGrav = (global.grav + 1) / 2;
					#endif
					#if not RENEX
						#if PLAYER2
							if(@specObj == %arg0){
								@specGrav = 0;
							}else{
								@specGrav = 1;
							}
						#endif
						#if not PLAYER2
							@specGrav = 0;
						#endif
					#endif
				#endif
			#endif
			with(@p){
				instance_destroy();
			}
			@spectating = true;
			@specTargetID = "";
			@specTargetName = "";
			@specCamX = @specX;
			@specCamY = @specY;
			@specGraceFrames = 0;
			@specSnapCamera = true;
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@specTarget = instance_find(@onlinePlayer, @i);
				if(!@specTarget.@avatarAlive || !@specTarget.@lerpInit) continue;
				@specTargetIdx = 0;
				@specTargetID = @specTarget.@ID;
				@specTargetName = @specTarget.@name;
				@specCamX = @specTarget.x;
				@specCamY = @specTarget.y;
				@specSnapCamera = false;
				if(@specTarget.@oRoom != room && room_exists(@specTarget.@oRoom)){
					room_goto(@specTarget.@oRoom);
					@specSnapCamera = true;
				}
				@i = instance_number(@onlinePlayer);
			}
		}
	}else{
		if(@specRoom == room){
			@p = %arg0;
			#if PLAYER2
				if(@specGrav == 1){
					if(instance_exists(%arg0)){
						@specDepth = instance_find(%arg0, 0).depth;
						#if GMS2
							instance_create_depth(0, 0, @specDepth, %arg1);
						#endif
						#if not GMS2
							instance_create(0, 0, %arg1);
						#endif
						with(%arg0){
							instance_destroy();
						}
					}
					@p = %arg1;
				}else{
					if(instance_exists(%arg1) && !instance_exists(%arg0)){
						@specDepth = instance_find(%arg1, 0).depth;
						#if GMS2
							instance_create_depth(0, 0, @specDepth, %arg0);
						#endif
						#if not GMS2
							instance_create(0, 0, %arg0);
						#endif
						with(%arg1){
							instance_destroy();
						}
					}
				}
			#endif
			if(instance_exists(@p)){
				@p = instance_find(@p, 0);
				@p.x = @specX;
				@p.y = @specY;
			}else{
				#if GMS2
					@p = instance_create_depth(@specX, @specY, 0, @specObj);
				#endif
				#if not GMS2
					@p = instance_create(@specX, @specY, @specObj);
				#endif
			}
			#if STUDIO
				#if GRAVITY
				if(global.grav != @specGrav){
					#if SCR_FLIP_GRAV
						scrFlipGrav();
					#endif
					#if not SCR_FLIP_GRAV
						with(@p){
							event_user(0);
						}
					#endif
				}
				#endif
			#endif
			#if not STUDIO
				global.grav = @specGrav;
			#endif
			if(view_enabled && view_visible[0]){
				view_object[0] = @p;
			}
			@spectating = false;
		}else{
			@specPending = true;
			room_goto(@specRoom);
		}
	}
}
if(@spectating){
	#if PLAYER_LIST
		for(@di = 0; @di < ds_list_size(@obj_list); @di += 1){
			@dobj = ds_list_find_value(@obj_list, @di);
			if(instance_exists(@dobj)){
				with(instance_find(@dobj, 0)){
					instance_destroy();
				}
			}
		}
	#endif
	#if not PLAYER_LIST
		if(instance_exists(%arg0)){
			with(instance_find(%arg0, 0)){
				instance_destroy();
			}
		}
		#if PLAYER2
			if(instance_exists(%arg1)){
				with(instance_find(%arg1, 0)){
					instance_destroy();
				}
			}
		#endif
	#endif
	if(view_enabled && view_visible[0]){
		view_object[0] = -1;
	}
	@specFound = false;
	@specTargetLive = false;
	@specCount = 0;
	if(@specTargetID != ""){
		for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
			@specTarget = instance_find(@onlinePlayer, @i);
			if(@specTarget.@ID == @specTargetID){
				@specFound = true;
				@specTargetName = @specTarget.@name;
				if(@specTarget.@avatarAlive && @specTarget.@lerpInit){
					@specTargetLive = true;
					@specTargetIdx = @specCount;
					if(@specTarget.@oRoom == room){
						if(@specSnapCamera){
							@specCamX = @specTarget.x;
							@specCamY = @specTarget.y;
							@specSnapCamera = false;
						}else{
							@specCamX += (@specTarget.x - @specCamX) * 0.35;
							@specCamY += (@specTarget.y - @specCamY) * 0.35;
						}
					}
					if(@specTarget.@oRoom != room && room_exists(@specTarget.@oRoom)){
						room_goto(@specTarget.@oRoom);
						@specSnapCamera = true;
					}
				}
			}
			if(@specTarget.@avatarAlive && @specTarget.@lerpInit) @specCount += 1;
		}
	}else{
		for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
			@specTarget = instance_find(@onlinePlayer, @i);
			if(!@specTarget.@avatarAlive || !@specTarget.@lerpInit) continue;
			@specCount += 1;
		}
	}
	// SWITCH TARGET
	if(@specCount > 0){
		if(!@specFound){
			@specTargetIdx = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@specTarget = instance_find(@onlinePlayer, @i);
				if(!@specTarget.@avatarAlive || !@specTarget.@lerpInit) continue;
				@specTargetID = @specTarget.@ID;
				@specTargetName = @specTarget.@name;
				@specCamX = @specTarget.x;
				@specCamY = @specTarget.y;
				@specSnapCamera = false;
				if(@specTarget.@oRoom != room && room_exists(@specTarget.@oRoom)){
					room_goto(@specTarget.@oRoom);
					@specSnapCamera = true;
				}
				@specFound = true;
				@i = instance_number(@onlinePlayer);
			}
		}
		if(keyboard_check_pressed(vk_left)){
			@specTargetIdx -= 1;
			if(@specTargetIdx < 0) @specTargetIdx = @specCount - 1;
			@specLiveIdx = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@specTarget = instance_find(@onlinePlayer, @i);
				if(!@specTarget.@avatarAlive || !@specTarget.@lerpInit) continue;
				if(@specLiveIdx == @specTargetIdx){
					@specTargetID = @specTarget.@ID;
					@specTargetName = @specTarget.@name;
					@specCamX = @specTarget.x;
					@specCamY = @specTarget.y;
					@specSnapCamera = false;
					if(@specTarget.@oRoom != room && @specTarget.@oRoom != -1 && room_exists(@specTarget.@oRoom)){
						room_goto(@specTarget.@oRoom);
						@specSnapCamera = true;
					}
					@i = instance_number(@onlinePlayer);
				}else{
					@specLiveIdx += 1;
				}
			}
		}
		if(keyboard_check_pressed(vk_right)){
			@specTargetIdx += 1;
			if(@specTargetIdx >= @specCount) @specTargetIdx = 0;
			@specLiveIdx = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer); @i += 1){
				@specTarget = instance_find(@onlinePlayer, @i);
				if(!@specTarget.@avatarAlive || !@specTarget.@lerpInit) continue;
				if(@specLiveIdx == @specTargetIdx){
					@specTargetID = @specTarget.@ID;
					@specTargetName = @specTarget.@name;
					@specCamX = @specTarget.x;
					@specCamY = @specTarget.y;
					@specSnapCamera = false;
					if(@specTarget.@oRoom != room && @specTarget.@oRoom != -1 && room_exists(@specTarget.@oRoom)){
						room_goto(@specTarget.@oRoom);
						@specSnapCamera = true;
					}
					@i = instance_number(@onlinePlayer);
				}else{
					@specLiveIdx += 1;
				}
			}
		}
	}
	if(@specFound){
		@specGraceFrames = 0;
	}else{
		@specGraceFrames += 1;
	}
	if(!@specFound && @specCount == 0 && @specGraceFrames >= room_speed * 3){
		@specGraceFrames = 0;
		if(@specRoom == room){
			@p = %arg0;
			#if PLAYER2
				if(@specGrav == 1){
					if(instance_exists(%arg0)){
						@specDepth = instance_find(%arg0, 0).depth;
						#if GMS2
							instance_create_depth(0, 0, @specDepth, %arg1);
						#endif
						#if not GMS2
							instance_create(0, 0, %arg1);
						#endif
						with(%arg0){
							instance_destroy();
						}
					}
					@p = %arg1;
				}else{
					if(instance_exists(%arg1) && !instance_exists(%arg0)){
						@specDepth = instance_find(%arg1, 0).depth;
						#if GMS2
							instance_create_depth(0, 0, @specDepth, %arg0);
						#endif
						#if not GMS2
							instance_create(0, 0, %arg0);
						#endif
						with(%arg1){
							instance_destroy();
						}
					}
				}
			#endif
			if(instance_exists(@p)){
				@p = instance_find(@p, 0);
				@p.x = @specX;
				@p.y = @specY;
			}else{
				#if GMS2
					@p = instance_create_depth(@specX, @specY, 0, @specObj);
				#endif
				#if not GMS2
					@p = instance_create(@specX, @specY, @specObj);
				#endif
			}
			#if STUDIO
				#if GRAVITY
				if(global.grav != @specGrav){
					#if SCR_FLIP_GRAV
						scrFlipGrav();
					#endif
					#if not SCR_FLIP_GRAV
						with(@p){
							event_user(0);
						}
					#endif
				}
				#endif
			#endif
			#if not STUDIO
				global.grav = @specGrav;
			#endif
			if(view_enabled && view_visible[0]){
				view_object[0] = @p;
			}
			@spectating = false;
		}else{
			@specPending = true;
			room_goto(@specRoom);
		}
	}
	// CAMERA
	if(@spectating && view_enabled && view_visible[0]){
		if(@specCamMode == 1){
			@specViewX = floor(@specCamX / view_wview[0]) * view_wview[0];
			@specViewY = floor(@specCamY / view_hview[0]) * view_hview[0];
			view_xview[0] = @specViewX;
			view_yview[0] = @specViewY;
		}else{
			view_xview[0] = @specCamX - view_wview[0] / 2;
			view_yview[0] = @specCamY - view_hview[0] / 2;
		}
		if(view_xview[0] < 0) view_xview[0] = 0;
		if(view_yview[0] < 0) view_yview[0] = 0;
		@specClampX = room_width - view_wview[0];
		@specClampY = room_height - view_hview[0];
		if(@specClampX < 0) @specClampX = 0;
		if(@specClampY < 0) @specClampY = 0;
		if(view_xview[0] > @specClampX) view_xview[0] = @specClampX;
		if(view_yview[0] > @specClampY) view_yview[0] = @specClampY;
	}
}
if(@teamChanged){
	@teamChanged = false;
	__ONLINE_buffer_clear(@buffer);
	#if not GMNET
		__ONLINE_buffer_write_uint8(@buffer, 8);
		__ONLINE_buffer_write_uint8(@buffer, @team);
	#endif
	#if GMNET
		__ONLINE_buffer_write_u8(@buffer, 8);
		__ONLINE_buffer_write_u8(@buffer, @team);
	#endif
	__ONLINE_socket_write_message(@socket, @buffer);
	@lastTeamSent = @team;
	ini_open("@config.ini");
	ini_write_real("config", "team", @team);
	ini_close();
}
if(@spectating != @spectatingPrev && @socket != -1){
	@spectatingPrev = @spectating;
	__ONLINE_buffer_clear(@buffer);
	#if not GMNET
		__ONLINE_buffer_write_uint8(@buffer, 8);
		if(@spectating){ __ONLINE_buffer_write_uint8(@buffer, 254); }else{ __ONLINE_buffer_write_uint8(@buffer, @team); }
	#endif
	#if GMNET
		__ONLINE_buffer_write_u8(@buffer, 8);
		if(@spectating){ __ONLINE_buffer_write_u8(@buffer, 254); }else{ __ONLINE_buffer_write_u8(@buffer, @team); }
	#endif
	__ONLINE_socket_write_message(@socket, @buffer);
	@lastSpecSent = @spectating;
	@lastTeamSent = @team;
}
if(@visChanged){
	@visChanged = false;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	@a.@state = @vis;
}
if(@saveChanged){
	@saveChanged = false;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	@a.@state = @save_enabled + 3;
}
if(@fastLoadChanged){
	@fastLoadChanged = false;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	if(@fastLoadEnabled){
		@a.@name = "Fast: on";
	}else{
		@a.@name = "Fast: off";
	}
	@a.@state = -2;
	ini_open("@config.ini");
	ini_write_real("config", "fast_load", @fastLoadEnabled);
	ini_close();
}
if(@lerpChanged){
	@lerpChanged = false;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	if(@lerpEnabled){
		@a.@state = 5;
	}else{
		@a.@state = 6;
	}
	ini_open("@config.ini");
	ini_write_real("config", "lerp", @lerpEnabled);
	ini_close();
}
// S5 (PVP): persist mode/visibility changes. Switching PVP on forces bullet
// visibility back on (and re-persists it) - a PVP player must never hide the
// bullets that can kill them.
if(@pvpChanged){
	@pvpChanged = false;
	ini_open("@config.ini");
	ini_write_real("config", "pvp_mode", @pvpMode);
	if(@pvpMode != 0 && @bulletShow != 1){
		@bulletShow = 1;
		ini_write_real("config", "bullet_show", @bulletShow);
	}
	ini_close();
}
if(@bulletShowChanged){
	@bulletShowChanged = false;
	ini_open("@config.ini");
	ini_write_real("config", "bullet_show", @bulletShow);
	ini_close();
}
if(@syncEnabledChanged){
	@syncEnabledChanged = false;
	ini_open("@config.ini");
	ini_write_real("sync", "sync_enabled", @syncEnabled);
	ini_close();
}
if(@skinAutoDLChanged){
    @skinAutoDLChanged = false;
    ini_open("@config.ini");
    ini_write_real("config", "skinAutoDL", @skinAutoDL);
    ini_close();
}
if(@saveHistApply >= 0){
	if(@spectating){
		if(@socket != -1){
			__ONLINE_buffer_clear(@buffer);
			#if not GMNET
				__ONLINE_buffer_write_uint8(@buffer, 8);
				__ONLINE_buffer_write_uint8(@buffer, @team);
			#endif
			#if GMNET
				__ONLINE_buffer_write_u8(@buffer, 8);
				__ONLINE_buffer_write_u8(@buffer, @team);
			#endif
			__ONLINE_socket_write_message(@socket, @buffer);
		}
		@spectating = false;
		@spectatingPrev = false;
		@specPending = false;
	}
	@shIdx = @saveHistApply;
	@saveHistApply = -1;
	@saveHistPendingGrav = @saveHistGrav[@shIdx];
	@saveHistPendingX = @saveHistX[@shIdx];
	@saveHistPendingY = @saveHistY[@shIdx];
	@saveHistPendingRoom = @saveHistRoom[@shIdx];
	@saveHistPending = true;
	@saveForceLoad = true;
	@sGravity = @saveHistGrav[@shIdx];
	@sX = @saveHistX[@shIdx];
	@sY = @saveHistY[@shIdx];
	@sRoom = @saveHistRoom[@shIdx];
	@sSaved = true;
	#if TEMPFILE
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, @sGravity);
			__ONLINE_buffer_write_int32(@buffer, @sX);
			__ONLINE_buffer_write_float64(@buffer, @sY);
			__ONLINE_buffer_write_int16(@buffer, @sRoom);
			__ONLINE_buffer_write_to_file(@buffer, "tempOnline2");
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, @sGravity);
			__ONLINE_buffer_write_i32(@buffer, @sX);
			__ONLINE_buffer_write_double(@buffer, @sY);
			__ONLINE_buffer_write_i16(@buffer, @sRoom);
			__ONLINE_buffer_save(@buffer, "tempOnline2");
		#endif
	#endif
	// Real player only - never a PLAYER_LIST alt/display object (C1).
	@_rp = %arg0;
	#if PLAYER2
		if(!instance_exists(@_rp)) @_rp = %arg1;
	#endif
	if(instance_exists(@_rp)){
		@_rp.x = @sX;
		@_rp.y = @sY;
	}
	room_goto(@sRoom);
}
if(@saveHistClearFiles){
	@saveHistClearFiles = false;
		@shThinWrite = 0;
	@saveHistFavCount = 0;
	for(@shI = 0; @shI < @saveHistCount; @shI += 1){
		if(@saveHistFav[@shI]){
			if(@shThinWrite != @shI){
				@saveHistFav[@shThinWrite] = @saveHistFav[@shI];
				@saveHistHotkey[@shThinWrite] = @saveHistHotkey[@shI];
				@saveHistGrav[@shThinWrite] = @saveHistGrav[@shI];
				@saveHistX[@shThinWrite] = @saveHistX[@shI];
				@saveHistY[@shThinWrite] = @saveHistY[@shI];
				@saveHistRoom[@shThinWrite] = @saveHistRoom[@shI];
				@saveHistTime[@shThinWrite] = @saveHistTime[@shI];
				@saveHistName[@shThinWrite] = @saveHistName[@shI];
				@saveHistRoomName[@shThinWrite] = @saveHistRoomName[@shI];
			}
			@shThinWrite += 1;
			@saveHistFavCount += 1;
		}
	}
	@saveHistCount = @shThinWrite;
	// Clear-non-favorites compacts the array in place; bump the mutation
	// counter so an in-flight P6 scan/serialize (whose @shKeepIdx[] or
	// buffer addresses pre-clear positions) is invalidated and restarted.
	@shMutation += 1;
	@saveHistPage = 0;
	if(@saveHistCount > 0){
		@saveHistDirty = true;
		@saveHistDirtyTimer = 0;
	}else{
		@saveHistDirty = false;
		if(file_exists(@savesPath)){
			file_delete(@savesPath);
		}
	}
}
// DEFERRED SAVE WRITE (frame-sliced). A large history used to be thinned and
// fully serialized in ONE frame when the dirty timer expired: with up to 500
// entries that is thousands of GML/DLL calls in a single step - the
// ~half-second stall that followed every received "xxx saved!" once the
// history grew. The work now advances a few entries per frame: thinning
// first (only when over the cap, one excess shift per frame), then
// serialization into the dedicated @savesBuffer, then one file write.
// The thin scan is NON-destructive: it only records kept positions into
// @shKeepIdx[] and the in-place compaction happens once when the scan
// completes, so a game_restart/Game End takeover or the history UI never
// observes a half-compacted array (duplicate rows, misapplied actions).
// Both phases re-check a monotonic mutation counter (@shMutation, bumped by
// every add/delete/fav/hotkey change): phase 1 before compacting, since
// @shKeepIdx[] then still addresses pre-mutation positions, and phase 2
// BEFORE the file write. A stale pass is dropped and restarted next frame
// instead of scrambling the history or persisting a header/body-mismatched
// @saves.
if(@saveHistDirty){
	@saveHistDirtyTimer -= 1;
	if(@saveHistDirtyTimer <= 0 && @shWritePhase == 0){
		@shWritePhase = 1;
		@shWritePos = 0;
		@shWriteStartMut = @shMutation;
		@shThinWrite = 0;
		@shThinLastKept = -1;
		@shTrimActive = false;
		@saveHistFavCount = 0;
		@shThinNow = date_current_datetime();
		if(@saveHistCount <= @saveHistMax){
			@shWritePhase = 2;
			@shWritePos = 0;
			@shWriteStartMut = @shMutation;
			__ONLINE_buffer_clear(@savesBuffer);
			#if not GMNET
				__ONLINE_buffer_write_uint16(@savesBuffer, 65535);
				__ONLINE_buffer_write_uint8(@savesBuffer, 2);
				__ONLINE_buffer_write_uint16(@savesBuffer, @saveHistCount);
			#endif
			#if GMNET
				__ONLINE_buffer_write_u16(@savesBuffer, 65535);
				__ONLINE_buffer_write_u8(@savesBuffer, 2);
				__ONLINE_buffer_write_u16(@savesBuffer, @saveHistCount);
			#endif
		}
	}
}
if(@shWritePhase == 1){
	// thinning: scan up to 20 entries this frame, recording kept positions
	@shSlice = 0;
	while(@shWritePos < @saveHistCount && @shSlice < 20){
		@shI = @shWritePos;
		@shKeep = false;
		if(@saveHistFav[@shI]){
			@shKeep = true;
			@saveHistFavCount += 1;
		}else{
			@shAge = (@shThinNow - @saveHistTime[@shI]) * 1440;
			if(@shAge < 0) @shAge = 0;
			if(@shAge < 60){
				@shMinGap = 0;
			}else if(@shAge < 1440){
				@shMinGap = 5;
			}else if(@shAge < 10080){
				@shMinGap = 120;
			}else{
				@shMinGap = 720;
			}
			if(@shThinLastKept < 0){
				@shKeep = true;
			}else{
				@shGap = (@saveHistTime[@shI] - @shThinLastKept) * 1440;
				if(@shGap >= @shMinGap){
					@shKeep = true;
				}
			}
		}
		if(@shKeep){
			if(!@saveHistFav[@shI]){
				@shThinLastKept = @saveHistTime[@shI];
			}
			@shKeepIdx[@shThinWrite] = @shI;
			@shThinWrite += 1;
		}
		@shWritePos += 1;
		@shSlice += 1;
	}
	if(@shWritePos >= @saveHistCount && !@shTrimActive){
		if(@shMutation != @shWriteStartMut){
			// an add/delete/fav during the multi-frame scan re-indexes the
			// history, so @shKeepIdx[] no longer addresses the entries it
			// was built from: compacting now would scramble or drop rows.
			@shWritePhase = 0;
			@saveHistDirty = true;
			@saveHistDirtyTimer = 0;
		}else{
			// compact once: pure array assignments (~4500 ops worst case) are
			// never the bottleneck - the buffer/DLL serialization is. Kept
			// positions are strictly increasing and >= their target, so the
			// in-place copy reads each source before it can be overwritten.
			for(@shW = 0; @shW < @shThinWrite; @shW += 1){
				@shS = @shKeepIdx[@shW];
				if(@shS != @shW){
					@saveHistFav[@shW] = @saveHistFav[@shS];
					@saveHistHotkey[@shW] = @saveHistHotkey[@shS];
					@saveHistGrav[@shW] = @saveHistGrav[@shS];
					@saveHistX[@shW] = @saveHistX[@shS];
					@saveHistY[@shW] = @saveHistY[@shS];
					@saveHistRoom[@shW] = @saveHistRoom[@shS];
					@saveHistTime[@shW] = @saveHistTime[@shS];
					@saveHistName[@shW] = @saveHistName[@shS];
					@saveHistRoomName[@shW] = @saveHistRoomName[@shS];
				}
			}
			@saveHistCount = @shThinWrite;
			if(@saveHistCount > @saveHistMax){
				@shTrimActive = true;
			}else{
				@shWritePhase = 2;
				@shWritePos = 0;
				@shWriteStartMut = @shMutation;
				__ONLINE_buffer_clear(@savesBuffer);
				#if not GMNET
					__ONLINE_buffer_write_uint16(@savesBuffer, 65535);
					__ONLINE_buffer_write_uint8(@savesBuffer, 2);
					__ONLINE_buffer_write_uint16(@savesBuffer, @saveHistCount);
				#endif
				#if GMNET
					__ONLINE_buffer_write_u16(@savesBuffer, 65535);
					__ONLINE_buffer_write_u8(@savesBuffer, 2);
					__ONLINE_buffer_write_u16(@savesBuffer, @saveHistCount);
				#endif
			}
		}
	}
	if(@shTrimActive){
		// excess trim: one shift per frame until under the cap
		@shFound = -1;
		for(@shI = 0; @shI < @saveHistCount && @shFound < 0; @shI += 1){
			if(!@saveHistFav[@shI]) @shFound = @shI;
		}
		if(@shFound < 0) @shFound = 0;
		@saveHistCount -= 1;
		for(@shI = @shFound; @shI < @saveHistCount; @shI += 1){
			@saveHistFav[@shI] = @saveHistFav[@shI + 1];
			@saveHistHotkey[@shI] = @saveHistHotkey[@shI + 1];
			@saveHistGrav[@shI] = @saveHistGrav[@shI + 1];
			@saveHistX[@shI] = @saveHistX[@shI + 1];
			@saveHistY[@shI] = @saveHistY[@shI + 1];
			@saveHistRoom[@shI] = @saveHistRoom[@shI + 1];
			@saveHistTime[@shI] = @saveHistTime[@shI + 1];
			@saveHistName[@shI] = @saveHistName[@shI + 1];
			@saveHistRoomName[@shI] = @saveHistRoomName[@shI + 1];
		}
		if(@saveHistCount <= @saveHistMax){
			@shTrimActive = false;
			@shWritePhase = 2;
			@shWritePos = 0;
			@shWriteStartMut = @shMutation;
			__ONLINE_buffer_clear(@savesBuffer);
			#if not GMNET
				__ONLINE_buffer_write_uint16(@savesBuffer, 65535);
				__ONLINE_buffer_write_uint8(@savesBuffer, 2);
				__ONLINE_buffer_write_uint16(@savesBuffer, @saveHistCount);
			#endif
			#if GMNET
				__ONLINE_buffer_write_u16(@savesBuffer, 65535);
				__ONLINE_buffer_write_u8(@savesBuffer, 2);
				__ONLINE_buffer_write_u16(@savesBuffer, @saveHistCount);
			#endif
		}
	}
}
if(@shWritePhase == 2){
	// serialization: up to 12 entries this frame, then one file write
	@shSlice = 0;
	while(@shWritePos < @saveHistCount && @shSlice < 12){
		@shI = @shWritePos;
		#if not GMNET
			__ONLINE_buffer_write_uint8(@savesBuffer, @saveHistFav[@shI]);
			__ONLINE_buffer_write_uint8(@savesBuffer, @saveHistHotkey[@shI]);
			__ONLINE_buffer_write_uint8(@savesBuffer, @saveHistGrav[@shI]);
			__ONLINE_buffer_write_int32(@savesBuffer, @saveHistX[@shI]);
			__ONLINE_buffer_write_float64(@savesBuffer, @saveHistY[@shI]);
			__ONLINE_buffer_write_int16(@savesBuffer, @saveHistRoom[@shI]);
			__ONLINE_buffer_write_float64(@savesBuffer, @saveHistTime[@shI]);
			__ONLINE_buffer_write_string(@savesBuffer, @saveHistName[@shI]);
			__ONLINE_buffer_write_string(@savesBuffer, @saveHistRoomName[@shI]);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@savesBuffer, @saveHistFav[@shI]);
			__ONLINE_buffer_write_u8(@savesBuffer, @saveHistHotkey[@shI]);
			__ONLINE_buffer_write_u8(@savesBuffer, @saveHistGrav[@shI]);
			__ONLINE_buffer_write_i32(@savesBuffer, @saveHistX[@shI]);
			__ONLINE_buffer_write_double(@savesBuffer, @saveHistY[@shI]);
			__ONLINE_buffer_write_i16(@savesBuffer, @saveHistRoom[@shI]);
			__ONLINE_buffer_write_double(@savesBuffer, @saveHistTime[@shI]);
			__ONLINE_buffer_write_string(@savesBuffer, @saveHistName[@shI]);
			__ONLINE_buffer_write_string(@savesBuffer, @saveHistRoomName[@shI]);
		#endif
		@shWritePos += 1;
		@shSlice += 1;
	}
	if(@shWritePos >= @saveHistCount){
		// Any mutation since the header was written (add/delete/fav/hotkey
		// during serialization) makes the buffered body stale: discard it
		// and schedule a fresh full write next frame. Checked BEFORE the
		// file write, so a kill/crash can never leave a truncated or
		// header/body-mismatched @saves on disk.
		if(@shMutation != @shWriteStartMut){
			@shWritePhase = 0;
			@saveHistDirty = true;
			@saveHistDirtyTimer = 0;
		}else{
			#if not GMNET
				__ONLINE_buffer_write_to_file(@savesBuffer, "@saves");
			#endif
			#if GMNET
				__ONLINE_buffer_save(@savesBuffer, "@saves");
			#endif
			@shWritePhase = 0;
			@saveHistDirty = false;
		}
	}
}
// RATING SUBMIT
if(@ratingSubmit){
	@ratingSubmit = false;
	if(!@ratingSubmitting && @ratingCooldown <= 0 && @connected && @rStars >= 1 && @rStars <= 5){
		@ratingSubmitting = true;
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint8(@buffer, 9);
			__ONLINE_buffer_write_uint8(@buffer, @rStars);
			__ONLINE_buffer_write_uint8(@buffer, @rCleared);
		#endif
		#if GMNET
			__ONLINE_buffer_write_u8(@buffer, 9);
			__ONLINE_buffer_write_u8(@buffer, @rStars);
			__ONLINE_buffer_write_u8(@buffer, @rCleared);
		#endif
		__ONLINE_socket_write_message(@socket, @buffer);
	}
}
if(@ratingResultTimer > 0) @ratingResultTimer -= 1;
if(@ratingCooldown > 0) @ratingCooldown -= 1;
if(@rClearWarn > 0) @rClearWarn -= 1;
// FLUSH TCP
#if not GMNET
__ONLINE_socket_update_write(@socket);
#endif
#if GMNET
__ONLINE_socket_send(@socket);
#endif

#if PLAYER_LIST
// PLAYER OBJECT PICK MODE (entered from settings tab 0, "Player Objects" row).
// L-click an instance: add/remove its object; R-click: add at top priority;
// Enter/Esc/settings key: close and persist (only when edited this session).
if(@debug_pick_player){
	if(keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_enter) || keyboard_check_pressed(@keySettings)){
		@debug_pick_player = false;
		if(@objListEdited){
			@objListEdited = false;
			@f = file_text_open_write("__online_player_objects");
			for(@i = 0; @i < ds_list_size(@obj_list); @i += 1){
				file_text_write_real(@f, ds_list_find_value(@obj_list, @i) + 1); // +1: GM8 text files and 0 don't mix
				file_text_writeln(@f);
			}
			file_text_close(@f);
			// export a shareable converter config snippet (games/<game>.ini format)
			@str = "alt_player_objects=";
			@comma = "";
			for(@i = 0; @i < ds_list_size(@obj_list); @i += 1){
				@obj_id = ds_list_find_value(@obj_list, @i);
				#if PLAYER2
					if(@obj_id != %arg0 && @obj_id != %arg1){
				#endif
				#if not PLAYER2
					if(@obj_id != %arg0){
				#endif
					@str += @comma + object_get_name(@obj_id);
					@comma = ",";
				}
			}
			@f = file_text_open_write(@gameName + ".ini");
			file_text_write_string(@f, "# " + @gameName + " player objects");
			file_text_writeln(@f);
			file_text_write_string(@f, "[iwpo]");
			file_text_writeln(@f);
			file_text_write_string(@f, @str);
			file_text_writeln(@f);
			file_text_close(@f);
		}
	}else{
		@target_instance = instance_position(mouse_x, mouse_y, all);
		if(@target_instance != noone){
			@pickIdx = ds_list_find_index(@obj_list, @target_instance.object_index);
			if(@pickIdx >= 0){
				if(mouse_check_button_pressed(mb_left)){
					ds_list_delete(@obj_list, @pickIdx);
					@objListEdited = true;
				}
			}else{
				if(mouse_check_button_pressed(mb_left)){
					ds_list_add(@obj_list, @target_instance.object_index);
					@objListEdited = true;
				}else if(mouse_check_button_pressed(mb_right)){
					ds_list_insert(@obj_list, 0, @target_instance.object_index);
					@objListEdited = true;
				}
			}
		}
	}
}
#endif

// SETTINGS PANEL
if(@settingsOpen && @keybindEditing < 0){
	if(@kbDelay > 0) @kbDelay -= 1;
	@kbAct = 0;
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 0){
		if(keyboard_check_pressed(vk_left)){
			@settingsTab -= 1;
			if(@settingsTab < 0) @settingsTab = 5;
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_right)){
			@settingsTab += 1;
			if(@settingsTab > 5) @settingsTab = 0;
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_enter)){
			@kbFocus = 1;
			@kbAct = 1;
		}
	}
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 0){
		if(keyboard_check_pressed(vk_up)){
			if(@kbRow[0] <= 0){
				@kbRow[0] = 0;
				@kbFocus = 0;
			}else{
				@kbRow[0] -= 1;
			}
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_down)){
			#if PLAYER_LIST
				@kbRow[0] += 1; if(@kbRow[0] > 8) @kbRow[0] = 8;
			#endif
			#if not PLAYER_LIST
				@kbRow[0] += 1; if(@kbRow[0] > 7) @kbRow[0] = 7;
			#endif
			@kbAct = 1;
		}
		#if PLAYER_LIST
			if(keyboard_check_pressed(vk_enter) && @kbRow[0] == 7){
				@settingsOpen = false;
				@debug_pick_player = true;
				@kbAct = 1;
			}
			if(keyboard_check_pressed(vk_enter) && @kbRow[0] == 8){
				@manualReconnect = true;
				@settingsOpen = false;
				@kbAct = 1;
			}
		#endif
		#if not PLAYER_LIST
			if(keyboard_check_pressed(vk_enter) && @kbRow[0] == 7){
				@manualReconnect = true;
				@settingsOpen = false;
				@kbAct = 1;
			}
		#endif
		if(keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)){
			if(keyboard_check_pressed(vk_right)) @kbDir = 1; else @kbDir = -1;
			if(@kbRow[0] == 0){
				@team += @kbDir;
				if(@team < 0) @team = 7;
				if(@team > 7) @team = 0;
				@teamChanged = true;
			}else if(@kbRow[0] == 1){
				@lerpEnabled = !@lerpEnabled;
				@lerpChanged = true;
			}else if(@kbRow[0] == 2){
				@save_enabled = 1 - @save_enabled;
				@saveChanged = true;
				if(!@save_enabled){
					#if TEMPFILE
						if(file_exists("tempOnline2")){
							file_delete("tempOnline2");
						}
					#endif
					@sSaved = false;
				}
			}else if(@kbRow[0] == 3){
				@fastLoadEnabled = !@fastLoadEnabled;
				@fastLoadChanged = true;
			}else if(@kbRow[0] == 4){
				@vis += @kbDir;
				if(@vis < 0) @vis = 2;
				if(@vis > 2) @vis = 0;
				@visChanged = true;
			}else if(@kbRow[0] == 5){
				@showArrows = !@showArrows;
			}else if(@kbRow[0] == 6){
				@specCamMode += @kbDir;
				if(@specCamMode < 0) @specCamMode = 1;
				if(@specCamMode > 1) @specCamMode = 0;
			}
			@kbAct = 1;
		}
	}
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 1){
		@kbVisCount = 0;
		for(@kbI = 0; @kbI < @saveHistCount; @kbI += 1){
			if(@saveHistFilter == 0 || @saveHistFav[@kbI]) @kbVisCount += 1;
		}
		if(keyboard_check(vk_shift) && keyboard_check_pressed(70)){
			@saveHistFilter = 1 - @saveHistFilter;
			@saveHistPage = 0;
			@kbRow[1] = 0;
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_backspace)){
			@saveHistFilter = 1 - @saveHistFilter;
			@saveHistPage = 0;
			@kbRow[1] = 0;
			@kbAct = 1;
		}
		if(@kbAct == 0 && keyboard_check(vk_shift) && keyboard_check_pressed(vk_delete)){
			if(@saveHistCount > @saveHistFavCount){
				@saveHistClearFiles = true;
			}
			@kbAct = 1;
		}
		if(@kbAct == 0 && keyboard_check_pressed(vk_home)){
			@saveHistPage = 0;
			@kbRow[1] = 0;
			@kbAct = 1;
		}
		if(@kbAct == 0 && keyboard_check_pressed(vk_end)){
			if(@kbVisCount > 0){
				@kbRow[1] = @kbVisCount - 1;
				@saveHistPage = @kbRow[1] div 8;
			}
			@kbAct = 1;
		}
		if(@kbVisCount > 0){
			if(@kbRow[1] >= @kbVisCount) @kbRow[1] = @kbVisCount - 1;
			if(@kbRow[1] < 0) @kbRow[1] = 0;
			if(keyboard_check_pressed(vk_up)){
				if(@kbRow[1] <= 0){
					@kbRow[1] = 0;
					@kbFocus = 0;
				}else{
					@kbRow[1] -= 1;
					@saveHistPage = @kbRow[1] div 8;
				}
				@kbAct = 1;
			}
			if(keyboard_check_pressed(vk_down)){
				@kbRow[1] += 1; if(@kbRow[1] >= @kbVisCount) @kbRow[1] = @kbVisCount - 1;
				@saveHistPage = @kbRow[1] div 8;
				@kbAct = 1;
			}
			if(keyboard_check_pressed(vk_pageup) || keyboard_check_pressed(vk_left)){
				@kbRow[1] -= 8; if(@kbRow[1] < 0) @kbRow[1] = 0;
				@saveHistPage = @kbRow[1] div 8;
				@kbAct = 1;
			}
			if(keyboard_check_pressed(vk_pagedown) || keyboard_check_pressed(vk_right)){
				@kbRow[1] += 8; if(@kbRow[1] >= @kbVisCount) @kbRow[1] = @kbVisCount - 1;
				@saveHistPage = @kbRow[1] div 8;
				@kbAct = 1;
			}
			@kbVisCur = -1;
			@kbVI = 0;
			for(@kbI = @saveHistCount - 1; @kbI >= 0 && @kbVisCur < 0; @kbI -= 1){
				if(@saveHistFilter == 0 || @saveHistFav[@kbI]){
					if(@kbVI == @kbRow[1]) @kbVisCur = @kbI;
					@kbVI += 1;
				}
			}
			if(keyboard_check_pressed(vk_enter)){
				if(@kbVisCur >= 0){
					@saveHistApply = @kbVisCur;
					@settingsOpen = false;
				}
				@kbAct = 1;
			}
			if(!keyboard_check(vk_shift) && keyboard_check_pressed(70)){
				if(@kbVisCur >= 0){
					if(@saveHistFav[@kbVisCur]){
						@saveHistFav[@kbVisCur] = 0;
						@saveHistFavCount -= 1;
					}else{
						if(@saveHistFavCount < @saveHistFavMax){
							@saveHistFav[@kbVisCur] = 1;
							@saveHistFavCount += 1;
						}
					}
					@shMutation += 1;
					if(!@saveHistDirty) @saveHistDirtyTimer = room_speed * 3;
					@saveHistDirty = true;
				}
				@kbAct = 1;
			}
			for(@kbHot = 1; @kbHot <= 8 && @kbAct == 0; @kbHot += 1){
				if(keyboard_check_pressed(48 + @kbHot)){
					if(@kbVisCur >= 0){
						if(@saveHistHotkey[@kbVisCur] == @kbHot){
							@saveHistHotkey[@kbVisCur] = 0;
						}else{
							for(@kbI = 0; @kbI < @saveHistCount; @kbI += 1){
								if(@saveHistHotkey[@kbI] == @kbHot) @saveHistHotkey[@kbI] = 0;
							}
							@saveHistHotkey[@kbVisCur] = @kbHot;
						}
						@shMutation += 1;
						if(!@saveHistDirty) @saveHistDirtyTimer = room_speed * 3;
						@saveHistDirty = true;
						@kbAct = 1;
					}
				}
			}
			if(keyboard_check_pressed(vk_delete)){
				// Nested guard: GM8.0 does not short-circuit && - a combined
				// condition would index @saveHistFav[-1] when @kbVisCur < 0.
				if(@kbVisCur >= 0){
					if(!@saveHistFav[@kbVisCur]){
						for(@kbI = @kbVisCur; @kbI < @saveHistCount - 1; @kbI += 1){
							@saveHistFav[@kbI] = @saveHistFav[@kbI + 1];
							@saveHistHotkey[@kbI] = @saveHistHotkey[@kbI + 1];
							@saveHistGrav[@kbI] = @saveHistGrav[@kbI + 1];
							@saveHistX[@kbI] = @saveHistX[@kbI + 1];
							@saveHistY[@kbI] = @saveHistY[@kbI + 1];
							@saveHistRoom[@kbI] = @saveHistRoom[@kbI + 1];
							@saveHistName[@kbI] = @saveHistName[@kbI + 1];
							@saveHistRoomName[@kbI] = @saveHistRoomName[@kbI + 1];
							@saveHistTime[@kbI] = @saveHistTime[@kbI + 1];
						}
						@saveHistCount -= 1;
						@shMutation += 1;
						if(!@saveHistDirty) @saveHistDirtyTimer = room_speed * 3;
						@saveHistDirty = true;
					}
				}
				@kbAct = 1;
			}
		}
		if(@kbVisCount <= 0 && keyboard_check_pressed(vk_up)){
			@kbFocus = 0;
			@kbAct = 1;
		}
	}
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 2){
		if(keyboard_check_pressed(vk_up)){
			if(@kbRow[2] <= 0){
				@kbRow[2] = 0;
				@kbFocus = 0;
			}else{
				@kbRow[2] -= 1;
			}
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_down)){
			@kbRow[2] += 1; if(@kbRow[2] > 2) @kbRow[2] = 2;
			@kbAct = 1;
		}
		for(@kbI = 1; @kbI <= 5; @kbI += 1){
			if(keyboard_check_pressed(48 + @kbI)){
				if(@rStars == @kbI) @rStars = 0; else @rStars = @kbI;
				@kbRow[2] = 0;
				@kbAct = 1;
			}
		}
		if(@kbAct == 0 && @kbRow[2] == 0 && (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right))){
			if(keyboard_check_pressed(vk_left)) @rStars -= 1; else @rStars += 1;
			if(@rStars < 0) @rStars = 5;
			if(@rStars > 5) @rStars = 0;
			@kbAct = 1;
		}
		if(@kbAct == 0 && (@kbRow[2] == 1 && (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space)))){
			@rCleared = 1 - @rCleared;
			@kbAct = 1;
		}
		if(@kbAct == 0 && @kbRow[2] == 2 && keyboard_check_pressed(vk_enter)){
			if(@rStars > 0 && @ratingCooldown <= 0 && !@ratingSubmitting){
				@ratingSubmit = true;
			}
			@kbAct = 1;
		}
	}
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 3){
		if(keyboard_check_pressed(vk_up)){
			if(@kbRow[3] <= 0){
				@kbRow[3] = 0;
				@kbFocus = 0;
			}else{
				@kbRow[3] -= 1;
			}
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_down)){
			@kbRow[3] += 1; if(@kbRow[3] > 10) @kbRow[3] = 10;
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_enter)){
			if(@kbRow[3] < 10){
				@keybindEditing = @kbRow[3];
				@keybindArmTimer = 6;
			}else{
				@keyVis = 86;
				@keySave = 84;
				@keySpectate = 89;
				@keyChatLog = 85;
				@keyArrows = 73;
				@keySettings = 79;
				@keyPlayerList = 76;
				@keyChat = 32;
				@keyPing = 72;
				@keyFastLoad = 70;
				@keybindEditing = -1;
				@keybindSave = true;
			}
			@kbAct = 1;
		}
	}
	if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 4){
		if(keyboard_check_pressed(vk_up)){
			@kbFocus = 0;
			@kbAct = 1;
		}
		if(keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)){
			@syncEnabled = !@syncEnabled;
			@syncEnabledChanged = true;
			@kbAct = 1;
		}
	}
    if(@kbDelay <= 0 && @kbAct == 0 && @kbFocus == 1 && @settingsTab == 5){
        // Rows 0..skinCount-1 are skins, row skinCount is Auto-download,
        // row skinCount+1 is Clear.
        @skRows = @skinVisCount + 2;
        if(@kbRow[5] > @skRows - 1) @kbRow[5] = @skRows - 1;
        if(keyboard_check_pressed(vk_up)){
            if(@kbRow[5] <= 0){
                @kbRow[5] = 0;
                @kbFocus = 0;
            }else{
                @kbRow[5] -= 1;
            }
            if(@kbRow[5] < @skinVisCount) @skinPage = @kbRow[5] div 12;
            @kbAct = 1;
        }
        if(keyboard_check_pressed(vk_down)){
            @kbRow[5] += 1;
            if(@kbRow[5] > @skRows - 1) @kbRow[5] = @skRows - 1;
            if(@kbRow[5] < @skinVisCount) @skinPage = @kbRow[5] div 12;
            @kbAct = 1;
        }
        if(keyboard_check_pressed(vk_pageup)){
            @kbRow[5] -= 12;
            if(@kbRow[5] < 0) @kbRow[5] = 0;
            if(@kbRow[5] < @skinVisCount) @skinPage = @kbRow[5] div 12;
            @kbAct = 1;
        }
        if(keyboard_check_pressed(vk_pagedown)){
            @kbRow[5] += 12;
            if(@kbRow[5] > @skRows - 1) @kbRow[5] = @skRows - 1;
            if(@kbRow[5] < @skinVisCount) @skinPage = @kbRow[5] div 12;
            @kbAct = 1;
        }
        if(@kbRow[5] == @skinVisCount && (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_enter))){
            @skinAutoDL = 1 - @skinAutoDL;
            @skinAutoDLChanged = true;
            if(@skinAutoDL == 1){
                // Re-enabled: forget the one-per-hash notice/download marks so
                // the next roster replay re-triggers unknown skins as downloads.
                for(@skH = 0; @skH < 8; @skH += 1){
                    @skinHint[@skH] = "";
                }
            }
            @kbAct = 1;
        }
        if(@kbRow[5] < @skinVisCount && keyboard_check_pressed(vk_enter)){
            @skin_select(@kbRow[5]);
            @kbAct = 1;
        }
        if(@kbRow[5] == @skinVisCount + 1 && keyboard_check_pressed(vk_enter)){
            @skin_clear();
            @kbAct = 1;
        }
    }
	if(@kbAct){
		@kbDelay = 6;
	}
}

// KEYBIND EDITING
if(@keybindArmTimer > 0) @keybindArmTimer -= 1;
if(@keybindEditing >= 0 && @settingsOpen && @settingsTab == 3 && @keybindArmTimer <= 0){
	@kbPressed = keyboard_key;
	if(@kbPressed > 0 && @kbPressed < 256 && keyboard_check_pressed(@kbPressed)){
		if(@kbPressed != vk_escape){
			if(@keybindEditing == 0) @keyVis = @kbPressed;
			if(@keybindEditing == 1) @keySave = @kbPressed;
			if(@keybindEditing == 2) @keySpectate = @kbPressed;
			if(@keybindEditing == 3) @keyChatLog = @kbPressed;
			if(@keybindEditing == 4) @keyArrows = @kbPressed;
			if(@keybindEditing == 5) @keySettings = @kbPressed;
			if(@keybindEditing == 6) @keyPlayerList = @kbPressed;
			if(@keybindEditing == 7) @keyChat = @kbPressed;
			if(@keybindEditing == 8) @keyPing = @kbPressed;
			if(@keybindEditing == 9) @keyFastLoad = @kbPressed;
			@keybindSave = true;
		}
		@keybindEditing = -1;
		@keybindArmTimer = 0;
	}
}
if(@keybindSave){
	@keybindSave = false;
	ini_open("@config.ini");
	ini_write_string("config", "server", @server);
	ini_write_real("config", "key_chat", @keyChat);
	ini_write_real("config", "key_visibility", @keyVis);
	ini_write_real("config", "key_save", @keySave);
	ini_write_real("config", "key_playerlist", @keyPlayerList);
	ini_write_real("config", "key_settings", @keySettings);
	ini_write_real("config", "key_chatlog", @keyChatLog);
	ini_write_real("config", "key_spectate", @keySpectate);
	ini_write_real("config", "key_arrows", @keyArrows);
	ini_write_real("config", "key_ping", @keyPing);
	ini_write_real("config", "key_fastload", @keyFastLoad);
	ini_write_real("config", "team", @team);
	ini_write_real("config", "lerp", @lerpEnabled);
	ini_write_real("config", "fast_load", @fastLoadEnabled);
	ini_write_real("config", "skinAutoDL", @skinAutoDL);
	ini_close();
}
