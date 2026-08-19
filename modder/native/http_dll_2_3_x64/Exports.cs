using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

internal static class NativeState
{
    internal static int NextBufferId;
    internal static int NextSocketId;
    internal static int NextUdpSocketId;
    internal static readonly Dictionary<int, NativeBuffer> Buffers = new();
    internal static readonly Dictionary<int, TcpSocketState> Sockets = new();
    internal static readonly Dictionary<int, UdpSocketState> UdpSockets = new();
}

internal static class NativeStrings
{
    private static IntPtr buffer = IntPtr.Zero;
    private static int capacity;
    private static readonly UTF8Encoding Utf8Strict = new(false, true);
    // On x86 (GM8) we need ANSI↔UTF-8 conversion at the GM↔DLL boundary.
    // GM8 passes/expects strings in the system ANSI codepage (e.g. GBK on Chinese Windows).
    // On x64 (GMS2) strings are UTF-8 end-to-end.
    // GMS 1.4 x86 also uses UTF-8 — call set_utf8_mode(1) to override.
    private static bool UseAnsi = IntPtr.Size == 4;

    internal static void SetUtf8Mode(bool enable)
    {
        UseAnsi = !enable;
    }
    private static readonly Encoding AnsiEncoding = GetAnsiEncoding();
    private static Encoding GetAnsiEncoding()
    {
        if (IntPtr.Size != 4) return Encoding.UTF8;
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        return Encoding.GetEncoding((int)GetACP());
    }
    [DllImport("kernel32.dll")]
    private static extern uint GetACP();

    internal static string Read(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
            return string.Empty;

        var length = 0;
        while (Marshal.ReadByte(ptr, length) != 0)
            length++;

        if (length == 0)
            return string.Empty;

        var bytes = new byte[length];
        Marshal.Copy(ptr, bytes, 0, length);
        if (UseAnsi)
            return AnsiEncoding.GetString(bytes);
        try
        {
            return Utf8Strict.GetString(bytes);
        }
        catch
        {
            return AnsiEncoding.GetString(bytes);
        }
    }

    internal static IntPtr Write(string? value)
    {
        value ??= string.Empty;
        var bytes = UseAnsi ? AnsiEncoding.GetBytes(value) : Encoding.UTF8.GetBytes(value);
        var required = bytes.Length + 1;
        if (required > capacity)
        {
            if (buffer != IntPtr.Zero)
                Marshal.FreeHGlobal(buffer);
            capacity = Math.Max(required, 256);
            buffer = Marshal.AllocHGlobal(capacity);
        }

        Marshal.Copy(bytes, 0, buffer, bytes.Length);
        Marshal.WriteByte(buffer, bytes.Length, 0);
        return buffer;
    }

    /// <summary>
    /// Convert a string from the system ANSI codepage (e.g. GBK) to UTF-8 bytes.
    /// Always performs conversion regardless of UseAnsi mode, because the input
    /// comes from Windows ANSI APIs (e.g. wd_input_box) which always return
    /// system codepage bytes.
    /// </summary>
    internal static IntPtr ConvertAnsiToUtf8(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
            return Write(string.Empty);

        var length = 0;
        while (Marshal.ReadByte(ptr, length) != 0)
            length++;

        if (length == 0)
            return Write(string.Empty);

        var bytes = new byte[length];
        Marshal.Copy(ptr, bytes, 0, length);

        // Always decode as system codepage (e.g. GBK) then re-encode as UTF-8.
        // wd_input_box returns system ANSI bytes regardless of GM version or UseAnsi mode.
        var utf8Bytes = Encoding.UTF8.GetBytes(AnsiEncoding.GetString(bytes));

        var required = utf8Bytes.Length + 1;
        if (required > capacity)
        {
            if (buffer != IntPtr.Zero)
                Marshal.FreeHGlobal(buffer);
            capacity = Math.Max(required, 256);
            buffer = Marshal.AllocHGlobal(capacity);
        }
        Marshal.Copy(utf8Bytes, 0, buffer, utf8Bytes.Length);
        Marshal.WriteByte(buffer, utf8Bytes.Length, 0);
        return buffer;
    }
}

