using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Underanalyzer.Decompiler;
using UndertaleModLib;
using UndertaleModLib.Compiler;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Models;
using UndertaleModLib.Util;

namespace ConverterGMS;

sealed class ConverterConfig
{
    public string GameId { get; set; }
    public string Server { get; set; }
    public int TcpPort { get; set; }
    public int UdpPort { get; set; }
    public string GameName { get; set; }
    public string Version { get; set; }
    public string GmlDirectory { get; set; }
    public string ResourceDirectory { get; set; }
    public bool UseX64NativeHttpDll { get; set; }
    public string SuccessMarkerPath { get; set; }
    // iwpo.* define overrides (nullable; absent in older config files).
    public Dictionary<string, string> Defines { get; set; }
}

sealed class SharedSavePatch
{
    public UndertaleCode SaveCodeToAppend { get; set; }
    public string SaveAppendCode { get; set; }
    public UndertaleCode LoadCodeToAppend { get; set; }
    public string LoadAppendCode { get; set; }
    public UndertaleCode RootCodeToReplace { get; set; }
    public string RootReplacementCode { get; set; }
}

sealed class ParseResult
{
    public ParseResult(List<string> lines, int linesRead)
    {
        Lines = lines;
        LinesRead = linesRead;
    }
    public List<string> Lines { get; }
    public int LinesRead { get; }
}

static class Program
{
    const string Prefix = "__ONLINE_";

