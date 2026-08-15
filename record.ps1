#Requires -Version 5.0
# 烽火地带 弹道录制工具 (WH_MOUSE_LL)

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public class LLMouseRecorder {
    const int WH_MOUSE_LL    = 14;
    const int WM_MOUSEMOVE   = 0x0200;
    const int WM_LBUTTONDOWN = 0x0201;
    const int WM_LBUTTONUP   = 0x0202;
    const int WM_RBUTTONDOWN = 0x0204;
    const int WM_RBUTTONUP   = 0x0205;
    const uint LLMHF_INJECTED = 0x00000001;
    const uint PM_REMOVE = 1;

    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData, flags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam, lParam;
        public uint time;
        public int pt_x, pt_y;
    }

    delegate IntPtr LLProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int hook, LLProc proc, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int n, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr hwnd, uint mn, uint mx, uint rm);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

    public volatile bool Recording;
    public volatile bool Done;
    public volatile bool HookOk;
    public int MoveEvents;
    public int ButtonEvents;
    public Stopwatch Timer = new Stopwatch();
    public List<int[]> Deltas = new List<int[]>();

    bool _leftDown, _rightDown;
    int _lastX = int.MinValue, _lastY = int.MinValue;
    IntPtr _hook;
    LLProc _proc; // prevent GC

    IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            var ms = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
            bool injected = (ms.flags & LLMHF_INJECTED) != 0;

            if (msg == WM_LBUTTONDOWN) {
                ButtonEvents++;
                _leftDown = true;
                if (_rightDown && !Recording) {
                    Deltas.Clear();
                    Timer.Restart();
                    _lastX = int.MinValue;
                    Recording = true;
                }
            } else if (msg == WM_LBUTTONUP) {
                ButtonEvents++;
                _leftDown = false;
                if (Recording) { Recording = false; Done = true; }
            } else if (msg == WM_RBUTTONDOWN) {
                ButtonEvents++;
                _rightDown = true;
            } else if (msg == WM_RBUTTONUP) {
                ButtonEvents++;
                _rightDown = false;
            } else if (msg == WM_MOUSEMOVE && !injected) {
                MoveEvents++;
                if (_lastX != int.MinValue && Recording) {
                    int dx = ms.pt.x - _lastX;
                    int dy = ms.pt.y - _lastY;
                    if (dx != 0 || dy != 0)
                        Deltas.Add(new int[] { dx, dy, (int)Timer.ElapsedMilliseconds });
                }
                _lastX = ms.pt.x;
                _lastY = ms.pt.y;
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Start() {
        _proc = new LLProc(MouseProc);
        var t = new Thread(() => {
            _hook = SetWindowsHookEx(WH_MOUSE_LL, _proc, GetModuleHandle(null), 0);
            HookOk = _hook != IntPtr.Zero;
            MSG m;
            while (!Done) {
                while (PeekMessage(out m, IntPtr.Zero, 0, 0, PM_REMOVE)) {
                    TranslateMessage(ref m);
                    DispatchMessage(ref m);
                }
                Thread.Sleep(1);
            }
            if (_hook != IntPtr.Zero) UnhookWindowsHookEx(_hook);
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
    }
}
'@

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

$rec = New-Object LLMouseRecorder
$rec.Start()
Start-Sleep -Milliseconds 300

if (-not $rec.HookOk) {
    Write-Host " 钩子安装失败，请以管理员身份运行" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host " 鼠标钩子安装成功" -ForegroundColor DarkGray
Read-Host " 按 Enter 后切换到游戏，右键+左键开枪即自动开始..."
Write-Host ""
Write-Host " 等待开枪..." -ForegroundColor Cyan

$timeout = [DateTime]::Now.AddSeconds(60)
$notified = $false

while (-not $rec.Done -and [DateTime]::Now -lt $timeout) {
    if ($rec.Recording -and -not $notified) {
        Write-Host " 录制中！打完松开左键..." -ForegroundColor Green
        $notified = $true
    }
    Start-Sleep -Milliseconds 50
}

$rec.Done = $true
Start-Sleep -Milliseconds 100
$deltas = $rec.Deltas

Write-Host ""
Write-Host " 移动事件: $($rec.MoveEvents)  按键事件: $($rec.ButtonEvents)  数据点: $($deltas.Count)" -ForegroundColor DarkGray

if ($deltas.Count -lt 5) {
    if ($rec.ButtonEvents -gt 0 -and $rec.MoveEvents -gt 0) {
        Write-Host " 收到了鼠标事件但位移为零：游戏锁定了光标位置，无法用此方法录制" -ForegroundColor Yellow
    } elseif ($rec.ButtonEvents -eq 0) {
        Write-Host " 未收到任何鼠标事件，请以管理员身份运行" -ForegroundColor Red
    } else {
        Write-Host " 数据太少，请重试" -ForegroundColor Red
    }
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

$cumX = 0; $cumY = 0
$lines = $deltas | ForEach-Object {
    $cumX += -$_[0]
    $cumY += -$_[1]
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
