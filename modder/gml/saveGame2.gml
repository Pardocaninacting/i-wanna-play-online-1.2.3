/// ONLINE
// %arg0: The name of the world object
#if TEMPFILE
	with(%arg0){
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint16(@buffer, @socket);
			buffer_write_uint16(@buffer, @udpsocket);
			buffer_write_string(@buffer, @selfID);
			buffer_write_string(@buffer, @name);
			buffer_write_string(@buffer, @selfGameID);
			buffer_write_uint8(@buffer, @race);
			@n = instance_number(@onlinePlayer);
			buffer_write_uint16(@buffer, @n);
			buffer_write_uint16(@buffer, @vis);
			buffer_write_uint16(@buffer, @save_enabled);
			buffer_write_uint8(@buffer, @team);
			buffer_write_uint8(@buffer, @lerpEnabled);
			for(@i = 0; @i < @n; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				buffer_write_string(@buffer, @oPlayer.@ID);
				buffer_write_int32(@buffer, @oPlayer.x);
				buffer_write_int32(@buffer, @oPlayer.y);
				buffer_write_int32(@buffer, @oPlayer.sprite_index);
				buffer_write_float32(@buffer, @oPlayer.image_speed);
				buffer_write_float32(@buffer, @oPlayer.image_xscale);
				buffer_write_float32(@buffer, @oPlayer.image_yscale);
				buffer_write_float32(@buffer, @oPlayer.image_angle);
				buffer_write_uint16(@buffer, @oPlayer.@oRoom);
				buffer_write_string(@buffer, @oPlayer.@name);
				buffer_write_uint8(@buffer, @oPlayer.@team);
			}
			buffer_write_uint8(@buffer, @showPlayerList);
			buffer_write_to_file(@buffer, "tempOnline");
		#endif
		#if GMNET
			buffer_write_u16(@buffer, @socket);
			buffer_write_u16(@buffer, @udpsocket);
			buffer_write_string(@buffer, @selfID);
			buffer_write_string(@buffer, @name);
			buffer_write_string(@buffer, @selfGameID);
			buffer_write_u8(@buffer, @race);
			@n = instance_number(@onlinePlayer);
			buffer_write_u16(@buffer, @n);
			buffer_write_u16(@buffer, @vis);
			buffer_write_u16(@buffer, @save_enabled);
			buffer_write_u8(@buffer, @team);
			buffer_write_u8(@buffer, @lerpEnabled);
			for(@i = 0; @i < @n; @i += 1){
				@oPlayer = instance_find(@onlinePlayer, @i);
				buffer_write_string(@buffer, @oPlayer.@ID);
				buffer_write_i32(@buffer, @oPlayer.x);
				buffer_write_i32(@buffer, @oPlayer.y);
				buffer_write_i32(@buffer, @oPlayer.sprite_index);
				buffer_write_float(@buffer, @oPlayer.image_speed);
				buffer_write_float(@buffer, @oPlayer.image_xscale);
				buffer_write_float(@buffer, @oPlayer.image_yscale);
				buffer_write_float(@buffer, @oPlayer.image_angle);
				buffer_write_u16(@buffer, @oPlayer.@oRoom);
				buffer_write_string(@buffer, @oPlayer.@name);
				buffer_write_u8(@buffer, @oPlayer.@team);
			}
			buffer_write_u8(@buffer, @showPlayerList);
			buffer_save(@buffer, "tempOnline");
		#endif
		// SAVE CHAT HISTORY
		buffer_clear(@buffer);
		#if not GMNET
			buffer_write_uint16(@buffer, @chatHistCount);
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				buffer_write_string(@buffer, @chatHistName[@ci]);
				buffer_write_string(@buffer, @chatHistMsg[@ci]);
				buffer_write_uint8(@buffer, @chatHistTeam[@ci]);
			}
			buffer_write_to_file(@buffer, "tempOnlineChat");
		#endif
		#if GMNET
			buffer_write_u16(@buffer, @chatHistCount);
			for(@ci = 0; @ci < @chatHistCount; @ci += 1){
				buffer_write_string(@buffer, @chatHistName[@ci]);
				buffer_write_string(@buffer, @chatHistMsg[@ci]);
				buffer_write_u8(@buffer, @chatHistTeam[@ci]);
			}
			buffer_save(@buffer, "tempOnlineChat");
		#endif
	}
#endif