/// <summary>
/// Win32-based modal input dialog with full Unicode/IME support.
/// Returns user input as a .NET string (UTF-16), which the caller encodes as needed.
/// </summary>
internal static class InputDialog
{
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS
    {
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left, top, right, bottom;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassW(ref WNDCLASS wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string cls, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")]
    private static extern bool UpdateWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool EnableWindow(IntPtr hWnd, bool enable);
    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hWnd, char[] buf, int maxCount);
    [DllImport("user32.dll")]
    private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern int GetMessageW(out MSG msg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessageW(ref MSG msg);
    [DllImport("user32.dll")]
    private static extern void PostQuitMessage(int code);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DefWindowProcW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern IntPtr LoadCursorW(IntPtr inst, int id);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool IsDialogMessageW(IntPtr hDlg, ref MSG msg);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
    private delegate bool EnumThreadWndProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern bool EnumThreadWindows(uint threadId, EnumThreadWndProc callback, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandleW(string? name);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFontW(int h, int w, int esc, int orient, int weight, uint italic, uint ul, uint strike, uint charset, uint outPrec, uint clipPrec, uint quality, uint pitch, string face);
    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr dc);
    [DllImport("gdi32.dll")]
    private static extern int GetDeviceCaps(IntPtr dc, int index);

    private const uint CS_HREDRAW = 2, CS_VREDRAW = 1;
    private const uint WS_OVERLAPPED = 0, WS_CAPTION = 0xC00000, WS_SYSMENU = 0x80000;
    private const uint WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000, WS_TABSTOP = 0x10000;
    private const uint WS_EX_CLIENTEDGE = 0x200, WS_EX_DLGMODALFRAME = 1;
    private const uint BS_DEFPUSHBUTTON = 1, ES_AUTOHSCROLL = 0x80, SS_LEFT = 0;
    private const uint WM_CREATE = 1, WM_DESTROY = 2, WM_CLOSE = 0x10;
    private const uint WM_COMMAND = 0x111, WM_SETFONT = 0x30, EM_SETSEL = 0xB1;
    private const int LOGPIXELSY = 90, SW_SHOW = 5, IDC_ARROW = 32512;
    private const int IDC_EDIT = 101, IDC_OK = 1, IDC_CANCEL = 2;

    private static IntPtr s_editHwnd, s_dlgHwnd, s_parentHwnd, s_font;
    private static IntPtr s_gameHwnd, s_enumFound; // cached game window handle
    private static string s_result = "", s_prompt = "", s_default = "";
    private static bool s_registered;
    private static WndProcDelegate? s_wndProc;
    private static EnumThreadWndProc? s_enumProc;
    private const string CLS = "HttpDll23Input";

    private static IntPtr FindGameWindow()
    {
        // If we already cached a valid game window, reuse it
        if (s_gameHwnd != IntPtr.Zero && IsWindowVisible(s_gameHwnd))
            return s_gameHwnd;
        // Find the first visible top-level window on the current thread (the GM runner's main window)
        s_enumFound = IntPtr.Zero;
        s_enumProc ??= (hWnd, _) =>
        {
            if (IsWindowVisible(hWnd))
            {
                s_enumFound = hWnd;
                return false; // stop enumeration
            }
            return true;
        };
        EnumThreadWindows(GetCurrentThreadId(), s_enumProc, IntPtr.Zero);
        if (s_enumFound != IntPtr.Zero)
            s_gameHwnd = s_enumFound;
        return s_enumFound;
    }

    private static IntPtr WndProcImpl(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case WM_CREATE:
            {
                var dc = GetDC(hWnd);
                int dpi = GetDeviceCaps(dc, LOGPIXELSY);
                ReleaseDC(hWnd, dc);
                s_font = CreateFontW(-(9 * dpi / 72), 0, 0, 0, 400, 0, 0, 0,
                    1 /* DEFAULT_CHARSET */, 0, 0, 0, 0, "MS Shell Dlg 2");

                var lbl = CreateWindowExW(0, "STATIC", s_prompt,
                    WS_CHILD | WS_VISIBLE | SS_LEFT, 12, 10, 356, 20,
                    hWnd, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                SendMessageW(lbl, WM_SETFONT, s_font, (IntPtr)1);

                s_editHwnd = CreateWindowExW(WS_EX_CLIENTEDGE, "EDIT", s_default,
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL, 12, 35, 356, 24,
                    hWnd, (IntPtr)IDC_EDIT, IntPtr.Zero, IntPtr.Zero);
                SendMessageW(s_editHwnd, WM_SETFONT, s_font, (IntPtr)1);

                var ok = CreateWindowExW(0, "BUTTON", "OK",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 208, 70, 75, 28,
                    hWnd, (IntPtr)IDC_OK, IntPtr.Zero, IntPtr.Zero);
                SendMessageW(ok, WM_SETFONT, s_font, (IntPtr)1);

                var cancel = CreateWindowExW(0, "BUTTON", "Cancel",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP, 293, 70, 75, 28,
                    hWnd, (IntPtr)IDC_CANCEL, IntPtr.Zero, IntPtr.Zero);
                SendMessageW(cancel, WM_SETFONT, s_font, (IntPtr)1);

                SetFocus(s_editHwnd);
                SendMessageW(s_editHwnd, EM_SETSEL, IntPtr.Zero, (IntPtr)(-1));
                return IntPtr.Zero;
            }
            case WM_COMMAND:
            {
                int id = (int)wParam & 0xFFFF;
                if (id == IDC_OK)
                {
                    int len = GetWindowTextLengthW(s_editHwnd);
                    if (len > 0)
                    {
                        var buf = new char[len + 1];
                        GetWindowTextW(s_editHwnd, buf, buf.Length);
                        s_result = new string(buf, 0, len);
                    }
                    else
                        s_result = "";
                    DestroyWindow(hWnd);
                    return IntPtr.Zero;
                }
                if (id == IDC_CANCEL)
                {
                    s_result = "";
                    DestroyWindow(hWnd);
                    return IntPtr.Zero;
                }
                break;
            }
            case WM_CLOSE:
                s_result = "";
                DestroyWindow(hWnd);
                return IntPtr.Zero;
            case WM_DESTROY:
                if (s_font != IntPtr.Zero) { DeleteObject(s_font); s_font = IntPtr.Zero; }
                if (s_parentHwnd != IntPtr.Zero)
                {
                    EnableWindow(s_parentHwnd, true);
                    SetForegroundWindow(s_parentHwnd);
                }
                PostQuitMessage(0);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    internal static string Show(string title, string prompt, string defaultText)
    {
        s_prompt = prompt;
        s_default = defaultText;
        s_result = "";

        var inst = GetModuleHandleW(null);
        if (!s_registered)
        {
            s_wndProc = WndProcImpl;
            var wc = new WNDCLASS
            {
                style = CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc = Marshal.GetFunctionPointerForDelegate(s_wndProc),
                hInstance = inst,
                hCursor = LoadCursorW(IntPtr.Zero, IDC_ARROW),
                hbrBackground = (IntPtr)(15 + 1), // COLOR_BTNFACE + 1
                lpszClassName = CLS
            };
            if (RegisterClassW(ref wc) == 0)
                return "";
            s_registered = true;
        }

        s_parentHwnd = FindGameWindow();
        int dlgW = 392, dlgH = 145;
        int posX = unchecked((int)0x80000000); // CW_USEDEFAULT
        int posY = unchecked((int)0x80000000);
        if (s_parentHwnd != IntPtr.Zero && GetWindowRect(s_parentHwnd, out var rc))
        {
            posX = (rc.left + rc.right - dlgW) / 2;
            posY = (rc.top + rc.bottom - dlgH) / 2;
        }

        s_dlgHwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, CLS, title,
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
            posX, posY, dlgW, dlgH,
            s_parentHwnd, IntPtr.Zero, inst, IntPtr.Zero);
        if (s_dlgHwnd == IntPtr.Zero)
            return "";

        if (s_parentHwnd != IntPtr.Zero)
            EnableWindow(s_parentHwnd, false);

        ShowWindow(s_dlgHwnd, SW_SHOW);
        UpdateWindow(s_dlgHwnd);
        SetForegroundWindow(s_dlgHwnd);

        MSG msg;
        while (GetMessageW(out msg, IntPtr.Zero, 0, 0) > 0)
        {
            if (!IsDialogMessageW(s_dlgHwnd, ref msg))
            {
                TranslateMessage(ref msg);
                DispatchMessageW(ref msg);
            }
        }

        return s_result;
    }
}

internal static class NativeCast
{
    internal static bool ToBool(double value) => value >= 0.5;
    internal static byte ToByte(double value) => value <= byte.MinValue ? byte.MinValue : value >= byte.MaxValue ? byte.MaxValue : (byte)value;
    internal static sbyte ToSByte(double value) => value <= sbyte.MinValue ? sbyte.MinValue : value >= sbyte.MaxValue ? sbyte.MaxValue : (sbyte)value;
    internal static ushort ToUInt16(double value) => value <= ushort.MinValue ? ushort.MinValue : value >= ushort.MaxValue ? ushort.MaxValue : (ushort)value;
    internal static uint ToUInt32(double value) => value <= uint.MinValue ? uint.MinValue : value >= uint.MaxValue ? uint.MaxValue : (uint)value;
    internal static ulong ToUInt64(double value) => value <= 0 ? 0UL : value >= ulong.MaxValue ? ulong.MaxValue : (ulong)value;
    internal static short ToInt16(double value) => value <= short.MinValue ? short.MinValue : value >= short.MaxValue ? short.MaxValue : (short)value;
    internal static int ToInt32(double value) => value <= int.MinValue ? int.MinValue : value >= int.MaxValue ? int.MaxValue : (int)value;
    internal static long ToInt64(double value) => value <= long.MinValue ? long.MinValue : value >= long.MaxValue ? long.MaxValue : (long)value;
    internal static float ToFloat(double value)
    {
        if (double.IsNaN(value))
            return 0;
        if (value <= -float.MaxValue)
            return -float.MaxValue;
        if (value >= float.MaxValue)
            return float.MaxValue;
        return (float)value;
    }
}

internal sealed class NativeBuffer
{
    private byte[] data = Array.Empty<byte>();

    internal int Length { get; private set; }
    internal int Position { get; private set; }
    internal bool Error { get; private set; }
    internal int Remaining => Length - Position;
    internal ArraySegment<byte> RemainingSegment => new(data, Position, Remaining);

    internal void Clear()
    {
        data = Array.Empty<byte>();
        Length = 0;
        Position = 0;
        Error = false;
    }

    internal void ClearError() => Error = false;

    internal void SetPosition(int newPosition)
    {
        Position = Math.Clamp(newPosition, 0, Length);
    }

    private void EnsureCapacity(int newLength)
    {
        if (newLength <= data.Length)
            return;
        var required = Math.Max(newLength, 16);
        var nextCapacity = required + required / 2;
        if (nextCapacity < required)
            nextCapacity = required;
        Array.Resize(ref data, nextCapacity);
    }

    internal void SetLength(int newLength)
    {
        if (newLength < 0)
            newLength = 0;
        EnsureCapacity(newLength);
        if (newLength > Length)
            Array.Clear(data, Length, newLength - Length);
        Length = newLength;
        if (Position > Length)
            Position = Length;
    }

    internal ReadOnlySpan<byte> Slice(int offset, int count) => data.AsSpan(offset, count);

    internal void WriteBytes(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length == 0)
            return;
        var start = Length;
        SetLength(Length + bytes.Length);
        bytes.CopyTo(data.AsSpan(start, bytes.Length));
    }

    internal void LoadBytes(ReadOnlySpan<byte> bytes)
    {
        Clear();
        WriteBytes(bytes);
        Position = 0;
        Error = false;
    }

    internal bool ReadFromFile(string path)
    {
        try
        {
            LoadBytes(File.ReadAllBytes(path));
            return true;
        }
        catch
        {
            Clear();
            return false;
        }
    }

    internal bool WriteToFile(string path)
    {
        try
        {
            File.WriteAllBytes(path, data.AsSpan(0, Length).ToArray());
            return true;
        }
        catch
        {
            return false;
        }
    }

    internal void CompactIfNeeded()
    {
        if (Position == 0)
            return;
        if (Position >= Length)
        {
            Clear();
            return;
        }
        if (Position > Length / 4)
        {
            Array.Copy(data, Position, data, 0, Length - Position);
            Length -= Position;
            Position = 0;
        }
    }

    internal void EraseConsumed(int count)
    {
        SetPosition(Position + count);
        CompactIfNeeded();
    }

    private bool EnsureReadable(int count)
    {
        if (Error)
            return false;
        if (Position + count > Length)
        {
            Error = true;
            return false;
        }
        return true;
    }

    internal byte ReadUInt8()
    {
        if (!EnsureReadable(1))
            return 0;
        return data[Position++];
    }

    internal sbyte ReadInt8()
    {
        if (!EnsureReadable(1))
            return 0;
        return (sbyte)data[Position++];
    }

    internal ushort ReadUInt16()
    {
        if (!EnsureReadable(2))
            return 0;
        var value = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(Position, 2));
        Position += 2;
        return value;
    }

    internal short ReadInt16()
    {
        if (!EnsureReadable(2))
            return 0;
        var value = BinaryPrimitives.ReadInt16LittleEndian(data.AsSpan(Position, 2));
        Position += 2;
        return value;
    }

    internal int ReadInt32()
    {
        if (!EnsureReadable(4))
            return 0;
        var value = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(Position, 4));
        Position += 4;
        return value;
    }

