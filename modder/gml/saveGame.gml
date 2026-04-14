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
				if(argument0){
			#endif
			#if not STUDIO
				#if not GM8YY
					%arg3
				#endif
			#endif
				var @p;
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
						buffer_clear(@buffer);
						#if not GMNET
							buffer_write_uint8(@buffer, 5);
							#if STUDIO
								buffer_write_uint8(@buffer, global.grav);
							#endif
							#if GM8YY
								buffer_write_uint8(@buffer, (global.grav+1)/2);
							#endif
							#if not STUDIO
								#if not GM8YY
									if(@p == instance_find(%arg1, 0)){
										buffer_write_uint8(@buffer, 0);
									}else{
										buffer_write_uint8(@buffer, 1);
									}
								#endif
							#endif
							buffer_write_int32(@buffer, @p.x);
							buffer_write_float64(@buffer, @p.y);
							buffer_write_int16(@buffer, room);
						#endif
						#if GMNET
							buffer_write_u8(@buffer, 5);
							#if RENEX
								buffer_write_u8(@buffer, (global.grav+1)/2);
							#endif
							#if not RENEX
								#if STUDIO
									buffer_write_u8(@buffer, global.grav);
								#endif
								#if GM8YY
									buffer_write_u8(@buffer, (global.grav+1)/2);
								#endif
								#if not STUDIO
									#if not GM8YY
										if(@p == instance_find(%arg1, 0)){
											buffer_write_u8(@buffer, 0);
										}else{
											buffer_write_u8(@buffer, 1);
										}
									#endif
								#endif
							#endif
							buffer_write_i32(@buffer, @p.x);
							buffer_write_double(@buffer, @p.y);
							buffer_write_i16(@buffer, room);
						#endif
						socket_write_message(@socket, @buffer);
					}
					// SAVE HISTORY
					var @selfGrav, @shIdx, @shNow;
					@shNow = current_time;
					if (@shNow - @saveHistLastTime < 100) {
					} else {
					@saveHistLastTime = @shNow;
					#if STUDIO
						@selfGrav = global.grav;
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
		}
	}
}
