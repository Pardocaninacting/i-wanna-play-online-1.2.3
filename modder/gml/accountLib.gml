/// ONLINE
// ============================================================================
// Account store: name + session key persistence.
//
// Why this exists: without a disk store the startup dialogs (name / password)
// run on every launch - tempOnline only carries state across room changes and
// game_restart within one process.
//
// Tiers (highest first):
//   P1 environment  IWPO_NAME / IWPO_PASSWORD   (read-only; probes + parallel tests)
//   P2 this folder  <program_directory>\__ONLINE_account.ini   (per-game override)
//   P3 global       %APPDATA%\iwpo\account.ini                 (default for every game)
//   P0 first run    two modal prompts, then written to P3
//
// The file is a hand-parsed ini section; GM8.0 has no ini_key_first/ini_key_next
// (8.1+) and the ini_* family resolves against the working directory while the
// rest of the mod resolves against program_directory. file_text_* behaves the
// same on GM8.0 and GMS1, so both engines share this parser.
//
//   [account]
//   name=PlayerOne
//   password=secret
//   store=global            ; 0/global = write to P3, 1/local = write to P2
//
// Values are stored RAW (no '#' escaping): the file is single-line key=value,
// so a '#' inside a name is harmless, and the GM8/GMS2.3 backslash-escape
// semantics stay out of the file format entirely. The '#' -> '\#' escaping is
// applied where it belongs - when the name is handed to the game (see
// @account_apply).
//
// The session key is NOT a credential: the client appends it to the game id and
// the server uses that as the session/save partition (players sharing a key meet
// each other). Never describe it as authentication in UI text.
// ============================================================================

///// script @account_dir
// Normalises a directory into "ends with exactly one separator".
// The engines disagree about the trailing slash of program_directory /
// working_directory (the existing config code at worldCreate.gml:547 has to
// append one defensively), and APPDATA never has one. Without this,
// program_directory + "__ONLINE_account.ini" can become
// "C:\game\folder__ONLINE_account.ini" and silently miss the file.
// GM8.0 has neither string_ends_with nor string_delete_trailing; both separators
// are single bytes, so ord(string_char_at()) is enough.
// args: dir -> dir with exactly one trailing separator
var _d, _c, _n;
_d = argument0;
if(_d == "") return _d;
_n = string_length(_d);
while(_n > 0){
  _c = ord(string_char_at(_d, _n));
  if(_c == 92 || _c == 47){ _n -= 1; }else{ break; }
}
_d = string_copy(_d, 1, _n);
_d += chr(92);
return _d;

///// script @account_paths
// Resolves the two file locations into globals. Safe to call repeatedly.
//
// The global (P3) root is engine dependent. GMS2 sandboxes file access: a store
// under %APPDATA% is outside the sandbox, so file_exists() returns false there.
// On those engines the global store lives in the game's own save area
// (game_save_id), which is inside the sandbox. GM8.0/8.1/GMS1 have no sandbox,
// so they keep %APPDATA%.
// args: none -> 0
var _appdata, _save;
global.__ONLINE_accGlobalDir = "";
#if STUDIO
// The native API makes the shared location reachable, so GMS uses the same file
// as GM8. Two candidates, decided by what can actually be written:
//   primary  %APPDATA%\iwpo\account.ini   (shared with GM8 builds; the folder
//            may not exist on a GMS-only machine)
//   alt      %APPDATA%\iwpo_account.ini    (no folder needed, still shared by
//            every GMS game on the machine)
//   last     the save area file, so a locked-down machine still works per game
_appdata = environment_get_variable("APPDATA");
if(_appdata != ""){
  global.__ONLINE_accGlobalDir = @account_dir(_appdata) + "iwpo" + chr(92);
  global.__ONLINE_accGlobalPath = global.__ONLINE_accGlobalDir + "account.ini";
  global.__ONLINE_accAltPath = @account_dir(_appdata) + "iwpo_account.ini";
}else{
  global.__ONLINE_accGlobalDir = "";
  global.__ONLINE_accGlobalPath = @account_dir(working_directory) + "__ONLINE_account.ini";
  global.__ONLINE_accAltPath = "";
}
_save = game_save_id;
if(_save != "") global.__ONLINE_accSavePath = @account_dir(_save) + "iwpo_account.ini"; else global.__ONLINE_accSavePath = "";
#endif
#if not STUDIO
_appdata = environment_get_variable("APPDATA");
if(_appdata != ""){
  // P3: per-user, writable, survives game uninstalls.
  global.__ONLINE_accGlobalDir = @account_dir(_appdata) + "iwpo" + chr(92);
  global.__ONLINE_accGlobalPath = global.__ONLINE_accGlobalDir + "account.ini";
}else{
  // No APPDATA (rare): fall back to the working directory so the feature still
  // works, even though it is then per-install rather than per-user.
  global.__ONLINE_accGlobalPath = @account_dir(working_directory) + "__ONLINE_account.ini";
}
#endif
global.__ONLINE_accLocalPath = @account_dir(program_directory) + "__ONLINE_account.ini";
return 0;

