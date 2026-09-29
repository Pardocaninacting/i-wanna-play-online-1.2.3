I wanna play online 

Description:
  This software is designed to automatically convert an 'I wanna be the guy' fangame into an online playable version.

Maker:
  Engel

Former Maker:
  DapperMink (QuentinJanuel)
  quentinjanuelkij@gmail.com
  (my discord changes all the time, sorry)

Special thanks:
  Adam
  viri
  Maarten Baert
  krzys-h
  Nikaple
  hirtown
  Samiboule
  大部队

How to use:
  In order to use this software, all you need to do is drag and drop the executable (.exe) of any game onto iwpo.exe.
  Make sure to let iwpo in its own directory.
  The server is configured in iwpo-settings.ini. To use a custom server, edit that file or pass server=IP on the command line.
  If no error message is thrown, then three cases can happen:
   - If the game is made with GameMaker 8 (or 8.1), the online game will be created as a new executable in the same directory.
   - If the game is made with GameMaker Studio and is self contained, the online game will be created in a new folder with all the resources unpacked.
   - If the game is made with GameMaker Studio and is already unpacked, a file data_backup.win will be created. The game will now be online, and in order to get back to the original version replace the file data.win by data_backup.win.
  The runtime config file for the converted game is __ONLINE_config.ini.
  PLAYER_GUIDE.txt is the bilingual manual for players. Keep it in the tool package or distribute it separately if you want to provide player-facing instructions.
  Older online packs may also read __ONLINE_server.txt as a server override fallback.

GM8 extension package selection:
  Some GM8 games have a non-vanilla runtime stub (UPX-packed, Antidec-patched, ...) where one or more
  IWPO extension packages fails to register, producing "Error defining an external function" at startup.
  For those games, choose which package(s) to inject in iwpo-settings.ini:

  [settings]
  extension_packages=wd_only

  Values:
   auto      Inject every supported package (default).
   wd_only   Only gm_windows_dialog8 (Windows dialog boxes). Empirically the safest fallback.
   fw_only   Only ChineseChatSupport8 (Chinese rendering, GM8.0 only).
   gm_only   Only gaseous_marble8 (GM8.1+ only).
   none      Skip all (same as no_extension_packages=1).

  Skipped packages fall back to vanilla GML stubs (e.g. wd_input_box -> get_string), so the rest
  of the injected world GML still compiles. Functionality is reduced but the game runs.

  Known case: "I wanna be the Fish ver1.1" now automatically falls back to the safe GM8.0 stub path instead of loading native CJK plugins. wd_only is still available if you want to force the minimal Windows-dialog-only package set manually.

GM8.2 tick injection compatibility:
  IWPO normally injects its per-frame GM8 tick into End Step. This remains the default for GM8, GM8.1 and ordinary GM8.2 games.

  Some games made by compiling older yuuutu-engine source directly with the community GameMaker 8.2 runtime may ignore some injected helper Step / End Step ticks. For those games, enable the Step compatibility scheduler before converting:

  [settings]
  inject_into_step=1

  When enabled, IWPO runs the main world tick from Step and schedules helper ticks from that reliable world tick, while helper Draw events remain draw-only. On these runtimes the injected objects' own Step/EndStep events never dispatch, so this mode also falls back to the game's native world object instead of the injected __ONLINE_world (override with iwpo.insert_custom_world=true if ever needed). Use this only as a compatibility workaround for affected games. Ordinary GM8.2 games should keep the default End Step injection.

Files to keep with the converted game:
 - the converted exe or online folder
 - http_dll_2_3.dll
 - __ONLINE_config.ini

Shared progress sync:
  If you want to ship default sync targets, edit the generated __ONLINE_config.ini or prefill iwpo-settings.ini before converting.
  The runtime [sync] section looks like this:

  [sync]
  entryCount = 2
  sync0_name  = boss
  sync0_count = 8
  sync1_name  = item
  sync1_count = 8

  sync_enabled = 1 is optional because the game defaults it to ON when omitted.
  Players should close the game before editing this section and restart afterward.

FAQ:
  Q: Me and my friend can't play [some game] together, the server seems to think we are playing two different games
  A: Make sure you converted the exact same executable, probably you two had different versions of the game.

  Q: The tool I try to convert a GameMaker:Studio game even though it is GameMaker8
  A: Probably you have a data.win file in the same directory, I check its presence to detect GameMaker:Studio and unfortunately that can lead to this bug. To fix this, you can simply temporarily remove the data.win file from the directory.

  Q: I tried to convert [some game] but the converter failed. Why?
  A: Sorry about that, I cannot convert every game. Some just won't work. I will try my best at covering the greatest majority of fangames. Feel free to contact me if there is a game you really want to play online, but be aware I have other priorities and will not do updates that often.

  Q: This sucks, the server keeps crashing or is way too slow!
  A: Well, sorry again. This is my first experience at creating online games, so I may have done some things wrong. If you have advices or recommendations about the way I should code the server, once again feel free to contact me.

