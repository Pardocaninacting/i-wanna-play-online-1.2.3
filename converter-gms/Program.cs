using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
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

        var world = FindObjectInteractive("world object", "world", "World", "objWorld", "oWorld");
        var player = FindObjectInteractive("player object", "player", "Player", "objPlayer", "oPlayer", "objplayer");
        var player2 = FindObject("player2", "objPlayer2", "oPlayer2");
        var saveGame = FindScriptInteractive("save script", "save_save", "savegame", "saveGame", "savedata_save", "scrSaveGame", "SaveGame");
        var loadGame = FindScriptInteractive("load script", "save_load", "loadgame", "loadGame", "savedata_load", "scrLoadGame", "LoadGame");

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

        if (Data.Variables.Any(v => v?.Name?.Content == "xScale"))
            activeFlags.Add("PLAYER_XSCALE");

        if (Data.Variables.Any(v => v?.Name?.Content == "xscale"))
            activeFlags.Add("PLAYER_XSCALE_LOWER");

        if (Data.Scripts.ByName("scrFlipGrav") != null)
            activeFlags.Add("SCR_FLIP_GRAV");

        // Build shared save patch
        var player2Name = player2?.Name?.Content ?? string.Empty;
        var saveGameHookCode = RenderTemplate(activeFlags, "saveGame", world.Name.Content, player.Name.Content, player2Name);
        var loadGameHookCode = string.Join("\r\n",
            RenderTemplate(activeFlags, "saveGame2", world.Name.Content, player.Name.Content, player2Name),
            RenderTemplate(activeFlags, "loadGame", world.Name.Content, player.Name.Content, player2Name));
        var sharedSavePatch = BuildSharedSavePatch(saveGame, saveGameHookCode, loadGame, loadGameHookCode);
        var sharedSaveSupported = sharedSavePatch != null;
        if (!sharedSaveSupported)
            Console.WriteLine("Shared save hooks disabled (scripts could not be decompiled).");

        // Add extension
        if (Config.UseX64NativeHttpDll)
        {
            AddNativeX64ExtensionIfMissing();
        }
        else
        {
            AddExtensionIfMissing(Path.Combine(Config.ResourceDirectory, "http_dll"));
            // Add set_utf8_mode to x86 extension (not in the binary definition file)
            AddSetUtf8ModeToExtension();
        }

        // Add sounds
        AddSoundIfMissing(Path.Combine(Config.ResourceDirectory, "sound_chatbox"));
        AddSoundIfMissing(Path.Combine(Config.ResourceDirectory, "sound_saved"));

        // Find a suitable small font for the online UI
        var onlineFontIndex = FindBestFontIndex();
        Console.WriteLine($"Using font index {onlineFontIndex}.");

        // Embed CJK font for Chinese text support (font_add is broken in GMS1.4)
        var cjkFontIndex = EmbedCjkFont();
        if (cjkFontIndex >= 0)
            onlineFontIndex = cjkFontIndex;

        // Create objects
        var onlinePlayer = CreateObject(Prefix + "onlinePlayer", false, -10, true);
        var chatbox = CreateObject(Prefix + "chatbox", true, -11, true);
        var playerSaved = CreateObject(Prefix + "playerSaved", true, -10, false);
        var ui = CreateObject(Prefix + "userInterface", true, -2147483648, true);
        Data.GameObjects.Add(onlinePlayer);
        Data.GameObjects.Add(chatbox);
        Data.GameObjects.Add(playerSaved);
        Data.GameObjects.Add(ui);

        // Compile and import GML
        var importGroup = new CodeImportGroup(Data) { AutoCreateAssets = false };

        var worldCreateCode = RenderTemplate(activeFlags, "worldCreateGMS", Config.GameId, Config.Server,
                Config.TcpPort.ToString(), Config.UdpPort.ToString(), Config.GameName,
                Config.Version, sharedSaveSupported ? "1" : "0", onlineFontIndex.ToString());
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
            RenderTemplate(activeFlags, "chatboxEndStep", player.Name.Content, player2Name));
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

        if (sharedSaveSupported)
            QueueSharedSavePatch(importGroup, sharedSavePatch);

        Console.WriteLine("Compiling GML...");
        importGroup.Import();
    }

    // --- Asset lookup ---

    static UndertaleGameObject FindObject(params string[] names)
    {
        return Data.GameObjects.FirstOrDefault(obj => NameMatches(obj?.Name?.Content, names));
    }

    static UndertaleScript FindScript(params string[] names)
    {
        return Data.Scripts.FirstOrDefault(script => NameMatches(script?.Name?.Content, names));
    }

    static UndertaleGameObject FindObjectInteractive(string typeName, params string[] names)
    {
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

    static UndertaleScript FindScriptInteractive(string typeName, params string[] names)
    {
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

    static void AddNativeX64ExtensionIfMissing()
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
        DefineNative(file, ref functionId, "hbuffer_read_uint64", "buffer_read_uint64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_float32", "buffer_read_float32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_float64", "buffer_read_float64", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_read_string", "buffer_read_string", UndertaleExtensionVarType.String, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint8", "buffer_write_uint8", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_uint16", "buffer_write_uint16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_int16", "buffer_write_int16", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "hbuffer_write_int32", "buffer_write_int32", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
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

        Data.Extensions.Add(extension);
        AddExtensionProductIdIfEligible();
    }

    static void AddSetUtf8ModeToExtension()
    {
        var ext = Data.Extensions.ByName("Http Dll 2.3");
        if (ext == null || ext.Files.Count == 0)
            return;
        var file = ext.Files[0];
        // Use a high function ID to avoid collisions
        uint functionId = 200;
        DefineNative(file, ref functionId, "set_utf8_mode", "set_utf8_mode", UndertaleExtensionVarType.Double, UndertaleExtensionVarType.Double);
        DefineNative(file, ref functionId, "strip_non_bmp", "strip_non_bmp", UndertaleExtensionVarType.String, UndertaleExtensionVarType.String);
    }

    static void DefineNative(UndertaleExtensionFile file, ref uint functionId, string name, string extName, UndertaleExtensionVarType returnType, params UndertaleExtensionVarType[] arguments)
    {
        file.Functions.DefineExtensionFunction(Data.Functions, Data.Strings, functionId++, 0xC, name, returnType, extName, arguments);
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

        foreach (var name in candidates)
        {
            try
            {
                var f = new Font(name, 10f, FontStyle.Regular, GraphicsUnit.Pixel);
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
            Console.WriteLine("No CJK system font found, skipping CJK font embedding.");
            return -1;
        }

        Console.WriteLine($"Embedding CJK font: {fontFamily} ...");

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

        int atlasW = 2048, atlasH = 2048;
        using var atlas = new Bitmap(atlasW, atlasH, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(atlas);
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.SmoothingMode = SmoothingMode.HighQuality;

        using var brush = new SolidBrush(Color.White);
        using var sf = new StringFormat(StringFormat.GenericTypographic);
        sf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;

        int cellPad = 1;
        int penX = 0, penY = 0, rowH = 0;
        int lineH = sysFont.Height;

        // Render glyphs and store positions in a dictionary
        var rendered = new Dictionary<int, (ushort sx, ushort sy, ushort sw, ushort sh, short shift)>();

        foreach (int ch in renderSet.OrderBy(c => c))
        {
            var sz = g.MeasureString(((char)ch).ToString(), sysFont, PointF.Empty, sf);
            int charW = Math.Max(1, (int)Math.Ceiling(sz.Width));
            int charH = Math.Max(lineH, (int)Math.Ceiling(sz.Height));

            if (penX + charW + cellPad > atlasW)
            {
                penX = 0;
                penY += rowH + cellPad;
                rowH = 0;
            }

            if (penY + charH > atlasH)
                break;

            g.DrawString(((char)ch).ToString(), sysFont, brush, penX, penY, sf);

            rendered[ch] = (
                sx: (ushort)penX,
                sy: (ushort)penY,
                sw: (ushort)charW,
                sh: (ushort)charH,
                shift: (short)(charW + 1)
            );

            penX += charW + cellPad;
            if (charH > rowH) rowH = charH;
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
        font.EmSize = 10f;
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

    // --- GML template engine ---

    static string RenderTemplate(ISet<string> activeFlags, string templateName, params string[] args)
    {
        var templatePath = Path.Combine(Config.GmlDirectory, templateName + ".gml");
        var gml = File.ReadAllText(templatePath);
        gml = gml.Replace("@", Prefix);
        gml = gml.Replace("\t", string.Empty);

        for (var i = 0; i < args.Length; i++)
            gml = gml.Replace($"%arg{i}", args[i] ?? string.Empty);

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