///// script @account_native_read
// Reads a whole file through the native buffer API. The engine file functions are
// confined to the game save area on GMS, but http_dll is native code (plain fopen)
// so this reaches the shared %APPDATA% location. Returns "" when unreadable.
// args: path -> text
#if STUDIO
// dedicated file API: deterministic UTF-8 on write, tolerant on read. The buffer
// API would work but buffer_write_string appends a NUL, which ended up in the file.
return file_read_text(argument0);
#endif
#if not STUDIO
return "";
#endif

///// script @account_native_write
// Writes text to a path through the native buffer API. 1 on success.
// args: path, text -> 1/0
#if STUDIO
// ANSI (the system codepage) rather than UTF-8: that is what a GM8.0 build
// writes and reads natively, so one file stays readable by both engines and the
// tolerant native decode (strict UTF-8, then ANSI) always takes the right branch.
return file_write_text(argument0, argument1, 1);
#endif
#if not STUDIO
return 0;
#endif

///// script @account_ini_parse
// Parses the account file TEXT (argument0) into the account globals.
// argument1 = 1 when this is the global store (its "store" key is honoured; a
// local file always means local). Returns 1 when a usable name was found.
//
// Name/password are stored twice: a generic pair and an engine-tagged pair
// (name_gbk on GM8.0, name_utf8 elsewhere), so one shared file can serve an ANSI
// engine and a UTF-8 engine without CJK names turning into mojibake. The tagged
// key wins, the generic one is the compatibility fallback.
// args: text, isGlobal -> 1/0
var _line, _lp, _key, _val, _inSec, _found, _storeVal;
var _genName, _genPass, _tagName, _tagPass, _rest, _cut;
_found = 0;
_storeVal = -1;
_genName = "";
_genPass = "";
_tagName = "";
_tagPass = "";
_inSec = 0;
global.__ONLINE_accName = "";
global.__ONLINE_accPassword = "";
_rest = argument0;
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
  if(string_length(_line) > 0){
    if(string_copy(_line, 1, 1) == ";"){ /* comment */ }
    else if(string_copy(_line, 1, 1) == "["){ _inSec = (@account_lower(_line) == "[account]"); }
    else if(_inSec){
      _lp = string_pos("=", _line);
      if(_lp > 1){
        _key = @account_lower(@account_trim(string_copy(_line, 1, _lp - 1)));
        _val = @account_trim(string_copy(_line, _lp + 1, string_length(_line) - _lp));
        if(_key == "name"){ _genName = _val; }
        else if(_key == "password"){ _genPass = _val; }
        else if(_key == "name_gbk" || _key == "name_utf8"){ _tagName = _val; }
        else if(_key == "password_gbk" || _key == "password_utf8"){ _tagPass = _val; }
        else if(_key == "store"){
          if(@account_lower(_val) == "local") _storeVal = 1; else _storeVal = 0;
        }
      }
    }
  }
}
global.__ONLINE_accTagWasUtf8 = 0;
if(_tagName != ""){
  global.__ONLINE_accName = _tagName;
  global.__ONLINE_accPassword = _tagPass;
}else{
  global.__ONLINE_accName = _genName;
  global.__ONLINE_accPassword = _genPass;
}
// Legacy files (written before the single-encoding change) store real UTF-8
// under name_utf8 and have no name_gbk, which a GM8.0 build cannot read.
// Flagging it lets @account_load rewrite the file in ANSI once.
if(string_pos("name_utf8=", argument0) > 0) global.__ONLINE_accTagWasUtf8 = 1;
if(global.__ONLINE_accName != "") _found = 1;
if(argument1 == 1){
  if(_storeVal >= 0) global.__ONLINE_accStore = _storeVal; else global.__ONLINE_accStore = 0;
}else{
  global.__ONLINE_accStore = 1;
}
if(!_found){
  global.__ONLINE_accName = "";
  global.__ONLINE_accPassword = "";
}
return _found;

