/// ONLINE
// %arg0: The name of the player object
// %arg1: The name of the player2 object if it exists
// %arg2: The name of the world object
visible = @avatarAlive && @oRoom == room;
image_alpha = @alpha;
if(@avatarAlive && @lerpInit){
	@oWorld = noone;
	if(instance_exists(%arg2)){
		@oWorld = instance_find(%arg2, 0);
	}
	if(@oWorld != noone && @oWorld.@lerpEnabled){
		x += (@targetX - x) * @oWorld.@lerpFactor;
		y += (@targetY - y) * @oWorld.@lerpFactor;
	}else{
		x = @targetX;
		y = @targetY;
	}
}
#if PLAYER_LIST
@p = @get_active_player();
#endif
#if not PLAYER_LIST
@p = %arg0;
#if PLAYER2
	if(!instance_exists(@p)){
		@p = %arg1;
	}
#endif
#endif
if(@avatarAlive && instance_exists(@p)){
	@dist = distance_to_object(@p);
	image_alpha = min(@alpha, @dist/100);
}
// TEAM CHANGE
if(@prevTeam >= 0 && @team != @prevTeam){
	@oWorld = noone;
	if(instance_exists(%arg2)){
		@oWorld = instance_find(%arg2, 0);
	}
	if(@oWorld != noone){
		@_tn[0] = "None";
		@_tn[1] = "Red";
		@_tn[2] = "Blue";
		@_tn[3] = "Yellow";
		@_tn[4] = "Purple";
		@_tn[5] = "Green";
		@_tn[6] = "Orange";
		@_tn[7] = "Cyan";
		#if GMS2
			@a = instance_create_depth(0, 0, @oWorld.@playerSavedDepth, @playerSaved);
		#endif
		#if not GMS2
			@a = instance_create(0, 0, @playerSaved);
		#endif
		with(@oWorld){
			other.@_tc = @teamColors[other.@team];
		}
		@a.@name = @name + " joined Team " + @_tn[@team];
		@a.@state = -2;
		@a.@teamColor = @_tc;
	}
}
@prevTeam = @team;
