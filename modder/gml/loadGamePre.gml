/// ONLINE
// %arg0: The name of the world object
// Spectate-disconnect preamble for loadGame. Always injected into the game's
// loadGame script (after saveGame2), for every engine family: a spectator
// pressing the load key leaves spectate mode before the save flow continues.
// The save application itself lives in loadGame.gml, which the converter
// targets at tempExe/saveExe instead of loadGame for game_restart+tempfile
// engines (TheBiob parity), so this preamble must not consume tempOnline2 or
// touch @sSaved - doing so pre-restart would eat the pending online save.
if(instance_exists(%arg0)){
	var @_w;
	@_w = instance_find(%arg0, 0);
	with(@_w){
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
				#if not GMNET
					__ONLINE_socket_update_write(@socket);
				#endif
				#if GMNET
					__ONLINE_socket_send(@socket);
				#endif
			}
			if(@socket != -1){
				__ONLINE_socket_destroy(@socket);
				@socket = -1;
			}
			if(__ONLINE_udpsocket_exists(@udpsocket)){
				__ONLINE_udpsocket_destroy(@udpsocket);
			}
			@udpsocket = -1;
			@connected = false;
			@udpReady = false;
			@spectating = false;
			@spectatingPrev = false;
			@specPending = false;
		}
	}
}