///// script @account_ini_read
// Reads argument0 and fills the account globals (see @account_ini_parse).
// On STUDIO the text comes through the native API, because the engine file
// functions cannot leave the save area; elsewhere the plain file functions are
// used and the text is handed to the same parser.
// args: path, isGlobal -> 1/0
#if STUDIO
return @account_ini_parse(@account_native_read(argument0), argument1);
#endif
#if not STUDIO
var _f, _txt, _l;
if(!file_exists(argument0)) return 0;
_f = file_text_open_read(argument0);
if(_f < 0) return 0;
_txt = "";
while(!file_text_eof(_f)){
  _l = file_text_read_string(_f);
  file_text_readln(_f);
  _txt += _l + chr(10);
}
file_text_close(_f);
return @account_ini_parse(_txt, argument1);
#endif

///// script @account_save
// Writes the current values to the active store target. The text is composed
// once and handed to the engine-appropriate writer: the native API on STUDIO
// (the engine file functions cannot leave the save area there), the ordinary
// file functions elsewhere.
// args: none -> 1 on success, 0 on failure (caller shows the red hint and may
// offer "Store in: This folder" as a fallback)
var _path, _f, _store, _tag, _out;
// self-sufficient: never depend on @account_load having run (a tempOnline
// restore skips it, and an undefined path global aborts the save).
@account_paths();
if(global.__ONLINE_accStore == 1) _path = global.__ONLINE_accLocalPath; else _path = global.__ONLINE_accGlobalPath;
// Compose the file text once; the writer differs per engine.
// Name/password are written twice: the generic pair (readable by any engine)
// and the engine-tagged pair that wins on read (see @account_ini_parse).
// NOTE: no #else here - the GM8 render pipeline (getGMLCode.parseGML) only
// understands #if / #if not / #endif, so an #else would survive into the game
// code and fail to compile.
// Both engines write this file in the system ANSI codepage (GM8.0 natively, GMS
// through the native API), so there is one tag for both; old files tagged
// name_utf8 still read because the parser accepts either tag.
_tag = "_gbk";
if(global.__ONLINE_accStore == 1) _store = "local"; else _store = "global";
_out = "[account]" + chr(10);
_out += "name=" + global.__ONLINE_accName + chr(10);
_out += "password=" + global.__ONLINE_accPassword + chr(10);
_out += "name" + _tag + "=" + global.__ONLINE_accName + chr(10);
_out += "password" + _tag + "=" + global.__ONLINE_accPassword + chr(10);
_out += "store=" + _store + chr(10);
#if STUDIO
// Native write: the engine file functions cannot leave the save area, so a
// plain file_text_open_write here would silently fail on the shared path.
if(@account_native_write(_path, _out)) return 1;
if(global.__ONLINE_accStore != 1){
  if(global.__ONLINE_accAltPath != "" && global.__ONLINE_accAltPath != _path){
    if(@account_native_write(global.__ONLINE_accAltPath, _out)){
      global.__ONLINE_accGlobalPath = global.__ONLINE_accAltPath;
      return 1;
    }
  }
  if(global.__ONLINE_accSavePath != "" && global.__ONLINE_accSavePath != _path){
    if(@account_native_write(global.__ONLINE_accSavePath, _out)){
      global.__ONLINE_accGlobalPath = global.__ONLINE_accSavePath;
      return 1;
    }
  }
}
global.__ONLINE_accWritePath = _path;
return 0;
#endif
#if not STUDIO
if(global.__ONLINE_accStore != 1){
  if(global.__ONLINE_accGlobalDir != ""){
    if(!directory_exists(global.__ONLINE_accGlobalDir)) directory_create(global.__ONLINE_accGlobalDir);
  }
}
_f = file_text_open_write(_path);
if(_f < 0){
  global.__ONLINE_accWritePath = _path;
  return 0;
}
file_text_write_string(_f, _out);
file_text_close(_f);
return 1;
#endif

