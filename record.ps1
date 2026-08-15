#Requires -Version 5.0
# 烽火地带 弹道录制工具

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public static class LLHook {
    const int  WH_MOUSE_LL    = 14;
    const int  WM_MOUSEMOVE   = 0x0200;
    const int  WM_LBUTTONDOWN = 0x0201;
    const int  WM_LBUTTONUP   = 0x0202;
    const int  WM_RBUTTONDOWN = 0x0204;
    const int  WM_RBUTTONUP   = 0x0205;
    const uint LLMHF_INJECTED = 0x00000001;
    const uint PM_REMOVE      = 1;

    [StructLayout(LayoutKind.Sequential)]
    struct POINT  { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT {
        public POINT  pt;
        public uint   mouseData, flags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG {
        public IntPtr hwnd;
        public uint   message;
        public IntPtr wParam, lParam;
        public uint   time;
        public int    pt_x, pt_y;
    }

    delegate IntPtr LLProc(int n, IntPtr wp, IntPtr lp);

    [DllImport("user32.dll")]   static extern IntPtr SetWindowsHookEx(int h, LLProc p, IntPtr m, uint t);
    [DllImport("user32.dll")]   static extern bool   UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")]   static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")]   static extern bool   PeekMessage(out MSG m, IntPtr hw, uint mn, uint mx, uint r);
    [DllImport("user32.dll")]   static extern bool   TranslateMessage(ref MSG m);
    [DllImport("user32.dll")]   static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);

    // --- shared state (static so no lambda capture issues) ---
    public static volatile bool Recording;
    public static volatile bool Done;
    public static volatile bool HookOk;
    public static int MoveEvents;
    public static int ButtonEvents;
    public static readonly Stopwatch Timer = new Stopwatch();
    public static readonly List<int[]> Deltas = new List<int[]>();

    static bool   s_left, s_right;
    static int    s_lastX = int.MinValue, s_lastY;
    static IntPtr s_hook;
    static LLProc s_proc;   // keep alive

    static IntPtr Proc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && !Done) {
            int  msg = wParam.ToInt32();
            MSLLHOOKSTRUCT ms = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
            bool inj = (ms.flags & LLMHF_INJECTED) != 0;

            if (msg == WM_LBUTTONDOWN) {
                ButtonEvents++;
                s_left = true;
                if (s_right && !Recording) {
                    Deltas.Clear();
                    Timer.Restart();
                    s_lastX = int.MinValue;
                    Recording = true;
                }
            } else if (msg == WM_LBUTTONUP) {
                ButtonEvents++;
                s_left = false;
                if (Recording) { Recording = false; Done = true; }
            } else if (msg == WM_RBUTTONDOWN) {
                ButtonEvents++;
                s_right = true;
            } else if (msg == WM_RBUTTONUP) {
                ButtonEvents++;
                s_right = false;
            } else if (msg == WM_MOUSEMOVE && !inj) {
                MoveEvents++;
                if (Recording && s_lastX != int.MinValue) {
                    int dx = ms.pt.x - s_lastX;
                    int dy = ms.pt.y - s_lastY;
                    if (dx != 0 || dy != 0)
                        Deltas.Add(new int[] { dx, dy, (int)Timer.ElapsedMilliseconds });
                }
                s_lastX = ms.pt.x;
                s_lastY = ms.pt.y;
            }
        }
        return CallNextHookEx(s_hook, nCode, wParam, lParam);
    }

    static void PumpLoop() {
        s_proc = new LLProc(Proc);
        s_hook = SetWindowsHookEx(WH_MOUSE_LL, s_proc, GetModuleHandle(null), 0);
        HookOk = s_hook != IntPtr.Zero;
        MSG m;
        while (!Done) {
            while (PeekMessage(out m, IntPtr.Zero, 0, 0, PM_REMOVE)) {
                TranslateMessage(ref m);
                DispatchMessage(ref m);
            }
            Thread.Sleep(1);
        }
        if (s_hook != IntPtr.Zero) UnhookWindowsHookEx(s_hook);
    }

    public static void Start() {
        Thread t = new Thread(new ThreadStart(PumpLoop));
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
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
Write-Host "  烽火地带 弹道录制工具" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 【重要】游戏必须设置为全屏窗口化" -ForegroundColor Yellow
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 训练场瞄准靶子，关闭压枪器"
Write-Host "  2. 此窗口按 Enter，切换回游戏"
Write-Host "  3. 右键（开镜）+ 左键（开枪），自动开始录制"
Write-Host "  4. 打完松开左键，自动停止保存"
Write-Host "  5. 回到浏览器点「载入录制」"
Write-Host ""

[LLHook]::Start()
Start-Sleep -Milliseconds 400

if (-not [LLHook]::HookOk) {
    Write-Host " 钩子安装失败，请以管理员身份运行" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host " 鼠标钩子安装成功" -ForegroundColor DarkGray
Read-Host " 按 Enter 后切换到游戏，右键+左键开枪即自动开始..."
Write-Host ""
Write-Host " 等待开枪..." -ForegroundColor Cyan

$timeout  = [DateTime]::Now.AddSeconds(60)
$notified = $false
while (-not [LLHook]::Done -and [DateTime]::Now -lt $timeout) {
    if ([LLHook]::Recording -and -not $notified) {
        Write-Host " 录制中！打完松开左键..." -ForegroundColor Green
        $notified = $true
    }
    Start-Sleep -Milliseconds 50
}

[LLHook]::Done = $true
Start-Sleep -Milliseconds 100
$deltas = [LLHook]::Deltas

Write-Host ""
Write-Host " 移动事件: $([LLHook]::MoveEvents)  按键事件: $([LLHook]::ButtonEvents)  数据点: $($deltas.Count)" -ForegroundColor DarkGray

if ($deltas.Count -lt 5) {
    if ([LLHook]::ButtonEvents -gt 0 -and [LLHook]::MoveEvents -gt 0) {
        Write-Host " 检测到鼠标移动但位移为0：游戏完全锁定光标，请用「描绘弹道」手动画" -ForegroundColor Yellow
    } elseif ([LLHook]::ButtonEvents -eq 0) {
        Write-Host " 未收到任何鼠标事件，请以管理员身份运行" -ForegroundColor Red
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
