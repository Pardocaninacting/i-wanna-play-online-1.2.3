/// ONLINE
@msgSlot = 0;
@teamColor = c_white;
for(@i = 0; @i < instance_number(object_index); @i += 1){
	@other = instance_find(object_index, @i);
	if(@other.id != id){
		@other.@msgSlot += 1;
	}
}
