/// ONLINE
// %arg0: The name of the world object
// %arg1: The name of the player object
// %arg2: The name of the player2 object if it exists
if(instance_exists(%arg0)){
	var @_w;
	@_w = instance_find(%arg0, 0);
	with(@_w){
		if(!@spectating){
			#if STUDIO
				if(argument0){
			#endif
			#if GM8YY
				if(argument_count == 0 || argument0){
			#endif
			#if not STUDIO
				#if not GM8YY
					%arg3
				#endif
			#endif
				// A successful local save invalidates any pending online save.
				#if TEMPFILE
					if(file_exists("tempOnline2")){
						file_delete("tempOnline2");
					}
				#endif
				@sSaved = false;
				var @p;
				// Save data always comes from the real player object(s) - never a
				// PLAYER_LIST alt/display object (C1). An alt object carries no player
				// vars and would broadcast a bogus position/gravity packet.
				@p = %arg1;
				#if PLAYER2
					if(!instance_exists(@p)){
						@p = %arg2;
					}
				#endif
				if(instance_exists(@p)){
					@p = instance_find(@p, 0);
					// NETWORK BROADCAST
					if(!@race){
						__ONLINE_buffer_clear(@buffer);
						#if not GMNET
							__ONLINE_buffer_write_uint8(@buffer, 5);
							#if STUDIO
								#if GRAVITY
									__ONLINE_buffer_write_uint8(@buffer, global.grav);
								#endif
								#if not GRAVITY
									__ONLINE_buffer_write_uint8(@buffer, 1);
								#endif
							#endif
							#if GM8YY
								__ONLINE_buffer_write_uint8(@buffer, (global.grav+1)/2);
							#endif
							#if not STUDIO
								#if not GM8YY
									if(@p == instance_find(%arg1, 0)){
										__ONLINE_buffer_write_uint8(@buffer, 0);
									}else{
										__ONLINE_buffer_write_uint8(@buffer, 1);
									}
								#endif
							#endif
							__ONLINE_buffer_write_int32(@buffer, @p.x);
							__ONLINE_buffer_write_float64(@buffer, @p.y);
							__ONLINE_buffer_write_int16(@buffer, room);
						#endif
						#if GMNET
							__ONLINE_buffer_write_u8(@buffer, 5);
							#if RENEX
								__ONLINE_buffer_write_u8(@buffer, (global.grav+1)/2);
							#endif
							#if not RENEX
								#if STUDIO
									#if GRAVITY
										__ONLINE_buffer_write_u8(@buffer, global.grav);
									#endif
									#if not GRAVITY
										__ONLINE_buffer_write_u8(@buffer, 1);
									#endif
								#endif
								#if GM8YY
									__ONLINE_buffer_write_u8(@buffer, (global.grav+1)/2);
								#endif
								#if not STUDIO
									#if not GM8YY
										if(@p == instance_find(%arg1, 0)){
											__ONLINE_buffer_write_u8(@buffer, 0);
										}else{
											__ONLINE_buffer_write_u8(@buffer, 1);
										}
									#endif
								#endif
							#endif
							__ONLINE_buffer_write_i32(@buffer, @p.x);
							__ONLINE_buffer_write_double(@buffer, @p.y);
							__ONLINE_buffer_write_i16(@buffer, room);
						#endif
						__ONLINE_socket_write_message(@socket, @buffer);
					}
					// SAVE HISTORY
					var @selfGrav, @shIdx, @shNow;
					@shNow = current_time;
					if (@shNow - @saveHistLastTime < 100) {
					} else {
					@saveHistLastTime = @shNow;
					#if STUDIO
						#if GRAVITY
							@selfGrav = global.grav;
						#endif
						#if not GRAVITY
							@selfGrav = 1;
						#endif
					#endif
					#if GM8YY
						@selfGrav = (global.grav+1)/2;
					#endif
					#if not STUDIO
						#if not GM8YY
							#if RENEX
								@selfGrav = (global.grav+1)/2;
							#endif
							#if not RENEX
								if(@p == instance_find(%arg1, 0)){ @selfGrav = 0; }else{ @selfGrav = 1; }
							#endif
						#endif
					#endif
					@shIdx = @saveHistCount;
					@saveHistCount += 1;
					@saveHistFav[@shIdx] = 0;
					@saveHistHotkey[@shIdx] = 0;
					@saveHistGrav[@shIdx] = @selfGrav;
					@saveHistX[@shIdx] = @p.x;
					@saveHistY[@shIdx] = @p.y;
					@saveHistRoom[@shIdx] = room;
					@saveHistName[@shIdx] = @name;
					@saveHistRoomName[@shIdx] = room_get_name(room);
					@saveHistTime[@shIdx] = date_current_datetime();
					if(!@saveHistDirty){
						@saveHistDirtyTimer = room_speed * 3;
					}
					@saveHistDirty = true;
					}
				}
			}
			// SYNC
			if(@syncEnabled && @socket != -1 && @syncEntryCount > 0){
				@scSendCount = 0;
				for(@scI = 0; @scI < @syncEntryCount; @scI += 1){
					if(@syncName[@scI] == "") continue;
					if(!variable_global_exists(@syncName[@scI])) continue;
					@scSig = "";
					for(@scS = 0; @scS < @syncSlotCount[@scI]; @scS += 1){
						@scV = 0;
						for(@scB = 0; @scB < 32; @scB += 1){
							@scIdx = @scS * 32 + @scB + 1;
							if(@scIdx > @syncCount[@scI]) break;
							#if not STUDIO
								@scBit = real(execute_string("return global." + @syncName[@scI] + "[" + string(@scIdx) + "];"));
							#endif
							#if STUDIO
								@scArr = variable_global_get(@syncName[@scI]);
								@scBit = is_array(@scArr) && array_length_1d(@scArr) > @scIdx ? real(@scArr[@scIdx]) : 0;
							#endif
							if(@scBit != 0) @scV = @scV | (1 << @scB);
						}
						@scSlotVal[@scI, @scS] = @scV;
						@scSig += string(@scV) + ",";
					}
					if(@scSig == @syncLastSig[@scI] && !@syncDirty[@scI]) continue;
					@syncLastSig[@scI] = @scSig;
					@syncDirty[@scI] = false;
					@scSendIdx[@scSendCount] = @scI;
					@scSendCount += 1;
				}
				if(@scSendCount > 0){
					__ONLINE_buffer_clear(@buffer);
					#if not GMNET
						__ONLINE_buffer_write_uint8(@buffer, 7);
						__ONLINE_buffer_write_uint8(@buffer, 1);
						__ONLINE_buffer_write_uint8(@buffer, @scSendCount);
						for(@scK = 0; @scK < @scSendCount; @scK += 1){
							@scI = @scSendIdx[@scK];
							__ONLINE_buffer_write_string(@buffer, @syncName[@scI]);
							__ONLINE_buffer_write_uint16(@buffer, @syncCount[@scI]);
							__ONLINE_buffer_write_uint16(@buffer, @syncSlotCount[@scI]);
							for(@scS = 0; @scS < @syncSlotCount[@scI]; @scS += 1){
								__ONLINE_buffer_write_uint32(@buffer, @scSlotVal[@scI, @scS]);
							}
						}
					#endif
					#if GMNET
						__ONLINE_buffer_write_u8(@buffer, 7);
						__ONLINE_buffer_write_u8(@buffer, 1);
						__ONLINE_buffer_write_u8(@buffer, @scSendCount);
						for(@scK = 0; @scK < @scSendCount; @scK += 1){
							@scI = @scSendIdx[@scK];
							__ONLINE_buffer_write_string(@buffer, @syncName[@scI]);
							__ONLINE_buffer_write_u16(@buffer, @syncCount[@scI]);
							__ONLINE_buffer_write_u16(@buffer, @syncSlotCount[@scI]);
							for(@scS = 0; @scS < @syncSlotCount[@scI]; @scS += 1){
								__ONLINE_buffer_write_u32(@buffer, @scSlotVal[@scI, @scS]);
							}
						}
					#endif
					__ONLINE_socket_write_message(@socket, @buffer);
				}
			}
		}
	}
}
