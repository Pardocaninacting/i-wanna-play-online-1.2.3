# I wanna play online 1.2.3

A tool that converts "I wanna be the guy" fangames into online multiplayer versions.

This is a major rewrite of [I wanna play online](https://gitlab.com/i-wanna-play-online) (1.1.9). See the [changelog](#whats-new-in-123) for a summary of changes.

## Components

| Directory | Description | Language |
|-----------|-------------|----------|
| `modder/` | Main converter — patches GM8/GM8.1/GM8.2 executables in-place | TypeScript (Node.js) |
| `converter-gms/` | GMS converter — patches GameMaker Studio data.win files | C# (.NET 10) |
| `server/` | Game server — TCP/UDP relay + HTTP API | TypeScript (Node.js) |

### Not included in this repository

- **Launcher** — unchanged from the original, see [gitlab.com/i-wanna-play-online/launcher](https://gitlab.com/i-wanna-play-online/launcher)
- **Website** — left for other developers to implement; see [Server HTTP API](#server-http-api) for the endpoints it depends on

## Quick Start

### 1. Server

```bash
cd server
cp .env.template .env   # edit ports if needed
npm install
npm run build
npm start
```

The server listens on three ports (configurable in `.env`):
- **8001** — HTTP API
- **8002** — TCP game protocol
- **8003** — UDP game protocol

Or use Docker:

```bash
cd server
docker compose up --build -d
```

### 2. Modder (GM8 converter)

**Prerequisites**: Node.js 18+, npm

```bash
cd modder
npm install
```

**Configure the server** — create `iwpo-settings.ini` next to `modder/`:

```ini
[settings]
server=YOUR_SERVER_IP
tcp_port=8002
udp_port=8003
```

**Convert a game** (development mode):

```bash
npx tsc -p .
node index.js "path/to/game.exe"
```

**Build distributable** (produces `build/iwpo 1.2.3.zip`):

```bash
npm run build
```

The NativeAOT DLLs (`http_dll_2_3.dll`, `http_dll_2_3_x64.dll`) are built automatically during the build process from `native/` source. Requires .NET SDK 10+.

### 3. Converter GMS

**Prerequisites**: .NET SDK 10

The GMS converter is built as part of the modder build process and placed in `modder/lib/converterGMS2/`. To build it standalone:

```bash
cd converter-gms
dotnet publish -c Release
```

This project depends on [UndertaleModTool](https://github.com/UnderMiners-Mods/UndertaleModTool) which is included as a git submodule:

```bash
git submodule update --init --recursive
```

## Supported Games

| Engine | Support |
|--------|---------|
| GameMaker 8.0 | ✅ Full |
| GameMaker 8.1 | ✅ Full |
| GameMaker 8.2 (gm82) | ✅ Full (gm82net/gm82buf path) |
| GameMaker Studio 1.x (x86) | ✅ Full |
| GameMaker Studio 2.x (x86) | ✅ Full |
| GameMaker Studio (x64) | ✅ Full |

Different games may encounter different issues. Bug reports with specific game names are welcome.

## Server HTTP API

The server exposes an HTTP API that can be consumed by a website or other tools:

| Endpoint | Description |
|----------|-------------|
| `GET /` | Active game list (`{games: [...]}`) |
| `GET /api/ratings` | All ratings data |
| `GET /api/ratings/:id` | Ratings for a specific game (by 32-char hash prefix) |

## What's New in 1.2.3 beta 4

Compared with beta 3, beta 4 adds or substantially rewrites:

- **Shared progress sync** with a dedicated Sync tab and protocol v2 `CUSTOM_DATA`
- **Ping / marker wheel** with 9 marker types, room-aware filtering, and team-colored labels
- **Expanded settings UI** with 5 tabs, keyboard navigation, save-history actions, rating flow, and key rebinding
- **Roster / reconnect hardening** with LIST reconcile, periodic heartbeat, spectator-state recovery, and stricter same-team save routing
- **GMS text and runtime updates** including the bundled CJK atlas path and x64 NativeAOT DLL support
- **Server-side protocol updates** while preserving beta3 basic interop for chat and movement

See `modder/README.md` for the full beta4 changelog.

## License

[MIT](LICENSE)

Based on [I wanna play online](https://gitlab.com/i-wanna-play-online) by DapperMink.
