import dotenv from "dotenv";
dotenv.config();

export const PORT_HTTP = parseInt(process.env.PORT_HTTP || "8001");
export const PORT_TCP = parseInt(process.env.PORT_SOCKETS || "8002");
export const PORT_UDP = parseInt(process.env.PORT_SOCKETS_UDP || "8003");

export const LAST_VERSION = "1.1.9";
export const PROTOCOL_VERSION = 1;
export const MIN_PROTOCOL_VERSION = 1;
export const MAX_PLAYERS_PER_IP = 8;
export const HEARTBEAT_INTERVAL_SEC = 10;
export const HEARTBEAT_TIMEOUT_SEC = 20;
export const UDP_CLEANUP_INTERVAL_MIN = 2;
export const UDP_EXPIRY_MIN = 5;
export const MAX_TCP_MESSAGE = 1000;
export const MAX_TCP_BUFFER = 8192;
export const MAX_UDP_MESSAGE = 127;
export const MAX_CUSTOM_SLOTS = 256;
export const MAX_TEAMS = 8;
export const TCP_RATE_LIMIT = 20;  // per second
export const UDP_RATE_LIMIT = 100; // per second

export const RATING_COOLDOWN_SEC = 300;     // 5 min between ratings per player
export const RATING_MAX_PER_GAME = 500;     // max stored ratings per game
export const RATING_DATA_DIR = process.env.RATING_DATA_DIR || "./data/ratings";