///// script @account_load
// P1 -> P2 -> P3 resolution. Fills the account globals and global.__ONLINE_accSource.
// args: none -> 1 when a name is available (no prompt needed), 0 for first run
var _env;
@account_paths();
global.__ONLINE_accSource = 0;
global.__ONLINE_accEnvManaged = 0;
global.__ONLINE_accName = "";
global.__ONLINE_accPassword = "";
global.__ONLINE_accStore = 0;
_env = environment_get_variable("IWPO_NAME");
if(_env != ""){
  // P1: the whole tier is taken from the environment (name AND password), so a
  // half-configured probe cannot silently mix environment and file values.
  global.__ONLINE_accName = _env;
  global.__ONLINE_accPassword = environment_get_variable("IWPO_PASSWORD");
  global.__ONLINE_accSource = 1;
  global.__ONLINE_accEnvManaged = 1;
  return 1;
}
if(@account_ini_read(global.__ONLINE_accLocalPath, 0)){
  global.__ONLINE_accSource = 2;
  return 1;
}
if(@account_ini_read(global.__ONLINE_accGlobalPath, 1)){
  global.__ONLINE_accSource = 3;
  @account_migrate_encoding();
  return 1;
}
#if STUDIO
// the alternate shared file (GMS-only machine: the iwpo folder may not exist)
if(global.__ONLINE_accAltPath != ""){
  if(@account_ini_read(global.__ONLINE_accAltPath, 1)){
    global.__ONLINE_accGlobalPath = global.__ONLINE_accAltPath;
    global.__ONLINE_accSource = 3;
    return 1;
  }
}
// last resort: the per-game save area file written by an earlier run
if(global.__ONLINE_accSavePath != ""){
  if(@account_ini_read(global.__ONLINE_accSavePath, 1)){
    global.__ONLINE_accGlobalPath = global.__ONLINE_accSavePath;
    global.__ONLINE_accSource = 4;
    return 1;
  }
}
#endif
return 0;

///// script @account_migrate_encoding
// One-time migration: a legacy file stores real UTF-8 (name_utf8) and no ANSI
// tag, so a GM8.0 build reads mojibake. Rewriting it through the native writer
// converts it to the system ANSI codepage, which both engines read correctly.
// Only STUDIO builds can write outside the save area, and only they can produce
// such a file in the first place, so this runs there and nowhere else.
// args: none -> 0
#if STUDIO
if(global.__ONLINE_accTagWasUtf8){
  global.__ONLINE_accTagWasUtf8 = 0;
  @account_save();
}
#endif
return 0;

///// script @account_apply
// Single source of truth: pushes the stored values into the live connection
// identity. Called from worldCreate (startup) and from the settings menu
// (Apply & Reconnect, wrapped in with(world) so the world instance owns them).
//
// IMPORTANT: @name/@password/@selfGameID/@hasPassword/@accBaseGameID are NOT
// declared globalvar here. In GameMaker 8 globalvar is a game-wide binding, not
// a script-local one: declaring them would hijack the world instance's own
// variables for the rest of the game (the NAME packet then goes out with an
// empty game id). A script without the declaration writes the CALLER's
// variables, which is exactly the intent.
// args: none -> 0
@name = global.__ONLINE_accName;
if(@name == "") @name = "Anonymous";
@name = @account_clean(@name);
@password = string_copy(global.__ONLINE_accPassword, 1, 20);
@selfGameID = @accBaseGameID;
@selfGameID += @password;
@hasPassword = 0;
if(string_length(string(@password)) > 0) @hasPassword = 1;
return 0;

