#Requires -Version 5.0
# 烽火地带 弹道录制工具 (Raw Input API)

Add-Type -AssemblyName System.Windows.Forms

Add-Type -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Diagnostics;

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

    const int WM_INPUT = 0x00FF;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const uint RID_INPUT = 0x10000003;
    const uint RIM_TYPEMOUSE = 0;

    public volatile bool Recording;
    public Stopwatch Timer = new Stopwatch();
    public List<int[]> Deltas = new List<int[]>();

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT && Recording) {
            uint size = (uint)Marshal.SizeOf(typeof(RAWINPUT));
            RAWINPUT ri;
            if (GetRawInputData(m.LParam, RID_INPUT, out ri, ref size,
                (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER))) > 0
                && ri.header.dwType == RIM_TYPEMOUSE) {
                int dx = ri.mouse.lLastX;
                int dy = ri.mouse.lLastY;
                if (dx != 0 || dy != 0)
                    Deltas.Add(new int[] { dx, dy, (int)Timer.ElapsedMilliseconds });
            }
        }
        base.WndProc(ref m);
    }

    public bool Register() {
        var rid = new RAWINPUTDEVICE[1];
        rid[0].usUsagePage = 0x01;
        rid[0].usUsage    = 0x02;
        rid[0].dwFlags    = RIDEV_INPUTSINK;
        rid[0].hwndTarget = Handle;
        return RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
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
Write-Host "  2. 此窗口按 Enter，立刻切换回游戏"
Write-Host "  3. 5秒倒计时结束后自动开始录制"
Write-Host "  4. 立刻开枪，边打边手动压枪（最长8秒）"
Write-Host "  5. 打完后切回此窗口，回到浏览器点「载入录制」"
Write-Host ""

$capture = New-Object RawMouseCapture
$capture.Show()
[System.Windows.Forms.Application]::DoEvents()

if (-not $capture.Register()) {
    Write-Host " 注册 Raw Input 失败，请以管理员身份运行" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Read-Host " 按 Enter 开始倒计时，立刻切换到游戏瞄准..."
Write-Host ""

foreach ($i in 5..1) {
    Write-Host " $i ..." -ForegroundColor Yellow
    $deadline2 = [DateTime]::Now.AddSeconds(1)
    while ([DateTime]::Now -lt $deadline2) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
}

Write-Host " 开始！立刻开枪压枪！" -ForegroundColor Green

$capture.Timer.Restart()
$capture.Recording = $true

$deadline = [DateTime]::Now.AddSeconds(8)
while ([DateTime]::Now -lt $deadline) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 5
}

$capture.Recording = $false
$deltas = $capture.Deltas
$capture.Close()

Write-Host ""
Write-Host " 录制完成：$($deltas.Count) 个原始事件" -ForegroundColor Green

if ($deltas.Count -lt 5) {
    Write-Host " 数据太少，请重试" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 累加并取反：压枪方向 -> 后坐力方向
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
