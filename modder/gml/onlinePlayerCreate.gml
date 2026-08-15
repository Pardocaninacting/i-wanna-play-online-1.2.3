/// ONLINE
@alpha = 1;
@oRoom = -1;
@name = "";
@team = 0;
@prevTeam = -1;
@spectating = false;
@avatarAlive = false;
@oWorld = noone;
visible = true;
@syncTime = 0;
@targetX = 0;
@targetY = 0;
@lerpInit = false;
@cs_slot[0] = 0;
@cs_slot_count = 0;
// S2 remote skin state: 0 = none (native sprite), 1 = pending hash
// resolution, 2 = resolved into @skinSlot, 3 = explicitly missing (Unknown
// fallback + [?] marker). Set by the world's @skin_apply_remote.
@skinHash = "";
@skinState = 0;
@skinSlot = -1;
@skinAnPos = 0;
@skinAnPrevImg = 0;
@skinAnState = -1;