    internal uint ReadUInt32()
    {
        if (!EnsureReadable(4))
            return 0;
        var value = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(Position, 4));
        Position += 4;
        return value;
    }

    internal long ReadInt64()
    {
        if (!EnsureReadable(8))
            return 0;
        var value = BinaryPrimitives.ReadInt64LittleEndian(data.AsSpan(Position, 8));
        Position += 8;
        return value;
    }

    internal ulong ReadUInt64()
    {
        if (!EnsureReadable(8))
            return 0;
        var value = BinaryPrimitives.ReadUInt64LittleEndian(data.AsSpan(Position, 8));
        Position += 8;
        return value;
    }

    internal float ReadFloat32()
    {
        return BitConverter.Int32BitsToSingle(ReadInt32());
    }

    internal double ReadFloat64()
    {
        if (!EnsureReadable(8))
            return 0;
        var value = BinaryPrimitives.ReadDoubleLittleEndian(data.AsSpan(Position, 8));
        Position += 8;
        return value;
    }

    internal uint ReadUIntV()
    {
        if (Error)
            return 0;
        if (!EnsureReadable(1))
            return 0;
        uint value = data[Position];
        if ((value & 1) != 0)
        {
            Position += 1;
            return value >> 1;
        }
        if ((value & 2) != 0)
        {
            if (!EnsureReadable(2))
                return 0;
            value = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(Position, 2));
            Position += 2;
            return (value >> 2) + 0x80U;
        }
        if ((value & 4) != 0)
        {
            if (!EnsureReadable(3))
                return 0;
            value |= (uint)BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(Position + 1, 2)) << 8;
            Position += 3;
            return (value >> 3) + 0x4080U;
        }
        if (!EnsureReadable(4))
            return 0;
        value = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(Position, 4));
        Position += 4;
        return (value >> 3) + 0x204080U;
    }

    internal string ReadString()
    {
        if (Error)
            return string.Empty;
        for (var index = Position; index < Length; index++)
        {
            if (data[index] == 0)
            {
                var bytes = data.AsSpan(Position, index - Position).ToArray();
                Position = index + 1;
                return Encoding.UTF8.GetString(bytes);
            }
        }
        Error = true;
        return string.Empty;
    }

    internal void WriteUInt8(byte value)
    {
        SetLength(Length + 1);
        data[Length - 1] = value;
    }

    internal void WriteInt8(sbyte value)
    {
        SetLength(Length + 1);
        data[Length - 1] = (byte)value;
    }

    internal void WriteUInt16(ushort value)
    {
        var start = Length;
        SetLength(Length + 2);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(start, 2), value);
    }

    internal void WriteInt16(short value)
    {
        var start = Length;
        SetLength(Length + 2);
        BinaryPrimitives.WriteInt16LittleEndian(data.AsSpan(start, 2), value);
    }

    internal void WriteInt32(int value)
    {
        var start = Length;
        SetLength(Length + 4);
        BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(start, 4), value);
    }

    internal void WriteUInt32(uint value)
    {
        var start = Length;
        SetLength(Length + 4);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(start, 4), value);
    }

    internal void WriteInt64(long value)
    {
        var start = Length;
        SetLength(Length + 8);
        BinaryPrimitives.WriteInt64LittleEndian(data.AsSpan(start, 8), value);
    }

    internal void WriteUInt64(ulong value)
    {
        var start = Length;
        SetLength(Length + 8);
        BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(start, 8), value);
    }

    internal void WriteFloat32(float value) => WriteInt32(BitConverter.SingleToInt32Bits(value));
    internal void WriteFloat64(double value)
    {
        var start = Length;
        SetLength(Length + 8);
        BinaryPrimitives.WriteDoubleLittleEndian(data.AsSpan(start, 8), value);
    }

    internal void WriteUIntV(uint value)
    {
        if (value < 0x80U)
        {
            WriteUInt8((byte)((value << 1) | 1));
            return;
        }
        if (value < 0x4080U)
        {
            WriteUInt16((ushort)(((value - 0x80U) << 2) | 2));
            return;
        }
        if (value < 0x204080U)
        {
            var encoded = ((value - 0x4080U) << 3) | 4;
            var start = Length;
            SetLength(Length + 3);
            data[start] = (byte)(encoded & 0xFF);
            data[start + 1] = (byte)((encoded >> 8) & 0xFF);
            data[start + 2] = (byte)((encoded >> 16) & 0xFF);
            return;
        }
        var full = (value - 0x204080U) << 3;
        var offset = Length;
        SetLength(Length + 4);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(offset, 4), full);
    }

    internal void WriteString(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value ?? string.Empty);
        WriteBytes(bytes);
        WriteUInt8(0);
    }
}

