/// ONLINE
// ============================================================================
// Account store: name + session key persistence.
//
// Why this exists: the startup dialogs (name / password / RACE) used to run on
// every launch, and nothing was ever written to disk - tempOnline only carries
// state across room changes and game_restart within one process. Players type
// the same two values forever; testers have to retype them per client.
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
// @account_apply), matching the previous behaviour.
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
// args: none -> 0
var _appdata;
global.__ONLINE_accGlobalDir = "";
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
global.__ONLINE_accLocalPath = @account_dir(program_directory) + "__ONLINE_account.ini";
return 0;

///// script @account_ini_read
// Parses argument0 and fills the account globals. argument1 = 1 when this is the
// global file (its "store" key is honoured; a local file always means local).
// Returns 1 when a usable (non-empty) name was found, else 0.
//
// Name/password are stored twice: a generic "name"/"password" pair and an
// engine-tagged pair (name_gbk/password_gbk on GM8.0, name_utf8/password_utf8
// elsewhere). One global file can therefore serve both a GM8.0 install (ANSI
// strings) and a GM8.1+/GMS install (UTF-8 strings) without the CJK names
// turning into mojibake; the tagged key wins, the generic one is the fallback
// written for compatibility.
// args: path, isGlobal -> 1/0
var _f, _line, _lp, _key, _val, _inSec, _found, _storeVal;
var _genName, _genPass, _tagName, _tagPass;
_found = 0;
_storeVal = -1;
_genName = "";
_genPass = "";
_tagName = "";
_tagPass = "";
if(!file_exists(argument0)) return 0;
_f = file_text_open_read(argument0);
if(_f < 0) return 0;
_inSec = 0;
global.__ONLINE_accName = "";
global.__ONLINE_accPassword = "";
while(!file_text_eof(_f)){
  _line = file_text_read_string(_f);
  file_text_readln(_f);
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
file_text_close(_f);
if(_tagName != ""){
  global.__ONLINE_accName = _tagName;
  global.__ONLINE_accPassword = _tagPass;
}else{
  global.__ONLINE_accName = _genName;
  global.__ONLINE_accPassword = _genPass;
}
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

///// script @account_save
// Writes the current values to the active store target.
// args: none -> 1 on success, 0 on failure (caller shows the red hint and may
// offer "Store in: This folder" as a fallback)
var _path, _f, _store, _tag;
// self-sufficient: never depend on @account_load having run (a tempOnline
// restore skips it, and an undefined path global used to abort the save).
@account_paths();
if(global.__ONLINE_accStore == 1) _path = global.__ONLINE_accLocalPath; else _path = global.__ONLINE_accGlobalPath;
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
file_text_write_string(_f, "[account]");
file_text_writeln(_f);
// Generic pair first (readable by any engine / older builds), then the
// engine-tagged pair that wins on read (see @account_ini_read).
file_text_write_string(_f, "name=" + global.__ONLINE_accName);
file_text_writeln(_f);
file_text_write_string(_f, "password=" + global.__ONLINE_accPassword);
file_text_writeln(_f);
// NOTE: no #else here - the GM8 render pipeline (getGMLCode.parseGML) only
// understands #if / #if not / #endif, so an #else would survive into the game
// code and fail to compile.
_tag = "";
#if GM80
_tag = "_gbk";
#endif
#if not GM80
_tag = "_utf8";
#endif
file_text_write_string(_f, "name" + _tag + "=" + global.__ONLINE_accName);
file_text_writeln(_f);
file_text_write_string(_f, "password" + _tag + "=" + global.__ONLINE_accPassword);
file_text_writeln(_f);
if(global.__ONLINE_accStore == 1) _store = "local"; else _store = "global";
file_text_write_string(_f, "store=" + _store);
file_text_writeln(_f);
file_text_close(_f);
return 1;

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
  return 1;
}
return 0;

///// script @account_apply
// Single source of truth: pushes the stored values into the live connection
// identity. Called from worldCreate (startup) and from the settings menu
// (Apply & Reconnect, wrapped in with(world) so the world instance owns them).
//
// IMPORTANT: @name/@password/@selfGameID/@hasPassword/@accBaseGameID are NOT
// declared globalvar here. In GameMaker 8 globalvar is a game-wide binding, not
// a script-local one: declaring them would hijack the world instance's own
// variables for the rest of the game (the NAME packet then went out with an
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
// Trims, escapes and truncates a name exactly like the old startup dialog did.
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
if(global.__ONLINE_accEnvManaged) return "Environment";
if(global.__ONLINE_accStore == 1) return "This folder";
return "Global";
