import dotenv from "dotenv";
dotenv.config();

export const PORT_HTTP = parseInt(process.env.PORT_HTTP || "8001");
export const PORT_TCP = parseInt(process.env.PORT_SOCKETS || "8002");
export const PORT_UDP = parseInt(process.env.PORT_SOCKETS_UDP || "8003");

export const LAST_VERSION = "1.2.3_beta_5";
export const MIN_CLIENT_VERSION = "1.1.9";
export const PROTOCOL_VERSION = 5;
export const MIN_PROTOCOL_VERSION = 1;
export const MAX_PLAYERS_PER_IP = 8;
export const HEARTBEAT_INTERVAL_SEC = 5;
export const HEARTBEAT_TIMEOUT_SEC = 12;
export const UDP_CLEANUP_INTERVAL_MIN = 2;
export const UDP_EXPIRY_MIN = 5;
export const MAX_TCP_MESSAGE = 1000;
export const MAX_TCP_BUFFER = 8192;
export const MAX_UDP_MESSAGE = 127;
export const MAX_CUSTOM_SLOTS = 128;       // sum of slotCount across all sync entries (uint32 slots)
export const MAX_PER_ENTRY_SLOTS = 16;     // per-entry slot count cap (= 512 bits)
export const MAX_SYNC_ENTRIES = 16;        // distinct entry names per team
export const MAX_SYNC_NAME_LEN = 32;       // bytes of an entry name
export const MAX_TEAMS = 8;
export const TCP_RATE_LIMIT = 60;  // per second (legitimate bursts: rapid save-on-death loops, boss-flag CUSTOM_DATA, chat, etc.)
export const UDP_RATE_LIMIT = 100; // per second

// N4: per-game session caches (notes replay + last save), dropped after the
// game has been empty for GAME_CACHE_EXPIRY_MS.
export const NOTE_CACHE_MAX_PER_GAME = 256;   // ring entries (a multi-chunk stroke = 1 entry per chunk)
export const NOTE_SYNC_MIN_MS = 2000;         // per-player pull throttle
export const GAME_CACHE_EXPIRY_MS = 600000;   // 10 min empty grace

export const RATING_COOLDOWN_SEC = 300;     // 5 min between ratings per player
export const RATING_MAX_PER_GAME = 500;     // max stored ratings per game
export const RATING_DATA_DIR = process.env.RATING_DATA_DIR || "./data/ratings";

// Hash-addressed read-only skin package library: <SKIN_DATA_DIR>/<32-hex>/<files>
export const SKIN_DATA_DIR = process.env.SKIN_DATA_DIR || "./data/skins";
export const SKIN_MAX_FILES = 32;                    // manifest entry cap per package
export const SKIN_MAX_FILE_SIZE = 1024 * 1024;       // 1 MiB per package file
export const SKIN_MAX_TOTAL_SIZE = 4 * 1024 * 1024;  // 4 MiB per package
export const SKIN_CHUNK = 16384;                     // SKIN_FILE payload bytes per message
export const SKIN_DL_MAX_REQ_PER_MIN = 60;           // per-player manifest+file requests
export const SKIN_DL_MAX_BYTES_PER_MIN = 8 * 1024 * 1024; // per-player served file bytes