    static UndertaleData Data;
    static ConverterConfig Config;

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: converterGMS2 <input.win> <output.win> <config.json>");
            return 1;
        }

        var input = args[0];
        var output = args[1];
        var configPath = args.Length >= 3 ? args[2] : Path.Combine(Path.GetDirectoryName(input) ?? string.Empty, "__ONLINE_utmt_config.json");

        if (!File.Exists(input))
        {
            Console.Error.WriteLine($"Input file not found: {input}");
            return 1;
        }
        if (!File.Exists(configPath))
        {
            Console.Error.WriteLine($"Config file not found: {configPath}");
            return 1;
        }

        Config = JsonConvert.DeserializeObject<ConverterConfig>(File.ReadAllText(configPath));
        if (Config is null)
        {
            Console.Error.WriteLine("Failed to parse the converter config.");
            return 1;
        }

        try
        {
            Console.WriteLine("Reading data.win...");
            using (var stream = new FileStream(input, FileMode.Open, FileAccess.Read, FileShare.Read))
                Data = UndertaleIO.Read(stream);

            Convert();

            Console.WriteLine("Writing data.win...");
            using (var stream = new FileStream(output, FileMode.Create, FileAccess.Write))
                UndertaleIO.Write(stream, Data);

            if (!string.IsNullOrWhiteSpace(Config.SuccessMarkerPath))
                File.WriteAllText(Config.SuccessMarkerPath, "ok");

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    static void Convert()
    {
        if (Data.IsYYC())
            throw new Exception("YYC games are not supported by IWPO.");

        if (Data.GameObjects.ByName(Prefix + "onlinePlayer") != null)
            throw new Exception("This game is already an online version.");

        var world = FindObjectInteractive("world object", "iwpo.world", "world", "World", "objWorld", "oWorld");
        var player = FindObjectInteractive("player object", "iwpo.player", "player", "Player", "objPlayer", "oPlayer", "objplayer");
        var player2 = FindObject("player2", "objPlayer2", "oPlayer2");
        var saveGame = FindScriptInteractive("save script", "iwpo.saveGame", "save_save", "savegame", "saveGame", "savedata_save", "scrSaveGame", "SaveGame");
        var loadGame = FindScriptInteractive("load script", "iwpo.loadGame", "save_load", "loadgame", "loadGame", "savedata_load", "scrLoadGame", "LoadGame");

        if (saveGame?.Code is null)
            throw new Exception("Unable to find the save script.");
        if (loadGame?.Code is null)
            throw new Exception("Unable to find the load script.");

        // Build active flags
        // Note: TEMPFILE is intentionally NOT set for GMS — the world object persists
        // through room_goto() so temp files are unnecessary (unlike GM8 which uses game_restart()).
        var activeFlags = new HashSet<string>(StringComparer.Ordinal) { "STUDIO", "GMSND" };

        if ((Data.GeneralInfo?.Major ?? 0) >= 2)
            activeFlags.Add("GMS2");

        if (player2 != null)
            activeFlags.Add("PLAYER2");

        if (Data.Variables.Any(v => v?.Name?.Content == "player_xscale"))
            activeFlags.Add("GLOBAL_PLAYER_XSCALE");

        // C4: GMS errors at runtime when reading a variable that was never
        // defined (unlike GM8, where the modder treats undefined vars as 0), so
        // templates must only reference global.grav when it provably exists.
        if (Data.Variables.Any(v => v?.Name?.Content == "grav" && v.InstanceType == UndertaleInstruction.InstanceType.Global))
            activeFlags.Add("GRAVITY");

        // Facing variable: only trust a variable the player's own Create event
        // actually references; anything else would crash at broadcast time.
        var createVars = FindEventCode(player, EventType.Create)?.FindReferencedVars();
        bool CreateRefs(string name) => createVars != null && createVars.Any(v => v?.Name?.Content == name);

        if (CreateRefs("xScale"))
            activeFlags.Add("PLAYER_XSCALE");

        if (CreateRefs("xscale"))
            activeFlags.Add("PLAYER_XSCALE_LOWER");

        if (CreateRefs("facing"))
            activeFlags.Add("PLAYER_FACING");

        Console.WriteLine($"Gravity flag: {activeFlags.Contains("GRAVITY")}; facing: " +
            (activeFlags.Contains("PLAYER_XSCALE") ? "xScale" :
             activeFlags.Contains("PLAYER_XSCALE_LOWER") ? "xscale" :
             activeFlags.Contains("PLAYER_FACING") ? "facing" :
             activeFlags.Contains("GLOBAL_PLAYER_XSCALE") ? "global.player_xscale" : "none (bare image_xscale)"));

        if (Data.Scripts.ByName("scrFlipGrav") != null)
            activeFlags.Add("SCR_FLIP_GRAV");

        // The skin system (script assets + player draw injection + sprite mapping)
        // can be turned off entirely via the iwpo.no_skins define.
        var skinsEnabled = !GetDefineFlag("iwpo.no_skins");

        // Build shared save patch
        var player2Name = player2?.Name?.Content ?? string.Empty;
        var saveGameHookCode = RenderTemplate(activeFlags, "saveGame", world.Name.Content, player.Name.Content, player2Name);
        var loadGameHookCode = string.Join("\r\n",
            RenderTemplate(activeFlags, "saveGame2", world.Name.Content, player.Name.Content, player2Name),
            RenderTemplate(activeFlags, "loadGame", world.Name.Content, player.Name.Content, player2Name));
        var sharedSavePatch = BuildSharedSavePatch(saveGame, saveGameHookCode, loadGame, loadGameHookCode);
        var sharedSaveSupported = sharedSavePatch != null;
        if (!sharedSaveSupported)
            Console.WriteLine("Shared save hooks: disabled (scripts could not be decompiled)");

        // Add extension. P2: probe the shipped http_dll binary for the md5_dir
        // export (architecture-independent PE export-table walk) - only then the
        // native package-hash fast path (hmd5_dir native + MD5DIR template flag)
        // is enabled; otherwise the pure-GML walk stays.
        var md5DirAvailable = DllExportsFunction(
            Path.Combine(Config.ResourceDirectory, Config.UseX64NativeHttpDll ? "http_dll_2_3_x64.dll" : "http_dll_2_3.dll"),
            "md5_dir");
        if (md5DirAvailable)
        {
            activeFlags.Add("MD5DIR");
            Console.WriteLine("HTTP DLL md5_dir export: available (native package hash fast path)");
        }
        else
        {
            Console.WriteLine("HTTP DLL md5_dir export: missing (pure-GML hash fallback)");
        }
        if (Config.UseX64NativeHttpDll)
        {
            AddNativeX64ExtensionIfMissing(md5DirAvailable);
        }
        else
        {
            AddExtensionIfMissing(Path.Combine(Config.ResourceDirectory, "http_dll"));
            // Add set_utf8_mode + md5_dir to x86 extension (not in the binary definition file)
            AddSetUtf8ModeToExtension(md5DirAvailable);
        }

        // Add sounds
        AddSoundIfMissing(Path.Combine(Config.ResourceDirectory, "sound_chatbox"));
        AddSoundIfMissing(Path.Combine(Config.ResourceDirectory, "sound_saved"));

        // Find a suitable small font for the online UI
        var onlineFontIndex = FindBestFontIndex();
        Console.WriteLine($"Online UI font index: {onlineFontIndex}");

        // Embed CJK font for Chinese text support (font_add is broken in GMS1.4)
        var cjkFontIndex = EmbedCjkFont();
        if (cjkFontIndex >= 0)
            onlineFontIndex = cjkFontIndex;

        // Create objects
        var onlinePlayer = CreateObject(Prefix + "onlinePlayer", false, -10, true);
        var chatbox = CreateObject(Prefix + "chatbox", true, -11, true);
        var playerSaved = CreateObject(Prefix + "playerSaved", true, -10, false);
        var ui = CreateObject(Prefix + "userInterface", true, -2147483648, true);
        // S4: bullet-sharing proxy object. Sprite/depth/mask are copied from the
        // game's bullet object at convert time (static), so @bullet_init only
        // creates the registry map. The proxy is created unconditionally; it
        // stays inert (no instances) when no bullet object was resolved.
        // With iwpo.no_skins the whole feature is off: no resolution, and the
        // constants below are emitted as -1/-1 (matching the GM8 converter).
        var bulletSourceObj = skinsEnabled ? ResolveBulletObject() : null;
        var bulletProxy = CreateObject(Prefix + "bullet", true, bulletSourceObj?.Depth ?? 0, false);
        if (bulletSourceObj != null)
        {
            bulletProxy.Sprite = bulletSourceObj.Sprite;
            bulletProxy.TextureMaskId = bulletSourceObj.TextureMaskId;
        }
        Data.GameObjects.Add(onlinePlayer);
        Data.GameObjects.Add(chatbox);
        Data.GameObjects.Add(playerSaved);
        Data.GameObjects.Add(ui);
        Data.GameObjects.Add(bulletProxy);

        // Compile and import GML
        var importGroup = new CodeImportGroup(Data) { AutoCreateAssets = false };

        var worldCreateCode = RenderTemplate(activeFlags, "worldCreateGMS", Config.GameId, Config.Server,
                Config.TcpPort.ToString(), Config.UdpPort.ToString(), Config.GameName,
                Config.Version, sharedSaveSupported ? "1" : "0", onlineFontIndex.ToString());
        // The map slots are always assigned and run before the template body so
        // the skin library can rely on them at Create time: the real mapping when
        // skins are enabled, defaults -1/0 otherwise (the menu preview reads the
        // slots even with iwpo.no_skins, so they must never be uninitialised).
        // S4: the bullet-sharing constants are emitted the same way (ALWAYS
        // assigned, -1/-1 disables sharing: GMS errors on reading an unassigned
        // global and GM8 would read 0). Prepended BEFORE the template body so
        // @bullet_init (called inside worldCreateGMS) reads the real values.
        worldCreateCode = (skinsEnabled ? BuildSpriteMapCode() : BuildSpriteMapDefaultsCode())
            + "\r\n" + (skinsEnabled ? BuildBulletMapCode(bulletSourceObj) : "// Bullet sharing (skins disabled)\r\nglobal.__ONLINE_bulletObj = -1; global.__ONLINE_bulletSpr = -1;")
            + "\r\n" + $"global.__ONLINE_md5DirOk = {(md5DirAvailable ? 1 : 0)};\r\n"
            + "\r\n" + worldCreateCode;
        importGroup.QueueAppend(
            world.EventHandlerFor(EventType.Create, Data),
            worldCreateCode);

        var worldEndStepCode = RenderWorldEndStep(activeFlags, sharedSaveSupported, player.Name.Content, player2Name);
        importGroup.QueueAppend(
            world.EventHandlerFor(EventType.Step, EventSubtypeStep.EndStep, Data),
            worldEndStepCode);

        var drawCode = RenderTemplate(activeFlags, "worldDraw");
        var wrappedDraw = $"if(instance_exists({world.Name.Content})){{\nwith(instance_find({world.Name.Content}, 0)){{\n{drawCode}\n}}\n}}";
        importGroup.QueueReplace(
            ui.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
            wrappedDraw);

        var worldGameEndCode = RenderTemplate(activeFlags, "worldGameEnd");
        importGroup.QueueAppend(
            world.EventHandlerFor(EventType.Other, EventSubtypeOther.GameEnd, Data),
            worldGameEndCode);

        importGroup.QueueReplace(
            onlinePlayer.EventHandlerFor(EventType.Create, Data),
            RenderTemplate(activeFlags, "onlinePlayerCreate"));
        importGroup.QueueReplace(
            onlinePlayer.EventHandlerFor(EventType.Step, EventSubtypeStep.EndStep, Data),
            RenderTemplate(activeFlags, "onlinePlayerEndStep", player.Name.Content, player2Name, world.Name.Content));
        importGroup.QueueReplace(
            onlinePlayer.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
            RenderTemplate(activeFlags, "onlinePlayerDraw", world.Name.Content));

        importGroup.QueueReplace(
            chatbox.EventHandlerFor(EventType.Create, Data),
            RenderTemplate(activeFlags, "chatboxCreate"));
        importGroup.QueueReplace(
            chatbox.EventHandlerFor(EventType.Step, EventSubtypeStep.EndStep, Data),
            RenderTemplate(activeFlags, "chatboxEndStep", player.Name.Content, player2Name, world.Name.Content));
        importGroup.QueueReplace(
            chatbox.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
            RenderTemplate(activeFlags, "chatboxDraw"));

        importGroup.QueueReplace(
            playerSaved.EventHandlerFor(EventType.Create, Data),
            RenderTemplate(activeFlags, "playerSavedCreate"));
        importGroup.QueueReplace(
            playerSaved.EventHandlerFor(EventType.Step, EventSubtypeStep.EndStep, Data),
            RenderTemplate(activeFlags, "playerSavedEndStep"));
        importGroup.QueueReplace(
            playerSaved.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
            RenderTemplate(activeFlags, "playerSavedDraw"));

        // S4: bullet-sharing proxy events. The hit action is the raw
        // iwpo.bullet.hit code (empty = no collision action).
        importGroup.QueueReplace(
            bulletProxy.EventHandlerFor(EventType.Create, Data),
            RenderTemplate(activeFlags, "bulletShareCreate"));
        importGroup.QueueReplace(
            bulletProxy.EventHandlerFor(EventType.Step, EventSubtypeStep.EndStep, Data),
            RenderTemplate(activeFlags, "bulletShareEndStep", player.Name.Content, player2Name, GetDefine("iwpo.bullet.hit") ?? ""));
        importGroup.QueueReplace(
            bulletProxy.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
            RenderTemplate(activeFlags, "bulletShareDraw", world.Name.Content));

        // S4 local-bullet re-skin: give the GAME's bullet object a Draw event
        // so the local player's own bullets render the selected skin's
        // bullet.png. Only when the object had no Draw event (the injected
        // template redraws the native sprite as its fallback, since adding a
        // Draw event suppresses the engine's automatic sprite draw). Objects
        // that already draw themselves keep their custom draw.
        if (bulletSourceObj != null && FindEventCode(bulletSourceObj, EventType.Draw) == null)
        {
            importGroup.QueueReplace(
                bulletSourceObj.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data),
                RenderTemplate(activeFlags, "bulletSelfDraw"));
            Console.WriteLine($"Bullet sharing: local bullet re-skin Draw injected on {bulletSourceObj.Name.Content}");
        }
        else if (bulletSourceObj != null)
        {
            Console.WriteLine($"Bullet sharing: {bulletSourceObj.Name.Content} has its own Draw event; local bullet re-skin skipped");
        }

        if (sharedSaveSupported)
            QueueSharedSavePatch(importGroup, sharedSavePatch);

        // Skin system: script assets (md5, skinLib) are injected unconditionally —
        // worldCreate/worldEndStep call them in every converted game, so the assets
        // must exist even with iwpo.no_skins (they stay inert without an iwposkins
        // folder). Player Draw injection and the sprite map stay gated.
        InjectSkinScriptAssets(importGroup, activeFlags);
        if (skinsEnabled)
        {
            InjectPlayerDrawEvents(importGroup, activeFlags, player, player2);
        }
        else
        {
            Console.WriteLine("Skin player draw injection: disabled via iwpo.no_skins");
        }

        Console.WriteLine("Compiling GML...");
        importGroup.Import();
    }

    // --- Asset lookup ---

    static UndertaleGameObject FindObject(params string[] names)
    {
        return Data.GameObjects.FirstOrDefault(obj => NameMatches(obj?.Name?.Content, names));
    }

    // Finds an existing event's code entry without creating one (unlike EventHandlerFor).
    static UndertaleCode FindEventCode(UndertaleGameObject obj, EventType type, uint subtype = 0)
    {
        foreach (var ev in obj.Events[(int)type])
        {
            if (ev.EventSubtype != subtype) continue;
            var action = ev.Actions.FirstOrDefault();
            if (action?.CodeId is UndertaleCode code) return code;
        }
        return null;
    }

    static UndertaleScript FindScript(params string[] names)
    {
        return Data.Scripts.FirstOrDefault(script => NameMatches(script?.Name?.Content, names));
    }

    static UndertaleGameObject FindObjectInteractive(string typeName, string defineKey, params string[] names)
    {
        var defineValue = GetDefine(defineKey);
        if (defineValue != null)
        {
            // A define always wins over the candidate table and skips the interactive
            // prompt (mirrors the GM8 converter's findAssetInteractive define handling).
            var defineResult = FindObject(defineValue);
            if (defineResult != null) return defineResult;
            throw new Exception($"No {typeName} named '{defineValue}' (from {defineKey}) found.");
        }
        var result = FindObject(names);
        if (result != null) return result;
        if (!Console.IsInputRedirected)
        {
            var items = Data.GameObjects.Where(o => o?.Name?.Content != null).ToList();
            if (items.Count > 0)
            {
                Console.WriteLine($"\nCould not find {typeName} (tried: {string.Join(", ", names)})");
                Console.Write($"Would you like to select from {items.Count} available objects? (y/n): ");
                var confirm = Console.ReadLine()?.Trim().ToLower();
                if (confirm == "y")
                {
                    for (int i = 0; i < items.Count; i++)
                        Console.WriteLine($"  {i + 1}. {items[i].Name.Content}");
                    Console.Write($"Select {typeName} by number (or 0 to cancel): ");
                    if (int.TryParse(Console.ReadLine(), out int idx) && idx >= 1 && idx <= items.Count)
                        return items[idx - 1];
                }
            }
        }
        throw new Exception($"Unable to find the {typeName}.");
    }

    static UndertaleScript FindScriptInteractive(string typeName, string defineKey, params string[] names)
    {
        var defineValue = GetDefine(defineKey);
        if (defineValue != null)
        {
            // A define always wins over the candidate table and skips the interactive
            // prompt (mirrors the GM8 converter's findAssetInteractive define handling).
            var defineResult = FindScript(defineValue);
            if (defineResult != null) return defineResult;
            throw new Exception($"No {typeName} named '{defineValue}' (from {defineKey}) found.");
        }
        var result = FindScript(names);
        if (result != null) return result;
        if (!Console.IsInputRedirected)
        {
            var items = Data.Scripts.Where(s => s?.Name?.Content != null).ToList();
            if (items.Count > 0)
            {
                Console.WriteLine($"\nCould not find {typeName} (tried: {string.Join(", ", names)})");
                Console.Write($"Would you like to select from {items.Count} available scripts? (y/n): ");
                var confirm = Console.ReadLine()?.Trim().ToLower();
                if (confirm == "y")
                {
                    for (int i = 0; i < items.Count; i++)
                        Console.WriteLine($"  {i + 1}. {items[i].Name.Content}");
                    Console.Write($"Select {typeName} by number (or 0 to cancel): ");
                    if (int.TryParse(Console.ReadLine(), out int idx) && idx >= 1 && idx <= items.Count)
                        return items[idx - 1];
                }
            }
        }
        throw new Exception($"Unable to find the {typeName}.");
    }

    static bool NameMatches(string actualName, params string[] candidates)
    {
        if (string.IsNullOrWhiteSpace(actualName))
            return false;
        var normalizedActual = NormalizeAssetName(actualName);
        foreach (var candidate in candidates)
        {
            if (string.IsNullOrWhiteSpace(candidate))
                continue;
            if (string.Equals(actualName, candidate, StringComparison.OrdinalIgnoreCase))
                return true;
            if (string.Equals(normalizedActual, NormalizeAssetName(candidate), StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    static string NormalizeAssetName(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return string.Empty;
        const string ScriptPrefix = "gml_Script_";
        if (name.StartsWith(ScriptPrefix, StringComparison.OrdinalIgnoreCase))
            return name.Substring(ScriptPrefix.Length);
        return name;
    }

    // --- Object / Extension / Sound creation ---

    static UndertaleGameObject CreateObject(string name, bool visible, int depth, bool persistent)
    {
        return new UndertaleGameObject()
        {
            Name = Data.Strings.MakeString(name),
            Visible = visible,
            Depth = depth,
            Persistent = persistent,
            Awake = true,
        };
    }

    static void AddExtensionIfMissing(string path)
    {
        var extension = LoadExtension(path);
        if (Data.Extensions.ByName(extension.Name.Content) != null)
            return;
        Data.Extensions.Add(extension);
        AddExtensionProductIdIfEligible();
    }

    static void AddNativeX64ExtensionIfMissing(bool md5DirAvailable)
    {
        if (Data.Extensions.ByName("Http Dll 2.3") != null)
            return;

        var extension = new UndertaleExtension()
        {
            Name = Data.Strings.MakeString("Http Dll 2.3"),
            ClassName = Data.Strings.MakeString(string.Empty),
            FolderName = Data.Strings.MakeString(string.Empty),
            Version = Data.Strings.MakeString(string.Empty),
        };
        var file = new UndertaleExtensionFile()
        {
            Filename = Data.Strings.MakeString("http_dll_2_3.dll"),
            Kind = UndertaleExtensionKind.Dll,
            InitScript = Data.Strings.MakeString(string.Empty),
            CleanupScript = Data.Strings.MakeString(string.Empty),
        };
        extension.Files.Add(file);

        uint functionId = 1;
        DefineNative(file, ref functionId, "hbuffer_create", "buffer_create", UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_destroy", "buffer_destroy", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_clear", "buffer_clear", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_from_file", "buffer_read_from_file", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.String);
        DefineNative(file, ref functionId, "hbuffer_write_to_file", "buffer_write_to_file", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.String);
        DefineNative(file, ref functionId, "hbuffer_read_uint8", "buffer_read_uint8", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_uint16", "buffer_read_uint16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_int16", "buffer_read_int16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_int32", "buffer_read_int32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_uint32", "buffer_read_uint32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_uint64", "buffer_read_uint64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_float32", "buffer_read_float32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_float64", "buffer_read_float64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_string", "buffer_read_string", UndertaleExtensionVarType.String, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint8", "buffer_write_uint8", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint16", "buffer_write_uint16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_int16", "buffer_write_int16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_int32", "buffer_write_int32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint32", "buffer_write_uint32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint64", "buffer_write_uint64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_float32", "buffer_write_float32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_float64", "buffer_write_float64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_string", "buffer_write_string", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.String);
        DefineNative(file, ref functionId, "socket_create", "socket_create", UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_destroy", "socket_destroy", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_get_state", "socket_get_state", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_reset", "socket_reset", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_connect", "socket_connect", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.String, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_update_read", "socket_update_read", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_update_write", "socket_update_write", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_read_message", "socket_read_message", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "socket_write_message", "socket_write_message", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_create", "udpsocket_create", UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_destroy", "udpsocket_destroy", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_exists", "udpsocket_exists", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_get_state", "udpsocket_get_state", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_start", "udpsocket_start", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_set_destination", "udpsocket_set_destination", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.String, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_receive", "udpsocket_receive", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "udpsocket_send", "udpsocket_send", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "set_utf8_mode", "set_utf8_mode", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "strip_non_bmp", "strip_non_bmp", UndertaleExtensionVarType.String, UndertaleExtensionVarType.String);
        if (md5DirAvailable)
            DefineNative(file, ref functionId, "hmd5_dir", "md5_dir", UndertaleExtensionVarType.String, UndertaleExtensionVarType.String);

        Data.Extensions.Add(extension);
        AddExtensionProductIdIfEligible();
    }

    static void AddSetUtf8ModeToExtension(bool md5DirAvailable)
    {
        var ext = Data.Extensions.ByName("Http Dll 2.3");
        if (ext == null || ext.Files.Count == 0)
            return;
        var file = ext.Files[0];
        // Use a high function ID to avoid collisions
        uint functionId = 200;
        DefineNative(file, ref functionId, "set_utf8_mode", "set_utf8_mode", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "strip_non_bmp", "strip_non_bmp", UndertaleExtensionVarType.String, UndertaleExtensionVarType.String);
        if (md5DirAvailable)
            DefineNative(file, ref functionId, "hmd5_dir", "md5_dir", UndertaleExtensionVarType.String, UndertaleExtensionVarType.String);
    }

    static void DefineNative(UndertaleExtensionFile file, ref uint functionId, string name, string extName, UndertaleExtensionVarType returnType, params UndertaleExtensionVarType[] arguments)
    {
        file.Functions.DefineExtensionFunction(Data.Functions, Data.Strings, functionId++, 0xC, name, returnType, extName, arguments);
    }

    // P2: architecture-independent check that a DLL binary exports the given
    // function (the x86 DLL cannot be LoadLibrary'd from this x64 process, so a
    // plain PE export-table walk is the reliable way). Returns false on any
    // parse trouble.
    static bool DllExportsFunction(string dllPath, string funcName)
    {
        try
        {
            var data = File.ReadAllBytes(dllPath);
            if (data.Length < 0x40 || data[0] != 'M' || data[1] != 'Z')
                return false;
            var peOff = BitConverter.ToInt32(data, 0x3C);
            if (peOff <= 0 || peOff + 24 > data.Length || data[peOff] != 'P' || data[peOff + 1] != 'E')
                return false;
            var numSections = BitConverter.ToUInt16(data, peOff + 6);
            var optSize = BitConverter.ToUInt16(data, peOff + 20);
            var optOff = peOff + 24;
            if (optOff + optSize > data.Length)
                return false;
            // 16-bit optional-header magic: 0x10B = PE32, 0x20B = PE32+. The
            // low byte alone is 0x0B for both, so read the full UInt16.
            var optMagic = BitConverter.ToUInt16(data, optOff);
            var pe32Plus = optMagic == 0x20B;
            var dataDirOff = optOff + (pe32Plus ? 112 : 96);
            if (dataDirOff + 4 > data.Length)
                return false;
            var exportRva = BitConverter.ToInt32(data, dataDirOff); // first dir = exports
            if (exportRva == 0)
                return false;
            var secOff = optOff + optSize;
            int va = 0, raw = 0;
            for (var s = 0; s < numSections; s++)
            {
                var sh = secOff + s * 40;
                if (sh + 40 > data.Length)
                    return false;
                var vsize = BitConverter.ToInt32(data, sh + 8);
                var vaddr = BitConverter.ToInt32(data, sh + 12);
                var rawsize = BitConverter.ToInt32(data, sh + 16);
                var rawptr = BitConverter.ToInt32(data, sh + 20);
                if (exportRva >= vaddr && exportRva < vaddr + Math.Max(vsize, rawsize))
                {
                    va = vaddr;
                    raw = rawptr;
                    break;
                }
            }
            if (raw == 0)
                return false;
            var expOff = exportRva - va + raw;
            if (expOff + 40 > data.Length)
                return false;
            var numNames = BitConverter.ToInt32(data, expOff + 24);
            var addrNames = BitConverter.ToInt32(data, expOff + 32);
            if (numNames <= 0 || numNames > 65536)
                return false;
            var namesOff = addrNames - va + raw;
            var funcBytes = System.Text.Encoding.ASCII.GetBytes(funcName);
            for (var n = 0; n < numNames; n++)
            {
                if (namesOff + 4 > data.Length)
                    return false;
                var nameRva = BitConverter.ToInt32(data, namesOff);
                namesOff += 4;
                var noff = nameRva - va + raw;
                if (noff <= 0 || noff >= data.Length)
                    continue;
                var len = 0;
                while (noff + len < data.Length && data[noff + len] != 0 && len < 256)
                    len++;
                if (len != funcBytes.Length)
                    continue;
                var eq = true;
                for (var k = 0; k < len; k++)
                    if (data[noff + k] != funcBytes[k]) { eq = false; break; }
                if (eq)
                    return true;
            }
            return false;
        }
        catch
        {
            return false;
        }
    }

    static void AddExtensionProductIdIfEligible()
    {
        if (IsProductDataEligible(Data) && Data.FORM?.EXTN != null)
        {
            var productId = new byte[] { 0xBA, 0x5E, 0xBA, 0x11, 0xBA, 0xDD, 0x06, 0x60, 0xBE, 0xEF, 0xED, 0xBA, 0x0B, 0xAB, 0xBA, 0xBE };
            Data.FORM.EXTN.productIdData.Add(productId);
        }
    }

    static bool IsProductDataEligible(UndertaleData data)
    {
        var major = data?.GeneralInfo?.Major ?? 0;
        if (major >= 2)
            return true;
        var build = data?.GeneralInfo?.Build ?? 0;
        return build >= 1773 || build == 1559;
    }

    static UndertaleExtension LoadExtension(string path)
    {
        var extension = new UndertaleExtension();
        using var reader = new BinaryReader(File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read));
        extension.Name = Data.Strings.MakeString(reader.ReadString());
        extension.ClassName = Data.Strings.MakeString(reader.ReadString());
        extension.FolderName = Data.Strings.MakeString(reader.ReadString());
        extension.Version = Data.Strings.MakeString(string.Empty);

        var fileCount = reader.ReadInt32();
        for (var i = 0; i < fileCount; i++)
        {
            var file = new UndertaleExtensionFile()
            {
                Filename = Data.Strings.MakeString(reader.ReadString()),
                Kind = (UndertaleExtensionKind)reader.ReadUInt32(),
                InitScript = Data.Strings.MakeString(reader.ReadString()),
                CleanupScript = Data.Strings.MakeString(reader.ReadString()),
            };
            var functionCount = reader.ReadInt32();
            for (var j = 0; j < functionCount; j++)
            {
                var id = reader.ReadUInt32();
                var kind = reader.ReadUInt32();
                var name = reader.ReadString();
                var returnType = (UndertaleExtensionVarType)reader.ReadUInt32();
                var extName = reader.ReadString();
                var argumentCount = reader.ReadInt32();
                var arguments = new UndertaleExtensionVarType[argumentCount];
                for (var k = 0; k < argumentCount; k++)
                    arguments[k] = (UndertaleExtensionVarType)reader.ReadUInt32();
                file.Functions.DefineExtensionFunction(Data.Functions, Data.Strings, id, kind, name, returnType, extName, arguments);
            }
            extension.Files.Add(file);
        }
        return extension;
    }

    static void AddSoundIfMissing(string path)
    {
        var sound = LoadSound(path);
        if (Data.Sounds.ByName(sound.Name.Content) != null)
            return;
        Data.Sounds.Add(sound);
    }

    static UndertaleSound LoadSound(string path)
    {
        var sound = new UndertaleSound();
        using var reader = new BinaryReader(File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read));
        sound.Name = Data.Strings.MakeString(reader.ReadString());
        sound.Pitch = reader.ReadSingle();
        sound.GroupID = reader.ReadInt32();
        sound.Volume = reader.ReadSingle();
        sound.Type = Data.Strings.MakeString(reader.ReadString());
        sound.File = Data.Strings.MakeString(reader.ReadString());
        sound.Effects = reader.ReadUInt32();

        var hasAudioGroup = reader.ReadBoolean();
        if (hasAudioGroup)
        {
            var groupName = reader.ReadString();
            var group = Data.AudioGroups?.ByName(groupName);
            if (group == null)
            {
                group = new UndertaleAudioGroup() { Name = Data.Strings.MakeString(groupName) };
                if (Data.FORM.AGRP == null)
                    Data.FORM.Chunks["AGRP"] = new UndertaleChunkAGRP();
                Data.AudioGroups.Add(group);
            }
            sound.AudioGroup = group;
            sound.GroupID = Data.AudioGroups.IndexOf(group);
        }
        else if (Data.AudioGroups != null && sound.GroupID >= 0 && sound.GroupID < Data.AudioGroups.Count)
        {
            sound.AudioGroup = Data.AudioGroups[sound.GroupID];
        }

        sound.Flags = (UndertaleSound.AudioEntryFlags)reader.ReadUInt32();
        sound.AudioID = -1;
        var hasAudioFile = reader.ReadBoolean();
        if (hasAudioFile)
        {
            var audioLength = reader.ReadInt32();
            var audio = new UndertaleEmbeddedAudio()
            {
                Name = Data.Strings.MakeString($"EmbeddedSound {Data.EmbeddedAudio.Count}"),
                Data = reader.ReadBytes(audioLength),
            };
            sound.AudioID = Data.EmbeddedAudio.Count;
            Data.EmbeddedAudio.Add(audio);
            sound.AudioFile = audio;
        }
        return sound;
    }

    // --- Font selection ---

    static int FindBestFontIndex()
    {
        if (Data.Fonts.Count == 0)
            return -1;

        // Prefer fonts with EmSize between 8 and 16 (small UI-friendly sizes)
        int bestIndex = -1;
        float bestScore = float.MaxValue;
        for (int i = 0; i < Data.Fonts.Count; i++)
        {
            var font = Data.Fonts[i];
            if (font == null) continue;
            float size = font.EmSizeIsFloat ? font.EmSize : (float)(uint)font.EmSize;
            // Target size 12: score is distance from 12
            float score = Math.Abs(size - 12f);
            // Slight penalty for very small or very large fonts
            if (size < 6 || size > 24) score += 100;
            if (score < bestScore)
            {
                bestScore = score;
                bestIndex = i;
            }
        }

        // Fallback: use the first font
        if (bestIndex < 0)
            bestIndex = 0;
        return bestIndex;
    }

    /// <summary>
    /// Renders CJK glyphs to a texture atlas and embeds a font resource into data.win.
    /// Returns the font index, or -1 if no CJK system font is available.
    /// </summary>
    static int EmbedCjkFont()
    {
        // Try to find a CJK system font
        string[] candidates = { "Microsoft YaHei", "SimHei", "SimSun", "NSimSun", "KaiTi", "FangSong" };
        Font sysFont = null;
        string fontFamily = null;

        // CJK font size in pixels. The CJK atlas also includes ASCII (32-126),
        // so this size applies to both Chinese AND English UI text rendered via
        // global.__ONLINE_ftOnline. 12px is a balance: readable Chinese without
        // overwhelming the small game viewport.
        const float cjkFontSize = 12f;

        foreach (var name in candidates)
        {
            try
            {
                var f = new Font(name, cjkFontSize, FontStyle.Regular, GraphicsUnit.Pixel);
                if (!f.FontFamily.Name.Equals("Microsoft Sans Serif", StringComparison.OrdinalIgnoreCase))
                {
                    sysFont = f;
                    fontFamily = name;
                    break;
                }
                f.Dispose();
            }
            catch { /* font not available */ }
        }

        if (sysFont == null)
        {
            Console.WriteLine("CJK font: not found, skipping embed");
            return -1;
        }

        Console.WriteLine($"CJK font: {fontFamily}");

        // Characters to render on the atlas
        var renderSet = new HashSet<int>();
        for (int c = 32; c <= 126; c++) renderSet.Add(c);
        for (int c = 0x2000; c <= 0x206F; c++) renderSet.Add(c);   // General punctuation
        for (int c = 0x3000; c <= 0x30FF; c++) renderSet.Add(c);   // CJK symbols + Kana
        for (int c = 0x4E00; c <= 0x9FFF; c++) renderSet.Add(c);   // CJK Unified Ideographs
        for (int c = 0xFF01; c <= 0xFF5E; c++) renderSet.Add(c);   // Fullwidth forms

        // GMS runtime uses array-indexed glyph lookup: glyphs[charCode - RangeStart]
        // Must create contiguous entries from RangeStart to RangeEnd
        ushort rangeStart = 32;
        ushort rangeEnd = 0xFF5E;

        // Pass 1 — measure all glyphs using a throwaway Graphics context.
        // We need char metrics before allocating the atlas so we can pack tight.
        Console.WriteLine("Measuring CJK glyphs...");
        int lineH;
        var glyphMetrics = new List<(int ch, int w, int h)>(renderSet.Count);
        using (var tmpBmp = new Bitmap(1, 1, PixelFormat.Format32bppArgb))
        using (var tmpG = Graphics.FromImage(tmpBmp))
        {
            tmpG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            tmpG.SmoothingMode = SmoothingMode.HighQuality;
            using var tmpSf = new StringFormat(StringFormat.GenericTypographic);
            tmpSf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            lineH = sysFont.Height;
            foreach (int ch in renderSet)
            {
                var sz = tmpG.MeasureString(((char)ch).ToString(), sysFont, PointF.Empty, tmpSf);
                int w = Math.Max(1, (int)Math.Ceiling(sz.Width));
                int h = Math.Max(lineH, (int)Math.Ceiling(sz.Height));
                glyphMetrics.Add((ch, w, h));
            }
        }

        // Shelf-packing: sort by height descending so each shelf's wasted vertical
        // space is bounded by the tallest glyph in that shelf only. Within a shelf
        // glyphs are placed left-to-right. Atlas width is fixed; height is whatever
        // the packing requires (rounded up to a multiple of 64 for tidy texture sizes).
        glyphMetrics.Sort((a, b) => b.h.CompareTo(a.h));

        const int cellPad = 1;
        const int atlasW = 4096;
        var positions = new Dictionary<int, (int x, int y, int w, int h)>(glyphMetrics.Count);
        int packX = 0, packY = 0, shelfH = 0;
        foreach (var (ch, w, h) in glyphMetrics)
        {
            if (packX + w + cellPad > atlasW)
            {
                packX = 0;
                packY += shelfH + cellPad;
                shelfH = 0;
            }
            positions[ch] = (packX, packY, w, h);
            packX += w + cellPad;
            if (h > shelfH) shelfH = h;
        }
        int packedH = packY + shelfH;
        // GMS texture pages must have power-of-2 dimensions to avoid the runtime
        // warning "Texture page dimensions are not powers of 2. Sprite blurring is
        // very likely in-game." Round atlas height up to the next power of 2.
        int atlasH = 64;
        while (atlasH < packedH) atlasH <<= 1;
        long usedPx = 0;
        foreach (var (_, w, h) in glyphMetrics) usedPx += (long)w * h;
        Console.WriteLine($"CJK atlas: {atlasW}x{atlasH}, {(usedPx * 100.0 / ((long)atlasW * atlasH)):F1}% used, {glyphMetrics.Count} glyphs");

        // Pass 2 — allocate atlas at packed size and render at computed positions.
        using var atlas = new Bitmap(atlasW, atlasH, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(atlas);
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.SmoothingMode = SmoothingMode.HighQuality;

        using var brush = new SolidBrush(Color.White);
        using var sf = new StringFormat(StringFormat.GenericTypographic);
        sf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;

        var rendered = new Dictionary<int, (ushort sx, ushort sy, ushort sw, ushort sh, short shift)>();
        foreach (var kvp in positions)
        {
            var (x, y, w, h) = kvp.Value;
            g.DrawString(((char)kvp.Key).ToString(), sysFont, brush, x, y, sf);
            rendered[kvp.Key] = (
                sx: (ushort)x,
                sy: (ushort)y,
                sw: (ushort)w,
                sh: (ushort)h,
                shift: (short)(w + 1)
            );
        }

        sysFont.Dispose();

        // Save atlas as PNG bytes directly via System.Drawing (avoid Magick.NET)
        byte[] pngBytes;
        using (var ms = new MemoryStream())
        {
            atlas.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
            pngBytes = ms.ToArray();
        }

        var pngImage = GMImage.FromPng(pngBytes);

        // Create embedded texture
        var embTex = new UndertaleEmbeddedTexture();
        embTex.TextureData = new UndertaleEmbeddedTexture.TexData();
        embTex.TextureData.Image = pngImage;
        Data.EmbeddedTextures.Add(embTex);

        // Create texture page item
        var pageItem = new UndertaleTexturePageItem()
        {
            TexturePage = embTex,
            SourceX = 0, SourceY = 0,
            SourceWidth = (ushort)atlasW, SourceHeight = (ushort)atlasH,
            TargetX = 0, TargetY = 0,
            TargetWidth = (ushort)atlasW, TargetHeight = (ushort)atlasH,
            BoundingWidth = (ushort)atlasW, BoundingHeight = (ushort)atlasH,
        };
        Data.TexturePageItems.Add(pageItem);

        // Create font resource
        var font = new UndertaleFont();
        font.Name = Data.Strings.MakeString("__ONLINE_fnt_cjk");
        font.DisplayName = Data.Strings.MakeString(fontFamily);
        font.EmSizeIsFloat = (Data.GeneralInfo?.Major ?? 0) >= 2;
        font.EmSize = cjkFontSize;
        font.Bold = false;
        font.Italic = false;
        font.RangeStart = rangeStart;
        font.RangeEnd = rangeEnd;
        font.Charset = 0;
        font.AntiAliasing = 1;
        font.Texture = pageItem;
        font.ScaleX = 1f;
        font.ScaleY = 1f;

        // Build contiguous glyph array: runtime uses glyphs[charCode - RangeStart]
        // Unrendered characters get blank entries (Shift=0, no visual)
        int totalEntries = rangeEnd - rangeStart + 1;
        for (int c = rangeStart; c <= rangeEnd; c++)
        {
            if (rendered.TryGetValue(c, out var info))
            {
                font.Glyphs.Add(new UndertaleFont.Glyph()
                {
                    Character = (ushort)c,
                    SourceX = info.sx, SourceY = info.sy,
                    SourceWidth = info.sw, SourceHeight = info.sh,
                    Shift = info.shift,
                    Offset = 0,
                });
            }
            else
            {
                font.Glyphs.Add(new UndertaleFont.Glyph()
                {
                    Character = (ushort)c,
                    SourceX = 0, SourceY = 0,
                    SourceWidth = 0, SourceHeight = 0,
                    Shift = 0,
                    Offset = 0,
                });
            }
        }

        Data.Fonts.Add(font);
        int fontIndex = Data.Fonts.Count - 1;
        return fontIndex;
    }

    // --- Shared save patch ---

    static SharedSavePatch BuildSharedSavePatch(UndertaleScript saveScript, string saveAppendCode, UndertaleScript loadScript, string loadAppendCode)
    {
        if (saveScript?.Code is null || loadScript?.Code is null)
            return null;

        if (saveScript.Code.ParentEntry is null && loadScript.Code.ParentEntry is null && CanDecompile(saveScript.Code) && CanDecompile(loadScript.Code))
        {
            return new SharedSavePatch()
            {
                SaveCodeToAppend = saveScript.Code,
                SaveAppendCode = saveAppendCode,
                LoadCodeToAppend = loadScript.Code,
                LoadAppendCode = loadAppendCode,
            };
        }

        var saveRoot = GetRootCode(saveScript.Code);
        var loadRoot = GetRootCode(loadScript.Code);
        if (saveRoot is null || loadRoot is null || saveRoot != loadRoot || !CanDecompile(saveRoot))
            return null;

        var rootSource = DecompileCode(saveRoot);
        rootSource = AppendCodeToFunctionBody(rootSource, NormalizeAssetName(saveScript.Name?.Content), saveAppendCode);
        if (rootSource is null)
            return null;

        rootSource = AppendCodeToFunctionBody(rootSource, NormalizeAssetName(loadScript.Name?.Content), loadAppendCode);
        if (rootSource is null)
            return null;

        return new SharedSavePatch()
        {
            RootCodeToReplace = saveRoot,
            RootReplacementCode = rootSource,
        };
    }

    static void QueueSharedSavePatch(CodeImportGroup importGroup, SharedSavePatch patch)
    {
        if (patch.RootCodeToReplace != null)
        {
            importGroup.QueueReplace(patch.RootCodeToReplace, patch.RootReplacementCode);
            return;
        }
        importGroup.QueueAppend(patch.SaveCodeToAppend, patch.SaveAppendCode);
        importGroup.QueueAppend(patch.LoadCodeToAppend, patch.LoadAppendCode);
    }

    static UndertaleCode GetRootCode(UndertaleCode code)
    {
        while (code?.ParentEntry != null)
            code = code.ParentEntry;
        return code;
    }

    static string DecompileCode(UndertaleCode code)
    {
        return new DecompileContext(new GlobalDecompileContext(Data), code, new DecompileSettings()).DecompileToString();
    }

    static bool CanDecompile(UndertaleCode code)
    {
        try { _ = DecompileCode(code); return true; }
        catch { return false; }
    }

    static string AppendCodeToFunctionBody(string rootCode, string functionName, string appendCode)
    {
        if (string.IsNullOrWhiteSpace(rootCode) || string.IsNullOrWhiteSpace(functionName) || string.IsNullOrWhiteSpace(appendCode))
            return null;

        var marker = "function " + functionName + "(";
        var functionIndex = rootCode.IndexOf(marker, StringComparison.Ordinal);
        if (functionIndex < 0)
            return null;

        var openBraceIndex = rootCode.IndexOf('{', functionIndex);
        if (openBraceIndex < 0)
            return null;

        var closeBraceIndex = FindMatchingBrace(rootCode, openBraceIndex);
        if (closeBraceIndex < 0)
            return null;

        return rootCode.Insert(closeBraceIndex, "\r\n" + appendCode + "\r\n");
    }

    static int FindMatchingBrace(string code, int openBraceIndex)
    {
        var depth = 0;
        var inLineComment = false;
        var inBlockComment = false;
        var inString = false;
        var stringDelimiter = '\0';

        for (var i = openBraceIndex; i < code.Length; i++)
        {
            var ch = code[i];
            var next = (i + 1) < code.Length ? code[i + 1] : '\0';

            if (inLineComment) { if (ch == '\n') inLineComment = false; continue; }
            if (inBlockComment) { if (ch == '*' && next == '/') { inBlockComment = false; i++; } continue; }
            if (inString) { if (ch == '\\') { i++; continue; } if (ch == stringDelimiter) inString = false; continue; }

            if (ch == '/' && next == '/') { inLineComment = true; i++; continue; }
            if (ch == '/' && next == '*') { inBlockComment = true; i++; continue; }
            if (ch == '"' || ch == '\'') { inString = true; stringDelimiter = ch; continue; }
            if (ch == '{') { depth++; continue; }
            if (ch == '}') { depth--; if (depth == 0) return i; }
        }
        return -1;
    }

    // --- iwpo.* define channel ---

    static string GetDefine(string key)
    {
        if (key != null && Config.Defines != null &&
            Config.Defines.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            return value;
        return null;
    }

    static bool GetDefineFlag(string key)
    {
        var value = GetDefine(key);
        if (value is null) return false;
        return !(value == "0" || value.Equals("false", StringComparison.OrdinalIgnoreCase));
    }

    // --- Skin system ---

    // Game sprite -> skin state candidate names, in map slot order:
    // 0 idle, 1 run, 2 jump, 3 fall, 4 slide, 5 bow, 6 bullet.
    static readonly string[] SpriteStateNames = { "idle", "run", "jump", "fall", "slide", "bow", "bullet" };
    static readonly string[][] SpriteStateCandidates =
    {
        new[] { "playeridle", "sprplayeridle", "player_idle", "spr_player_idle", "splayeridle" },
        new[] { "playerrunning", "playerrun", "sprplayerrun", "sprplayerrunning", "player_running", "splayerrunning", "splayerrun" },
        new[] { "playerjump", "sprplayerjump", "player_jump", "splayerjump" },
        new[] { "playerfall", "sprplayerfall", "player_fall", "splayerfall" },
        new[] { "playersliding", "playerslide", "sprplayersliding", "sprplayerslide", "playerclimb", "sprplayerclimb", "splayersliding", "splayerslide" },
        new[] { "playerbow", "sprplayerbow", "sbow" },
        new[] { "sprbullet", "playerbullet", "sprplayerbullet", "bullet", "sbullet" },
    };

    static UndertaleSprite FindSpriteByName(string name)
    {
        return Data.Sprites.FirstOrDefault(s => string.Equals(s?.Name?.Content, name, StringComparison.OrdinalIgnoreCase));
    }

    // Emits the global.__ONLINE_mapSpr / global.__ONLINE_mapFrames constant
    // assignments consumed by the skin templates. Every slot is always assigned
    // (-1 / 0 when unmatched) so the skin library never reads an unassigned entry.
    static string BuildSpriteMapCode()
    {
        var sb = new StringBuilder("// Game sprite -> skin state mapping (generated by the converter)");
        for (var st = 0; st < SpriteStateNames.Length; st++)
        {
            var state = SpriteStateNames[st];
            var defineValue = GetDefine($"iwpo.skins.map.{state}");
            UndertaleSprite sprite = null;
            if (defineValue != null)
            {
                sprite = FindSpriteByName(defineValue);
                if (sprite is null)
                    throw new Exception($"No sprite named '{defineValue}' (from iwpo.skins.map.{state}) found.");
            }
            else
            {
                foreach (var candidate in SpriteStateCandidates[st])
                {
                    sprite = FindSpriteByName(candidate);
                    if (sprite != null) break;
                }
            }
            if (sprite is null)
            {
                Console.WriteLine($"Skin sprite map: {state} -> (no match)");
                sb.Append($"\r\nglobal.__ONLINE_mapSpr[{st}] = -1; global.__ONLINE_mapFrames[{st}] = 0;");
                continue;
            }
            // Sprite asset references compile to their data.Sprites list index, so
            // the raw integer is a valid constant in GML.
            var index = Data.Sprites.IndexOf(sprite);
            var frames = sprite.Textures?.Count ?? 0;
            Console.WriteLine($"Skin sprite map: {state} -> {sprite.Name.Content} (index {index}, {frames} frames)");
            sb.Append($"\r\nglobal.__ONLINE_mapSpr[{st}] = {index}; global.__ONLINE_mapFrames[{st}] = {frames};");
        }
        return sb.ToString();
    }

    // Defaults-only variant used when the skin system is disabled via
    // iwpo.no_skins: every slot assigned -1/0 without touching the game's sprite
    // list, so the skin menu preview can never read an uninitialised global.
    static string BuildSpriteMapDefaultsCode()
    {
        var sb = new StringBuilder("// Game sprite -> skin state mapping (defaults; skins disabled)");
        for (var st = 0; st < SpriteStateNames.Length; st++)
            sb.Append($"\r\nglobal.__ONLINE_mapSpr[{st}] = -1; global.__ONLINE_mapFrames[{st}] = 0;");
        return sb.ToString();
    }

    // --- Bullet sharing (S4) ---

    // Resolves the game's bullet object. Priority: the iwpo.bullet_object
    // define; otherwise the object whose DEFAULT sprite is the bullet sprite
    // (re-resolved with the skin map's slot-6 candidate table); null disables
    // sharing. Matches the GM8 converter's resolveBulletObject.
    static UndertaleGameObject ResolveBulletObject()
    {
        var defineValue = GetDefine("iwpo.bullet_object");
        if (defineValue != null)
        {
            if (defineValue.Trim() == "-")
            {
                // Explicitly disabled (findAsset convention: "-" = off).
                Console.WriteLine("Bullet sharing: iwpo.bullet_object=- -> disabled");
                return null;
            }
            var obj = FindObject(defineValue);
            if (obj != null) return obj;
            Console.WriteLine($"Bullet sharing: iwpo.bullet_object={defineValue}: no such object, falling back to default-sprite matching");
        }
        UndertaleSprite bulletSprite = null;
        var mapDefine = GetDefine("iwpo.skins.map.bullet");
        if (mapDefine != null)
        {
            bulletSprite = FindSpriteByName(mapDefine);
            if (bulletSprite is null)
                throw new Exception($"No sprite named '{mapDefine}' (from iwpo.skins.map.bullet) found.");
        }
        else
        {
            foreach (var candidate in SpriteStateCandidates[6])
            {
                bulletSprite = FindSpriteByName(candidate);
                if (bulletSprite != null) break;
            }
        }
        if (bulletSprite is null) return null;
        var matches = Data.GameObjects.Where(o => o?.Sprite == bulletSprite).ToList();
        if (matches.Count > 1)
            Console.WriteLine($"Bullet sharing: {matches.Count} objects share the bullet sprite: {string.Join(", ", matches.Select(o => o.Name.Content))}; using {matches[0].Name.Content} (override with iwpo.bullet_object)");
        return matches.Count > 0 ? matches[0] : null;
    }

    // Emits the global.__ONLINE_bulletObj / global.__ONLINE_bulletSpr constant
    // assignments consumed by the bulletShare templates. ALWAYS emitted
    // (-1/-1 when no bullet object was resolved): GMS errors on reading an
    // unassigned global, and GM8 would read 0. Takes the already-resolved
    // object to avoid re-resolving (the proxy object would otherwise be
    // re-matched by the default-sprite scan).
    static string BuildBulletMapCode(UndertaleGameObject bulletSourceObj)
    {
        // The native bullet sprite for the proxy draw fallback, resolved like
        // skin map slot 6 (independent of the bullet object's default sprite).
        var sprIndex = -1;
        string sprName = null;
        var mapDefine = GetDefine("iwpo.skins.map.bullet");
        UndertaleSprite bulletSprite = null;
        if (mapDefine != null)
        {
            bulletSprite = FindSpriteByName(mapDefine);
            if (bulletSprite is null)
                throw new Exception($"No sprite named '{mapDefine}' (from iwpo.skins.map.bullet) found.");
        }
        else
        {
            foreach (var candidate in SpriteStateCandidates[6])
            {
                bulletSprite = FindSpriteByName(candidate);
                if (bulletSprite != null) break;
            }
        }
        if (bulletSprite != null)
        {
            sprIndex = Data.Sprites.IndexOf(bulletSprite);
            sprName = bulletSprite.Name.Content;
        }
        var objIndex = bulletSourceObj is null ? -1 : Data.GameObjects.IndexOf(bulletSourceObj);
        if (bulletSourceObj != null)
            Console.WriteLine($"Bullet sharing: object -> {bulletSourceObj.Name.Content} (index {objIndex}, sprite {sprIndex} {sprName})");
        else
            Console.WriteLine("Bullet sharing: no bullet object resolved; disabled");
        return $"// Bullet sharing (generated by the converter)\r\nglobal.__ONLINE_bulletObj = {objIndex}; global.__ONLINE_bulletSpr = {sprIndex};";
    }

    // Renders a skin template, reporting a clear error when the shared GML file
    // has not been delivered to the gml directory yet.
    static string RenderSkinTemplate(ISet<string> activeFlags, string templateName)
    {
        var path = Path.Combine(Config.GmlDirectory, templateName + ".gml");
        if (!File.Exists(path))
            throw new Exception($"Skin system template not found: {path} (place {templateName}.gml in the gml directory, or set the iwpo.no_skins define to disable skin injection)");
        return RenderTemplate(activeFlags, templateName);
    }

    // Splits a rendered template into named sections introduced by
    // "///// script <name>" marker lines. The shared GM8/GMS skin templates pack
    // several one-function scripts into a single file; GMS needs one asset each.
    static List<KeyValuePair<string, string>> SplitMarkedScripts(string rendered, string templateName)
    {
        var sections = new List<KeyValuePair<string, string>>();
        string currentName = null;
        var body = new StringBuilder();
        void Flush()
        {
            if (currentName is null) return;
            var text = body.ToString().Trim();
            if (text.Length == 0)
                throw new Exception($"Section '///// script {currentName}' in {templateName}.gml has no code.");
            if (sections.Any(s => s.Key == currentName))
                throw new Exception($"Duplicate section '///// script {currentName}' in {templateName}.gml.");
            sections.Add(new KeyValuePair<string, string>(currentName, text));
        }
        foreach (var rawLine in Regex.Split(rendered, "\r\n|\r|\n"))
        {
            var match = Regex.Match(rawLine.Trim(), @"^/////\s*script\s+(\S+)\s*$");
            if (match.Success)
            {
                Flush();
                currentName = match.Groups[1].Value;
                body.Clear();
                continue;
            }
            if (currentName is null)
            {
                // Only blank lines and comments may precede the first marker.
                var trimmed = rawLine.Trim();
                if (trimmed.Length > 0 && !trimmed.StartsWith("//", StringComparison.Ordinal))
                    throw new Exception($"Unexpected content before the first ///// script section in {templateName}.gml: {trimmed}");
                continue;
            }
            body.AppendLine(rawLine);
        }
        Flush();
        if (sections.Count == 0)
            throw new Exception($"No ///// script sections found in {templateName}.gml.");
        return sections;
    }

    // Creates one script asset per marked section of the md5/skinLib templates.
    static void InjectSkinScriptAssets(CodeImportGroup importGroup, ISet<string> activeFlags)
    {
        foreach (var templateName in new[] { "md5", "skinLib", "bulletShare" })
        {
            var rendered = RenderSkinTemplate(activeFlags, templateName);
            foreach (var section in SplitMarkedScripts(rendered, templateName))
            {
                var name = section.Key;
                var body = section.Value;
                if (Data.Scripts.ByName(name) != null)
                    throw new Exception($"Cannot inject skin script '{name}': a script with that name already exists.");
                // AutoCreateAssets is off, so the script asset and its code entry are
                // created explicitly here (mirroring CodeImportGroup's own scheme:
                // code entry "gml_Script_<name>" plus script asset "<name>").
                var code = UndertaleCode.CreateEmptyEntry(Data, "gml_Script_" + name);
                Data.Scripts.Add(new UndertaleScript()
                {
                    Name = Data.Strings.MakeString(name),
                    Code = code,
                });
                // GMS2.3+ script assets hold function declarations; GMS1 holds the body directly.
                if (Data.IsVersionAtLeast(2, 3))
                    body = $"function {name}() {{\r\n{body}\r\n}}";
                importGroup.QueueReplace(code, body);
                Console.WriteLine($"Skin script: {name}");
            }
        }
    }

    // Splits the playerDrawInject template into its "replace" and "overlay"
    // sections (marked by "///// mode <name>" lines).
    static Dictionary<string, string> SplitMarkedModes(string rendered, string templateName)
    {
        var modes = new Dictionary<string, string>(StringComparer.Ordinal);
        string currentMode = null;
        var body = new StringBuilder();
        void Flush()
        {
            if (currentMode is null) return;
            modes[currentMode] = body.ToString().Trim();
        }
        foreach (var rawLine in Regex.Split(rendered, "\r\n|\r|\n"))
        {
            var match = Regex.Match(rawLine.Trim(), @"^/////\s*mode\s+(\w+)\s*$");
            if (match.Success)
            {
                Flush();
                currentMode = match.Groups[1].Value;
                body.Clear();
                continue;
            }
            if (currentMode is null)
            {
                // Only blank lines and comments may precede the first marker.
                var trimmed = rawLine.Trim();
                if (trimmed.Length > 0 && !trimmed.StartsWith("//", StringComparison.Ordinal))
                    throw new Exception($"Unexpected content before the first ///// mode section in {templateName}.gml: {trimmed}");
                continue;
            }
            body.AppendLine(rawLine);
        }
        Flush();
        return modes;
    }

    static void InjectPlayerDrawEvents(CodeImportGroup importGroup, ISet<string> activeFlags, UndertaleGameObject player, UndertaleGameObject player2)
    {
        var rendered = RenderSkinTemplate(activeFlags, "playerDrawInject");
        var modes = SplitMarkedModes(rendered, "playerDrawInject");
        if (!modes.TryGetValue("replace", out var replaceCode) || replaceCode.Length == 0)
            throw new Exception("playerDrawInject.gml is missing its '///// mode replace' section.");
        if (!modes.TryGetValue("overlay", out var overlayCode) || overlayCode.Length == 0)
            throw new Exception("playerDrawInject.gml is missing its '///// mode overlay' section.");
        InjectPlayerDrawEvent(importGroup, player, replaceCode, overlayCode);
        if (player2 != null)
            InjectPlayerDrawEvent(importGroup, player2, replaceCode, overlayCode);
    }

    static void InjectPlayerDrawEvent(CodeImportGroup importGroup, UndertaleGameObject obj, string replaceCode, string overlayCode)
    {
        var existing = FindEventCode(obj, EventType.Draw);
        if (existing is null)
        {
            // No Draw event: create one holding the replace section.
            importGroup.QueueReplace(obj.EventHandlerFor(EventType.Draw, EventSubtypeDraw.Draw, Data), replaceCode);
            Console.WriteLine($"Skin draw inject: {obj.Name.Content} (new Draw event)");
        }
        else
        {
            // Existing Draw event: append the overlay section so the skin draws on
            // top of the game's own drawing.
            importGroup.QueueAppend(existing, overlayCode);
            Console.WriteLine($"Skin draw inject: {obj.Name.Content} (appended to existing Draw event)");
        }
    }

    // --- GML template engine ---

    static string RenderTemplate(ISet<string> activeFlags, string templateName, params string[] args)
    {
        var templatePath = Path.Combine(Config.GmlDirectory, templateName + ".gml");
        var gml = File.ReadAllText(templatePath);
        gml = gml.Replace("@", Prefix);
        gml = gml.Replace("\t", string.Empty);

        for (var i = 0; i < args.Length; i++)
            gml = gml.Replace($"%arg{i}", args[i] ?? string.Empty);

        // The shared templates call the native DLL functions through __ONLINE_-prefixed
        // wrapper scripts (the GM8 converter generates those wrappers to avoid shadowing
        // gm82-style extension functions). GMS has no wrappers - its natives are
        // registered under their plain export names - so map the calls back here.
        gml = gml.Replace(Prefix + "udpsocket_", "udpsocket_");
        gml = gml.Replace(Prefix + "socket_", "socket_");
        gml = gml.Replace(Prefix + "buffer_", "hbuffer_");
        gml = gml.Replace(Prefix + "md5_dir", "hmd5_dir");
        gml = Regex.Replace(gml, @"\bbuffer_", "hbuffer_");
        if (templateName == "worldEndStep")
        {
            gml = gml.Replace(Prefix + "sndChatbox", Prefix + "sndChatboxId");
            gml = gml.Replace(Prefix + "sndSaved", Prefix + "sndSavedId");
        }

        var parsed = ParseGml(templateName, gml.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).ToList(), activeFlags);
        return string.Join("\r\n", parsed.Lines);
    }

    static string RenderWorldEndStep(ISet<string> activeFlags, bool sharedSaveSupported, params string[] args)
    {
        var gml = RenderTemplate(activeFlags, "worldEndStep", args);
        if (sharedSaveSupported)
            return gml;

        gml = Regex.Replace(gml, @"case 5:\r?\n// SOMEONE SAVED.*?\r?\nbreak;", "case 5:\r\nbreak;", RegexOptions.Singleline);
        gml = Regex.Replace(gml, @"\r?\nif\(keyboard_check_pressed\(" + Prefix + @"keySave\)\)\{.*?\}", string.Empty, RegexOptions.Singleline);
        return gml;
    }

    static ParseResult ParseGml(string templateName, List<string> lines, ISet<string> activeFlags)
    {
        var linesRead = 0;
        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i].Trim();
            linesRead++;
            if (line.StartsWith("#endif", StringComparison.Ordinal))
                return new ParseResult(lines.Take(i).ToList(), linesRead - 1);

            if (!line.StartsWith("#if ", StringComparison.Ordinal))
                continue;

            var beginIf = i;
            var isNegated = line.StartsWith("#if not ", StringComparison.Ordinal);
            var variable = line.Substring(isNegated ? 8 : 4);
            var keepSection = isNegated ? !activeFlags.Contains(variable) : activeFlags.Contains(variable);
            var nestedResult = ParseGml(templateName, lines.Skip(i + 1).ToList(), activeFlags);
            linesRead += nestedResult.LinesRead + 1;

            if (lines[i + nestedResult.LinesRead + 1].Trim() != "#endif")
                throw new Exception($"Unexpected GML conditional structure in {templateName}.gml");

            lines.RemoveRange(beginIf, nestedResult.LinesRead + 2);
            i = beginIf;
            if (keepSection)
            {
                lines.InsertRange(i, nestedResult.Lines);
                i += nestedResult.Lines.Count;
            }
            i--;
        }
        return new ParseResult(lines, linesRead);
    }
}