internal sealed class TcpSocketState : IDisposable
{
    private const int StateNotConnected = 0;
    private const int StateConnecting = 1;
    private const int StateConnected = 2;
    private const int StateClosed = 4;
    private const int StateError = 5;

    private Socket? socket;
    private List<IPEndPoint>? endpoints;
    private int endpointIndex;
    private bool shouldShutdown;
    private readonly NativeBuffer readBuffer = new();
    private readonly NativeBuffer writeBuffer = new();

    internal int State { get; private set; } = StateNotConnected;

    public void Dispose() => Reset();

    internal void Reset()
    {
        try
        {
            socket?.Dispose();
        }
        catch
        {
        }
        socket = null;
        endpoints = null;
        endpointIndex = -1;
        shouldShutdown = false;
        readBuffer.Clear();
        writeBuffer.Clear();
        State = StateNotConnected;
    }

    internal void Connect(string address, ushort port)
    {
        if (State != StateNotConnected)
            Reset();

        try
        {
            var resolved = Dns.GetHostAddresses(address);
            endpoints = new List<IPEndPoint>();
            foreach (var ip in resolved)
            {
                if (ip.AddressFamily == AddressFamily.InterNetwork || ip.AddressFamily == AddressFamily.InterNetworkV6)
                    endpoints.Add(new IPEndPoint(ip, port));
            }
        }
        catch
        {
            State = StateError;
            return;
        }

        if (endpoints == null || endpoints.Count == 0)
        {
            State = StateError;
            return;
        }

        endpointIndex = -1;
        TryNextEndpoint();
    }

