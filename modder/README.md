# I wanna play online

## Description
This is the main IWPO converter. It patches GM8/GM8.1/GM8.2 executables in place and bundles `converterGMS2` for GameMaker Studio (1.x/2.x, x86/x64) `data.win` patching.

## Launch
You will need [Node.js](https://nodejs.org/en/) and npm.
Install the dependencies by running
```
npm install
```
Then run
```
npm start
```

## Build
Install the dependencies by running
```
npm install
```
Then run
```
npm run build
```
The output will be in `build/iwpo 1.2.3_beta_4.zip`.

## Shipping a Converted Game

Every converted release should keep these runtime files together:

- the converted EXE or online folder
- `http_dll_2_3.dll`
- `__ONLINE_config.ini`

`PLAYER_GUIDE.txt` is the bilingual player manual. Keep it in the tool package or distribute it separately when you want to provide player-facing instructions, but it is not copied into converted game folders automatically.

If you want shared-progress defaults, prefill `iwpo-settings.ini [mod]` before conversion or edit the generated `__ONLINE_config.ini` afterward. The runtime `[sync]` shape is:

```ini
[sync]
entryCount = 2
sync0_name  = boss
sync0_count = 8
sync1_name  = item
sync1_count = 8
```

`sync_enabled = 1` is optional because the game defaults it to on when omitted. Players need to restart the game after editing the entry names or counts.

## GM8 Extension Package Selection

Some GM8 games ship with non-vanilla runtime stubs (UPX-packed, Antidec-patched, etc.) where one or more of the IWPO extension packages fails to register, producing `Error defining an external function` at game start. For those games, choose which package(s) to inject in `iwpo-settings.ini`:

```ini
[settings]
extension_packages=wd_only
```

Allowed values:

- `auto` (default): inject every supported package for the target version (GM8.0: `ChineseChatSupport8` + `gm_windows_dialog8`; GM8.1+: `gaseous_marble8` + `gm_windows_dialog8`).
- `wd_only`: only `gm_windows_dialog8` (Windows dialog boxes). Empirically the safest fallback — works on UPX/Antidec games where `ChineseChatSupport8` fails.
- `fw_only`: only `ChineseChatSupport8` (Chinese text rendering via FoxWriting). GM8.0 only.
- `gm_only`: only `gaseous_marble8`. GM8.1+ only.
- `none`: skip all packages (equivalent to `no_extension_packages=1`).

When a package is skipped, the converter injects vanilla-GML stub scripts (`wd_input_box` → `get_string`, `fw_draw_text_ext` → `draw_text_ext`, etc.) so the rest of the injected world GML still compiles. Functionality is reduced (no Windows dialogs / no Chinese rendering) but the game runs.

Known case: `I wanna be the Fish ver1.1` now automatically falls back to the safe GM8.0 stub path instead of loading native CJK plugins. `wd_only` is still available if you want to force the minimal Windows-dialog-only package set manually.

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

### 1.2.3 beta 4

#### New features

- **Shared progress sync**: adds protocol v2 `CUSTOM_DATA`, configurable `[sync]` entries, and a dedicated Sync tab for team-scoped boolean-array progress sharing.
- **Ping / marker system**: adds a radial ping wheel, 9 marker types, team-colored sender labels, room-aware filtering, and marker sound feedback.
- **Expanded settings panel**: grows the in-game panel to 5 tabs — Settings, Saves, Rating, Keys, Sync — with keyboard navigation and per-tab actions.
- **Save-history workflow**: adds favorites, hotkeys, filtering, pagination, relative timestamps, and one-click rollback on top of the shared-save flow.
- **Rating flow**: adds in-client 1–5 star submission with optional cleared flag and the matching HTTP API / website viewer path.
- **Roster and spectator HUD updates**: adds connection-based roster reconcile, remote `[SPEC]` state propagation, spectator camera modes, and a more reliable player list overlay.
- **HUD / overlay polish**: adds chat log overlay, off-screen arrows, richer ping rendering, and improved team-colored name display.

#### Compatibility and stability

- **Server / protocol update**: bumps the live protocol to v2, adds `PING` and `CUSTOM_DATA`, keeps beta3 clients compatible for basic chat/move flow, and tightens same-team save routing.
- **Reconnect hardening**: adds periodic heartbeat, periodic LIST reconcile, reconnect recovery, and spectator/team state resync after reconnect or room transitions.
- **GMS text pipeline**: replaces the old GMS text path with a bundled CJK atlas flow, adds atlas packing/visibility logging, and improves Chinese path/name handling.
- **GMS runtime coverage**: fixes GMS1 bytecode 14 compatibility, keeps GMS2 support, and adds the x64 NativeAOT HTTP DLL path.
- **GM8 / GM8.2 coverage**: expands wrapper and extension handling for GM8.2 buffer/network paths and keeps the GM8 plugin-less path aligned with beta4 protocol behavior.
- **Config persistence**: stores team, visibility, save toggle, lerp, sync enabled state, and all current hotkeys in `__ONLINE_config.ini`.

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
- **INI config persistence**: server address, team, lerp toggle, visibility mode, save broadcast toggle and all keybinds saved to `__ONLINE_config.ini`
- **Reconnection**: automatic TCP reconnect with exponential backoff; UDP retry with graceful fallback to TCP full rebuild
- **Cross-room state persistence**: connection state, player list, chat history and team data survive room transitions via tempfile
- **Custom data channel**: TCP case 7 for syncing game-specific boolean arrays as UINT32 bit fields; OR-merge on receive; team-scoped broadcast
- **Memory overflow fix**: replaced `SmartBuffer.toBuffer()` + spread-operator pattern with zero-copy `Buffer.concat`, reducing peak memory from several GB to near input size for large GM8 games
- **GMS converter rewrite**: replaced 60 MB UTMT CLI + Roslyn scripting with 2.5 MB standalone C# converter using UndertaleModLib directly; self-contained trimmed publish at 25 MB
- **Server modernization**: rewritten from single-file JS to modular TypeScript with TCP stream reassembly, `recvBuf` per player, `MAX_TCP_BUFFER` cap, independent protocol versioning and backward compatibility
- **Engine compatibility**: case-insensitive asset lookup, robust brace matching that skips strings and comments, dynamic room guards from actual Room data, Verve/RENEX detection via `save_save` + `player_air_jump`, interactive resource selection in TTY mode
- **Binary format fixes**: vSync bitfield preservation for GM8.1, forced `zeroUninitializedVars`, includedfile endianness fix, sound effects bitfield correction, WebGL null safety
- **Bug fixes**: position rollback on room change, GMS bytecodeVersion 14 compatibility, gravity teleport offset, small-room spectator camera clamp, teamMap cleanup on disconnect, GBK-safe backspace and string truncation