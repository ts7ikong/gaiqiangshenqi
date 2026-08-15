#Requires -Version 5.0
# 烽火地带 弹道录制工具

Add-Type @"
using System.Runtime.InteropServices;
public class WinInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

$host.UI.RawUI.WindowTitle = "烽火地带 弹道录制"

Write-Host ""
Write-Host "  ★  烽火地带 弹道录制工具  ★" -ForegroundColor Cyan
Write-Host "─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 【重要】游戏必须设置为窗口模式" -ForegroundColor Yellow
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 打开游戏 → 训练场 → 瞄准靶子，关闭压枪器"
Write-Host "  2. 在此窗口按 Enter，然后切换到游戏"
Write-Host "  3. 按住右键（开镜）立刻左键射击，打完一梭子"
Write-Host "  4. 松开右键 → 自动结束录制"
Write-Host "  5. 回到浏览器点「载入录制」"
Write-Host ""

Read-Host " 按 Enter 开始等待右键触发..."
Write-Host ""
Write-Host " 切换到游戏，按住右键开始射击" -ForegroundColor Cyan
Write-Host ""

# 等右键按下（VK_RBUTTON = 0x02）
while (-not ([WinInput]::GetAsyncKeyState(0x02) -band 0x8000)) {
    Start-Sleep -Milliseconds 10
}

Write-Host " 右键已按下，录制开始！" -ForegroundColor Green

$pts = [System.Collections.Generic.List[PSCustomObject]]::new()
$ox = 0; $oy = 0; $first = $true
$t0 = [DateTime]::Now

# 右键按住期间持续采样
while ([WinInput]::GetAsyncKeyState(0x02) -band 0x8000) {
    $p = New-Object WinInput+POINT
    $null = [WinInput]::GetCursorPos([ref]$p)
    if ($first) { $ox = $p.X; $oy = $p.Y; $first = $false }
    $ms = [int](([DateTime]::Now - $t0).TotalMilliseconds)
    $pts.Add([PSCustomObject]@{ x = ($p.X - $ox); y = ($p.Y - $oy); t = $ms })
    Start-Sleep -Milliseconds 16
}

Write-Host " 录制完成：$($pts.Count) 个数据点" -ForegroundColor Green

if ($pts.Count -lt 5) {
    Write-Host " 数据太少，请重试" -ForegroundColor Red
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

$lines = $pts | ForEach-Object { '{"x":' + $_.x + ',"y":' + $_.y + ',"t":' + $_.t + '}' }
$json = "[" + ($lines -join ",") + "]"

$savePath = Join-Path $PSScriptRoot "trajectory.json"
[IO.File]::WriteAllText($savePath, $json, [Text.Encoding]::UTF8)

Write-Host " 已保存到: trajectory.json" -ForegroundColor Green
Write-Host ""
Write-Host " 请回到浏览器，点击「载入录制」按钮" -ForegroundColor Cyan
Write-Host ""
Write-Host " 按任意键关闭..."
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
