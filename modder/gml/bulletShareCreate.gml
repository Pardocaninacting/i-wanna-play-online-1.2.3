/// ONLINE
// Proxy bullet Create: all fields are set by @bullet_apply on creation; these
// defaults only guard against an uninitialised read before the first snapshot
// (GMS errors on undefined instance variables). @bSpd/@bAngle drive the
// dead-reckoning motion; @bXS/@bAA are the sender's image_xscale/image_angle
// (the visual flip/rotation; v1 senders yield xscale 1 + angle=direction).
@bOwner = "";
@bKey = "";
@bWorld = noone;
@bAlive = 4;
@bImg = 0;
@bSlot = -1;
@bAngle = 0;
@bSpd = 0;
@bXS = 1;
@bAA = 0;
