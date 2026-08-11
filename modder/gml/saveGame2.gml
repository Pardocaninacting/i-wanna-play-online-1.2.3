/// ONLINE
// %arg0: The name of the world object
#if TEMPFILE
	with(%arg0){
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint16(@buffer, @socket);
			__ONLINE_buffer_write_uint16(@buffer, @udpsocket);
			__ONLINE_buffer_write_string(@buffer, @selfID);
			__ONLINE_buffer_write_string(@buffer, @name);
			__ONLINE_buffer_write_string(@buffer, @selfGameID);
			__ONLINE_buffer_write_uint8(@buffer, @race);
			@n = instance_number(@onlinePlayer);
			__ONLINE_buffer_write_uint16(@buffer, @n);
			__ONLINE_buffer_write_uint16(@buffer, @vis);
			__ONLINE_buffer_write_uint16(@buffer, @save_enabled);
			__ONLINE_buffer_write_uint8(@buffer, @team);
			__ONLINE_buffer_write_uint8(@buffer, @lerpEnabled);
			for(@i = 0; @i < @n; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				__ONLINE_buffer_write_string(@buffer, @oPlayer.@ID);
				__ONLINE_buffer_write_int32(@buffer, @oPlayer.x);
				__ONLINE_buffer_write_int32(@buffer, @oPlayer.y);
				__ONLINE_buffer_write_int32(@buffer, @oPlayer.sprite_index);
				__ONLINE_buffer_write_float32(@buffer, @oPlayer.image_speed);
				__ONLINE_buffer_write_float32(@buffer, @oPlayer.image_xscale);
				__ONLINE_buffer_write_float32(@buffer, @oPlayer.image_yscale);
				__ONLINE_buffer_write_float32(@buffer, @oPlayer.image_angle);
				__ONLINE_buffer_write_uint16(@buffer, @oPlayer.@oRoom);
				__ONLINE_buffer_write_string(@buffer, @oPlayer.@name);
				__ONLINE_buffer_write_uint8(@buffer, @oPlayer.@team);
			}
			__ONLINE_buffer_write_uint8(@buffer, @showPlayerList);
			__ONLINE_buffer_write_to_file(@buffer, "tempOnline");
		#endif
		#if GMNET
			__ONLINE_buffer_write_u16(@buffer, @socket);
			__ONLINE_buffer_write_u16(@buffer, @udpsocket);
			__ONLINE_buffer_write_string(@buffer, @selfID);
			__ONLINE_buffer_write_string(@buffer, @name);
			__ONLINE_buffer_write_string(@buffer, @selfGameID);
			__ONLINE_buffer_write_u8(@buffer, @race);
			@n = instance_number(@onlinePlayer);
			__ONLINE_buffer_write_u16(@buffer, @n);
			__ONLINE_buffer_write_u16(@buffer, @vis);
			__ONLINE_buffer_write_u16(@buffer, @save_enabled);
			__ONLINE_buffer_write_u8(@buffer, @team);
			__ONLINE_buffer_write_u8(@buffer, @lerpEnabled);
			for(@i = 0; @i < @n; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				__ONLINE_buffer_write_string(@buffer, @oPlayer.@ID);
				__ONLINE_buffer_write_i32(@buffer, @oPlayer.x);
				__ONLINE_buffer_write_i32(@buffer, @oPlayer.y);
				__ONLINE_buffer_write_i32(@buffer, @oPlayer.sprite_index);
				__ONLINE_buffer_write_float(@buffer, @oPlayer.image_speed);
				__ONLINE_buffer_write_float(@buffer, @oPlayer.image_xscale);
				__ONLINE_buffer_write_float(@buffer, @oPlayer.image_yscale);
				__ONLINE_buffer_write_float(@buffer, @oPlayer.image_angle);
				__ONLINE_buffer_write_u16(@buffer, @oPlayer.@oRoom);
				__ONLINE_buffer_write_string(@buffer, @oPlayer.@name);
				__ONLINE_buffer_write_u8(@buffer, @oPlayer.@team);
			}
			__ONLINE_buffer_write_u8(@buffer, @showPlayerList);
			__ONLINE_buffer_save(@buffer, "tempOnline");
		#endif
		// SAVE CHAT HISTORY
		__ONLINE_buffer_clear(@buffer);
		#if not GMNET
			__ONLINE_buffer_write_uint16(@buffer, @chatHistCount);
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				__ONLINE_buffer_write_string(@buffer, @chatHistName[@ci]);
				__ONLINE_buffer_write_string(@buffer, @chatHistMsg[@ci]);
				__ONLINE_buffer_write_uint8(@buffer, @chatHistTeam[@ci]);
			}
			__ONLINE_buffer_write_to_file(@buffer, "tempOnlineChat");
		#endif
		#if GMNET
			__ONLINE_buffer_write_u16(@buffer, @chatHistCount);
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				__ONLINE_buffer_write_string(@buffer, @chatHistName[@ci]);
				__ONLINE_buffer_write_string(@buffer, @chatHistMsg[@ci]);
				__ONLINE_buffer_write_u8(@buffer, @chatHistTeam[@ci]);
			}
			__ONLINE_buffer_save(@buffer, "tempOnlineChat");
		#endif
	}
#endif
