/// ONLINE
// %arg0: The name of the world object
// %arg1: The name of the player object
// %arg2: The name of the player2 object if it exists
if(instance_exists(%arg0)){
	var @_w;
	@_w = instance_find(%arg0, 0);
	with(@_w){
		if(@spectating){
			if(@socket != -1){
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
				#if not GMNET
					socket_update_write(@socket);
				#endif
				#if GMNET
					socket_send(@socket);
				#endif
			}
			if(@socket != -1){
				socket_destroy(@socket);
				@socket = -1;
			}
			if(udpsocket_exists(@udpsocket)){
				udpsocket_destroy(@udpsocket);
			}
			@udpsocket = -1;
			@connected = false;
			@udpReady = false;
			@spectating = false;
			@spectatingPrev = false;
			@specPending = false;
		}
		if(@save_enabled || @saveForceLoad){
		#if TEMPFILE
			if(file_exists("tempOnline2")){
				buffer_clear(@buffer);
				#if not GMNET
					buffer_read_from_file(@buffer, "tempOnline2");
					#if GM8YY
						@sGravity = buffer_read_uint8(@buffer)*2-1;
					#endif
					#if not GM8YY
						@sGravity = buffer_read_uint8(@buffer);
					#endif
					@sX = buffer_read_int32(@buffer);
					@sY = buffer_read_float64(@buffer);
					@sRoom = buffer_read_int16(@buffer);
				#endif
				#if GMNET
					buffer_load(@buffer, "tempOnline2");
					#if GM8YY
						@sGravity = buffer_read_u8(@buffer)*2-1;
					#endif
					#if RENEX
						@sGravity = buffer_read_u8(@buffer)*2-1;
					#endif
					#if not RENEX
						#if not GM8YY
							@sGravity = buffer_read_u8(@buffer);
						#endif
					#endif
					@sX = buffer_read_i32(@buffer);
					@sY = buffer_read_double(@buffer);
					@sRoom = buffer_read_i16(@buffer);
				#endif
				file_delete("tempOnline2");
				@sSaved = true;
			}
		#endif
			if(@sSaved && room_exists(@sRoom)){
				if(room == @sRoom){
					var @p, @gravSwapped;
					@p = %arg1;
					@gravSwapped = 0;
					#if PLAYER2
						if(@sGravity == 1){
							if(instance_exists(%arg1)){
								var @loadDepth;
								@loadDepth = instance_find(%arg1, 0).depth;
								#if GMS2
									instance_create_depth(0, 0, @loadDepth, %arg2);
								#endif
								#if not GMS2
									instance_create(0, 0, %arg2);
								#endif
								with(%arg1){
									instance_destroy();
								}
								@gravSwapped = 1;
							}
							@p = %arg2;
						}else{
							if(instance_exists(%arg2) && !instance_exists(%arg1)){
								var @loadDepth;
								@loadDepth = instance_find(%arg2, 0).depth;
								#if GMS2
									instance_create_depth(0, 0, @loadDepth, %arg1);
								#endif
								#if not GMS2
									instance_create(0, 0, %arg1);
								#endif
								with(%arg2){
									instance_destroy();
								}
								@gravSwapped = -1;
							}
							@p = %arg1;
						}
					#endif
					@p = instance_find(@p, 0);
					#if STUDIO
						if(global.grav != @sGravity){
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
						global.grav = @sGravity;
					#endif
					@p.x = @sX;
					@p.y = @sY;
					@sSaved = false;
					@saveForceLoad = false;
					room_goto(@sRoom);
				}else{
					var @p, @gravSwapped;
					@p = %arg1;
					@gravSwapped = 0;
					#if PLAYER2
						if(@sGravity == 1){
							if(instance_exists(%arg1)){
								var @loadDepth;
								@loadDepth = instance_find(%arg1, 0).depth;
								#if GMS2
									instance_create_depth(0, 0, @loadDepth, %arg2);
								#endif
								#if not GMS2
									instance_create(0, 0, %arg2);
								#endif
								with(%arg1){
									instance_destroy();
								}
								@gravSwapped = 1;
							}
							@p = %arg2;
						}else{
							if(instance_exists(%arg2) && !instance_exists(%arg1)){
								var @loadDepth;
								@loadDepth = instance_find(%arg2, 0).depth;
								#if GMS2
									instance_create_depth(0, 0, @loadDepth, %arg1);
								#endif
								#if not GMS2
									instance_create(0, 0, %arg1);
								#endif
								with(%arg2){
									instance_destroy();
								}
								@gravSwapped = -1;
							}
							@p = %arg1;
						}
					#endif
					if(instance_exists(@p)){
						@p = instance_find(@p, 0);
						#if STUDIO
							if(global.grav != @sGravity){
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
							global.grav = @sGravity;
						#endif
						@p.x = @sX;
						@p.y = @sY;
					}
					@sSaved = false;
					@saveForceLoad = false;
					room_goto(@sRoom);
				}
			}
		}
	}
}