#Requires -Version 5.0
# 烽火地带 弹道录制工具 (HID 直读)

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

public static class HIDMouse {
    const uint GENERIC_READ         = 0x80000000;
    const uint FILE_SHARE_READ      = 1;
    const uint FILE_SHARE_WRITE     = 2;
    const uint OPEN_EXISTING        = 3;
    const uint DIGCF_PRESENT        = 2;
    const uint DIGCF_DEVICEINTERFACE = 0x10;
    const int  HIDP_STATUS_SUCCESS  = 0x00110000;
    const short HidP_Input          = 0;

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public uint Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
    struct SP_DEVICE_INTERFACE_DETAIL_DATA {
        public int cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=512)]
        public string DevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
        public ushort Usage, UsagePage;
        public ushort InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices;
        public ushort NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")]
    static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr en, IntPtr hw, uint fl);
    [DllImport("setupapi.dll", SetLastError=true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA d, ref SP_DEVICE_INTERFACE_DETAIL_DATA dd, uint sz, out uint req, IntPtr di);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("hid.dll")]
    static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr pd);
    [DllImport("hid.dll")]
    static extern bool HidD_FreePreparsedData(IntPtr pd);
    [DllImport("hid.dll")]
    static extern int HidP_GetCaps(IntPtr pd, out HIDP_CAPS caps);
    [DllImport("hid.dll")]
    static extern int HidP_GetScaledUsageValue(short rt, ushort up, ushort lc, ushort u, out int val, IntPtr pd, byte[] r, uint rlen);
    [DllImport("hid.dll")]
    static extern int HidP_GetUsageValue(short rt, ushort up, ushort lc, ushort u, out uint val, IntPtr pd, byte[] r, uint rlen);
    [DllImport("hid.dll")]
    static extern int HidP_GetUsages(short rt, ushort up, ushort lc, ushort[] ul, ref uint ulen, IntPtr pd, byte[] r, uint rlen);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern IntPtr CreateFile(string f, uint acc, uint share, IntPtr sec, uint cd, uint fl, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadFile(IntPtr h, byte[] buf, uint n, out uint read, IntPtr ov);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);

    static readonly IntPtr INVALID = new IntPtr(-1);

    public static volatile bool Recording;
    public static volatile bool Done;
    public static volatile bool Started;
    public static string Error = "";
    public static string DevInfo = "";
    public static string DebugLog = "";
    public static int MoveCount;
    public static readonly Stopwatch Timer = new Stopwatch();
    public static readonly List<int[]> Deltas = new List<int[]>();

    [DllImport("kernel32.dll")]
    static extern uint GetLastError();

    static int SignExtend(uint raw, uint logicalMax) {
        if (logicalMax > 127) {
            return (raw > 32767) ? (int)(raw | 0xFFFF0000) : (int)raw;
        } else {
            return (raw > 127) ? (int)(raw | 0xFFFFFF00) : (int)raw;
        }
    }

    static void ReadLoop() {
        var sb = new System.Text.StringBuilder();
        try {
            Guid hid; HidD_GetHidGuid(out hid);
            var hdi = SetupDiGetClassDevs(ref hid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
            if (hdi == INVALID) { Error = "SetupDiGetClassDevs 失败"; Started = true; return; }

            var paths = new List<string>();
            uint mi = 0;
            try {
                while (true) {
                    var id = new SP_DEVICE_INTERFACE_DATA();
                    id.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                    if (!SetupDiEnumDeviceInterfaces(hdi, IntPtr.Zero, ref hid, mi++, ref id)) break;
                    var dd = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                    dd.cbSize = IntPtr.Size == 8 ? 8 : 6;
                    uint req;
                    SetupDiGetDeviceInterfaceDetail(hdi, ref id, ref dd, 1024, out req, IntPtr.Zero);
                    if (!string.IsNullOrEmpty(dd.DevicePath)) paths.Add(dd.DevicePath);
                }
            } finally { SetupDiDestroyDeviceInfoList(hdi); }

            IntPtr hDev = INVALID, prep = IntPtr.Zero;
            int repLen = 0;
            uint xMax = 127;

            foreach (var path in paths) {
                string tail = path.Length > 60 ? path.Substring(path.Length - 60) : path;
                var h = CreateFile(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (h == INVALID) {
                    sb.AppendLine(string.Format("OPEN_FAIL(err={0}): ...{1}", GetLastError(), tail));
                    continue;
                }
                IntPtr pd;
                if (!HidD_GetPreparsedData(h, out pd)) {
                    sb.AppendLine("PREP_FAIL: ..." + tail);
                    CloseHandle(h); continue;
                }
                HIDP_CAPS caps;
                int rc = HidP_GetCaps(pd, out caps);
                if (rc != HIDP_STATUS_SUCCESS) {
                    sb.AppendLine(string.Format("CAPS_FAIL(r={0:X8}): ...{1}", rc, tail));
                    HidD_FreePreparsedData(pd); CloseHandle(h); continue;
                }
                sb.AppendLine(string.Format("UP=0x{0:X2} U=0x{1:X2} InLen={2}: ...{3}",
                    caps.UsagePage, caps.Usage, caps.InputReportByteLength, tail));

                if (caps.UsagePage == 0x01 && caps.Usage == 0x02 && caps.InputReportByteLength > 0 && hDev == INVALID) {
                    hDev = h; prep = pd;
                    repLen = caps.InputReportByteLength;
                    xMax = repLen >= 6 ? (uint)32767 : (uint)127;
                    DevInfo = string.Format("...{0} Len={1}", tail.Length > 30 ? tail.Substring(tail.Length - 30) : tail, repLen);
                } else {
                    HidD_FreePreparsedData(pd); CloseHandle(h);
                }
            }

            DebugLog = sb.ToString();

            if (hDev == INVALID) {
                Error = string.Format("未找到 HID 鼠标（共 {0} 个 HID 设备）", paths.Count);
                Started = true; return;
            }

            Started = true;
            bool leftDown = false, rightDown = false;
            var report = new byte[repLen];
            var btnBuf = new ushort[32];

            while (!Done) {
                uint read;
                if (!ReadFile(hDev, report, (uint)repLen, out read, IntPtr.Zero) || read == 0) {
                    Thread.Sleep(1); continue;
                }

                // 解析 X/Y：先试 ScaledUsageValue，失败则用 GetUsageValue+符号扩展
                int x = 0, y = 0;
                int sx, sy;
                bool xOk = HidP_GetScaledUsageValue(HidP_Input, 0x01, 0, 0x30, out sx, prep, report, read) == HIDP_STATUS_SUCCESS;
                bool yOk = HidP_GetScaledUsageValue(HidP_Input, 0x01, 0, 0x31, out sy, prep, report, read) == HIDP_STATUS_SUCCESS;
                if (xOk && yOk) { x = sx; y = sy; }
                else {
                    uint rx, ry;
                    if (HidP_GetUsageValue(HidP_Input, 0x01, 0, 0x30, out rx, prep, report, read) == HIDP_STATUS_SUCCESS)
                        x = SignExtend(rx, xMax);
                    if (HidP_GetUsageValue(HidP_Input, 0x01, 0, 0x31, out ry, prep, report, read) == HIDP_STATUS_SUCCESS)
                        y = SignExtend(ry, xMax);
                }

                // 解析按键
                uint blen = (uint)btnBuf.Length;
                for (int i = 0; i < btnBuf.Length; i++) btnBuf[i] = 0;
                HidP_GetUsages(HidP_Input, 0x09, 0, btnBuf, ref blen, prep, report, read);
                bool nl = false, nr = false;
                for (uint i = 0; i < blen; i++) {
                    if (btnBuf[i] == 1) nl = true;
                    if (btnBuf[i] == 2) nr = true;
                }

                // 触发逻辑：右键+左键开始，松开左键停止
                if (nl && nr && !leftDown && !Recording) {
                    Deltas.Clear(); Timer.Restart(); Recording = true;
                }
                if (leftDown && !nl && Recording) {
                    Recording = false; Done = true;
                }
                leftDown = nl; rightDown = nr;

                if (Recording && (x != 0 || y != 0)) {
                    MoveCount++;
                    Deltas.Add(new int[] { x, y, (int)Timer.ElapsedMilliseconds });
                }
            }

            HidD_FreePreparsedData(prep);
            CloseHandle(hDev);
        } catch (Exception ex) {
            Error = ex.Message; Started = true;
        }
    }

    public static void Start() {
        var t = new Thread(new ThreadStart(ReadLoop));
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
Write-Host "  烽火地带 弹道录制工具 (HID直读)" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " 流程："
Write-Host "  1. 训练场瞄准靶子，关闭压枪器"
Write-Host "  2. 此窗口按 Enter，切换回游戏"
Write-Host "  3. 右键（开镜）+ 左键（开枪），自动开始录制"
Write-Host "  4. 打完松开左键，自动停止保存"
Write-Host "  5. 回到浏览器点「载入录制」"
Write-Host ""

[HIDMouse]::Start()

$t0 = [DateTime]::Now
while (-not [HIDMouse]::Started -and ([DateTime]::Now - $t0).TotalSeconds -lt 5) {
    Start-Sleep -Milliseconds 50
}

if ([HIDMouse]::Error -ne "") {
    Write-Host " 错误: $([HIDMouse]::Error)" -ForegroundColor Red
    $dbgPath = Join-Path $PSScriptRoot "hid_debug.txt"
    [IO.File]::WriteAllText($dbgPath, [HIDMouse]::DebugLog, [Text.Encoding]::UTF8)
    Write-Host " 已生成诊断日志: hid_debug.txt" -ForegroundColor Yellow
    Write-Host " 请把该文件内容发给开发者" -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host " HID 设备: $([HIDMouse]::DevInfo)" -ForegroundColor DarkGray
Read-Host " 按 Enter 后切换到游戏，右键+左键开枪即自动开始..."
Write-Host ""
Write-Host " 等待开枪..." -ForegroundColor Cyan

$timeout = [DateTime]::Now.AddSeconds(60)
$notified = $false
while (-not [HIDMouse]::Done -and [DateTime]::Now -lt $timeout) {
    if ([HIDMouse]::Recording -and -not $notified) {
        Write-Host " 录制中！打完松开左键..." -ForegroundColor Green
        $notified = $true
    }
    Start-Sleep -Milliseconds 50
}

[HIDMouse]::Done = $true
Start-Sleep -Milliseconds 100
$deltas = [HIDMouse]::Deltas

Write-Host ""
Write-Host " 移动数据点: $([HIDMouse]::MoveCount)  总录制点: $($deltas.Count)" -ForegroundColor DarkGray

if ($deltas.Count -lt 5) {
    Write-Host " 数据太少，请重试" -ForegroundColor Red
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
