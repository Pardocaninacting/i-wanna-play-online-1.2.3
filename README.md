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

## What's New in 1.2.3

Major additions over the original 1.1.9:

- **Team system** with color-coded names and team-scoped saves
- **Save history** with favorites, filtering and one-click rollback
- **Spectator mode** — observer camera that follows online players across rooms
- **Chat log** and **chat bubbles** with animation
- **5-star rating system** with web viewer
- **Rebindable hotkeys**, 4-tab settings panel
- **Off-screen player arrows** and player list overlay
- **Chinese/CJK text support** (GM8 dynamic font switching, GMS glyph atlas embedding)
- **Emoji/non-BMP character protection**
- **GM8.2 support** (gm82net/gm82buf network path)
- **GMS x64 support** (NativeAOT native DLL)
- **INI config persistence**
- **Automatic reconnection** with exponential backoff
- **Custom data channel** for game-specific variable sync
- **GMS converter rewrite** — standalone 2.5 MB C# binary replacing 60 MB UTMT CLI
- **Server modernization** — modular TypeScript with TCP stream reassembly, rate limiting, protocol versioning
- Many engine compatibility improvements and bug fixes

See `modder/README.md` for the full changelog.

## License

[MIT](LICENSE)

Based on [I wanna play online](https://gitlab.com/i-wanna-play-online) by DapperMink.
