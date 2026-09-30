/// ONLINE
// ============================================================================
// langLib.gml - UI localization (design note lives in the dev workspace).
//
//   global.__ONLINE_Lang[i]     string table; "" means "no translation" and @L
//                               falls back to the English literal at the call
//                               site (there is no en.ini - the code IS English)
//   global.__ONLINE_LangKey[i]  key registry: table index <-> ini section name.
//                               A UI string gets the next free index and a
//                               namespaced name here BEFORE its call sites
//                               switch to @L(idx, "...")
//   global.__ONLINE_LK_*        index constants, so call sites read
//                               @L(global.__ONLINE_LK_TAB_SKINS, "Skins")
//                               instead of a magic number
//   global.__ONLINE_lang        active language code (built-in default zh-CN,
//                               "en" = no file load), [config] lang= overrides
//
// Files: lang/<code>.ini next to the exe (UTF-8). GM8.0 reads the converter-
// generated GBK copy lang/<code>.gbk.ini instead - its strings are byte
// strings and the CJK atlas/FoxWriting are keyed by GBK bytes, so the copy is
// GBK on EVERY machine, not the player's local codepage.
//
// Format:
//   [meta]  name = <display name>   (shown by the Language row, P4)
//   [<key>] text = <translation>    (hash= lines are for the converter-side
//                                    staleness check, the runtime ignores them)
// Do not use '#' in translations: GM draws it as a line break.
// ============================================================================

