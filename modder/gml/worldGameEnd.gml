/// ONLINE
// FLUSH SAVE HISTORY
if(@saveHistDirty){
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
				@saveHistHotkey[@shI] = @saveHistHotkey[@shI + 1];
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
	__ONLINE_buffer_clear(@buffer);
	#if not GMNET
		__ONLINE_buffer_write_uint16(@buffer, 65535);
		__ONLINE_buffer_write_uint8(@buffer, 2);
		__ONLINE_buffer_write_uint16(@buffer, @saveHistCount);
		for(@shI = 0; @shI < @saveHistCount; @shI += 1){
			__ONLINE_buffer_write_uint8(@buffer, @saveHistFav[@shI]);
			__ONLINE_buffer_write_uint8(@buffer, @saveHistHotkey[@shI]);
			__ONLINE_buffer_write_uint8(@buffer, @saveHistGrav[@shI]);
			__ONLINE_buffer_write_int32(@buffer, @saveHistX[@shI]);
			__ONLINE_buffer_write_float64(@buffer, @saveHistY[@shI]);
			__ONLINE_buffer_write_int16(@buffer, @saveHistRoom[@shI]);
			__ONLINE_buffer_write_float64(@buffer, @saveHistTime[@shI]);
			__ONLINE_buffer_write_string(@buffer, @saveHistName[@shI]);
			__ONLINE_buffer_write_string(@buffer, @saveHistRoomName[@shI]);
		}
		__ONLINE_buffer_write_to_file(@buffer, "@saves");
	#endif
	#if GMNET
		__ONLINE_buffer_write_u16(@buffer, 65535);
		__ONLINE_buffer_write_u8(@buffer, 2);
		__ONLINE_buffer_write_u16(@buffer, @saveHistCount);
		for(@shI = 0; @shI < @saveHistCount; @shI += 1){
			__ONLINE_buffer_write_u8(@buffer, @saveHistFav[@shI]);
			__ONLINE_buffer_write_u8(@buffer, @saveHistHotkey[@shI]);
			__ONLINE_buffer_write_u8(@buffer, @saveHistGrav[@shI]);
			__ONLINE_buffer_write_i32(@buffer, @saveHistX[@shI]);
			__ONLINE_buffer_write_double(@buffer, @saveHistY[@shI]);
			__ONLINE_buffer_write_i16(@buffer, @saveHistRoom[@shI]);
			__ONLINE_buffer_write_double(@buffer, @saveHistTime[@shI]);
			__ONLINE_buffer_write_string(@buffer, @saveHistName[@shI]);
			__ONLINE_buffer_write_string(@buffer, @saveHistRoomName[@shI]);
		}
		__ONLINE_buffer_save(@buffer, "@saves");
	#endif
}
#if TEMPFILE
	if(!file_exists("temp") && !file_exists(working_directory+"\save\temp") && !file_exists("temp.dat")){
		if(file_exists("tempOnline")){
			file_delete("tempOnline");
		}
		if(file_exists("tempOnline2")){
			file_delete("tempOnline2");
		}
		if(file_exists("tempOnlineChat")){
			file_delete("tempOnlineChat");
		}
	}
#endif
#if PLAYER_LIST
// persist player object list if edited in-game but pick mode was never closed cleanly
if(@objListEdited){
	@objListEdited = false;
	@f = file_text_open_write("__online_player_objects");
	for(@i = 0; @i < ds_list_size(@obj_list); @i += 1){
		file_text_write_real(@f, ds_list_find_value(@obj_list, @i) + 1);
		file_text_writeln(@f);
	}
	file_text_close(@f);
}
ds_list_destroy(@obj_list);
#endif
ds_map_destroy(@teamMap);
__ONLINE_buffer_destroy(@buffer);
__ONLINE_buffer_destroy(@dlBuffer);
if(@skinDlFile >= 0){
    file_bin_close(@skinDlFile);
    @skinDlFile = -1;
}
#if TEMPFILE
	if(!file_exists("tempOnline")){
#endif
__ONLINE_socket_destroy(@socket);
__ONLINE_udpsocket_destroy(@udpsocket);
#if TEMPFILE
	}
#endif
