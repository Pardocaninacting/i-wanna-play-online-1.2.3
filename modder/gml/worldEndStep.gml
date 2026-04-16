/// ONLINE
// %arg0: The name of the player object
// %arg1: The name of the player2 object if it exists
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
			if(!instance_exists(@p)) @p = %arg1;
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
socket_update_read(@socket);
#endif
#if GMNET
socket_receive(@socket);
#endif
while(socket_read_message(@socket, @buffer)){
	#if not GMNET
		switch(buffer_read_uint8(@buffer)){
	#endif
	#if GMNET
		switch(buffer_read_u8(@buffer)){
	#endif
		case 0:
			// CREATED
			@ID = buffer_read_string(@buffer);
			@found = false;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				if(instance_find(@onlinePlayer, @i).@ID == @ID){
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
				@oPlayer.@name = buffer_read_string(@buffer);
				if(ds_map_exists(@teamMap, @ID)){
					@oPlayer.@team = ds_map_find_value(@teamMap, @ID);
				}
			}
			break;
		case 1:
			// DESTROYED
			@ID = buffer_read_string(@buffer);
			if(ds_map_exists(@teamMap, @ID)) ds_map_delete(@teamMap, @ID);
			@found = false;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					with(@oPlayer){
						instance_destroy();
					}
					@found = true;
				}
			}
			break;
		case 2:
			// INCOMPATIBLE VERSION
			@lastVersion = buffer_read_string(@buffer);
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
			@ID = buffer_read_string(@buffer);
			@found = false;
			@oPlayer = 0;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@found = true;
				}
			}
			if(@found){
				@message = buffer_read_string(@buffer);
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
					@sGravity = buffer_read_uint8(@buffer);
					@sName = buffer_read_string(@buffer);
					@sX = buffer_read_int32(@buffer);
					@sY = buffer_read_float64(@buffer);
					@sRoom = buffer_read_int16(@buffer);
				#endif
				#if GMNET
					@sGravity = buffer_read_u8(@buffer);
					@sName = buffer_read_string(@buffer);
					@sX = buffer_read_i32(@buffer);
					@sY = buffer_read_double(@buffer);
					@sRoom = buffer_read_i16(@buffer);
				#endif
				#if GMS2
					@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
				#endif
				#if not GMS2
					@a = instance_create(0, 0, @playerSaved);
				#endif
				@a.@name = @sName;
				@a.@state = -1;
				@shIdx = @saveHistCount;
				@saveHistCount += 1;
				@saveHistFav[@shIdx] = 0;
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
				if(@save_enabled){
					@sSaved = true;
					#if TEMPFILE
						buffer_clear(@buffer);
						#if not GMNET
							buffer_write_uint8(@buffer, @sGravity);
							buffer_write_int32(@buffer, @sX);
							buffer_write_float64(@buffer, @sY);
							buffer_write_int16(@buffer, @sRoom);
							buffer_write_to_file(@buffer, "tempOnline2");
						#endif
						#if GMNET
							buffer_write_u8(@buffer, @sGravity);
							buffer_write_i32(@buffer, @sX);
							buffer_write_double(@buffer, @sY);
							buffer_write_i16(@buffer, @sRoom);
							buffer_save(@buffer, "tempOnline2");
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
			@selfID = buffer_read_string(@buffer);
			break;
		case 7:
			// CUSTOM DATA
			@ID = buffer_read_string(@buffer);
			#if not GMNET
				@customSlotCount = buffer_read_uint16(@buffer);
				if (@customSlotCount >= 1)
					@receivedSlot = buffer_read_int32(@buffer);
			#endif
			#if GMNET
				@customSlotCount = buffer_read_u16(@buffer);
				if (@customSlotCount >= 1)
					@receivedSlot = buffer_read_i32(@buffer);
			#endif
			break;
		case 8:
			// TEAM
			@ID = buffer_read_string(@buffer);
			#if not GMNET
				@receivedTeam = buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@receivedTeam = buffer_read_u8(@buffer);
			#endif
			@teamIsNew = !ds_map_exists(@teamMap, @ID);
			@teamOldVal = ds_map_find_value(@teamMap, @ID);
			ds_map_replace(@teamMap, @ID, @receivedTeam);
			@found = false;
			for(@i = 0; @i < instance_number(@onlinePlayer) && !@found; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				if(@oPlayer.@ID == @ID){
					@oPlayer.@team = @receivedTeam;
					@found = true;
				}
			}
			break;
		case 9:
			// RATING
			#if not GMNET
				@ratingReply = buffer_read_uint8(@buffer);
			#endif
			#if GMNET
				@ratingReply = buffer_read_u8(@buffer);
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
	}
}
@mustQuit = false;
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
			socket_destroy(@socket);
			@socket = socket_create();
			socket_connect(@socket, @server, @tcpPort);
			@reconnectDelay = min(@reconnectAttempts * 2, 10) * room_speed;
			@reconnectTimer = @reconnectDelay;
		}
	}
}
switch(socket_get_state(@socket)){
	case 2:
		if(!@connected || @reconnecting){
			if(@reconnecting){
				// RECONNECT
				@reconnecting = false;
				@reconnectAttempts = 0;
				buffer_clear(@buffer);
				#if not GMNET
					buffer_write_uint8(@buffer, 3);
					buffer_write_string(@buffer, @name);
					buffer_write_string(@buffer, @selfGameID);
					buffer_write_string(@buffer, @gameName);
					buffer_write_string(@buffer, @version);
					buffer_write_uint8(@buffer, 0);				buffer_write_uint8(@buffer, 1);					socket_write_message(@socket, @buffer);
				#endif
				#if GMNET
					buffer_write_u8(@buffer, 3);
					buffer_write_string(@buffer, @name);
					buffer_write_string(@buffer, @selfGameID);
					buffer_write_string(@buffer, @gameName);
					buffer_write_string(@buffer, @version);
					buffer_write_u8(@buffer, 0);				buffer_write_u8(@buffer, 1);					socket_write_message(@socket, @buffer);
				#endif
				buffer_clear(@buffer);
				#if not GMNET
					buffer_write_uint8(@buffer, 8);
					buffer_write_uint8(@buffer, @team);
				#endif
				#if GMNET
					buffer_write_u8(@buffer, 8);
					buffer_write_u8(@buffer, @team);
				#endif
				socket_write_message(@socket, @buffer);
				if(udpsocket_exists(@udpsocket)){
					udpsocket_destroy(@udpsocket);
				}
				@udpsocket = udpsocket_create();
				udpsocket_start(@udpsocket, false, 0);
				udpsocket_set_destination(@udpsocket, @server, @udpPort);
				buffer_clear(@buffer);
				#if not GMNET
					buffer_write_uint8(@buffer, 0);
				#endif
				#if GMNET
					buffer_write_u8(@buffer, 0);
				#endif
				udpsocket_send(@udpsocket, @buffer);
				@udpReady = false;
				@udpRetryCount = 0;
				@udpGraceFrames = room_speed*3;
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
if(!@spectating){
@p = %arg0;
#if PLAYER2
	if(!instance_exists(@p)){
		@p = %arg1;
	}
#endif
@exists = instance_exists(@p);
@X = @pX;
@Y = @pY;
if(@exists){
	@p = instance_find(@p, 0);
	if(@exists != @pExists){
		// SEND PLAYER CREATE
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint8(@buffer, 0);
		#endif
		#if GMNET
			buffer_write_u8(@buffer, 0);
		#endif
		socket_write_message(@socket, @buffer);
	}
	@X = @p.x;
	@Y = @p.y;
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
			buffer_clear(@buffer);
			#if not GMNET
				buffer_write_uint8(@buffer, 1);
				buffer_write_string(@buffer, @selfID);
				buffer_write_string(@buffer, @selfGameID);
				buffer_write_uint16(@buffer, room);
				buffer_write_uint64(@buffer, current_time);
				buffer_write_int32(@buffer, @X);
				buffer_write_int32(@buffer, @Y);
				buffer_write_int32(@buffer, @p.sprite_index);
				buffer_write_float32(@buffer, @p.image_speed);
				#if GM8YY
					buffer_write_float32(@buffer, @p.image_xscale*@p.xScale);
				#endif
				#if GLOBAL_PLAYER_XSCALE
					buffer_write_float32(@buffer, @p.image_xscale*global.player_xscale);
				#endif
				#if not GLOBAL_PLAYER_XSCALE
					#if not GM8YY
						#if PLAYER_XSCALE
							buffer_write_float32(@buffer, @p.image_xscale*@p.xScale);
						#endif
						#if not PLAYER_XSCALE
							#if PLAYER_XSCALE_LOWER
								buffer_write_float32(@buffer, @p.image_xscale*@p.xscale);
							#endif
							#if not PLAYER_XSCALE_LOWER
								buffer_write_float32(@buffer, @p.image_xscale);
							#endif
						#endif
					#endif
				#endif
				#if STUDIO
				buffer_write_float32(@buffer, @p.image_yscale*global.grav);
			#endif
				#if GM8YY
					buffer_write_float32(@buffer, @p.image_yscale*global.grav);
				#endif
				#if not STUDIO
					#if not GM8YY
						buffer_write_float32(@buffer, @p.image_yscale);
					#endif
				#endif
				buffer_write_float32(@buffer, @p.image_angle);
				buffer_write_string(@buffer, @name);
			#endif
			#if GMNET
				buffer_write_u8(@buffer, 1);
				buffer_write_string(@buffer, @selfID);
				buffer_write_string(@buffer, @selfGameID);
				buffer_write_u16(@buffer, room);
				buffer_write_u64(@buffer, current_time);
				buffer_write_i32(@buffer, @X);
				buffer_write_i32(@buffer, @Y);
				buffer_write_i32(@buffer, @p.sprite_index);
				buffer_write_float(@buffer, @p.image_speed);
				#if not RENEX
					#if GLOBAL_PLAYER_XSCALE
						buffer_write_float(@buffer, @p.image_xscale*global.player_xscale);
					#endif
					#if GM8YY
						buffer_write_float(@buffer, @p.image_xscale*@p.xScale);
					#endif
					#if not GLOBAL_PLAYER_XSCALE
						#if not GM8YY
							#if PLAYER_XSCALE
								buffer_write_float(@buffer, @p.image_xscale*@p.xScale);
							#endif
							#if not PLAYER_XSCALE
								#if PLAYER_XSCALE_LOWER
									buffer_write_float(@buffer, @p.image_xscale*@p.xscale);
								#endif
								#if not PLAYER_XSCALE_LOWER
									buffer_write_float(@buffer, @p.image_xscale);
								#endif
							#endif
						#endif
					#endif
					#if STUDIO
						buffer_write_float(@buffer, @p.image_yscale*global.grav);
					#endif
					#if GM8YY
						buffer_write_float(@buffer, @p.image_yscale*global.grav);
					#endif
					#if not STUDIO
						#if not GM8YY
							buffer_write_float(@buffer, @p.image_yscale);
						#endif
					#endif
				#endif
				#if RENEX
					buffer_write_float(@buffer, @p.image_xscale*@p.x_scale);
					buffer_write_float(@buffer, @p.image_yscale*global.grav);
				#endif
				buffer_write_float(@buffer, @p.image_angle);
				buffer_write_string(@buffer, @name);
			#endif
			udpsocket_send(@udpsocket, @buffer);
		}
	}
	@t += 1;
	if(keyboard_check_pressed(@keyChat)){
		#if STUDIO
			@message = get_string("Say something:", "");
		#endif
		#if not STUDIO
			#if GM80
			@message = wd_input_box("Chat", "Say something:", "");
			#endif
			#if CJKTEXT
			@message = ansi_to_utf8(wd_input_box("Chat", "Say something:", ""));
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
			buffer_clear(@buffer);
			#if not GMNET
				buffer_write_uint8(@buffer, 4);
			#endif
			#if GMNET
				buffer_write_u8(@buffer, 4);
			#endif
			buffer_write_string(@buffer, @message);
			socket_write_message(@socket, @buffer);
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
// CUSTOM DATA SYNC
@customSlot = 0;
if (@customSlot != @customSlotPrev) {
	@customSlotPrev = @customSlot;
	buffer_clear(@buffer);
	#if not GMNET
		buffer_write_uint8(@buffer, 7);
		buffer_write_uint16(@buffer, 1);
		buffer_write_int32(@buffer, @customSlot);
	#endif
	#if GMNET
		buffer_write_u8(@buffer, 7);
		buffer_write_u16(@buffer, 1);
		buffer_write_i32(@buffer, @customSlot);
	#endif
	socket_write_message(@socket, @buffer);
}else{
	if(@exists != @pExists){
		// SEND PLAYER DESTROYED
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint8(@buffer, 1);
		#endif
		#if GMNET
			buffer_write_u8(@buffer, 1);
		#endif
		socket_write_message(@socket, @buffer);
	}
}
@pExists = @exists;
@pX = @X;
@pY = @Y;
}
@heartbeat += 1/room_speed;
if(@heartbeat > 3){
	@heartbeat = 0;
	// SEND PLAYER HEARTBEAT
	buffer_clear(@buffer);
	#if not GMNET
		buffer_write_uint8(@buffer, 2);
	#endif
	#if GMNET
		buffer_write_u8(@buffer, 2);
	#endif

	socket_write_message(@socket, @buffer);
}
#if not GMNET
socket_update_write(@socket);
#endif
#if GMNET
socket_send(@socket);
#endif
// UDP SOCKETS
while(udpsocket_receive(@udpsocket, @buffer)){
	#if not GMNET
		switch(buffer_read_uint8(@buffer)){
	#endif
	#if GMNET
		switch(buffer_read_u8(@buffer)){
	#endif
		case 1:
			// RECEIVED MOVED
			@ID = buffer_read_string(@buffer);
			@gameID = buffer_read_string(@buffer);
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
			#if not GMNET
				@oPlayer.@oRoom = buffer_read_uint16(@buffer);
				@syncTime = buffer_read_uint64(@buffer);
				if(@oPlayer.@syncTime < @syncTime){
					@oPlayer.@syncTime = @syncTime;
					@oPlayer.@targetX = buffer_read_int32(@buffer);
					@oPlayer.@targetY = buffer_read_int32(@buffer);
					if(!@oPlayer.@lerpInit){
						@oPlayer.x = @oPlayer.@targetX;
						@oPlayer.y = @oPlayer.@targetY;
						@oPlayer.@lerpInit = true;
					}
					@oPlayer.sprite_index = buffer_read_int32(@buffer);
					@oPlayer.image_speed = buffer_read_float32(@buffer);
					@oPlayer.image_xscale = buffer_read_float32(@buffer);
					@oPlayer.image_yscale = buffer_read_float32(@buffer);
					@oPlayer.image_angle = buffer_read_float32(@buffer);
					@oPlayer.@name = buffer_read_string(@buffer);
			#endif
			#if GMNET
				@oPlayer.@oRoom = buffer_read_u16(@buffer);
				@syncTime = buffer_read_u64(@buffer);
				if(@oPlayer.@syncTime < @syncTime){
					@oPlayer.@syncTime = @syncTime;
					@oPlayer.@targetX = buffer_read_i32(@buffer);
					@oPlayer.@targetY = buffer_read_i32(@buffer);
					if(!@oPlayer.@lerpInit){
						@oPlayer.x = @oPlayer.@targetX;
						@oPlayer.y = @oPlayer.@targetY;
						@oPlayer.@lerpInit = true;
					}
					@oPlayer.sprite_index = buffer_read_i32(@buffer);
					@oPlayer.image_speed = buffer_read_float(@buffer);
					@oPlayer.image_xscale = buffer_read_float(@buffer);
					@oPlayer.image_yscale = buffer_read_float(@buffer);
					@oPlayer.image_angle = buffer_read_float(@buffer);
					@oPlayer.@name = buffer_read_string(@buffer);
			#endif
			}
			break;
		default:
			break;
	}
}
@udpState = udpsocket_get_state(@udpsocket);
if(@udpState == 1){
	@udpReady = true;
	@udpGraceFrames = room_speed*3;
}else{
	if(!@udpReady && @udpGraceFrames > 0){
		@udpGraceFrames -= 1;
	}else if(!@udpReady && @udpRetryCount < 3){
		@udpRetryCount += 1;
		if(udpsocket_exists(@udpsocket)){
			udpsocket_destroy(@udpsocket);
		}
		@udpsocket = udpsocket_create();
		udpsocket_start(@udpsocket, false, 0);
		udpsocket_set_destination(@udpsocket, @server, @udpPort);
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint8(@buffer, 0);
		#endif
		#if GMNET
			buffer_write_u8(@buffer, 0);
		#endif
		udpsocket_send(@udpsocket, @buffer);
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
if(keyboard_check_pressed(@keyVis)){
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
if(keyboard_check_pressed(@keySave)){
	@save_enabled = 1 - @save_enabled;
	#if GMS2
		@a = instance_create_depth(0, 0, @playerSavedDepth, @playerSaved);
	#endif
	#if not GMS2
		@a = instance_create(0, 0, @playerSaved);
	#endif
	@a.@name = "";
	@a.@state = @save_enabled + 3;
}
if(keyboard_check_pressed(@keyPlayerList)){
	@showPlayerList = !@showPlayerList;
}
if(keyboard_check_pressed(@keySettings)){
	@settingsOpen = !@settingsOpen;
}
if(keyboard_check_pressed(@keyChatLog)){
	@chatLogOpen = !@chatLogOpen;
	@chatLogScroll = 0;
}
if(keyboard_check_pressed(@keyArrows)){
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
// SPECTATOR MODE
if(!keyboard_check(@keySpectate)){
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
		@p = %arg0;
		#if PLAYER2
			if(!instance_exists(@p)) @p = %arg1;
		#endif
		if(instance_exists(@p)){
			@p = instance_find(@p, 0);
			@specX = @p.x;
			@specY = @p.y;
			@specRoom = room;
			@specObj = @p.object_index;
			#if STUDIO
				@specGrav = global.grav;
			#endif
			#if not STUDIO
				@specGrav = 0;
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
			if(instance_number(@onlinePlayer) > 0){
				@specTarget = instance_find(@onlinePlayer, 0);
				@specTargetID = @specTarget.@ID;
				@specTargetName = @specTarget.@name;
				if(@specTarget.@lerpInit){
					@specCamX = @specTarget.x;
					@specCamY = @specTarget.y;
				}
				@specSnapCamera = false;
				if(@specTarget.@oRoom != room && room_exists(@specTarget.@oRoom)){
					room_goto(@specTarget.@oRoom);
					@specSnapCamera = true;
				}
			}
		}
	}else{
		if(@specRoom == room){
			@p = %arg0;
			#if PLAYER2
				if(!instance_exists(@p)) @p = %arg1;
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
	if(view_enabled && view_visible[0]){
		view_object[0] = -1;
	}
	@specFound = false;
	@specCount = instance_number(@onlinePlayer);
	if(@specTargetID != ""){
		for(@i = 0; @i < @specCount; @i += 1){
			@specTarget = instance_find(@onlinePlayer, @i);
			if(@specTarget.@ID == @specTargetID){
				@specFound = true;
				@specTargetIdx = @i;
				@specTargetName = @specTarget.@name;
				if(@specTarget.@lerpInit && @specTarget.@oRoom == room){
					if(@specSnapCamera){
						@specCamX = @specTarget.x;
						@specCamY = @specTarget.y;
						@specSnapCamera = false;
					}else{
						@specCamX += (@specTarget.x - @specCamX) * 0.35;
						@specCamY += (@specTarget.y - @specCamY) * 0.35;
					}
				}
				if(@specTarget.@oRoom != room && @specTarget.@oRoom != -1 && room_exists(@specTarget.@oRoom)){
					room_goto(@specTarget.@oRoom);
					@specSnapCamera = true;
				}
			}
		}
	}
	// SWITCH TARGET
	if(@specCount > 0){
		if(keyboard_check_pressed(vk_left)){
			@specTargetIdx -= 1;
			if(@specTargetIdx < 0) @specTargetIdx = @specCount - 1;
			@specTarget = instance_find(@onlinePlayer, @specTargetIdx);
			@specTargetID = @specTarget.@ID;
			@specTargetName = @specTarget.@name;
			@specCamX = @specTarget.x;
			@specCamY = @specTarget.y;
			@specSnapCamera = false;
			if(@specTarget.@oRoom != room && @specTarget.@oRoom != -1 && room_exists(@specTarget.@oRoom)){
				room_goto(@specTarget.@oRoom);
				@specSnapCamera = true;
			}
		}
		if(keyboard_check_pressed(vk_right)){
			@specTargetIdx += 1;
			if(@specTargetIdx >= @specCount) @specTargetIdx = 0;
			@specTarget = instance_find(@onlinePlayer, @specTargetIdx);
			@specTargetID = @specTarget.@ID;
			@specTargetName = @specTarget.@name;
			@specCamX = @specTarget.x;
			@specCamY = @specTarget.y;
			@specSnapCamera = false;
			if(@specTarget.@oRoom != room && @specTarget.@oRoom != -1 && room_exists(@specTarget.@oRoom)){
				room_goto(@specTarget.@oRoom);
				@specSnapCamera = true;
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
				if(!instance_exists(@p)) @p = %arg1;
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
	buffer_clear(@buffer);
	#if not GMNET
		buffer_write_uint8(@buffer, 8);
		buffer_write_uint8(@buffer, @team);
	#endif
	#if GMNET
		buffer_write_u8(@buffer, 8);
		buffer_write_u8(@buffer, @team);
	#endif
	socket_write_message(@socket, @buffer);
	ini_open("@config.ini");
	ini_write_real("config", "team", @team);
	ini_close();
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
if(@saveHistApply >= 0){
	if(@spectating){
		@spectating = false;
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
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint8(@buffer, @sGravity);
			buffer_write_int32(@buffer, @sX);
			buffer_write_float64(@buffer, @sY);
			buffer_write_int16(@buffer, @sRoom);
			buffer_write_to_file(@buffer, "tempOnline2");
		#endif
		#if GMNET
			buffer_write_u8(@buffer, @sGravity);
			buffer_write_i32(@buffer, @sX);
			buffer_write_double(@buffer, @sY);
			buffer_write_i16(@buffer, @sRoom);
			buffer_save(@buffer, "tempOnline2");
		#endif
	#endif
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
// DEFERRED SAVE WRITE
if(@saveHistDirty){
	@saveHistDirtyTimer -= 1;
	if(@saveHistDirtyTimer <= 0){
		@saveHistDirty = false;
		if(@saveHistCount > @saveHistMax){
			@shNow = date_current_datetime();
			@shThinWrite = 0;
			@shThinLastKept = -1;
			@saveHistFavCount = 0;
			for(@shI = 0; @shI < @saveHistCount; @shI += 1){
				@shKeep = false;
				if(@saveHistFav[@shI]){
					@shKeep = true;
					@saveHistFavCount += 1;
				}else{
					@shAge = (@shNow - @saveHistTime[@shI]) * 1440;
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
					if(@shThinWrite != @shI){
						@saveHistFav[@shThinWrite] = @saveHistFav[@shI];
						@saveHistGrav[@shThinWrite] = @saveHistGrav[@shI];
						@saveHistX[@shThinWrite] = @saveHistX[@shI];
						@saveHistY[@shThinWrite] = @saveHistY[@shI];
						@saveHistRoom[@shThinWrite] = @saveHistRoom[@shI];
						@saveHistTime[@shThinWrite] = @saveHistTime[@shI];
						@saveHistName[@shThinWrite] = @saveHistName[@shI];
						@saveHistRoomName[@shThinWrite] = @saveHistRoomName[@shI];
					}
					@shThinWrite += 1;
				}
			}
			@saveHistCount = @shThinWrite;
			for(@shEmrg = 0; @shEmrg < 200 && @saveHistCount > @saveHistMax; @shEmrg += 1){
				@shFound = -1;
				for(@shI = 0; @shI < @saveHistCount && @shFound < 0; @shI += 1){
					if(!@saveHistFav[@shI]) @shFound = @shI;
				}
				if(@shFound < 0) @shFound = 0;
				@saveHistCount -= 1;
				for(@shI = @shFound; @shI < @saveHistCount; @shI += 1){
					@saveHistFav[@shI] = @saveHistFav[@shI + 1];
					@saveHistGrav[@shI] = @saveHistGrav[@shI + 1];
					@saveHistX[@shI] = @saveHistX[@shI + 1];
					@saveHistY[@shI] = @saveHistY[@shI + 1];
					@saveHistRoom[@shI] = @saveHistRoom[@shI + 1];
					@saveHistTime[@shI] = @saveHistTime[@shI + 1];
					@saveHistName[@shI] = @saveHistName[@shI + 1];
					@saveHistRoomName[@shI] = @saveHistRoomName[@shI + 1];
				}
			}
		}
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint16(@buffer, 65535);
			buffer_write_uint8(@buffer, 1);
			buffer_write_uint16(@buffer, @saveHistCount);
			for(@shI = 0; @shI < @saveHistCount; @shI += 1){
				buffer_write_uint8(@buffer, @saveHistFav[@shI]);
				buffer_write_uint8(@buffer, @saveHistGrav[@shI]);
				buffer_write_int32(@buffer, @saveHistX[@shI]);
				buffer_write_float64(@buffer, @saveHistY[@shI]);
				buffer_write_int16(@buffer, @saveHistRoom[@shI]);
				buffer_write_float64(@buffer, @saveHistTime[@shI]);
				buffer_write_string(@buffer, @saveHistName[@shI]);
				buffer_write_string(@buffer, @saveHistRoomName[@shI]);
			}
			buffer_write_to_file(@buffer, "@saves");
		#endif
		#if GMNET
			buffer_write_u16(@buffer, 65535);
			buffer_write_u8(@buffer, 1);
			buffer_write_u16(@buffer, @saveHistCount);
			for(@shI = 0; @shI < @saveHistCount; @shI += 1){
				buffer_write_u8(@buffer, @saveHistFav[@shI]);
				buffer_write_u8(@buffer, @saveHistGrav[@shI]);
				buffer_write_i32(@buffer, @saveHistX[@shI]);
				buffer_write_double(@buffer, @saveHistY[@shI]);
				buffer_write_i16(@buffer, @saveHistRoom[@shI]);
				buffer_write_double(@buffer, @saveHistTime[@shI]);
				buffer_write_string(@buffer, @saveHistName[@shI]);
				buffer_write_string(@buffer, @saveHistRoomName[@shI]);
			}
			buffer_save(@buffer, "@saves");
		#endif
	}
}
// RATING SUBMIT
if(@ratingSubmit){
	@ratingSubmit = false;
	if(!@ratingSubmitting && @ratingCooldown <= 0 && @connected && @rStars >= 1 && @rStars <= 5){
		@ratingSubmitting = true;
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint8(@buffer, 9);
			buffer_write_uint8(@buffer, @rStars);
			buffer_write_uint8(@buffer, @rCleared);
		#endif
		#if GMNET
			buffer_write_u8(@buffer, 9);
			buffer_write_u8(@buffer, @rStars);
			buffer_write_u8(@buffer, @rCleared);
		#endif
		socket_write_message(@socket, @buffer);
	}
}
if(@ratingResultTimer > 0) @ratingResultTimer -= 1;
if(@ratingCooldown > 0) @ratingCooldown -= 1;
if(@rClearWarn > 0) @rClearWarn -= 1;
// FLUSH TCP
#if not GMNET
socket_update_write(@socket);
#endif
#if GMNET
socket_send(@socket);
#endif

// KEYBIND EDITING
if(@keybindEditing >= 0 && @settingsOpen && @settingsTab == 3){
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
			@keybindSave = true;
		}
		@keybindEditing = -1;
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
	ini_write_real("config", "team", @team);
	ini_write_real("config", "lerp", @lerpEnabled);
	ini_close();
}