///// script @lang_init
// Rebuilds the table. Called from worldCreate on EVERY create, because
// game_restart wipes globals (same discipline as @stg_init).
//
// KEY REGISTRY - append-only, never renumber (converted games in the field keep
// their language files). Namespaces: menu.tab/head/row/empty/val/status/rating/
// keycap/age/count/fact/factv/act/desc/hint/dialog/misc, skinstate, account,
// keys.
// args: none -> 0
var _i;
global.__ONLINE_LangCap = 1024;
global.__ONLINE_LK_TAB_SETTINGS = 0;
global.__ONLINE_LK_TAB_SAVES = 1;
global.__ONLINE_LK_TAB_RATING = 2;
global.__ONLINE_LK_TAB_KEYS = 3;
global.__ONLINE_LK_TAB_SYNC = 4;
global.__ONLINE_LK_TAB_SKINS = 5;
global.__ONLINE_LK_CLOSE = 6;
global.__ONLINE_LK_HINT_FALLBACK = 7;
global.__ONLINE_LK_HEAD_CONNECTION = 8;
global.__ONLINE_LK_HEAD_ACCOUNT = 9;
global.__ONLINE_LK_HEAD_GAMEPLAY = 10;
global.__ONLINE_LK_HEAD_DISPLAY = 11;
global.__ONLINE_LK_HEAD_NOTES = 12;
global.__ONLINE_LK_HEAD_ADVANCED = 13;
global.__ONLINE_LK_HEAD_SAVE_HISTORY = 14;
global.__ONLINE_LK_HEAD_MANAGE = 15;
global.__ONLINE_LK_HEAD_THIS_GAME = 16;
global.__ONLINE_LK_HEAD_RATING = 17;
global.__ONLINE_LK_HEAD_STATUS = 18;
global.__ONLINE_LK_HEAD_KEY_BINDINGS = 19;
global.__ONLINE_LK_HEAD_RESET = 20;
global.__ONLINE_LK_HEAD_SYNC = 21;
global.__ONLINE_LK_HEAD_ENTRIES = 22;
global.__ONLINE_LK_HEAD_INSTALLED = 23;
global.__ONLINE_LK_HEAD_INSTALLED_OF = 24;
global.__ONLINE_LK_ROW_ON_FAILURE = 25;
global.__ONLINE_LK_ROW_SERVER = 26;
global.__ONLINE_LK_ROW_TCP_PORT = 27;
global.__ONLINE_LK_ROW_UDP_PORT = 28;
global.__ONLINE_LK_ROW_NAME = 29;
global.__ONLINE_LK_ROW_PASSWORD = 30;
global.__ONLINE_LK_ROW_STORE_IN = 31;
global.__ONLINE_LK_ROW_TEAM = 32;
global.__ONLINE_LK_ROW_LERP = 33;
global.__ONLINE_LK_ROW_SAVE = 34;
global.__ONLINE_LK_ROW_FAST = 35;
global.__ONLINE_LK_ROW_PVP = 36;
global.__ONLINE_LK_ROW_BULLETS = 37;
global.__ONLINE_LK_ROW_VISUAL = 38;
global.__ONLINE_LK_ROW_INDICATOR = 39;
global.__ONLINE_LK_ROW_SPEC_CAM = 40;
global.__ONLINE_LK_ROW_MENU_LAYOUT = 41;
global.__ONLINE_LK_ROW_PLAYER_OBJECTS = 42;
global.__ONLINE_LK_ROW_HIDE_OTHERS = 43;
global.__ONLINE_LK_ROW_HIDE_ALL = 44;
global.__ONLINE_LK_ROW_SAVE_HISTORY = 45;
global.__ONLINE_LK_ROW_CHAT_HISTORY = 46;
global.__ONLINE_LK_ROW_FAVOURITES = 47;
global.__ONLINE_LK_ROW_STARS = 48;
global.__ONLINE_LK_ROW_CLEARED = 49;
global.__ONLINE_LK_ROW_LAST_RESULT = 50;
global.__ONLINE_LK_ROW_SYNC_ENABLED = 51;
global.__ONLINE_LK_ROW_AUTO_DOWNLOAD = 52;
global.__ONLINE_LK_EMPTY_NO_SAVES = 53;
global.__ONLINE_LK_EMPTY_NO_FAVOURITES = 54;
global.__ONLINE_LK_EMPTY_NO_ENTRIES = 55;
global.__ONLINE_LK_EMPTY_NO_SKINS = 56;
global.__ONLINE_LK_EMPTY_NO_MATCHES = 57;
global.__ONLINE_LK_VAL_ON = 58;
global.__ONLINE_LK_VAL_OFF = 59;
global.__ONLINE_LK_VAL_QUIT = 60;
global.__ONLINE_LK_VAL_STAY = 61;
global.__ONLINE_LK_VAL_NA = 62;
global.__ONLINE_LK_VAL_LOCKED = 63;
global.__ONLINE_LK_VAL_PICK = 64;
global.__ONLINE_LK_VAL_RECONNECT_NOW = 65;
global.__ONLINE_LK_VAL_APPLY_RECONNECT = 66;
global.__ONLINE_LK_VAL_CLEAR_ALL = 67;
global.__ONLINE_LK_VAL_CLEAR_SKIN = 68;
global.__ONLINE_LK_VAL_SEARCH_PROMPT = 69;
global.__ONLINE_LK_VAL_SEARCH_ACTIVE = 70;
global.__ONLINE_LK_VAL_KEY_N = 71;
global.__ONLINE_LK_VAL_BITS = 72;
global.__ONLINE_LK_VAL_OF_5 = 73;
global.__ONLINE_LK_VAL_RESET_KEYS = 74;
global.__ONLINE_LK_VAL_SUBMIT_RATING = 75;
global.__ONLINE_LK_VAL_SENDING = 76;
global.__ONLINE_LK_VAL_WAIT_S = 77;
global.__ONLINE_LK_VAL_LOADED = 78;
global.__ONLINE_LK_VAL_PRESS_KEY = 79;
global.__ONLINE_LK_VAL_NOT_SET = 80;
global.__ONLINE_LK_VAL_EMPTY = 81;
global.__ONLINE_LK_VAL_NONE = 82;
global.__ONLINE_LK_VAL_SAVE_N = 83;
global.__ONLINE_LK_VAL_TEAM_FMT = 84;
global.__ONLINE_LK_VAL_TEAM_NONE = 85;
global.__ONLINE_LK_VAL_TEAM_RED = 86;
global.__ONLINE_LK_VAL_TEAM_BLUE = 87;
global.__ONLINE_LK_VAL_TEAM_YELLOW = 88;
global.__ONLINE_LK_VAL_TEAM_PURPLE = 89;
global.__ONLINE_LK_VAL_TEAM_GREEN = 90;
global.__ONLINE_LK_VAL_TEAM_ORANGE = 91;
global.__ONLINE_LK_VAL_TEAM_CYAN = 92;
global.__ONLINE_LK_VAL_LERP_LIGHT = 93;
global.__ONLINE_LK_VAL_LERP_STANDARD = 94;
global.__ONLINE_LK_VAL_LERP_STRONG = 95;
global.__ONLINE_LK_VAL_VIS_ALL = 96;
global.__ONLINE_LK_VAL_VIS_NO_NAMES = 97;
global.__ONLINE_LK_VAL_VIS_HIDDEN = 98;
global.__ONLINE_LK_VAL_SPECCAM_FREE = 99;
global.__ONLINE_LK_VAL_SPECCAM_FOLLOW = 100;
global.__ONLINE_LK_VAL_PVP_OFF = 101;
global.__ONLINE_LK_VAL_PVP_TEAM = 102;
global.__ONLINE_LK_VAL_PVP_FFA = 103;
global.__ONLINE_LK_VAL_LAYOUT_AUTO = 104;
global.__ONLINE_LK_VAL_LAYOUT_NARROW = 105;
global.__ONLINE_LK_VAL_LAYOUT_FULL = 106;
global.__ONLINE_LK_STATUS_NOT_CONFIGURED = 107;
global.__ONLINE_LK_STATUS_RECONNECTING = 108;
global.__ONLINE_LK_STATUS_ONLINE = 109;
global.__ONLINE_LK_STATUS_UNREACHABLE = 110;
global.__ONLINE_LK_STATUS_CONNECTING = 111;
global.__ONLINE_LK_STATUS_OFFLINE = 112;
global.__ONLINE_LK_RATING_SUBMITTED = 113;
global.__ONLINE_LK_RATING_FAILED_COOLDOWN = 114;
global.__ONLINE_LK_RATING_IDLE = 115;
global.__ONLINE_LK_RATING_COOLDOWN = 116;
global.__ONLINE_LK_KEYCAP_SPACE = 117;
global.__ONLINE_LK_KEYCAP_CHAR = 118;
global.__ONLINE_LK_KEYCAP_KEY_N = 119;
global.__ONLINE_LK_AGE_NOW = 120;
global.__ONLINE_LK_AGE_MIN = 121;
global.__ONLINE_LK_AGE_HOUR = 122;
global.__ONLINE_LK_AGE_DAY = 123;
global.__ONLINE_LK_AGE_DATE = 124;
global.__ONLINE_LK_COUNT_OPTION = 125;
global.__ONLINE_LK_COUNT_OPTIONS = 126;
global.__ONLINE_LK_FACT_STORE = 127;
global.__ONLINE_LK_FACT_STATE = 128;
global.__ONLINE_LK_FACT_ROOM = 129;
global.__ONLINE_LK_FACT_POSITION = 130;
global.__ONLINE_LK_FACT_GRAVITY = 131;
global.__ONLINE_LK_FACT_PLAYER = 132;
global.__ONLINE_LK_FACT_SAVED = 133;
global.__ONLINE_LK_FACT_HOTKEY = 134;
global.__ONLINE_LK_FACT_FAVOURITE = 135;
global.__ONLINE_LK_FACT_MAKER = 136;
global.__ONLINE_LK_FACT_SOURCE = 137;
global.__ONLINE_LK_FACT_FRAMES = 138;
global.__ONLINE_LK_FACT_STATUS = 139;
global.__ONLINE_LK_FACT_GLOBAL = 140;
global.__ONLINE_LK_FACT_BITS = 141;
global.__ONLINE_LK_FACT_SLOTS = 142;
global.__ONLINE_LK_FACT_PRESENT = 143;
global.__ONLINE_LK_FACT_THIS_FOLDER = 144;
global.__ONLINE_LK_FACT_ENV_OVERRIDE = 145;
global.__ONLINE_LK_FACTV_SET_MASKED = 146;
global.__ONLINE_LK_FACTV_EMPTY = 147;
global.__ONLINE_LK_FACTV_NONE = 148;
global.__ONLINE_LK_FACTV_NOT_LOADED = 149;
global.__ONLINE_LK_FACTV_YES = 150;
global.__ONLINE_LK_FACTV_NO_SKIPPED = 151;
global.__ONLINE_LK_FACTV_SLOTS_FMT = 152;
global.__ONLINE_LK_ACT_EDIT = 153;
global.__ONLINE_LK_ACT_SWITCH_STORE = 154;
global.__ONLINE_LK_ACT_RUN = 155;
global.__ONLINE_LK_ACT_PICK = 156;
global.__ONLINE_LK_ACT_SAVE_ROW = 157;
global.__ONLINE_LK_ACT_TOGGLE = 158;
global.__ONLINE_LK_ACT_REBIND = 159;
global.__ONLINE_LK_ACT_RESET = 160;
global.__ONLINE_LK_ACT_APPLY = 161;
global.__ONLINE_LK_ACT_CLEAR = 162;
global.__ONLINE_LK_ACT_RATE = 163;
global.__ONLINE_LK_ACT_SUBMIT = 164;
global.__ONLINE_LK_ACT_CONFIRM_CLEAR = 165;
global.__ONLINE_LK_ACT_CLICK_CLEAR = 166;
global.__ONLINE_LK_DESC_RECONNECT = 167;
global.__ONLINE_LK_DESC_APPLY_RECONNECT = 168;
global.__ONLINE_LK_DESC_NAME = 169;
global.__ONLINE_LK_DESC_PASSWORD = 170;
global.__ONLINE_LK_DESC_STORE = 171;
global.__ONLINE_LK_DESC_TEAM = 172;
global.__ONLINE_LK_DESC_LERP = 173;
global.__ONLINE_LK_DESC_ON_FAILURE = 174;
global.__ONLINE_LK_DESC_SERVER = 175;
global.__ONLINE_LK_DESC_TCP = 176;
global.__ONLINE_LK_DESC_UDP = 177;
global.__ONLINE_LK_DESC_SAVE_HISTORY = 178;
global.__ONLINE_LK_DESC_CHAT_HISTORY = 179;
global.__ONLINE_LK_DESC_SAVE = 180;
global.__ONLINE_LK_DESC_FAST = 181;
global.__ONLINE_LK_DESC_PVP = 182;
global.__ONLINE_LK_DESC_BULLETS = 183;
global.__ONLINE_LK_DESC_VISUAL = 184;
global.__ONLINE_LK_DESC_INDICATOR = 185;
global.__ONLINE_LK_DESC_SPEC_CAM = 186;
global.__ONLINE_LK_DESC_MENU_LAYOUT = 187;
global.__ONLINE_LK_DESC_HIDE_OTHERS = 188;
global.__ONLINE_LK_DESC_HIDE_ALL = 189;
global.__ONLINE_LK_DESC_SAVE_ROW = 190;
global.__ONLINE_LK_DESC_FAVOURITES = 191;
global.__ONLINE_LK_DESC_CLEAR_SAVES = 192;
global.__ONLINE_LK_DESC_PLAYER_OBJECTS = 193;
global.__ONLINE_LK_DESC_REBIND = 194;
global.__ONLINE_LK_DESC_RESET_KEYS = 195;
global.__ONLINE_LK_DESC_SYNC = 196;
global.__ONLINE_LK_DESC_SKIN_ROW = 197;
global.__ONLINE_LK_DESC_AUTO_DOWNLOAD = 198;
global.__ONLINE_LK_DESC_CLEAR_SKIN = 199;
global.__ONLINE_LK_DESC_SEARCH = 200;
global.__ONLINE_LK_DESC_SYNC_ENTRY = 201;
global.__ONLINE_LK_DESC_GAME = 202;
global.__ONLINE_LK_DESC_STARS = 203;
global.__ONLINE_LK_DESC_CLEARED = 204;
global.__ONLINE_LK_DESC_LAST_RESULT = 205;
global.__ONLINE_LK_DESC_SUBMIT = 206;
global.__ONLINE_LK_HINT_NAME = 207;
global.__ONLINE_LK_HINT_PASSWORD = 208;
global.__ONLINE_LK_HINT_STORE = 209;
global.__ONLINE_LK_HINT_APPLY_RECONNECT = 210;
global.__ONLINE_LK_HINT_RECONNECT = 211;
global.__ONLINE_LK_HINT_PLAYER_OBJECTS = 212;
global.__ONLINE_LK_HINT_TEAM = 213;
global.__ONLINE_LK_HINT_LERP = 214;
global.__ONLINE_LK_HINT_ON_FAILURE = 215;
global.__ONLINE_LK_HINT_TCP = 216;
global.__ONLINE_LK_HINT_UDP = 217;
global.__ONLINE_LK_HINT_SERVER = 218;
global.__ONLINE_LK_HINT_SAVE_HISTORY = 219;
global.__ONLINE_LK_HINT_CHAT_HISTORY = 220;
global.__ONLINE_LK_HINT_SAVE = 221;
global.__ONLINE_LK_HINT_FAST = 222;
global.__ONLINE_LK_HINT_VISUAL = 223;
global.__ONLINE_LK_HINT_INDICATOR = 224;
global.__ONLINE_LK_HINT_SPEC_CAM = 225;
global.__ONLINE_LK_HINT_MENU_LAYOUT = 226;
global.__ONLINE_LK_HINT_HIDE_OTHERS = 227;
global.__ONLINE_LK_HINT_HIDE_ALL = 228;
global.__ONLINE_LK_HINT_PVP = 229;
global.__ONLINE_LK_HINT_BULLETS = 230;
global.__ONLINE_LK_HINT_SAVE_ROW = 231;
global.__ONLINE_LK_HINT_FAVOURITES = 232;
global.__ONLINE_LK_HINT_CLEAR_SAVES = 233;
global.__ONLINE_LK_HINT_REBIND = 234;
global.__ONLINE_LK_HINT_RESET_KEYS = 235;
global.__ONLINE_LK_HINT_SYNC = 236;
global.__ONLINE_LK_HINT_SYNC_ENTRY = 237;
global.__ONLINE_LK_HINT_SKIN_ROW = 238;
global.__ONLINE_LK_HINT_AUTO_DOWNLOAD = 239;
global.__ONLINE_LK_HINT_CLEAR_SKIN = 240;
global.__ONLINE_LK_HINT_SEARCH = 241;
global.__ONLINE_LK_HINT_GAME = 242;
global.__ONLINE_LK_HINT_STARS = 243;
global.__ONLINE_LK_HINT_CLEARED = 244;
global.__ONLINE_LK_HINT_LAST_RESULT = 245;
global.__ONLINE_LK_HINT_SUBMIT = 246;
global.__ONLINE_LK_DLG_NAME_TITLE = 247;
global.__ONLINE_LK_DLG_NAME_PROMPT = 248;
global.__ONLINE_LK_DLG_PASS_TITLE = 249;
global.__ONLINE_LK_DLG_PASS_PROMPT = 250;
global.__ONLINE_LK_DLG_SERVER_TITLE = 251;
global.__ONLINE_LK_DLG_HOST_PROMPT = 252;
global.__ONLINE_LK_DLG_TCP_TITLE = 253;
global.__ONLINE_LK_DLG_UDP_TITLE = 254;
global.__ONLINE_LK_DLG_PORT_PROMPT = 255;
global.__ONLINE_LK_DLG_SEARCH_FULL = 256;
global.__ONLINE_LK_DLG_SEARCH_TITLE = 257;
global.__ONLINE_LK_DLG_SEARCH_PROMPT = 258;
global.__ONLINE_LK_MISC_NO_STATE = 259;
global.__ONLINE_LK_MISC_PREVIEW = 260;
global.__ONLINE_LK_MISC_SERVER_PREFIX = 261;
global.__ONLINE_LK_SKINSTATE_IDLE = 262;
global.__ONLINE_LK_SKINSTATE_RUN = 263;
global.__ONLINE_LK_SKINSTATE_JUMP = 264;
global.__ONLINE_LK_SKINSTATE_FALL = 265;
global.__ONLINE_LK_SKINSTATE_SLIDE = 266;
global.__ONLINE_LK_SKINSTATE_BOW = 267;
global.__ONLINE_LK_SKINSTATE_BULLET = 268;
global.__ONLINE_LK_ACCOUNT_STORE_GLOBAL = 269;
global.__ONLINE_LK_ACCOUNT_STORE_FOLDER = 270;
global.__ONLINE_LK_ACCOUNT_STORE_ENV = 271;
global.__ONLINE_LK_KEYS_VISIBILITY = 272;
global.__ONLINE_LK_KEYS_TOGGLE_SAVE = 273;
global.__ONLINE_LK_KEYS_SPECTATE = 274;
global.__ONLINE_LK_KEYS_CHAT_LOG = 275;
global.__ONLINE_LK_KEYS_OPTIONS = 276;
global.__ONLINE_LK_KEYS_PLAYER_LIST = 277;
global.__ONLINE_LK_KEYS_CHAT = 278;
global.__ONLINE_LK_KEYS_HERE = 279;
global.__ONLINE_LK_KEYS_FAST_LOAD = 280;
global.__ONLINE_LK_KEYS_CANVAS = 281;
global.__ONLINE_LK_DETAIL_CONNECTION = 282;
global.__ONLINE_LK_FACT_SERVER = 283;
global.__ONLINE_LK_DLG_SERVER_HOST = 284;
// --- P3: HUD / announcements / dialogs outside the menu
global.__ONLINE_LK_HUD_CHAT_LOG = 285;
global.__ONLINE_LK_HUD_NO_MESSAGES = 286;
global.__ONLINE_LK_HUD_PLAYERS_ONLINE = 287;
global.__ONLINE_LK_HUD_EXITING = 288;
global.__ONLINE_LK_HUD_SPECTATING = 289;
global.__ONLINE_LK_HUD_NO_PLAYERS = 290;
global.__ONLINE_LK_HUD_SCREEN = 291;
global.__ONLINE_LK_HUD_FOLLOW = 292;
global.__ONLINE_LK_HUD_SPECTATING_PREFIX = 293;
global.__ONLINE_LK_HUD_PICK_TITLE = 294;
global.__ONLINE_LK_HUD_PICK_LINE2 = 295;
global.__ONLINE_LK_HUD_PICK_DONE = 296;
global.__ONLINE_LK_HUD_PICK_ACTIVE = 297;
global.__ONLINE_LK_HUD_SPEC_TAG = 298;
global.__ONLINE_LK_NOTIFY_SAVE_ON = 299;
global.__ONLINE_LK_NOTIFY_SAVE_OFF = 300;
global.__ONLINE_LK_NOTIFY_VISUAL_MODE = 301;
global.__ONLINE_LK_NOTIFY_SAVED = 302;
global.__ONLINE_LK_NOTIFY_RECONNECTING = 303;
global.__ONLINE_LK_NOTIFY_OFFLINE_MENU = 304;
global.__ONLINE_LK_NOTIFY_NOTES_TRANSIENT = 305;
global.__ONLINE_LK_NOTIFY_NOTES_CANVAS = 306;
global.__ONLINE_LK_NOTIFY_NOTES_OFF = 307;
global.__ONLINE_LK_NOTIFY_VERSION_OLD = 308;
global.__ONLINE_LK_DLG_CHAT_TITLE = 309;
global.__ONLINE_LK_DLG_CHAT_PROMPT = 310;
global.__ONLINE_LK_DLG_NOTE_TITLE = 311;
global.__ONLINE_LK_DLG_NOTE_PROMPT = 312;
global.__ONLINE_LK_SKIN_MISSING = 313;
global.__ONLINE_LK_SKIN_DL_FAILED = 314;
global.__ONLINE_LK_SKIN_DL_DONE = 315;
global.__ONLINE_LK_HUD_NOTE_HINT_NODE = 316;
global.__ONLINE_LK_HUD_NOTE_HINT_DRAW = 317;
global.__ONLINE_LK_HUD_YOU = 318;
global.__ONLINE_LK_HUD_PICK_CURRENT = 319;
global.__ONLINE_LK_HUD_PICK_REMOVE = 320;
global.__ONLINE_LK_HUD_PICK_NO_INSTANCE = 321;
global.__ONLINE_LK_NOTIFY_RECONNECT_FAILED = 322;
global.__ONLINE_LK_ROW_LANGUAGE = 323;
global.__ONLINE_LK_DESC_LANGUAGE = 324;
global.__ONLINE_LK_HINT_LANGUAGE = 325;
global.__ONLINE_LangKey[0] = "menu.tab.settings";
global.__ONLINE_LangKey[1] = "menu.tab.saves";
global.__ONLINE_LangKey[2] = "menu.tab.rating";
global.__ONLINE_LangKey[3] = "menu.tab.keys";
global.__ONLINE_LangKey[4] = "menu.tab.sync";
global.__ONLINE_LangKey[5] = "menu.tab.skins";
global.__ONLINE_LangKey[6] = "menu.close";
global.__ONLINE_LangKey[7] = "menu.hint.fallback";
global.__ONLINE_LangKey[8] = "menu.head.connection";
global.__ONLINE_LangKey[9] = "menu.head.account";
global.__ONLINE_LangKey[10] = "menu.head.gameplay";
global.__ONLINE_LangKey[11] = "menu.head.display";
global.__ONLINE_LangKey[12] = "menu.head.notes";
global.__ONLINE_LangKey[13] = "menu.head.advanced";
global.__ONLINE_LangKey[14] = "menu.head.save_history";
global.__ONLINE_LangKey[15] = "menu.head.manage";
global.__ONLINE_LangKey[16] = "menu.head.this_game";
global.__ONLINE_LangKey[17] = "menu.head.rating";
global.__ONLINE_LangKey[18] = "menu.head.status";
global.__ONLINE_LangKey[19] = "menu.head.key_bindings";
global.__ONLINE_LangKey[20] = "menu.head.reset";
global.__ONLINE_LangKey[21] = "menu.head.sync";
global.__ONLINE_LangKey[22] = "menu.head.entries";
global.__ONLINE_LangKey[23] = "menu.head.installed";
global.__ONLINE_LangKey[24] = "menu.head.installed_of";
global.__ONLINE_LangKey[25] = "menu.row.on_failure";
global.__ONLINE_LangKey[26] = "menu.row.server";
global.__ONLINE_LangKey[27] = "menu.row.tcp_port";
global.__ONLINE_LangKey[28] = "menu.row.udp_port";
global.__ONLINE_LangKey[29] = "menu.row.name";
global.__ONLINE_LangKey[30] = "menu.row.password";
global.__ONLINE_LangKey[31] = "menu.row.store_in";
global.__ONLINE_LangKey[32] = "menu.row.team";
global.__ONLINE_LangKey[33] = "menu.row.lerp";
global.__ONLINE_LangKey[34] = "menu.row.save";
global.__ONLINE_LangKey[35] = "menu.row.fast";
global.__ONLINE_LangKey[36] = "menu.row.pvp";
global.__ONLINE_LangKey[37] = "menu.row.bullets";
global.__ONLINE_LangKey[38] = "menu.row.visual";
global.__ONLINE_LangKey[39] = "menu.row.indicator";
global.__ONLINE_LangKey[40] = "menu.row.spec_cam";
global.__ONLINE_LangKey[41] = "menu.row.menu_layout";
global.__ONLINE_LangKey[42] = "menu.row.player_objects";
global.__ONLINE_LangKey[43] = "menu.row.hide_others";
global.__ONLINE_LangKey[44] = "menu.row.hide_all";
global.__ONLINE_LangKey[45] = "menu.row.save_history";
global.__ONLINE_LangKey[46] = "menu.row.chat_history";
global.__ONLINE_LangKey[47] = "menu.row.favourites";
global.__ONLINE_LangKey[48] = "menu.row.stars";
global.__ONLINE_LangKey[49] = "menu.row.cleared";
global.__ONLINE_LangKey[50] = "menu.row.last_result";
global.__ONLINE_LangKey[51] = "menu.row.sync_enabled";
global.__ONLINE_LangKey[52] = "menu.row.auto_download";
global.__ONLINE_LangKey[53] = "menu.empty.no_saves";
global.__ONLINE_LangKey[54] = "menu.empty.no_favourites";
global.__ONLINE_LangKey[55] = "menu.empty.no_entries";
global.__ONLINE_LangKey[56] = "menu.empty.no_skins";
global.__ONLINE_LangKey[57] = "menu.empty.no_matches";
global.__ONLINE_LangKey[58] = "menu.val.on";
global.__ONLINE_LangKey[59] = "menu.val.off";
global.__ONLINE_LangKey[60] = "menu.val.quit";
global.__ONLINE_LangKey[61] = "menu.val.stay";
global.__ONLINE_LangKey[62] = "menu.val.na";
global.__ONLINE_LangKey[63] = "menu.val.locked";
global.__ONLINE_LangKey[64] = "menu.val.pick";
global.__ONLINE_LangKey[65] = "menu.val.reconnect_now";
global.__ONLINE_LangKey[66] = "menu.val.apply_reconnect";
global.__ONLINE_LangKey[67] = "menu.val.clear_all";
global.__ONLINE_LangKey[68] = "menu.val.clear_skin";
global.__ONLINE_LangKey[69] = "menu.val.search_prompt";
global.__ONLINE_LangKey[70] = "menu.val.search_active";
global.__ONLINE_LangKey[71] = "menu.val.key_n";
global.__ONLINE_LangKey[72] = "menu.val.bits";
global.__ONLINE_LangKey[73] = "menu.val.of_5";
global.__ONLINE_LangKey[74] = "menu.val.reset_keys";
global.__ONLINE_LangKey[75] = "menu.val.submit_rating";
global.__ONLINE_LangKey[76] = "menu.val.sending";
global.__ONLINE_LangKey[77] = "menu.val.wait_s";
global.__ONLINE_LangKey[78] = "menu.val.loaded";
global.__ONLINE_LangKey[79] = "menu.val.press_key";
global.__ONLINE_LangKey[80] = "menu.val.not_set";
global.__ONLINE_LangKey[81] = "menu.val.empty";
global.__ONLINE_LangKey[82] = "menu.val.none";
global.__ONLINE_LangKey[83] = "menu.val.save_n";
global.__ONLINE_LangKey[84] = "menu.val.team_fmt";
global.__ONLINE_LangKey[85] = "menu.val.team_none";
global.__ONLINE_LangKey[86] = "menu.val.team_red";
global.__ONLINE_LangKey[87] = "menu.val.team_blue";
global.__ONLINE_LangKey[88] = "menu.val.team_yellow";
global.__ONLINE_LangKey[89] = "menu.val.team_purple";
global.__ONLINE_LangKey[90] = "menu.val.team_green";
global.__ONLINE_LangKey[91] = "menu.val.team_orange";
global.__ONLINE_LangKey[92] = "menu.val.team_cyan";
global.__ONLINE_LangKey[93] = "menu.val.lerp_light";
global.__ONLINE_LangKey[94] = "menu.val.lerp_standard";
global.__ONLINE_LangKey[95] = "menu.val.lerp_strong";
global.__ONLINE_LangKey[96] = "menu.val.vis_all";
global.__ONLINE_LangKey[97] = "menu.val.vis_no_names";
global.__ONLINE_LangKey[98] = "menu.val.vis_hidden";
global.__ONLINE_LangKey[99] = "menu.val.speccam_free";
global.__ONLINE_LangKey[100] = "menu.val.speccam_follow";
global.__ONLINE_LangKey[101] = "menu.val.pvp_off";
global.__ONLINE_LangKey[102] = "menu.val.pvp_team";
global.__ONLINE_LangKey[103] = "menu.val.pvp_ffa";
global.__ONLINE_LangKey[104] = "menu.val.layout_auto";
global.__ONLINE_LangKey[105] = "menu.val.layout_narrow";
global.__ONLINE_LangKey[106] = "menu.val.layout_full";
global.__ONLINE_LangKey[107] = "menu.status.not_configured";
global.__ONLINE_LangKey[108] = "menu.status.reconnecting";
global.__ONLINE_LangKey[109] = "menu.status.online";
global.__ONLINE_LangKey[110] = "menu.status.unreachable";
global.__ONLINE_LangKey[111] = "menu.status.connecting";
global.__ONLINE_LangKey[112] = "menu.status.offline";
global.__ONLINE_LangKey[113] = "menu.rating.submitted";
global.__ONLINE_LangKey[114] = "menu.rating.failed_cooldown";
global.__ONLINE_LangKey[115] = "menu.rating.idle";
global.__ONLINE_LangKey[116] = "menu.rating.cooldown";
global.__ONLINE_LangKey[117] = "menu.keycap.space";
global.__ONLINE_LangKey[118] = "menu.keycap.char";
global.__ONLINE_LangKey[119] = "menu.keycap.key_n";
global.__ONLINE_LangKey[120] = "menu.age.now";
global.__ONLINE_LangKey[121] = "menu.age.min";
global.__ONLINE_LangKey[122] = "menu.age.hour";
global.__ONLINE_LangKey[123] = "menu.age.day";
global.__ONLINE_LangKey[124] = "menu.age.date";
global.__ONLINE_LangKey[125] = "menu.count.option";
global.__ONLINE_LangKey[126] = "menu.count.options";
global.__ONLINE_LangKey[127] = "menu.fact.store";
global.__ONLINE_LangKey[128] = "menu.fact.state";
global.__ONLINE_LangKey[129] = "menu.fact.room";
global.__ONLINE_LangKey[130] = "menu.fact.position";
global.__ONLINE_LangKey[131] = "menu.fact.gravity";
global.__ONLINE_LangKey[132] = "menu.fact.player";
global.__ONLINE_LangKey[133] = "menu.fact.saved";
global.__ONLINE_LangKey[134] = "menu.fact.hotkey";
global.__ONLINE_LangKey[135] = "menu.fact.favourite";
global.__ONLINE_LangKey[136] = "menu.fact.maker";
global.__ONLINE_LangKey[137] = "menu.fact.source";
global.__ONLINE_LangKey[138] = "menu.fact.frames";
global.__ONLINE_LangKey[139] = "menu.fact.status";
global.__ONLINE_LangKey[140] = "menu.fact.global";
global.__ONLINE_LangKey[141] = "menu.fact.bits";
global.__ONLINE_LangKey[142] = "menu.fact.slots";
global.__ONLINE_LangKey[143] = "menu.fact.present";
global.__ONLINE_LangKey[144] = "menu.fact.this_folder";
global.__ONLINE_LangKey[145] = "menu.fact.env_override";
global.__ONLINE_LangKey[146] = "menu.factv.set_masked";
global.__ONLINE_LangKey[147] = "menu.factv.empty";
global.__ONLINE_LangKey[148] = "menu.factv.none";
global.__ONLINE_LangKey[149] = "menu.factv.not_loaded";
global.__ONLINE_LangKey[150] = "menu.factv.yes";
global.__ONLINE_LangKey[151] = "menu.factv.no_skipped";
global.__ONLINE_LangKey[152] = "menu.factv.slots_fmt";
global.__ONLINE_LangKey[153] = "menu.act.edit";
global.__ONLINE_LangKey[154] = "menu.act.switch_store";
global.__ONLINE_LangKey[155] = "menu.act.run";
global.__ONLINE_LangKey[156] = "menu.act.pick";
global.__ONLINE_LangKey[157] = "menu.act.save_row";
global.__ONLINE_LangKey[158] = "menu.act.toggle";
global.__ONLINE_LangKey[159] = "menu.act.rebind";
global.__ONLINE_LangKey[160] = "menu.act.reset";
global.__ONLINE_LangKey[161] = "menu.act.apply";
global.__ONLINE_LangKey[162] = "menu.act.clear";
global.__ONLINE_LangKey[163] = "menu.act.rate";
global.__ONLINE_LangKey[164] = "menu.act.submit";
global.__ONLINE_LangKey[165] = "menu.act.confirm_clear";
global.__ONLINE_LangKey[166] = "menu.act.click_clear";
global.__ONLINE_LangKey[167] = "menu.desc.reconnect";
global.__ONLINE_LangKey[168] = "menu.desc.apply_reconnect";
global.__ONLINE_LangKey[169] = "menu.desc.name";
global.__ONLINE_LangKey[170] = "menu.desc.password";
global.__ONLINE_LangKey[171] = "menu.desc.store";
global.__ONLINE_LangKey[172] = "menu.desc.team";
global.__ONLINE_LangKey[173] = "menu.desc.lerp";
global.__ONLINE_LangKey[174] = "menu.desc.on_failure";
global.__ONLINE_LangKey[175] = "menu.desc.server";
global.__ONLINE_LangKey[176] = "menu.desc.tcp";
global.__ONLINE_LangKey[177] = "menu.desc.udp";
global.__ONLINE_LangKey[178] = "menu.desc.save_history";
global.__ONLINE_LangKey[179] = "menu.desc.chat_history";
global.__ONLINE_LangKey[180] = "menu.desc.save";
global.__ONLINE_LangKey[181] = "menu.desc.fast";
global.__ONLINE_LangKey[182] = "menu.desc.pvp";
global.__ONLINE_LangKey[183] = "menu.desc.bullets";
global.__ONLINE_LangKey[184] = "menu.desc.visual";
global.__ONLINE_LangKey[185] = "menu.desc.indicator";
global.__ONLINE_LangKey[186] = "menu.desc.spec_cam";
global.__ONLINE_LangKey[187] = "menu.desc.menu_layout";
global.__ONLINE_LangKey[188] = "menu.desc.hide_others";
global.__ONLINE_LangKey[189] = "menu.desc.hide_all";
global.__ONLINE_LangKey[190] = "menu.desc.save_row";
global.__ONLINE_LangKey[191] = "menu.desc.favourites";
global.__ONLINE_LangKey[192] = "menu.desc.clear_saves";
global.__ONLINE_LangKey[193] = "menu.desc.player_objects";
global.__ONLINE_LangKey[194] = "menu.desc.rebind";
global.__ONLINE_LangKey[195] = "menu.desc.reset_keys";
global.__ONLINE_LangKey[196] = "menu.desc.sync";
global.__ONLINE_LangKey[197] = "menu.desc.skin_row";
global.__ONLINE_LangKey[198] = "menu.desc.auto_download";
global.__ONLINE_LangKey[199] = "menu.desc.clear_skin";
global.__ONLINE_LangKey[200] = "menu.desc.search";
global.__ONLINE_LangKey[201] = "menu.desc.sync_entry";
global.__ONLINE_LangKey[202] = "menu.desc.game";
global.__ONLINE_LangKey[203] = "menu.desc.stars";
global.__ONLINE_LangKey[204] = "menu.desc.cleared";
global.__ONLINE_LangKey[205] = "menu.desc.last_result";
global.__ONLINE_LangKey[206] = "menu.desc.submit";
global.__ONLINE_LangKey[207] = "menu.hint.name";
global.__ONLINE_LangKey[208] = "menu.hint.password";
global.__ONLINE_LangKey[209] = "menu.hint.store";
global.__ONLINE_LangKey[210] = "menu.hint.apply_reconnect";
global.__ONLINE_LangKey[211] = "menu.hint.reconnect";
global.__ONLINE_LangKey[212] = "menu.hint.player_objects";
global.__ONLINE_LangKey[213] = "menu.hint.team";
global.__ONLINE_LangKey[214] = "menu.hint.lerp";
global.__ONLINE_LangKey[215] = "menu.hint.on_failure";
global.__ONLINE_LangKey[216] = "menu.hint.tcp";
global.__ONLINE_LangKey[217] = "menu.hint.udp";
global.__ONLINE_LangKey[218] = "menu.hint.server";
global.__ONLINE_LangKey[219] = "menu.hint.save_history";
global.__ONLINE_LangKey[220] = "menu.hint.chat_history";
global.__ONLINE_LangKey[221] = "menu.hint.save";
global.__ONLINE_LangKey[222] = "menu.hint.fast";
global.__ONLINE_LangKey[223] = "menu.hint.visual";
global.__ONLINE_LangKey[224] = "menu.hint.indicator";
global.__ONLINE_LangKey[225] = "menu.hint.spec_cam";
global.__ONLINE_LangKey[226] = "menu.hint.menu_layout";
global.__ONLINE_LangKey[227] = "menu.hint.hide_others";
global.__ONLINE_LangKey[228] = "menu.hint.hide_all";
global.__ONLINE_LangKey[229] = "menu.hint.pvp";
global.__ONLINE_LangKey[230] = "menu.hint.bullets";
global.__ONLINE_LangKey[231] = "menu.hint.save_row";
global.__ONLINE_LangKey[232] = "menu.hint.favourites";
global.__ONLINE_LangKey[233] = "menu.hint.clear_saves";
global.__ONLINE_LangKey[234] = "menu.hint.rebind";
global.__ONLINE_LangKey[235] = "menu.hint.reset_keys";
global.__ONLINE_LangKey[236] = "menu.hint.sync";
global.__ONLINE_LangKey[237] = "menu.hint.sync_entry";
global.__ONLINE_LangKey[238] = "menu.hint.skin_row";
global.__ONLINE_LangKey[239] = "menu.hint.auto_download";
global.__ONLINE_LangKey[240] = "menu.hint.clear_skin";
global.__ONLINE_LangKey[241] = "menu.hint.search";
global.__ONLINE_LangKey[242] = "menu.hint.game";
global.__ONLINE_LangKey[243] = "menu.hint.stars";
global.__ONLINE_LangKey[244] = "menu.hint.cleared";
global.__ONLINE_LangKey[245] = "menu.hint.last_result";
global.__ONLINE_LangKey[246] = "menu.hint.submit";
global.__ONLINE_LangKey[247] = "menu.dialog.name_title";
global.__ONLINE_LangKey[248] = "menu.dialog.name_prompt";
global.__ONLINE_LangKey[249] = "menu.dialog.pass_title";
global.__ONLINE_LangKey[250] = "menu.dialog.pass_prompt";
global.__ONLINE_LangKey[251] = "menu.dialog.server_title";
global.__ONLINE_LangKey[252] = "menu.dialog.host_prompt";
global.__ONLINE_LangKey[253] = "menu.dialog.tcp_title";
global.__ONLINE_LangKey[254] = "menu.dialog.udp_title";
global.__ONLINE_LangKey[255] = "menu.dialog.port_prompt";
global.__ONLINE_LangKey[256] = "menu.dialog.search_full";
global.__ONLINE_LangKey[257] = "menu.dialog.search_title";
global.__ONLINE_LangKey[258] = "menu.dialog.search_prompt";
global.__ONLINE_LangKey[259] = "menu.misc.no_state";
global.__ONLINE_LangKey[260] = "menu.misc.preview";
global.__ONLINE_LangKey[261] = "menu.misc.server_prefix";
global.__ONLINE_LangKey[262] = "skinstate.idle";
global.__ONLINE_LangKey[263] = "skinstate.run";
global.__ONLINE_LangKey[264] = "skinstate.jump";
global.__ONLINE_LangKey[265] = "skinstate.fall";
global.__ONLINE_LangKey[266] = "skinstate.slide";
global.__ONLINE_LangKey[267] = "skinstate.bow";
global.__ONLINE_LangKey[268] = "skinstate.bullet";
global.__ONLINE_LangKey[269] = "account.store.global";
global.__ONLINE_LangKey[270] = "account.store.folder";
global.__ONLINE_LangKey[271] = "account.store.env";
global.__ONLINE_LangKey[272] = "keys.visibility";
global.__ONLINE_LangKey[273] = "keys.toggle_save";
global.__ONLINE_LangKey[274] = "keys.spectate";
global.__ONLINE_LangKey[275] = "keys.chat_log";
global.__ONLINE_LangKey[276] = "keys.options";
global.__ONLINE_LangKey[277] = "keys.player_list";
global.__ONLINE_LangKey[278] = "keys.chat";
global.__ONLINE_LangKey[279] = "keys.here";
global.__ONLINE_LangKey[280] = "keys.fast_load";
global.__ONLINE_LangKey[281] = "keys.canvas";
global.__ONLINE_LangKey[282] = "menu.detail.connection";
global.__ONLINE_LangKey[283] = "menu.fact.server";
global.__ONLINE_LangKey[284] = "menu.dialog.server_host";
global.__ONLINE_LangKey[285] = "hud.chat_log";
global.__ONLINE_LangKey[286] = "hud.no_messages";
global.__ONLINE_LangKey[287] = "hud.players_online";
global.__ONLINE_LangKey[288] = "hud.exiting";
global.__ONLINE_LangKey[289] = "hud.spectating";
global.__ONLINE_LangKey[290] = "hud.no_players";
global.__ONLINE_LangKey[291] = "hud.screen";
global.__ONLINE_LangKey[292] = "hud.follow";
global.__ONLINE_LangKey[293] = "hud.spectating_prefix";
global.__ONLINE_LangKey[294] = "hud.pick_title";
global.__ONLINE_LangKey[295] = "hud.pick_line2";
global.__ONLINE_LangKey[296] = "hud.pick_done";
global.__ONLINE_LangKey[297] = "hud.pick_active";
global.__ONLINE_LangKey[298] = "hud.spec_tag";
global.__ONLINE_LangKey[299] = "notify.save_on";
global.__ONLINE_LangKey[300] = "notify.save_off";
global.__ONLINE_LangKey[301] = "notify.visual_mode";
global.__ONLINE_LangKey[302] = "notify.saved";
global.__ONLINE_LangKey[303] = "notify.reconnecting";
global.__ONLINE_LangKey[304] = "notify.offline_menu";
global.__ONLINE_LangKey[305] = "notify.notes_transient";
global.__ONLINE_LangKey[306] = "notify.notes_canvas";
global.__ONLINE_LangKey[307] = "notify.notes_off";
global.__ONLINE_LangKey[308] = "notify.version_old";
global.__ONLINE_LangKey[309] = "dialog.chat_title";
global.__ONLINE_LangKey[310] = "dialog.chat_prompt";
global.__ONLINE_LangKey[311] = "dialog.note_title";
global.__ONLINE_LangKey[312] = "dialog.note_prompt";
global.__ONLINE_LangKey[313] = "skin.missing";
global.__ONLINE_LangKey[314] = "skin.dl_failed";
global.__ONLINE_LangKey[315] = "skin.dl_done";
global.__ONLINE_LangKey[316] = "hud.note_hint_node";
global.__ONLINE_LangKey[317] = "hud.note_hint_draw";
global.__ONLINE_LangKey[318] = "hud.you";
global.__ONLINE_LangKey[319] = "hud.pick_current";
global.__ONLINE_LangKey[320] = "hud.pick_remove";
global.__ONLINE_LangKey[321] = "hud.pick_no_instance";
global.__ONLINE_LangKey[322] = "notify.reconnect_failed";
global.__ONLINE_LangKey[323] = "menu.row.language";
global.__ONLINE_LangKey[324] = "menu.desc.language";
global.__ONLINE_LangKey[325] = "menu.hint.language";
global.__ONLINE_LangCount = 326;
// every slot pre-initialised: on GMS, reading an array slot that was never
// written aborts the event (engine compat note 1, kept in the dev workspace)
for(_i = 0; _i < global.__ONLINE_LangCap; _i += 1) global.__ONLINE_Lang[_i] = "";
global.__ONLINE_lang = "zh-CN";   // built-in default; [config] lang= overrides
global.__ONLINE_LangName = "";    // display name from the file's [meta] section
return 0;