    private static bool IsWouldBlock(SocketError error)
    {
        return error == SocketError.WouldBlock || error == SocketError.IOPending || error == SocketError.InProgress || error == SocketError.AlreadyInProgress;
    }

    private void TryNextEndpoint()
    {
        socket?.Dispose();
        socket = null;

        var remainingEndpoints = endpoints;
        if (remainingEndpoints == null)
        {
            State = StateError;
            return;
        }

        while (++endpointIndex < remainingEndpoints.Count)
        {
            var endpoint = remainingEndpoints[endpointIndex];
            var candidate = new Socket(endpoint.AddressFamily, SocketType.Stream, ProtocolType.Tcp)
            {
                Blocking = false,
                NoDelay = true,
            };
            try
            {
                candidate.Connect(endpoint);
                socket = candidate;
                State = StateConnected;
                endpoints = null;
                return;
            }
            catch (SocketException ex) when (IsWouldBlock(ex.SocketErrorCode) || ex.SocketErrorCode == SocketError.IsConnected)
            {
                socket = candidate;
                State = StateConnecting;
                return;
            }
            catch
            {
                candidate.Dispose();
            }
        }

        endpoints = null;
        State = StateError;
    }

    private void CloseToError()
    {
        try
        {
            socket?.Dispose();
        }
        catch
        {
        }
        socket = null;
        State = StateError;
    }

    internal void UpdateRead()
    {
        if (State == StateConnecting)
        {
            if (socket == null)
            {
                State = StateError;
                return;
            }
            try
            {
                var writable = socket.Poll(0, SelectMode.SelectWrite);
                var errored = socket.Poll(0, SelectMode.SelectError);
                if (!writable && !errored)
                    return;
                var rawError = socket.GetSocketOption(SocketOptionLevel.Socket, SocketOptionName.Error);
                var code = rawError is int errorCode ? (SocketError)errorCode : SocketError.SocketError;
                if (errored || code != SocketError.Success)
                {
                    TryNextEndpoint();
                    return;
                }
                State = StateConnected;
                endpoints = null;
            }
            catch
            {
                CloseToError();
                return;
            }
        }

        if (State != StateConnected || socket == null)
            return;

        var buffer = new byte[10240];
        while (true)
        {
            try
            {
                var received = socket.Receive(buffer, SocketFlags.None);
                if (received == 0)
                {
                    State = StateClosed;
                    return;
                }
                readBuffer.WriteBytes(buffer.AsSpan(0, received));
                if (received < buffer.Length)
                    return;
            }
            catch (SocketException ex) when (ex.SocketErrorCode == SocketError.WouldBlock)
            {
                return;
            }
            catch
            {
                CloseToError();
                return;
            }
        }
    }

