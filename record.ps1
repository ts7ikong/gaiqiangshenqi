#Requires -Version 5.0
# 烽火地带 弹道录制工具 (Raw Input API)

Add-Type -AssemblyName System.Windows.Forms

Add-Type -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public class RawMouseCapture : Form {

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE {
        public ushort usUsagePage;
        public ushort usUsage;
        public uint dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER {
        public uint dwType;
        public uint dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWMOUSE {
        public ushort usFlags;
        public ushort _pad;
        public uint ulButtons;
        public uint ulRawButtons;
        public int lLastX;
        public int lLastY;
        public uint ulExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUT {
        public RAWINPUTHEADER header;
        public RAWMOUSE mouse;
    }

    [DllImport("user32.dll", SetLastError=true)]
    static extern bool RegisterRawInputDevices(
        [In] RAWINPUTDEVICE[] pRawInputDevices, uint uiNumDevices, uint cbSize);

    [DllImport("user32.dll")]
    static extern uint GetRawInputData(
        IntPtr hRawInput, uint uiCommand,
        out RAWINPUT pData, ref uint pcbSize, uint cbSizeHeader);

    // ulButtons 标志位
    const uint RI_MOUSE_LEFT_DOWN  = 0x0001;
    const uint RI_MOUSE_LEFT_UP    = 0x0002;
    const uint RI_MOUSE_RIGHT_DOWN = 0x0004;
    const uint RI_MOUSE_RIGHT_UP   = 0x0008;

    const int WM_INPUT = 0x00FF;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const uint RID_INPUT = 0x10000003;
    const uint RIM_TYPEMOUSE = 0;

    public volatile bool Recording;
    public volatile bool Done;
    public volatile bool RegisteredOk;
    public Stopwatch Timer = new Stopwatch();
    public List<int[]> Deltas = new List<int[]>();

    bool _leftDown;
    bool _rightDown;

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        var rid = new RAWINPUTDEVICE[1];
        rid[0].usUsagePage = 0x01;
        rid[0].usUsage    = 0x02;
        rid[0].dwFlags    = RIDEV_INPUTSINK;
        rid[0].hwndTarget = Handle;
        RegisteredOk = RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT && !Done) {
            uint size = (uint)Marshal.SizeOf(typeof(RAWINPUT));
            RAWINPUT ri;
            if (GetRawInputData(m.LParam, RID_INPUT, out ri, ref size,
                (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER))) > 0
                && ri.header.dwType == RIM_TYPEMOUSE) {

                uint btn = ri.mouse.ulButtons;

                // 更新按键状态
                if ((btn & RI_MOUSE_LEFT_DOWN)  != 0) _leftDown  = true;
                if ((btn & RI_MOUSE_LEFT_UP)    != 0) _leftDown  = false;
                if ((btn & RI_MOUSE_RIGHT_DOWN) != 0) _rightDown = true;
                if ((btn & RI_MOUSE_RIGHT_UP)   != 0) _rightDown = false;

                // 左右键同时按下 → 开始录制
                if (_leftDown && _rightDown && !Recording) {
                    Deltas.Clear();
                    Timer.Restart();
                    Recording = true;
                }

                // 录制中：采集移动量
                if (Recording) {
                    int dx = ri.mouse.lLastX;
                    int dy = ri.mouse.lLastY;
                    if (dx != 0 || dy != 0)
                        Deltas.Add(new int[] { dx, dy, (int)Timer.ElapsedMilliseconds });
                }

                // 左键松开 → 停止录制
                if (Recording && !_leftDown) {
                    Recording = false;
                    Done = true;
                }
            }
        }
        base.WndProc(ref m);
    }

    public void StartPumpAsync() {
        var t = new Thread(() => Application.Run(this));
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
    }

    public RawMouseCapture() {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar   = false;
        Size            = new System.Drawing.Size(1, 1);
        Location        = new System.Drawing.Point(-200, -200);
        Opacity         = 0;
    }
}
'@

$host.UI.RawUI.WindowTitle = "烽火地带 弹道录制"

Write-Host ""
Write-Host "  烽火地带 弹道录制工具" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 【重要】游戏必须设置为窗口模式或全屏窗口化" -ForegroundColor Yellow
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 训练场瞄准靶子，关闭压枪器"
Write-Host "  2. 此窗口按 Enter，切换回游戏"
Write-Host "  3. 右键（开镜）+ 左键（开枪），自动开始录制"
Write-Host "  4. 打完松开左键，自动停止保存"
Write-Host "  5. 回到浏览器点「载入录制」"
Write-Host ""

$capture = New-Object RawMouseCapture
$capture.StartPumpAsync()
Start-Sleep -Milliseconds 500

if (-not $capture.RegisteredOk) {
    Write-Host " 注册 Raw Input 失败，请以管理员身份运行" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host " Raw Input 注册成功" -ForegroundColor DarkGray
Read-Host " 按 Enter 后切换到游戏，右键+左键开枪即自动开始..."
Write-Host ""
Write-Host " 等待开枪..." -ForegroundColor Cyan

$timeout = [DateTime]::Now.AddSeconds(60)
$notified = $false

while (-not $capture.Done -and [DateTime]::Now -lt $timeout) {
    if ($capture.Recording -and -not $notified) {
        Write-Host " 录制中！打完松开左键..." -ForegroundColor Green
        $notified = $true
    }
    Start-Sleep -Milliseconds 50
}

if (-not $capture.Done) {
    $capture.Recording = $false
    $capture.Done = $true
}

Start-Sleep -Milliseconds 100
$deltas = $capture.Deltas
try { $capture.Invoke([System.Action]{ [System.Windows.Forms.Application]::Exit() }) } catch {}

Write-Host ""
Write-Host " 录制完成：$($deltas.Count) 个原始事件" -ForegroundColor Green

if ($deltas.Count -lt 5) {
    Write-Host " 数据太少，请重试" -ForegroundColor Red
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

Write-Host " 已保存: trajectory.json" -ForegroundColor Green
Write-Host ""
Write-Host " 请回到浏览器，点击「载入录制」" -ForegroundColor Cyan
Write-Host ""
Write-Host " 按任意键关闭..."
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
