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

  Q: The tool ran successfully, but gave me a game that I can't run. When I open it nothing happens and no window is created at all
  A: GameMaker8.1 checks the executable length to ensure the data is not corrupted. Since my mod require to change that length, I disable that check for the most common version of GameMaker8.1. Unfortunately, there are too many versions I should specifically cover. What you can do to fix this issue is to decompile the game and recompile it.

  Q: I tried to convert [some game] but the converter failed. Why?
  A: Sorry about that, I cannot convert every game. Some just won't work. I will try my best at covering the greatest majority of fangames. Feel free to contact me if there is a game you really want to play online, but be aware I have other priorities and will not do updates that often.

  Q: This sucks, the server keeps crashing or is way too slow!
  A: Well, sorry again. This is my first experience at creating online games, so I may have done some things wrong. If you have advices or recommendations about the way I should code the server, once again feel free to contact me.

Thank you so much for downloading, I really hope you will have a lot of fun!



CHANGE LOGS:

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
