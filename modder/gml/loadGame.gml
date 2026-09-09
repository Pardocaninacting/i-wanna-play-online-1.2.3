/// ONLINE
// %arg0: The name of the world object
// %arg1: The name of the player object
// %arg2: The name of the player2 object if it exists
// Save application only - the spectate-disconnect preamble lives in
// loadGamePre.gml (always injected into loadGame). TheBiob parity: for
// game_restart+tempfile engines (saveExe/tempExe present) the converter
// injects THIS block into tempExe/saveExe instead of loadGame, so the online
// save is applied AFTER the restart on the fresh boot state. Applying it
// pre-restart moves the wrong instance: the game own loadGame creates a
// spare player at (0,0) when only player2 exists, which then becomes a
// leftover player object (B-to-A direction bug).
if(instance_exists(%arg0)){
	var @_w;
	@_w = instance_find(%arg0, 0);
	with(@_w){
		if(@save_enabled || @saveForceLoad){
		#if TEMPFILE
			if(file_exists("tempOnline2")){
				__ONLINE_buffer_clear(@buffer);
				#if not GMNET
					__ONLINE_buffer_read_from_file(@buffer, "tempOnline2");
					#if GM8YY
						@sGravity = __ONLINE_buffer_read_uint8(@buffer)*2-1;
					#endif
					#if not GM8YY
						@sGravity = __ONLINE_buffer_read_uint8(@buffer);
					#endif
					@sX = __ONLINE_buffer_read_int32(@buffer);
					@sY = __ONLINE_buffer_read_float64(@buffer);
					@sRoom = __ONLINE_buffer_read_int16(@buffer);
				#endif
				#if GMNET
					__ONLINE_buffer_load(@buffer, "tempOnline2");
					#if GM8YY
						@sGravity = __ONLINE_buffer_read_u8(@buffer)*2-1;
					#endif
					#if RENEX
						@sGravity = __ONLINE_buffer_read_u8(@buffer)*2-1;
					#endif
					#if not RENEX
						#if not GM8YY
							@sGravity = __ONLINE_buffer_read_u8(@buffer);
						#endif
					#endif
					@sX = __ONLINE_buffer_read_i32(@buffer);
					@sY = __ONLINE_buffer_read_double(@buffer);
					@sRoom = __ONLINE_buffer_read_i16(@buffer);
				#endif
				file_delete("tempOnline2");
				@sSaved = true;
			}
		#endif
			if(@sSaved && room_exists(@sRoom)){
				if(room == @sRoom){
					var @p, @pyoffset;
					// Real player only - never a PLAYER_LIST alt/display object (C1).
					@p = %arg1;
					@pyoffset = 0;
					#if PLAYER2
						// TheBiob parity: NO object swap - the flipped state is driven by
						// global.grav alone (the engine flips sprite + physics from it).
						// The 4px offset keeps the flipped sprite from clipping.
						if(@sGravity == 1){
							@pyoffset = 4;
						}
						if(!instance_exists(@p)){
							@p = %arg2;
						}
					#endif
					@p = instance_find(@p, 0);
					if(instance_exists(@p)){
						#if STUDIO
							#if GRAVITY
							@flip_grav(@sGravity);

							#endif
						#endif
						#if not STUDIO
							global.grav = @sGravity;
						#endif
						@p.x = @sX;
						@p.y = @sY + @pyoffset;
					}
					@sSaved = false;
					@saveForceLoad = false;
					room_goto(@sRoom);
				}else{
					var @p, @pyoffset;
					// Real player only - never a PLAYER_LIST alt/display object (C1).
					@p = %arg1;
					@pyoffset = 0;
					#if PLAYER2
						// TheBiob parity: NO object swap - the flipped state is driven by
						// global.grav alone (the engine flips sprite + physics from it).
						// The 4px offset keeps the flipped sprite from clipping.
						if(@sGravity == 1){
							@pyoffset = 4;
						}
						if(!instance_exists(@p)){
							@p = %arg2;
						}
					#endif
					if(instance_exists(@p)){
						@p = instance_find(@p, 0);
						#if STUDIO
							#if GRAVITY
							@flip_grav(@sGravity);

							#endif
						#endif
						#if not STUDIO
							global.grav = @sGravity;
						#endif
						@p.x = @sX;
						@p.y = @sY + @pyoffset;
					}
					@sSaved = false;
					@saveForceLoad = false;
					room_goto(@sRoom);
				}
			}
		}
	}
}