///// script @L
// The lookup every UI string goes through. The English fallback lives at the
// call site, so a missing file or key can never blank the interface.
// args: keyIndex, englishFallback -> text
var _t;
_t = "";
if(argument0 >= 0 && argument0 < global.__ONLINE_LangCap) _t = global.__ONLINE_Lang[argument0];
if(_t == "") return argument1;
return _t;

///// script @lang_load
// Loads lang/<code>.ini into the table. A missing file or unknown keys are
// fine - @L simply falls back. Returns the number of keys applied.
// args: code -> count
var _code, _path, _txt, _rest, _line, _cut, _sec, _lp, _k, _v, _i, _n, _f;
_code = argument0;
_n = 0;
if(_code == "" || _code == "en") return 0;
// GM8.0 strings are byte strings and the CJK renderer is keyed by GBK bytes, so
// it reads the converter-generated GBK copy; everything else reads the UTF-8
// original.
#if GM80
_path = @cfgDir + "lang" + chr(92) + _code + ".gbk.ini";
#endif
#if not GM80
_path = @cfgDir + "lang" + chr(92) + _code + ".ini";
#endif
_txt = "";
#if STUDIO
// the engine file functions cannot leave the save area on GMS; the native API
// can (same route as @account_ini_read), and it returns "" when unreadable
_txt = @account_native_read(_path);
#endif
#if not STUDIO
if(file_exists(_path)){
  _f = file_text_open_read(_path);
  if(_f >= 0){
    while(!file_text_eof(_f)){
      _txt += file_text_read_string(_f) + chr(10);
      file_text_readln(_f);
    }
    file_text_close(_f);
  }
}
#endif
if(_txt == "") return 0;
// a BOM from a user-edited file must not poison the first line
if(string_copy(_txt, 1, 3) == chr(239) + chr(187) + chr(191)) _txt = string_delete(_txt, 1, 3);
_sec = "";
_rest = _txt;
while(string_length(_rest) > 0){
  _cut = string_pos(chr(10), _rest);
  if(_cut > 0){
    _line = string_copy(_rest, 1, _cut - 1);
    _rest = string_delete(_rest, 1, _cut);
  }else{
    _line = _rest;
    _rest = "";
  }
  _line = @account_trim(_line);
  if(string_length(_line) == 0) continue;
  if(string_copy(_line, 1, 1) == ";") continue;
  if(string_copy(_line, 1, 1) == "["){
    _sec = string_copy(_line, 2, string_length(_line) - 2);
    continue;
  }
  _lp = string_pos("=", _line);
  if(_lp <= 1) continue;
  _k = @account_trim(string_copy(_line, 1, _lp - 1));
  _v = @account_trim(string_copy(_line, _lp + 1, string_length(_line) - _lp));
  if(_sec == "meta"){
    if(_k == "name") global.__ONLINE_LangName = _v;
    continue;
  }
  if(_k != "text") continue;
  // linear scan over the registry: a few hundred keys, once per load
  for(_i = 0; _i < global.__ONLINE_LangCount; _i += 1){
    if(global.__ONLINE_LangKey[_i] == _sec){
      global.__ONLINE_Lang[_i] = _v;
      _n += 1;
      break;
    }
  }
}
return _n;