    internal void UpdateWrite()
    {
        if ((State != StateConnected && State != StateClosed) || socket == null || writeBuffer.Remaining == 0)
            return;

        try
        {
            var sent = socket.Send(writeBuffer.RemainingSegment, SocketFlags.None);
            writeBuffer.SetPosition(writeBuffer.Position + sent);
            writeBuffer.CompactIfNeeded();
            if (shouldShutdown && writeBuffer.Remaining == 0)
                socket.Shutdown(SocketShutdown.Send);
        }
        catch (SocketException ex) when (ex.SocketErrorCode == SocketError.WouldBlock)
        {
        }
        catch
        {
            CloseToError();
        }
    }

    internal void MarkShutdown() => shouldShutdown = true;

    internal bool ReadMessage(NativeBuffer destination)
    {
        readBuffer.ClearError();
        var start = readBuffer.Position;
        var length = readBuffer.ReadUIntV();
        var contentStart = readBuffer.Position;
        readBuffer.SetPosition(start);
        if (readBuffer.Error || length > readBuffer.Length - contentStart)
            return false;

        destination.LoadBytes(readBuffer.Slice(contentStart, (int)length));
        readBuffer.EraseConsumed(contentStart - start + (int)length);
        return true;
    }

    internal void WriteMessage(NativeBuffer source)
    {
        if (shouldShutdown || State == StateError)
            return;
        writeBuffer.WriteUIntV((uint)source.Length);
        writeBuffer.WriteBytes(source.Slice(0, source.Length));
    }
}

internal sealed class UdpSocketState : IDisposable
{
    private const int StateNotStarted = 0;
    private const int StateStarted = 1;
    private const int StateError = 2;

    private Socket? socket;
    private EndPoint? destination;
    private EndPoint? lastRemote;

    internal int State { get; private set; } = StateNotStarted;
    internal int MaxMessageSize { get; private set; }

    public void Dispose() => Reset();

    internal void Reset()
    {
        try
        {
            socket?.Dispose();
        }
        catch
        {
        }
        socket = null;
        destination = null;
        lastRemote = null;
        MaxMessageSize = 0;
        State = StateNotStarted;
    }

    internal void Start(bool ipv6, ushort port)
    {
        if (State != StateNotStarted)
            Reset();

        try
        {
            socket = new Socket(ipv6 ? AddressFamily.InterNetworkV6 : AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp)
            {
                Blocking = false,
            };
            if (port != 0)
            {
                socket.Bind(new IPEndPoint(ipv6 ? IPAddress.IPv6Any : IPAddress.Any, port));
            }
            MaxMessageSize = 65507;
            State = StateStarted;
        }
        catch
        {
            try
            {
                socket?.Dispose();
            }
            catch
            {
            }
            socket = null;
            State = StateError;
        }
    }

    internal void SetDestination(string address, ushort port)
    {
        if (socket == null)
        {
            State = StateError;
            return;
        }

        try
        {
            foreach (var ip in Dns.GetHostAddresses(address))
            {
                if (ip.AddressFamily != AddressFamily.InterNetwork && ip.AddressFamily != AddressFamily.InterNetworkV6)
                    continue;
                destination = new IPEndPoint(ip, port);
                return;
            }
        }
        catch
        {
        }

        try
        {
            socket.Dispose();
        }
        catch
        {
        }
        socket = null;
        State = StateError;
    }

    internal bool Receive(NativeBuffer destinationBuffer)
    {
        if (State != StateStarted || socket == null)
            return false;

        var bytes = new byte[Math.Max(MaxMessageSize, 1024)];
        EndPoint remote = socket.AddressFamily == AddressFamily.InterNetworkV6
            ? new IPEndPoint(IPAddress.IPv6Any, 0)
            : new IPEndPoint(IPAddress.Any, 0);

        try
        {
            var received = socket.ReceiveFrom(bytes, 0, bytes.Length, SocketFlags.None, ref remote);
            destinationBuffer.LoadBytes(bytes.AsSpan(0, received));
            lastRemote = remote;
            return true;
        }
        catch (SocketException ex) when (ex.SocketErrorCode == SocketError.WouldBlock)
        {
            destinationBuffer.Clear();
            return false;
        }
        catch
        {
            try
            {
                socket.Dispose();
            }
            catch
            {
            }
            socket = null;
            State = StateError;
            destinationBuffer.Clear();
            return false;
        }
    }

    internal void Send(NativeBuffer source)
    {
        if (State != StateStarted || socket == null || destination == null)
            return;

        try
        {
            socket.SendTo(source.Slice(0, source.Length).ToArray(), SocketFlags.None, destination);
        }
        catch (SocketException ex) when (ex.SocketErrorCode == SocketError.WouldBlock)
        {
        }
        catch
        {
            try
            {
                socket.Dispose();
            }
            catch
            {
            }
            socket = null;
            State = StateError;
        }
    }
}

