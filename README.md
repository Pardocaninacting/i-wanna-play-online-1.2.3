# I wanna play online 1.2.3

Turns "I wanna be the guy" fangames made with GameMaker into online multiplayer games: players in the
same room see each other move, share saves, chat, place markers on the screen, wear skins and more.

This is a rewrite of [I wanna play online](https://gitlab.com/i-wanna-play-online) 1.1.9 by DapperMink.
Downloads, the online lobby, the skin library and game ratings are at **[iwannaplay.online](https://iwannaplay.online)**.

## Repository

| Directory | What it is | Stack |
|-----------|------------|-------|
| [`modder/`](modder/) | The converter (`iwpo.exe`): patches GM8 / 8.1 / 8.2 executables, drives the GMS converter, builds the release package | TypeScript (Node.js) |
| [`converter-gms/`](converter-gms/) | GameMaker Studio converter: patches `data.win` (GMS 1.x / 2.x, x86 / x64) | C# (.NET 10) |
| [`server/`](server/) | Game server: TCP/UDP relay, ratings, skin library, HTTP API | TypeScript (Node.js) |
| [`iwpo-website/`](iwpo-website/) | The iwannaplay.online website | Static HTML / CSS / JS |
| `UndertaleModTool/` | Git submodule used by `converter-gms` | C# |

The launcher that becomes `iwpo.exe` is unchanged from the original project:
[gitlab.com/i-wanna-play-online/launcher](https://gitlab.com/i-wanna-play-online/launcher).

## Supported games

| Engine | Support |
|--------|---------|
| GameMaker 8.0 / 8.1 | ✅ |
| GameMaker 8.2 (community runtime) | ✅ |
| GameMaker Studio 1.x (x86, including early bytecode 14/15 runners) | ✅ |
| GameMaker Studio 2.x (x86 / x64) | ✅ |

Not every game converts: heavily protected executables can still fail, and Unity games are detected and
refused. Bug reports with the game's name are welcome.

## Building from source

Prerequisites: Node.js 18+, .NET SDK 10, and the submodule:

```bash
git clone --recurse-submodules https://github.com/Pardocaninacting/i-wanna-play-online-1.2.3.git
# or, in an existing clone:
git submodule update --init --recursive
```

### Server

```bash
cd server
cp .env.template .env   # ports: HTTP 8001, TCP 8002, UDP 8003
npm install
npm run build
npm start
```

Or with Docker: `docker compose up --build -d` in `server/`.

HTTP API, used by the website and other tools:

| Endpoint | Returns |
|----------|---------|
| `GET /` or `GET /api/games` | Active rooms: `{ games: [{ name, players, hasPassword }] }` (password rooms carry no name) |
| `GET /api/ratings` | All ratings |
| `GET /api/ratings/:id` | Ratings of one game, matched by the 32-character hash prefix |

### Converter

```bash
cd modder
npm install
```

Point it at a server with `iwpo-settings.ini` in the repository root (next to `modder/`):

```ini
[settings]
server=127.0.0.1
tcp_port=8002
udp_port=8003
```

Convert a game:

```bash
npx tsc -p .
node index.js "path/to/game.exe"
```

Build the release package `modder/build/iwpo <version>.zip`:

```bash
npm run build
```

The build also compiles the GMS converter into `modder/lib/converterGMS2/` and the NativeAOT DLLs
(`http_dll_2_3.dll`, `http_dll_2_3_x64.dll`) from `modder/native/`. The packaged `iwpo-settings.ini`
points at the public server `123.iwannaplay.online`.

Converter options (shared-progress defaults, GM8 extension packages, GM8.2 tick injection) and the GML
template conventions are documented in [`modder/README.md`](modder/README.md). The manual bundled with
the release is [`modder/README.txt`](modder/README.txt); players get
[`modder/PLAYER_GUIDE.txt`](modder/PLAYER_GUIDE.txt).

### GMS converter

Built by the converter's `npm run build`. To build it alone:

```bash
cd converter-gms
dotnet publish -c Release
```

### Website

```bash
node iwpo-website/_dev/dev-server.cjs   # http://127.0.0.1:8199/
```

Static files, no build step. See [`iwpo-website/README.md`](iwpo-website/README.md) (in Chinese).

## Release notes

The current version is **1.2.3 beta 6**: a six-tab settings menu, UI localization (Simplified Chinese by
default), player skins with automatic download, a notes system, PVP bullet sharing and broader engine
coverage. The full changelog is in [`modder/README.md`](modder/README.md#changelog).

## Credits

Maker: Engel. Former maker: DapperMink (QuentinJanuel).

Special thanks: Adam, viri, Maarten Baert, krzys-h, Nikaple, hirtown, Samiboule, TheBiob, 大部队.

## License

[MIT](LICENSE). Based on [I wanna play online](https://gitlab.com/i-wanna-play-online) by DapperMink.
