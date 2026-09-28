/// ONLINE
// ============================================================================
// langLib.gml - UI localization (PROPOSAL_i18n.md v3).
//
//   global.__ONLINE_Lang[i]     string table; "" means "no translation" and @L
//                               falls back to the English literal at the call
//                               site (there is no en.ini - the code IS English)
//   global.__ONLINE_LangKey[i]  key registry: table index <-> ini section name.
//                               A UI string gets the next free index and a
//                               namespaced name here BEFORE its call sites
//                               switch to @L(idx, "...")
//   global.__ONLINE_LK_*        index constants, so call sites read
//                               @L(global.__ONLINE_LK_TAB_SKINS, "Skins")
//                               instead of a magic number
//   global.__ONLINE_lang        active language code (built-in default zh-CN,
//                               "en" = no file load), [config] lang= overrides
//
// Files: lang/<code>.ini next to the exe (UTF-8). GM8.0 reads the converter-
// generated GBK copy lang/<code>.gbk.ini instead - its strings are byte
// strings and the CJK atlas/FoxWriting are keyed by GBK bytes, so the copy is
// GBK on EVERY machine, not the player's local codepage.
//
// Format:
//   [meta]  name = <display name>   (shown by the Language row, P4)
//   [<key>] text = <translation>    (hash= lines are for the converter-side
//                                    staleness check, the runtime ignores them)
// Do not use '#' in translations: GM draws it as a line break.
// ============================================================================

///// script @lang_init
// Rebuilds the table. Called from worldCreate on EVERY create, because
// game_restart wipes globals (same discipline as @stg_init).
// args: none -> 0
var _i;
global.__ONLINE_LangCap = 1024;
// --- key registry: index <-> ini section. Append-only; never renumber.
global.__ONLINE_LK_TAB_SETTINGS = 0;
global.__ONLINE_LK_TAB_SAVES = 1;
global.__ONLINE_LK_TAB_RATING = 2;
global.__ONLINE_LK_TAB_KEYS = 3;
global.__ONLINE_LK_TAB_SYNC = 4;
global.__ONLINE_LK_TAB_SKINS = 5;
global.__ONLINE_LK_CLOSE = 6;
global.__ONLINE_LK_HINT_FALLBACK = 7;
global.__ONLINE_LangKey[0] = "menu.tab.settings";
global.__ONLINE_LangKey[1] = "menu.tab.saves";
global.__ONLINE_LangKey[2] = "menu.tab.rating";
global.__ONLINE_LangKey[3] = "menu.tab.keys";
global.__ONLINE_LangKey[4] = "menu.tab.sync";
global.__ONLINE_LangKey[5] = "menu.tab.skins";
global.__ONLINE_LangKey[6] = "menu.close";
global.__ONLINE_LangKey[7] = "menu.hint.fallback";
global.__ONLINE_LangCount = 8;
// every slot pre-initialised: on GMS, reading an array slot that was never
// written aborts the event (GML_COMPAT.md section 1)
for(_i = 0; _i < global.__ONLINE_LangCap; _i += 1) global.__ONLINE_Lang[_i] = "";
global.__ONLINE_lang = "zh-CN";   // built-in default; [config] lang= overrides
global.__ONLINE_LangName = "";    // display name from the file's [meta] section
return 0;

///// script @L
// The lookup every UI string goes through. The English fallback lives at the
// call site, so a missing file or key can never blank the interface.
// args: keyIndex, englishFallback -> text
var _t;
_t = "";
if(argument0 >= 0 && argument0 < global.__ONLINE_LangCap) _t = global.__ONLINE_Lang[argument0];
if(_t == "") return argument1;
return _t;

///// script @lang_load
// Loads lang/<code>.ini into the table. A missing file or unknown keys are
// fine - @L simply falls back. Returns the number of keys applied.
// args: code -> count
var _code, _path, _txt, _rest, _line, _cut, _sec, _lp, _k, _v, _i, _n, _f;
_code = argument0;
_n = 0;
if(_code == "" || _code == "en") return 0;
// GM8.0 strings are byte strings and the CJK renderer is keyed by GBK bytes, so
// it reads the converter-generated GBK copy; everything else reads the UTF-8
// original.
#if GM80
_path = @cfgDir + "lang" + chr(92) + _code + ".gbk.ini";
#endif
#if not GM80
_path = @cfgDir + "lang" + chr(92) + _code + ".ini";
#endif
_txt = "";
#if STUDIO
// the engine file functions cannot leave the save area on GMS; the native API
// can (same route as @account_ini_read), and it returns "" when unreadable
_txt = @account_native_read(_path);
#endif
#if not STUDIO
if(file_exists(_path)){
  _f = file_text_open_read(_path);
  if(_f >= 0){
    while(!file_text_eof(_f)){
      _txt += file_text_read_string(_f) + chr(10);
      file_text_readln(_f);
    }
    file_text_close(_f);
  }
}
#endif
if(_txt == "") return 0;
// a BOM from a user-edited file must not poison the first line
if(string_copy(_txt, 1, 3) == chr(239) + chr(187) + chr(191)) _txt = string_delete(_txt, 1, 3);
_sec = "";
_rest = _txt;
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
  if(string_length(_line) == 0) continue;
  if(string_copy(_line, 1, 1) == ";") continue;
  if(string_copy(_line, 1, 1) == "["){
    _sec = string_copy(_line, 2, string_length(_line) - 2);
    continue;
  }
  _lp = string_pos("=", _line);
  if(_lp <= 1) continue;
  _k = @account_trim(string_copy(_line, 1, _lp - 1));
  _v = @account_trim(string_copy(_line, _lp + 1, string_length(_line) - _lp));
  if(_sec == "meta"){
    if(_k == "name") global.__ONLINE_LangName = _v;
    continue;
  }
  if(_k != "text") continue;
  // linear scan over the registry: a few hundred keys, once per load
  for(_i = 0; _i < global.__ONLINE_LangCount; _i += 1){
    if(global.__ONLINE_LangKey[_i] == _sec){
      global.__ONLINE_Lang[_i] = _v;
      _n += 1;
      break;
    }
  }
}
return _n;