///// script @lang_scan
// Enumerates the available languages into global.__ONLINE_langList[0..N):
// "en" first (the built-in fallback - there is no en.ini), then one entry per
// lang/<code>.ini next to the exe. The path is RELATIVE on purpose: it is the
// sandbox-friendly route (same as iwposkins); GM8.0 additionally filters the
// .gbk.ini copies out (they are the same languages re-encoded).
// args: none -> count
var _f, _code;
global.__ONLINE_langList[0] = "en";
global.__ONLINE_langListN = 1;
_f = file_find_first("lang" + chr(92) + "*.ini", 0);
while(_f != ""){
  if(string_pos(".gbk.ini", string_lower(_f)) == 0){
    _code = string_copy(_f, 1, string_length(_f) - 4);
    if(_code != "en"){
      global.__ONLINE_langList[global.__ONLINE_langListN] = _code;
      global.__ONLINE_langListN += 1;
    }
  }
  _f = file_find_next();
}
file_find_close();
return global.__ONLINE_langListN;

///// script @lang_apply
// Switch language at runtime: rebuild the table (every slot back to the English
// fallback), then load the new file. Instant effect - the row table is rebuilt
// every frame, so the next frame reads the new strings.
// args: code -> 0
var _keep;
_keep = argument0;
@lang_init();
global.__ONLINE_lang = _keep;
@lang_load(_keep);
return 0;