Thank you so much for downloading, I really hope you will have a lot of fun!



CHANGE LOGS:

1.2.3 beta 6:
 - New settings menu: six tabs (Settings / Saves / Rating / Keys / Sync / Skins) with a detail pane, scrolling, and full mouse + keyboard control
 - UI localization system: Simplified Chinese by default, English one row away (Settings -> Language); drop-in lang/<code>.ini files add more languages
 - Player skins: installable skin packages (iwposkins/), per-state animation preview, auto-download of missing skins over the game connection
 - Notes system: ping wheel, polyline arrows, freehand strokes, text notes, canvas view
 - PVP: bullet sharing with team/FFA modes and kill detection
 - Multiple player objects: games with more than one player object can pick which one to drive
 - GM8.2-native Draw GUI HUD, early-GMS1 (bytecode 15) support, GM8.1/GMS2.3 compatibility hardening
 - The converter ships lang/, iwposkins/ and (for GMS games) DBGHELP.dll next to the game
 - GM8.0 renders Chinese with the built-in bitmap atlas by default (FoxWriting is unmaintained and crashes on current GPU drivers)
 - iwpo-settings.ini no longer accepts the extension-packages bisection switches globally; they moved to per-game games/<game>.ini
 - Various bug fixes and stability work

1.2.3 beta 5:
 - Default F Fast Load for the latest save-history entry; Fast Load can now be rebound or disabled in Settings
 - GM8 save hooks now run before successful early returns in custom save wrappers
 - GM8 load restore code is always injected into loadGame as a fallback, while keeping tempExe/saveExe for restart-based games
 - Optional inject_into_step=1 world-Step scheduler workaround for affected community-GM8.2 / old-yuuutu builds
 - Fish-class UPX + Antidec runners automatically fall back to the safe GM8.0 CJK stub path
 - Server legacy compatibility now uses an explicit minimum client version and tolerates old CUSTOM_DATA frames

1.2.3 beta 4:
 - Shared progress sync with a dedicated Sync tab
 - Ping wheel and map markers
 - Expanded 5-tab settings panel, save history, ratings, key rebinding
 - More reliable online roster, reconnect, spectator and team-state recovery
 - Chat log, player list, off-screen arrows and ping HUD polish
 - GMS CJK atlas pipeline, GMS x64 DLL path, improved GM8.2 / GMS compatibility
 - Server protocol v2 with beta3 basic compatibility for chat and movement
 - Various bug fixes and release-stabilization work

1.2.3:
 - Team system with color-coded names and team-scoped saves
 - Save history with favorites, filtering and one-click rollback
 - Spectator mode
 - Chat log, chat bubbles
 - 5-star rating system
 - Rebindable hotkeys
 - Off-screen player arrows, player list overlay
 - 4-tab settings panel
 - Chinese/CJK text support
 - Emoji/non-BMP character protection
 - GM8.2 support
 - GMS x64 support
 - INI config persistence
 - Automatic reconnection
 - Cross-room state persistence
 - Custom data channel for game-specific variable sync
 - Memory overflow fix for large GM8 games
 - Various bug fixes and engine compatibility improvements

1.1.9:
 - Added support for Unicode characters (GM8.0 only) (thanks to Nikaple)

1.1.8:
 - Renex engine compatility (thanks to Samiboule)

1.1.7:
 - Fixed text encoding issues (thanks to Samiboule)

1.1.6:
 - Use the new server (isocodes.org => 212.64.24.80)

1.1.5:
 - Fixed the heap out of memory crash for heavy GM8 games
 - Accurate "online players" for the website
 - Race mod
 - Destroy player when the change of rooms
 - Fixed saves for Nikaple engine
 - Slightly better player continuity
 - Games protected by a password are not shown on the website anymore

1.1.4:
 - Support for Nikaple engine
 - Better player continuity

1.1.3:
 - Fixed the heap out of memory crash for heavy GMS games

1.1.2:
 - Fixed a typo in the GameMaker:Studio converter

1.1.1:
 - Don't try to use unexisting assets anymore

1.1.0:
 - Improved server security and speed
 - Added password
 - Fixed games that keep asking the username
 - Fixed mixed games
 - Fixed 32 bit compatility (FAILED)

1.0.0:
 - First release