///// script @account_clean
// Trims, escapes and truncates a name to the startup dialog's rules.
// args: raw name -> cleaned name (<= 20 chars, '#' escaped)
var _n;
_n = @account_trim(argument0);
if(string_length(_n) > 20) _n = string_copy(_n, 1, 20);
_n = string_replace_all(_n, "#", "\#");
return _n;

///// script @account_trim
// GM8.0 has no string_trim; strip spaces/tabs/CR from both ends.
// args: str -> trimmed str
var _s, _i, _n, _c;
_s = argument0;
_n = string_length(_s);
_i = 1;
while(_i <= _n){
  _c = ord(string_char_at(_s, _i));
  if(_c == 32 || _c == 9 || _c == 13 || _c == 10) _i += 1; else break;
}
_s = string_delete(_s, 1, _i - 1);
_n = string_length(_s);
_i = _n;
while(_i >= 1){
  _c = ord(string_char_at(_s, _i));
  if(_c == 32 || _c == 9 || _c == 13 || _c == 10) _i -= 1; else break;
}
if(_i < _n) _s = string_delete(_s, _i + 1, _n - _i);
return _s;

///// script @account_lower
// ASCII lowercase (GM8.0 has no string_lower; the config keys are ASCII).
// args: str -> lowercased str
var _s, _i, _n, _c, _o;
_s = argument0;
_n = string_length(_s);
_o = "";
_i = 1;
while(_i <= _n){
  _c = ord(string_char_at(_s, _i));
  if(_c >= 65 && _c <= 90) _c += 32;
  _o += chr(_c);
  _i += 1;
}
return _o;

///// script @account_set_store
// Switches where account edits are written. Copies the values to the new target
// first so switching can never lose data, then drops the stale P2 file when
// moving back to global. args: 0 = global, 1 = this folder -> 1/0 (write result)
var _target, _ok, _prev;
if(global.__ONLINE_accEnvManaged) return 0;
_target = argument0;
if(_target == global.__ONLINE_accStore) return 1;
@account_paths();
_prev = global.__ONLINE_accStore;
global.__ONLINE_accStore = _target;
_ok = @account_save();
if(!_ok){
  // the write failed - keep pointing at the store that still has the values
  global.__ONLINE_accStore = _prev;
  return 0;
}
if(_ok && _target == 0){
  // values now live in the global file; the local override must not shadow it
  if(file_exists(global.__ONLINE_accLocalPath)) file_delete(global.__ONLINE_accLocalPath);
}
if(_ok){
  if(_target == 1) global.__ONLINE_accSource = 2; else global.__ONLINE_accSource = 3;
}
return _ok;

///// script @account_source_label
// Short badge for the menu: where the current values come from.
// args: none -> "Environment" / "This folder" / "Global" / "(not set)"
if(global.__ONLINE_accEnvManaged) return "Environment";
if(global.__ONLINE_accSource == 2) return "This folder";
if(global.__ONLINE_accSource == 3) return "Global";
if(global.__ONLINE_accSource == 1) return "Environment";
return "(not set)";

///// script @account_store_label
// Menu text for the "Store in" row.
// args: none -> "Global" / "This folder" / "Environment"
if(global.__ONLINE_accEnvManaged) return @L(global.__ONLINE_LK_ACCOUNT_STORE_ENV, "Environment");
if(global.__ONLINE_accStore == 1) return @L(global.__ONLINE_LK_ACCOUNT_STORE_FOLDER, "This folder");
return @L(global.__ONLINE_LK_ACCOUNT_STORE_GLOBAL, "Global");
