#Requires -Version 5.0
# 烽火地带 弹道录制工具

Add-Type @"
using System.Runtime.InteropServices;
public class WinCursor {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT p);
}
"@

$host.UI.RawUI.WindowTitle = "烽火地带 弹道录制"

Write-Host ""
Write-Host "  ★  烽火地带 弹道录制工具  ★" -ForegroundColor Cyan
Write-Host "─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 【重要】游戏必须设置为「窗口模式」" -ForegroundColor Yellow
Write-Host "         全屏模式下鼠标位置无法被读取" -ForegroundColor Yellow
Write-Host ""
Write-Host " 步骤："
Write-Host "  1. 打开游戏 → 训练场 → 瞄准靶子"
Write-Host "  2. 关闭压枪器（确保设备没有写入任何配置）"
Write-Host "  3. 在此窗口按 Enter 开始倒计时"
Write-Host "  4. 立即切换到游戏窗口"
Write-Host "  5. 倒计时结束立刻开枪，打完一梭子"
Write-Host "  6. 等录制结束提示后回到浏览器"
Write-Host "  7. 在自定义配置页点「📥 载入录制」"
Write-Host ""

$delayInput = Read-Host " 倒计时秒数（默认 3，直接回车）"
$delay = if ($delayInput -match '^\d+$') { [int]$delayInput } else { 3 }

$durationInput = Read-Host " 录制时长（秒，默认 6，一梭子够了）"
$duration = if ($durationInput -match '^\d+$') { [int]$durationInput } else { 6 }

Write-Host ""
Write-Host " ▶ 请切换到游戏窗口！" -ForegroundColor Red
Write-Host ""

for ($i = $delay; $i -gt 0; $i--) {
    Write-Host "   $i ..." -ForegroundColor Yellow
    Start-Sleep 1
}
Write-Host ""
Write-Host " ★★★  开枪！！！  ★★★" -ForegroundColor Green
Write-Host ""

$pts = [System.Collections.Generic.List[PSCustomObject]]::new()
$ox = 0; $oy = 0; $first = $true
$t0 = [DateTime]::Now

while (([DateTime]::Now - $t0).TotalSeconds -lt $duration) {
    $p = New-Object WinCursor+POINT
    $null = [WinCursor]::GetCursorPos([ref]$p)
    if ($first) { $ox = $p.X; $oy = $p.Y; $first = $false }
    $ms = [int](([DateTime]::Now - $t0).TotalMilliseconds)
    $pts.Add([PSCustomObject]@{ x = ($p.X - $ox); y = ($p.Y - $oy); t = $ms })
    Start-Sleep -Milliseconds 16
}

Write-Host " 录制完成：$($pts.Count) 个数据点" -ForegroundColor Green

# 手动拼接 JSON（兼容性更好）
$lines = $pts | ForEach-Object { "{`"x`":$($_.x),`"y`":$($_.y),`"t`":$($_.t)}" }
$json = "[" + ($lines -join ",") + "]"

$savePath = Join-Path $PSScriptRoot "trajectory.json"
[IO.File]::WriteAllText($savePath, $json, [Text.Encoding]::UTF8)

Write-Host " 数据已保存到: trajectory.json" -ForegroundColor Green
Write-Host ""
Write-Host " ► 请回到浏览器，点击「📥 载入录制」按钮" -ForegroundColor Cyan
Write-Host ""
Write-Host " 按任意键关闭..."
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
