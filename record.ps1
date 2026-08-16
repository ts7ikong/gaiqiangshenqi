#Requires -Version 5.0
# 烽火地带 弹道录制工具 (Raw Input + 倒计时)

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public static class RawMouse {
    const int  WM_INPUT        = 0x00FF;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const uint RID_INPUT       = 0x10000003;
    const uint RIM_TYPEMOUSE   = 0;

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE {
        public ushort usUsagePage, usUsage;
        public uint   dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER {
        public uint   dwType, dwSize;
        public IntPtr hDevice, wParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWMOUSE {
        public ushort usFlags;
        public uint   ulButtons, ulRawButtons;
        public int    lLastX, lLastY;
        public uint   ulExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUT {
        public RAWINPUTHEADER header;
        public RAWMOUSE       mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG {
        public IntPtr hwnd;
        public uint   message;
        public IntPtr wParam, lParam;
        public uint   time;
        public int    ptX, ptY;
    }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct WNDCLASSEX {
        public uint   cbSize, style;
        public IntPtr lpfnWndProc;
        public int    cbClsExtra, cbWndExtra;
        public IntPtr hInstance, hIcon, hCursor, hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
        public IntPtr hIconSm;
    }

    delegate IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);

    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateWindowEx(uint ex, string cls, string wnd, uint style,
        int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
    [DllImport("user32.dll")]
    static extern IntPtr DefWindowProc(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool RegisterRawInputDevices(
        [MarshalAs(UnmanagedType.LPArray)] RAWINPUTDEVICE[] d, uint n, uint sz);
    [DllImport("user32.dll")]
    static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdr);
    [DllImport("user32.dll")]
    static extern int GetMessage(out MSG m, IntPtr hwnd, uint mn, uint mx);
    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetModuleHandle(string n);

    static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

    public static volatile bool Recording, Done, Started;
    public static string Error = "";
    public static int MoveCount, TotalMessages;
    public static readonly Stopwatch Timer = new Stopwatch();
    public static readonly List<int[]> Deltas = new List<int[]>();

    static WndProc s_proc;

    static IntPtr WndProcFn(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp) {
        if (msg == WM_INPUT) {
            TotalMessages++;
            uint hdrSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            uint size = 0;
            GetRawInputData(lp, RID_INPUT, IntPtr.Zero, ref size, hdrSize);
            if (size > 0 && Recording) {
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    if (GetRawInputData(lp, RID_INPUT, buf, ref size, hdrSize) == size) {
                        RAWINPUT ri = (RAWINPUT)Marshal.PtrToStructure(buf, typeof(RAWINPUT));
                        if (ri.header.dwType == RIM_TYPEMOUSE && (ri.mouse.usFlags & 1) == 0) {
                            int x = ri.mouse.lLastX, y = ri.mouse.lLastY;
                            if (x != 0 || y != 0) {
                                MoveCount++;
                                lock (Deltas) {
                                    Deltas.Add(new int[] { x, y, (int)Timer.ElapsedMilliseconds });
                                }
                            }
                        }
                    }
                } finally { Marshal.FreeHGlobal(buf); }
            }
        }
        return DefWindowProc(hwnd, msg, wp, lp);
    }

    public static void StartRecording() {
        lock (Deltas) { Deltas.Clear(); }
        MoveCount = 0;
        Timer.Restart();
        Recording = true;
    }

    public static void StopRecording() {
        Recording = false;
        Done = true;
    }

    static void MsgLoop() {
        try {
            s_proc = new WndProc(WndProcFn);
            var wc = new WNDCLASSEX();
            wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
            wc.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(s_proc);
            wc.hInstance = GetModuleHandle(null);
            wc.lpszClassName = "RawMouseWnd2";
            if (RegisterClassEx(ref wc) == 0) {
                Error = "RegisterClassEx failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            var hwnd = CreateWindowEx(0, "RawMouseWnd2", "", 0, 0, 0, 0, 0,
                HWND_MESSAGE, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
            if (hwnd == IntPtr.Zero) {
                Error = "CreateWindowEx failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            var rid = new RAWINPUTDEVICE[] {
                new RAWINPUTDEVICE {
                    usUsagePage = 0x01, usUsage = 0x02,
                    dwFlags = RIDEV_INPUTSINK, hwndTarget = hwnd
                }
            };
            if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) {
                Error = "RegisterRawInputDevices failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            Started = true;
            MSG m; int ret;
            while (!Done && (ret = GetMessage(out m, IntPtr.Zero, 0, 0)) != 0) {
                if (ret == -1) break;
                TranslateMessage(ref m);
                DispatchMessage(ref m);
            }
        } catch (Exception ex) {
            Error = ex.Message; Started = true;
        }
    }

    public static void Start() {
        var t = new Thread(new ThreadStart(MsgLoop));
        t.IsBackground = true; t.Start();
    }
}
'@

try {
    Add-Type -TypeDefinition $src -ErrorAction Stop
} catch {
    Write-Host ""
    Write-Host " [编译错误] $_" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

$host.UI.RawUI.WindowTitle = "烽火地带 弹道录制"
Write-Host ""
Write-Host "  烽火地带 弹道录制工具 (倒计时录制)" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

[RawMouse]::Start()
$t0 = [DateTime]::Now
while (-not [RawMouse]::Started -and ([DateTime]::Now - $t0).TotalSeconds -lt 5) {
    Start-Sleep -Milliseconds 50
}
if ([RawMouse]::Error -ne "") {
    Write-Host " 错误: $([RawMouse]::Error)" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
Write-Host " Raw Input 就绪" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 训练场瞄准靶子，关闭压枪器"
Write-Host "  2. 游戏切到全屏窗口化，把此窗口放一边可见"
Write-Host "  3. 按 Enter → 3秒倒计时 → 立刻开枪压枪"
Write-Host "  4. 射完后此窗口自动保存"
Write-Host ""

$duration = 0
while ($duration -lt 1 -or $duration -gt 30) {
    $input = Read-Host " 请输入录制时长（秒，建议4-6秒，对应一梭子时长）"
    $duration = [int]$input
}

Write-Host ""
Read-Host " 准备好后按 Enter 开始倒计时，然后立刻切到游戏射击"
Write-Host ""

for ($i = 3; $i -ge 1; $i--) {
    Write-Host " $i..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host " 开始！立刻射击！" -ForegroundColor Green

[RawMouse]::StartRecording()

$elapsed = 0
while ($elapsed -lt $duration) {
    Start-Sleep -Milliseconds 200
    $elapsed = [RawMouse]::Timer.ElapsedMilliseconds / 1000.0
    $bar = "#" * [int]($elapsed / $duration * 20)
    $pct = [int]($elapsed / $duration * 100)
    Write-Host -NoNewline "`r [$($bar.PadRight(20))] $pct%  移动点=$([RawMouse]::MoveCount) "
}
Write-Host ""

[RawMouse]::StopRecording()
Start-Sleep -Milliseconds 100

$deltas = [RawMouse]::Deltas

Write-Host ""
Write-Host " 录制完成：$($deltas.Count) 个数据点  移动消息=$([RawMouse]::TotalMessages)" -ForegroundColor DarkGray

if ($deltas.Count -lt 5) {
    Write-Host " 数据太少（移动消息=$([RawMouse]::TotalMessages)），请检查是否在射击" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

$cumX = 0; $cumY = 0
$lines = $deltas | ForEach-Object {
    $cumX += -$_[0]; $cumY += -$_[1]
    '{"x":' + $cumX + ',"y":' + $cumY + ',"t":' + $_[2] + '}'
}
$json = "[" + ($lines -join ",") + "]"
$savePath = Join-Path $PSScriptRoot "trajectory.json"
[IO.File]::WriteAllText($savePath, $json, [Text.Encoding]::UTF8)

Write-Host " 已保存: trajectory.json ($($deltas.Count) 个数据点)" -ForegroundColor Green
Write-Host ""
Write-Host " 请回到浏览器，点击「载入录制」" -ForegroundColor Cyan
Write-Host ""
Write-Host " 按任意键关闭..."
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
