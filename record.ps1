#Requires -Version 5.0
# 烽火地带 弹道录制工具 (Raw Input)

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public static class RawMouse {
    const int  WM_INPUT   = 0x00FF;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const uint RID_INPUT  = 0x10000003;
    const uint RIM_TYPEMOUSE = 0;

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE {
        public ushort usUsagePage;
        public ushort usUsage;
        public uint   dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER {
        public uint   dwType;
        public uint   dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWMOUSE {
        public ushort usFlags;
        public uint   ulButtons;      // low16=usButtonFlags, high16=usButtonData
        public uint   ulRawButtons;
        public int    lLastX;
        public int    lLastY;
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
        public IntPtr wParam;
        public IntPtr lParam;
        public uint   time;
        public int    ptX, ptY;
    }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct WNDCLASSEX {
        public uint   cbSize;
        public uint   style;
        public IntPtr lpfnWndProc;
        public int    cbClsExtra;
        public int    cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
        public IntPtr hIconSm;
    }

    delegate IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);

    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateWindowEx(uint exStyle, string cls, string wnd, uint style,
        int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr hInst, IntPtr param);
    [DllImport("user32.dll")]
    static extern IntPtr DefWindowProc(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool RegisterRawInputDevices(
        [MarshalAs(UnmanagedType.LPArray)] RAWINPUTDEVICE[] devs, uint n, uint sz);
    [DllImport("user32.dll")]
    static extern uint GetRawInputData(IntPtr hRaw, uint cmd, IntPtr data, ref uint size, uint hdrSize);
    [DllImport("user32.dll")]
    static extern int GetMessage(out MSG m, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int vk);

    static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

    public static volatile bool Recording, Done, Started;
    public static string Error = "";
    public static int MoveCount, TotalMessages;
    public static int AsyncL, AsyncR;   // GetAsyncKeyState 检测到的左/右键次数
    public static readonly Stopwatch Timer = new Stopwatch();
    public static readonly List<int[]> Deltas = new List<int[]>();

    static WndProc s_proc;

    // Raw Input 只负责接收 X/Y 移动量
    static IntPtr WndProcFn(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp) {
        if (msg == WM_INPUT && !Done) {
            TotalMessages++;
            uint hdrSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            uint size = 0;
            GetRawInputData(lp, RID_INPUT, IntPtr.Zero, ref size, hdrSize);
            if (size > 0) {
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    if (GetRawInputData(lp, RID_INPUT, buf, ref size, hdrSize) == size) {
                        RAWINPUT ri = (RAWINPUT)Marshal.PtrToStructure(buf, typeof(RAWINPUT));
                        if (ri.header.dwType == RIM_TYPEMOUSE && Recording
                            && (ri.mouse.usFlags & 1) == 0) {
                            int x = ri.mouse.lLastX, y = ri.mouse.lLastY;
                            if (x != 0 || y != 0) {
                                MoveCount++;
                                Deltas.Add(new int[] { x, y, (int)Timer.ElapsedMilliseconds });
                            }
                        }
                    }
                } finally { Marshal.FreeHGlobal(buf); }
            }
        }
        return DefWindowProc(hwnd, msg, wp, lp);
    }

    // 独立线程用 GetAsyncKeyState 轮询按键（不受 RIDEV_NOLEGACY 影响）
    static void ButtonPollLoop() {
        bool wasL = false, wasR = false;
        while (!Done) {
            bool curL = (GetAsyncKeyState(0x01) & 0x8000) != 0; // VK_LBUTTON
            bool curR = (GetAsyncKeyState(0x02) & 0x8000) != 0; // VK_RBUTTON
            if (curL && !wasL) AsyncL++;
            if (curR && !wasR) AsyncR++;

            // 触发：右键已按下时，左键按下 → 开始
            if (curL && curR && !wasL && !Recording) {
                lock (Deltas) { Deltas.Clear(); }
                Timer.Restart(); Recording = true;
            }
            // 停止：录制中左键松开
            if (wasL && !curL && Recording) {
                Recording = false; Done = true;
            }
            wasL = curL; wasR = curR;
            Thread.Sleep(1);
        }
    }

    static void MsgLoop() {
        try {
            s_proc = new WndProc(WndProcFn);
            var wc = new WNDCLASSEX();
            wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
            wc.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(s_proc);
            wc.hInstance = GetModuleHandle(null);
            wc.lpszClassName = "RawMouseWnd";
            if (RegisterClassEx(ref wc) == 0) {
                Error = "RegisterClassEx failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            var hwnd = CreateWindowEx(0, "RawMouseWnd", "", 0, 0, 0, 0, 0,
                HWND_MESSAGE, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
            if (hwnd == IntPtr.Zero) {
                Error = "CreateWindowEx failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            var rid = new RAWINPUTDEVICE[] {
                new RAWINPUTDEVICE {
                    usUsagePage = 0x01,
                    usUsage     = 0x02,
                    dwFlags     = RIDEV_INPUTSINK,
                    hwndTarget  = hwnd
                }
            };
            if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) {
                Error = "RegisterRawInputDevices failed err=" + Marshal.GetLastWin32Error();
                Started = true; return;
            }
            Started = true;
            MSG m; int ret;
            while (!Done && (ret = GetMessage(out m, IntPtr.Zero, 0, 0)) != 0) {
                if (ret == -1) { Error = "GetMessage error"; break; }
                TranslateMessage(ref m);
                DispatchMessage(ref m);
            }
        } catch (Exception ex) {
            Error = ex.Message; Started = true;
        }
    }

    public static void Start() {
        var t1 = new Thread(new ThreadStart(MsgLoop));
        t1.IsBackground = true; t1.Start();
        var t2 = new Thread(new ThreadStart(ButtonPollLoop));
        t2.IsBackground = true; t2.Start();
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
Write-Host "  烽火地带 弹道录制工具 (Raw Input)" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 训练场瞄准靶子，关闭压枪器"
Write-Host "  2. 此窗口按 Enter，切换回游戏"
Write-Host "  3. 右键（开镜）+ 左键（开枪），自动开始录制"
Write-Host "  4. 打完松开左键，自动停止保存"
Write-Host "  5. 回到浏览器点「载入录制」"
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

Write-Host " Raw Input 注册成功" -ForegroundColor DarkGray
Read-Host " 按 Enter 后切换到游戏，右键+左键开枪即自动开始..."
Write-Host ""
Write-Host " 等待开枪..." -ForegroundColor Cyan

$timeout = [DateTime]::Now.AddSeconds(60)
$notified = $false
$lastReport = [DateTime]::Now
while (-not [RawMouse]::Done -and [DateTime]::Now -lt $timeout) {
    if ([RawMouse]::Recording -and -not $notified) {
        Write-Host " 录制中！打完松开左键..." -ForegroundColor Green
        $notified = $true
    }
    if (([DateTime]::Now - $lastReport).TotalSeconds -ge 5) {
        Write-Host " [心跳] 移动消息=$([RawMouse]::TotalMessages) 异步左键=$([RawMouse]::AsyncL) 异步右键=$([RawMouse]::AsyncR)" -ForegroundColor DarkGray
        $lastReport = [DateTime]::Now
    }
    Start-Sleep -Milliseconds 50
}

[RawMouse]::Done = $true
Start-Sleep -Milliseconds 100
$deltas = [RawMouse]::Deltas

Write-Host ""
Write-Host " [诊断] 移动消息=$([RawMouse]::TotalMessages) 异步左键=$([RawMouse]::AsyncL) 异步右键=$([RawMouse]::AsyncR) 移动点=$([RawMouse]::MoveCount)" -ForegroundColor DarkGray

if ($deltas.Count -lt 5) {
    if ([RawMouse]::TotalMessages -eq 0) {
        Write-Host " Raw Input 未收到任何消息，游戏可能拦截了输入" -ForegroundColor Red
    } elseif ([RawMouse]::ButtonEvents -eq 0) {
        Write-Host " 收到移动消息但未检测到按键，请确认右键+左键触发" -ForegroundColor Yellow
    } else {
        Write-Host " 数据太少，请重试" -ForegroundColor Red
    }
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
