/// ONLINE
// %arg0: The name of the player object
// %arg1: The name of the player2 object if it exists
@f = @follower;
#if PLAYER2
	if(@f == %arg0 && !instance_exists(@f)){
		@f = %arg1;
	}
#endif
if(instance_exists(@f)){
	@targetX = @f.x;
	@targetY = @f.y;
	if(!@springInited){
		@springX = @targetX;
		@springY = @targetY;
		@springInited = true;
	}
	@prevSpringVX = @springVX;
	@springVX = @springVX * 0.82 + (@targetX - @springX) * 0.1;
	@springVY = @springVY * 0.82 + (@targetY - @springY) * 0.1;
	@springX += @springVX;
	@springY += @springVY;
	x = @springX;
	y = @springY;
}else{
	@timer = min(@timer, 1);
}
if(@wrappedMsg == "" && @message != ""){
	#if GM80
	@wrappedMsg = @message;
	#endif
	#if not GM80
	#if STUDIO
		if(global.@ftOnline >= 0){
			draw_set_font(global.@ftOnline);
		}
	#endif
	@wSrc = @message;
	@wOut = "";
	@wLineW = 0;
	for(@wI = 1; @wI <= string_length(@wSrc); @wI += 1){
		@wCh = string_copy(@wSrc, @wI, 1);
		@wChW = string_width(@wCh);
		if(@wCh == " "){
			@wLineW = 0;
			@wOut = @wOut + @wCh;
		}else{
			if(@wLineW + @wChW > @bubbleMaxW){
				@wOut = @wOut + " ";
				@wLineW = 0;
			}
			@wLineW += @wChW;
			@wOut = @wOut + @wCh;
		}
	}
	@wrappedMsg = @wOut;
	if(font_exists(0)){
		draw_set_font(0);
	}
	#endif
}
@scaleVel = @scaleVel * 0.6 + (1 - @scale) * 0.15;
@scale += @scaleVel;
if(abs(@scale - 1) < 0.005 && abs(@scaleVel) < 0.005){
	@scale = 1;
	@scaleVel = 0;
}
if(@scale > 0.95 && !@showText) @showText = true;
if(@showText && @textAlpha < 1){
	@textAlpha += 0.08;
	if(@textAlpha > 1) @textAlpha = 1;
}
@bobTime += 1;
@moveAccel = (@springVX - @prevSpringVX) * 0.12;
if(@moveAccel > 0.15) @moveAccel = 0.15;
if(@moveAccel < -0.15) @moveAccel = -0.15;
@squash = @scaleVel * 0.5 + @moveAccel + cos(@bobTime * 0.06) * 0.02;
@timer -= 1;
if(@timer < 30 && @timer >= 0){
	@fadeAlpha = @timer / 30;
}
if(@timer <= 0){
	instance_destroy();
	exit;
}
@drawAlpha = 1;
if(instance_exists(@f) && @f.object_index == @onlinePlayer){
	@p = %arg0;
	#if PLAYER2
		if(!instance_exists(@p)) @p = %arg1;
	#endif
	if(instance_exists(@p)){
		@dist = distance_to_object(@p);
		@drawAlpha = min(1, @dist / 100);
	}
	if(instance_exists(@f)){
		visible = @f.visible;
	}
}
// DESTROY OLDER
if(!@hasDestroyed){
	@oCb = 0;
	for(@i = 0; @i < instance_number(@chatbox); @i += 1){
		@oCb = instance_find(@chatbox, @i);
		if(@oCb.@follower == @follower && @oCb.id != id){
			with(@oCb){
				instance_destroy();
			}
			@i -= 1;
		}
	}
	@hasDestroyed = true;
}
