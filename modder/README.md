# I wanna play online

## Description
This is the main application for I wanna play online. It converts GM8/GM8.1/GM8.2 and GameMaker Studio (1.x/2.x, x86/x64) fangames into online multiplayer versions. An external [GMS modder](https://gitlab.com/i-wanna-play-online/modder-gms) (converterGMS2) is bundled for GMS data.win patching.

## Launch
You will need [node](https://nodejs.org/en/) and [yarn](https://yarnpkg.com/getting-started/install).
Then you will need to install the node modules by running
```
yarn
```
Finally, simply run
```
yarn start
```

## Build
First you will need to install the node modules by running
```
yarn
```
Then, simply run
```
yarn build
```
The output will be in `build/iwpo 1.2.3.zip`.

## Edit the GML files
The GML files contain the code that will be injected into the game.
If you want to edit these files to contribute, first there are 3 things you should note:
* For every custom variable name you use, prefix it with `@`. The converter will then add a longer prefix in order to avoid conflicts.
* All the occurences of `%arg[n]` will be replaced by the nth argument. Those are handled by the converter.
* You can add specific parts of code with some sorts of directives:
    ```c
    #if STUDIO
        // This will be added to the game only for GameMaker:Studio
        #if not NIKAPLE
            // This will be added to the game only for GameMaker:Studio with a non Nikaple engine
        #endif
    #endif
    ```

## Changelog

### 1.2.3
- **Team system**: 8 selectable teams with color-coded names, chat and arrows; team notifications on join/switch; team-scoped save broadcasting
- **Save history**: local binary save log up to 500 entries with favorites, text filtering, pagination, relative timestamps and one-click position rollback; V2 format with deferred writes and time-density thinning
- **Spectator mode**: hold-to-enter observer camera that follows online players across rooms; smooth-follow and screen-snap camera modes; auto-exit when the room is empty
- **Chat log panel**: scrollable chat history overlay with word-wrapping and scroll indicator
- **Chat bubbles**: animated speech bubbles above players with spring physics, squash/stretch and fade
- **Rating system**: 1–5 star rating with optional "cleared" flag per game; server-side JSON persistence with per-IP cooldown; interactive web viewer at `/ratings`
- **Keybind system**: 8 rebindable hotkeys via in-game settings panel, persisted to INI
- **Off-screen player arrows**: team-colored edge arrows with distance fade and name labels pointing to players in the same room
- **Player list overlay**: right-side HUD showing all players in the current room with team colors and spectator tags
- **Settings panel**: 4-tab UI — Settings, Saves, Rating, Keys — with close button and full mouse interaction
- **Chinese/CJK support**: GM8 NoisyFox dynamic font switching between Berlin Sans FB Demi and SimSun; GMS compile-time glyph atlas embedding via System.Drawing
- **Emoji protection**: non-BMP surrogate pairs stripped at DLL, GML and server layers to prevent `string_copy` index crashes
- **GM8.2 support**: full gm82net/gm82buf network path with 38 bypass wrapper scripts; NativeAOT x86 DLL auto-build
- **GMS x64 support**: PE header machine-type detection and NativeAOT x64 native DLL with 38 registered extension functions
- **INI config persistence**: server address, team, lerp toggle, visibility mode, save broadcast toggle and all keybinds saved to `@config.ini`
- **Reconnection**: automatic TCP reconnect with exponential backoff; UDP retry with graceful fallback to TCP full rebuild
- **Cross-room state persistence**: connection state, player list, chat history and team data survive room transitions via tempfile
- **Custom data channel**: TCP case 7 for syncing game-specific boolean arrays as UINT32 bit fields; OR-merge on receive; team-scoped broadcast
- **Memory overflow fix**: replaced `SmartBuffer.toBuffer()` + spread-operator pattern with zero-copy `Buffer.concat`, reducing peak memory from several GB to near input size for large GM8 games
- **GMS converter rewrite**: replaced 60 MB UTMT CLI + Roslyn scripting with 2.5 MB standalone C# converter using UndertaleModLib directly; self-contained trimmed publish at 25 MB
- **Server modernization**: rewritten from single-file JS to modular TypeScript with TCP stream reassembly, `recvBuf` per player, `MAX_TCP_BUFFER` cap, independent protocol versioning and backward compatibility
- **Engine compatibility**: case-insensitive asset lookup, robust brace matching that skips strings and comments, dynamic room guards from actual Room data, Verve/RENEX detection via `save_save` + `player_air_jump`, interactive resource selection in TTY mode
- **Binary format fixes**: vSync bitfield preservation for GM8.1, forced `zeroUninitializedVars`, includedfile endianness fix, sound effects bitfield correction, WebGL null safety
- **Bug fixes**: position rollback on room change, GMS bytecodeVersion 14 compatibility, gravity teleport offset, small-room spectator camera clamp, teamMap cleanup on disconnect, GBK-safe backspace and string truncation