public static class Exports
{
    private static NativeBuffer? GetBuffer(double id)
    {
        var key = NativeCast.ToInt32(id);
        NativeState.Buffers.TryGetValue(key, out var buffer);
        return buffer;
    }

    private static TcpSocketState? GetSocket(double id)
    {
        var key = NativeCast.ToInt32(id);
        NativeState.Sockets.TryGetValue(key, out var socket);
        return socket;
    }

    private static UdpSocketState? GetUdpSocket(double id)
    {
        var key = NativeCast.ToInt32(id);
        NativeState.UdpSockets.TryGetValue(key, out var socket);
        return socket;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_create", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferCreate()
    {
        var id = ++NativeState.NextBufferId;
        NativeState.Buffers[id] = new NativeBuffer();
        return id;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_destroy", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferDestroy(double id)
    {
        var key = NativeCast.ToInt32(id);
        if (!NativeState.Buffers.Remove(key))
            return 0;
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_clear", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferClear(double id)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.Clear();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_from_file", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadFromFile(double id, IntPtr filename)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        return buffer.ReadFromFile(NativeStrings.Read(filename)) ? 1 : 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_to_file", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteToFile(double id, IntPtr filename)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        return buffer.WriteToFile(NativeStrings.Read(filename)) ? 1 : 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_uint8", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadUInt8(double id) => GetBuffer(id)?.ReadUInt8() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_int8", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadInt8(double id) => GetBuffer(id)?.ReadInt8() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_uint16", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadUInt16(double id) => GetBuffer(id)?.ReadUInt16() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_int16", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadInt16(double id) => GetBuffer(id)?.ReadInt16() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_int32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadInt32(double id) => GetBuffer(id)?.ReadInt32() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_uint32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadUInt32(double id) => GetBuffer(id)?.ReadUInt32() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_int64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadInt64(double id) => GetBuffer(id)?.ReadInt64() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_uint64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadUInt64(double id) => GetBuffer(id)?.ReadUInt64() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_float32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadFloat32(double id) => GetBuffer(id)?.ReadFloat32() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_float64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferReadFloat64(double id) => GetBuffer(id)?.ReadFloat64() ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "buffer_read_string", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static IntPtr BufferReadString(double id)
    {
        var buffer = GetBuffer(id);
        return NativeStrings.Write(buffer?.ReadString() ?? string.Empty);
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_uint8", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteUInt8(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteUInt8(NativeCast.ToByte(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_uint16", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteUInt16(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteUInt16(NativeCast.ToUInt16(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_int16", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteInt16(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteInt16(NativeCast.ToInt16(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_int32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteInt32(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteInt32(NativeCast.ToInt32(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_uint32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteUInt32(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteUInt32(NativeCast.ToUInt32(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_int64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteInt64(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteInt64(NativeCast.ToInt64(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_int8", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteInt8(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteInt8(NativeCast.ToSByte(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_uint64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteUInt64(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteUInt64(NativeCast.ToUInt64(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_float32", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteFloat32(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteFloat32(NativeCast.ToFloat(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_float64", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteFloat64(double id, double value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteFloat64(value);
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "buffer_write_string", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double BufferWriteString(double id, IntPtr value)
    {
        var buffer = GetBuffer(id);
        if (buffer == null)
            return 0;
        buffer.WriteString(NativeStrings.Read(value));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "set_utf8_mode", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SetUtf8Mode(double enabled)
    {
        NativeStrings.SetUtf8Mode(enabled >= 0.5);
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "strip_non_bmp", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static IntPtr StripNonBmp(IntPtr value)
    {
        var str = NativeStrings.Read(value);
        var sb = new System.Text.StringBuilder(str.Length);
        foreach (var ch in str)
        {
            if (!char.IsSurrogate(ch))
                sb.Append(ch);
        }
        return NativeStrings.Write(sb.ToString());
    }

    [UnmanagedCallersOnly(EntryPoint = "ansi_to_utf8", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static IntPtr AnsiToUtf8(IntPtr value)
    {
        return NativeStrings.ConvertAnsiToUtf8(value);
    }

    // P2: native package hash. Byte-identical to the pure-GML @skin_hash_dir
    // (md5.gml): md5 over (file name bytes + 0x00 + raw file bytes) for every
    // regular file directly inside the directory, names sorted by byte order.
    // Non-ASCII file names are refused ("" -> the GML caller falls back to the
    // pure-GML walk, whose ANSI/UTF-8 byte semantics differ per engine string
    // mode). Any IO error returns "" as well.
    [UnmanagedCallersOnly(EntryPoint = "md5_dir", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static IntPtr Md5Dir(IntPtr path)
    {
        try
        {
            var dir = NativeStrings.Read(path);
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
                return NativeStrings.Write(string.Empty);
            var names = new List<string>();
            foreach (var full in Directory.GetFiles(dir))
            {
                var name = Path.GetFileName(full);
                foreach (var c in name)
                    if (c > 0x7F)
                        return NativeStrings.Write(string.Empty);
                // The engine's file_find_first(mask, 0) never yields Hidden or
                // System entries (verified in-game: a Hidden/System file inside
                // a skin dir is not enumerated, while ReadOnly/Archive/Normal
                // are). The native walk must mirror that exact set - otherwise
                // a pure-GML fallback client and a native client hash the same
                // package differently and can never match (silent split).
                var attrs = File.GetAttributes(full);
                if ((attrs & (FileAttributes.Hidden | FileAttributes.System)) != 0)
                    continue;
                names.Add(name);
            }
            // GML sorts by raw byte order; for the ASCII subset ordinal order
            // is the same.
            names.Sort(string.CompareOrdinal);
            using var md5 = MD5.Create();
            var ascii = Encoding.ASCII;
            var zero = new byte[1];
            foreach (var name in names)
            {
                var nameBytes = ascii.GetBytes(name);
                md5.TransformBlock(nameBytes, 0, nameBytes.Length, null, 0);
                md5.TransformBlock(zero, 0, 1, null, 0);
                byte[] data;
                try
                {
                    data = File.ReadAllBytes(Path.Combine(dir, name));
                }
                catch
                {
                    return NativeStrings.Write(string.Empty);
                }
                if (data.Length > 0)
                    md5.TransformBlock(data, 0, data.Length, null, 0);
            }
            md5.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            return NativeStrings.Write(Convert.ToHexString(md5.Hash!).ToLowerInvariant());
        }
        catch
        {
            return NativeStrings.Write(string.Empty);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "input_box", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static IntPtr InputBoxExport(IntPtr titlePtr, IntPtr promptPtr, IntPtr defaultPtr)
    {
        var title = NativeStrings.Read(titlePtr);
        var prompt = NativeStrings.Read(promptPtr);
        var defaultText = NativeStrings.Read(defaultPtr);
        var result = InputDialog.Show(title, prompt, defaultText);
        return NativeStrings.Write(result);
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_create", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketCreate()
    {
        var id = ++NativeState.NextSocketId;
        NativeState.Sockets[id] = new TcpSocketState();
        return id;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_destroy", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketDestroy(double id)
    {
        var key = NativeCast.ToInt32(id);
        if (!NativeState.Sockets.Remove(key, out var socket))
            return 0;
        socket.Dispose();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_get_state", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketGetState(double id) => GetSocket(id)?.State ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "socket_reset", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketReset(double id)
    {
        var socket = GetSocket(id);
        if (socket == null)
            return 0;
        socket.Reset();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_connect", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketConnect(double id, IntPtr address, double port)
    {
        var socket = GetSocket(id);
        if (socket == null)
            return 0;
        socket.Connect(NativeStrings.Read(address), NativeCast.ToUInt16(port));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_update_read", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketUpdateRead(double id)
    {
        var socket = GetSocket(id);
        if (socket == null)
            return 0;
        socket.UpdateRead();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_update_write", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketUpdateWrite(double id)
    {
        var socket = GetSocket(id);
        if (socket == null)
            return 0;
        socket.UpdateWrite();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_shut_down", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketShutDown(double id)
    {
        var socket = GetSocket(id);
        if (socket == null)
            return 0;
        socket.MarkShutdown();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_read_message", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketReadMessage(double id, double bufferId)
    {
        var socket = GetSocket(id);
        var buffer = GetBuffer(bufferId);
        if (socket == null || buffer == null)
            return 0;
        return socket.ReadMessage(buffer) ? 1 : 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "socket_write_message", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double SocketWriteMessage(double id, double bufferId)
    {
        var socket = GetSocket(id);
        var buffer = GetBuffer(bufferId);
        if (socket == null || buffer == null)
            return 0;
        socket.WriteMessage(buffer);
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_create", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketCreate()
    {
        var id = ++NativeState.NextUdpSocketId;
        NativeState.UdpSockets[id] = new UdpSocketState();
        return id;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_destroy", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketDestroy(double id)
    {
        var key = NativeCast.ToInt32(id);
        if (!NativeState.UdpSockets.Remove(key, out var socket))
            return 0;
        socket.Dispose();
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_exists", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketExists(double id) => GetUdpSocket(id) == null ? 0 : 1;

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_get_state", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketGetState(double id) => GetUdpSocket(id)?.State ?? 0;

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_start", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketStart(double id, double ipv6, double port)
    {
        var socket = GetUdpSocket(id);
        if (socket == null)
            return 0;
        socket.Start(NativeCast.ToBool(ipv6), NativeCast.ToUInt16(port));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_set_destination", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketSetDestination(double id, IntPtr address, double port)
    {
        var socket = GetUdpSocket(id);
        if (socket == null)
            return 0;
        socket.SetDestination(NativeStrings.Read(address), NativeCast.ToUInt16(port));
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_receive", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketReceive(double id, double bufferId)
    {
        var socket = GetUdpSocket(id);
        var buffer = GetBuffer(bufferId);
        if (socket == null || buffer == null)
            return 0;
        return socket.Receive(buffer) ? 1 : 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "udpsocket_send", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static double UdpSocketSend(double id, double bufferId)
    {
        var socket = GetUdpSocket(id);
        var buffer = GetBuffer(bufferId);
        if (socket == null || buffer == null)
            return 0;
        socket.Send(buffer);
        return 1;
    }
}
