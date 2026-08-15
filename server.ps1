$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dir

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8080/")

try {
    $listener.Start()
} catch {
    Write-Host "端口8080被占用，请关闭后重试"
    Read-Host "按回车退出"
    exit
}

Write-Host "========================================"
Write-Host "  魔王S 改枪码查询 - 服务已启动"
Write-Host "  http://localhost:8080/gun_search.html"
Write-Host "  关闭此窗口即可停止服务"
Write-Host "========================================"

Start-Sleep -Milliseconds 800
Start-Process "http://localhost:8080/gun_search.html"

function Get-MimeType($ext) {
    switch ($ext) {
        '.html' { return 'text/html; charset=utf-8' }
        '.js'   { return 'application/javascript' }
        '.css'  { return 'text/css' }
        '.png'  { return 'image/png' }
        '.jpg'  { return 'image/jpeg' }
        '.ico'  { return 'image/x-icon' }
        '.json' { return 'application/json; charset=utf-8' }
        default { return 'application/octet-stream' }
    }
}

# 标准枪名关键词列表
$gunKeywords = @(
    @{name="M14射手步枪"; keys=@("M14")},
    @{name="M7战斗步枪"; keys=@("M7")},
    @{name="M4A1突击步枪"; keys=@("M4A1")},
    @{name="M249轻机枪"; keys=@("M249")},
    @{name="M250通用机枪"; keys=@("M250")},
    @{name="AS Val突击步枪"; keys=@("AS Val","ASVAL","AS-VAL")},
    @{name="ASh-12战斗步枪"; keys=@("ASh-12","ASH-12")},
    @{name="AK-12突击步枪"; keys=@("AK-12")},
    @{name="AKM突击步枪"; keys=@("AKM")},
    @{name="AKS-74U突击步枪"; keys=@("AKS-74U")},
    @{name="AR57突击步枪"; keys=@("AR57","AR-57")},
    @{name="AUG突击步枪"; keys=@("AUG")},
    @{name="CAR-15突击步枪"; keys=@("CAR-15")},
    @{name="G18"; keys=@("G18")},
    @{name="G3战斗步枪"; keys=@("G3")},
    @{name="K416突击步枪"; keys=@("K416")},
    @{name="K437突击步枪"; keys=@("K437")},
    @{name="KC17突击步枪"; keys=@("KC17","kc17")},
    @{name="MCX LT突击步枪"; keys=@("MCX LT","MCXLT","MCX")},
    @{name="MK47突击步枪"; keys=@("MK47")},
    @{name="MK4冲锋枪"; keys=@("MK4")},
    @{name="MP5冲锋枪"; keys=@("MP5")},
    @{name="MP7冲锋枪"; keys=@("MP7")},
    @{name="Mini-14射手步枪"; keys=@("Mini-14")},
    @{name="P90冲锋枪"; keys=@("P90")},
    @{name="PKM通用机枪"; keys=@("PKM")},
    @{name="PTR-32突击步枪"; keys=@("PTR-32","PTR")},
    @{name="QBZ95-1突击步枪"; keys=@("QBZ95-1","QBZ")},
    @{name="QCQ171冲锋枪"; keys=@("QCQ171","QCQ")},
    @{name="QJB201轻机枪"; keys=@("QJB201","QJB")},
    @{name="RM277突击步枪"; keys=@("RM277")},
    @{name="SCAR-H战斗步枪"; keys=@("SCAR-H","SCAR")},
    @{name="SG552突击步枪"; keys=@("SG552")},
    @{name="SKS射手步枪"; keys=@("SKS")},
    @{name="SMG-45冲锋枪"; keys=@("SMG-45","SMG")},
    @{name="SR-25射手步枪"; keys=@("SR-25")},
    @{name="SR-3M紧凑突击步枪"; keys=@("SR-3M")},
    @{name="SVCH精确射手步枪"; keys=@("SVCH")},
    @{name="SVD狙击步枪"; keys=@("SVD")},
    @{name="UZI冲锋枪"; keys=@("UZI")},
    @{name="Vector冲锋枪"; keys=@("Vector")},
    @{name="VSS射手步枪"; keys=@("VSS")},
    @{name="勇士冲锋枪"; keys=@("勇士")},
    @{name="腾龙突击步枪"; keys=@("腾龙")},
    @{name="野牛冲锋枪"; keys=@("野牛")}
)

function Get-GunName($code) {
    $parts = $code -split "-"
    $nameParts = @()
    $skipList = @("烽火地带","烽火地 带","烽火地帶","烽 火地带","烽火带带","烽火地 帯")
    foreach ($p in $parts) {
        if ($p -match "^[A-Z0-9]{10,}$") { break }
        $clean = $p.Trim() -replace "[
 ]"," "
        if ($clean -and $clean -notin $skipList) { $nameParts += $clean }
    }
    $rawName = ($nameParts -join "-").Trim("-").Trim()
    if (-not $rawName) { return "" }
    
    # 用关键词匹配标准化枪名
    foreach ($gun in $gunKeywords) {
        foreach ($key in $gun.keys) {
            if ($rawName -like "*$key*") { return $gun.name }
        }
    }
    return $rawName
}

function Escape-CSV-Field($v) {
    $v = "$v".Trim() -replace "[\r\n]"," "
    if ($v -match '[,"
]') { return '"' + $v.Replace('"','""') + '"' }
    return $v
}



function Parse-CSV($csvPath) {
    if (-not (Test-Path $csvPath)) { return '[]' }
    
    $lines = Get-Content $csvPath -Encoding UTF8
    if ($lines.Count -lt 2) { return '[]' }
    
    # 自动检测分隔符（逗号 or Tab）
    $sample = $lines | Where-Object { $_.Trim() } | Select-Object -First 20
    $tabCount = ($sample | ForEach-Object { ($_ -split "`t").Count - 1 } | Measure-Object -Sum).Sum
    $commaCount = ($sample | ForEach-Object { ($_ -split ",").Count - 1 } | Measure-Object -Sum).Sum
    $sep = if ($tabCount -gt $commaCount) { "`t" } else { "," }

    function Parse-CSVLine($line) {
        $fields = [System.Collections.Generic.List[string]]::new()
        $inQuote = $false
        $current = [System.Text.StringBuilder]::new()
        foreach ($char in $line.ToCharArray()) {
            if ($char -eq '"') { $inQuote = -not $inQuote }
            elseif ("$char" -eq $sep -and -not $inQuote) { $fields.Add($current.ToString()); $current = [System.Text.StringBuilder]::new() }
            else { [void]$current.Append($char) }
        }
        $fields.Add($current.ToString())
        return ,$fields.ToArray()
    }
    
    $headerRow = -1
    $colCode = 0; $colPrice = 1; $colAmmo = 2; $colNote = 3; $colDate = 4; $colGunId = -1; $colGunIdHeader = -1
    
    for ($i = 0; $i -lt [Math]::Min($lines.Count, 30); $i++) {
        if ($lines[$i] -match "改枪码" -and $lines[$i] -match "价格") {
            $headerRow = $i
            $fields = Parse-CSVLine $lines[$i]
            for ($j = 0; $j -lt $fields.Count; $j++) {
                $v = $fields[$j].Trim()
                if ($v -match "改枪码" -and $v -match "游戏") { $colCode = $j }
                elseif ($v -eq "价格") { $colPrice = $j }
                elseif ($v -match "弹夹") { $colAmmo = $j }
                elseif ($v -match "备注") { $colNote = $j }
                elseif ($v -match "日期") { $colDate = $j }
                elseif (($v -match "控枪编号" -or $v -match "ID") -and $v -notmatch "特殊" -and $v -notmatch "数据") {
                    $colGunIdHeader = $j
                }
            }
            break
        }
    }
    
    if ($headerRow -lt 0) { return '[]' }
    
    if ($colGunIdHeader -ge 0) {
        $colGunId = $colGunIdHeader
        for ($i = $headerRow + 1; $i -lt [Math]::Min($lines.Count, $headerRow + 10); $i++) {
            $f = Parse-CSVLine $lines[$i]
            $vCur  = if ($f.Count -gt $colGunIdHeader) { $f[$colGunIdHeader].Trim() } else { "" }
            $vNext = if ($f.Count -gt ($colGunIdHeader + 1)) { $f[$colGunIdHeader + 1].Trim() } else { "" }
            if ($vNext -match "^[0-9]+$" -and $vCur -notmatch "^[0-9]+$") { $colGunId = $colGunIdHeader + 1; break }
            elseif ($vCur -match "^[0-9]+$") { $colGunId = $colGunIdHeader; break }
        }
    }
    
    $records = @()
    
    for ($i = $headerRow + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if (-not $line) { continue }
        
        $fields = Parse-CSVLine $line
        
        $code  = if ($fields.Count -gt $colCode)  { $fields[$colCode].Trim()  -replace "[\r\n]"," " } else { "" }
        $price = if ($fields.Count -gt $colPrice) { $fields[$colPrice].Trim() -replace "[\r\n]"," " } else { "" }
        $ammo  = if ($fields.Count -gt $colAmmo)  { $fields[$colAmmo].Trim()  -replace "[\r\n]"," " } else { "" }
        $note  = if ($fields.Count -gt $colNote)  { $fields[$colNote].Trim()  -replace "[\r\n]"," " } else { "" }
        $date  = if ($fields.Count -gt $colDate)  { $fields[$colDate].Trim()  -replace "[\r\n]"," " } else { "" }
        $gunId = if ($colGunId -ge 0 -and $fields.Count -gt $colGunId) { $fields[$colGunId].Trim() -replace "[\r\n]"," " } else { "" }
        
        if (-not $code -or $code -notmatch "[A-Z0-9]{5,}") { continue }
        
        # 跳过制式套行（col2是等级名的行，留给后面单独处理）
        $zhishiCheck = @("新兵","标准","精锐","特种","定制")
        $col2Check = if ($fields.Count -gt 2) { $fields[2].Trim() } else { "" }
        if ($zhishiCheck -contains $col2Check) { continue }
        
        $gunName = Get-GunName $code
        if (-not $gunName) { continue }

        # 过滤分隔标题行：price/ammo/date/note 全为空说明是占位行
        if (-not $price -and -not $ammo -and -not $date -and -not $note) { continue }
        
        $codeMatch = [regex]::Match($code, "[A-Z0-9]{10,}")
        $newCode = if ($codeMatch.Success) { "$gunName-烽火地带-$($codeMatch.Value)" } else { $code }
        
        # 制式套识别：价格列直接是等级名
        $zhishiLevels = @("新兵","标准","精锐","特种","定制")
        $isZhishi = $zhishiLevels -contains $price
        if ($isZhishi) {
            # 制式套数据：列2=等级 列7=控枪编号，重新读取
            $gunId = if ($fields.Count -gt 7) { $fields[7].Trim() -replace "[
]"," " } else { $gunId }
            $note  = if ($fields.Count -gt 3) { $fields[3].Trim() -replace "[
]"," " } else { "" }
            $ammo  = ""
            $date  = ""
        }
        
        $priceMatch = [regex]::Match($price, "[0-9]+")
        $priceVal = if ($priceMatch.Success) { [int]$priceMatch.Value } else { 0 }
        
        $ammoNums = [regex]::Matches($ammo, "[0-9]+") | ForEach-Object { [int]$_.Value }
        $ammoVal = if ($ammoNums.Count -gt 0) { ($ammoNums | Measure-Object -Maximum).Maximum } else { 0 }
        
        $dateMatch = [regex]::Match($date, "([0-9]+)[/年]([0-9]+)")
        $dateVal = if ($dateMatch.Success) { [int]$dateMatch.Groups[1].Value * 100 + [int]$dateMatch.Groups[2].Value } else { 0 }
        
        $obj = @{
            code       = $newCode
            gunName    = $gunName
            price      = $price
            priceVal   = $priceVal
            ammo       = $ammo
            ammoVal    = $ammoVal
            note       = $note
            date       = $date
            dateVal    = $dateVal
            gunId      = if ($gunId -and $gunId -ne "nan") { $gunId } else { "" }
            sheet      = [System.IO.Path]::GetFileNameWithoutExtension($csvPath)
            hasJiao    = ($note -notmatch "无精校")
            hasPingxi  = ($note -match "屏息")
            hasXiaoyin = ($note -match "消音")
            hasYao     = ($note -match "腰射")
        }
        $records += $obj
    }
    
    # 扫描所有行，找制式套数据（价格列=等级名的行）
    $zhishiLevels = @("新兵","标准","精锐","特种","定制")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if (-not $line) { continue }
        # 用简单分割扫描制式套（避免作用域问题）
        $fields = $line -split ","
        if ($fields.Count -lt 3) { continue }
        
        $col0 = $fields[0].Trim()
        $col2 = if ($fields.Count -gt 2) { $fields[2].Trim() } else { "" }
        $col7 = if ($fields.Count -gt 7) { $fields[7].Trim() } else { "" }
        
        # 制式套行：列0有改枪码，列2是等级名
        if ($col0 -match "[A-Z0-9]{10,}" -and $zhishiLevels -contains $col2) {
            $gunName = Get-GunName $col0
            if (-not $gunName) { continue }
            
            $codeMatch = [regex]::Match($col0, "[A-Z0-9]{10,}")
            $newCode = if ($codeMatch.Success) { "$gunName-烽火地带-$($codeMatch.Value)" } else { $col0 }
            
            $col3 = if ($fields.Count -gt 3) { $fields[3].Trim() } else { "" }
            
            # 检查是否已经存在相同改枪码（避免重复）
            $exists = $records | Where-Object { $_.code -eq $newCode }
            if ($exists) { continue }
            
            $obj = @{
                code       = $newCode
                gunName    = $gunName
                price      = $col2
                priceVal   = 0
                ammo       = ""
                ammoVal    = 0
                note       = $col3
                date       = ""
                dateVal    = 0
                gunId      = if ($col7 -and $col7 -ne "nan") { $col7 } else { "" }
                sheet      = [System.IO.Path]::GetFileNameWithoutExtension($csvPath)
                hasJiao    = $true
                hasPingxi  = $false
                hasXiaoyin = $false
                hasYao     = $false
            }
            $records += $obj
        }
    }
    
    return ($records | ConvertTo-Json -Compress)
}

function Send-Response($ctx, $statusCode, $contentType, $body) {
    $ctx.Response.StatusCode = $statusCode
    $ctx.Response.ContentType = $contentType
    $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}

# 确保data目录存在
$dataDir = Join-Path $dir "data"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $method = $ctx.Request.HttpMethod
    $path = $ctx.Request.Url.LocalPath

    # OPTIONS 预检
    if ($method -eq "OPTIONS") {
        $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $ctx.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $ctx.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        $ctx.Response.StatusCode = 200
        $ctx.Response.Close()
        continue
    }

    # API: 调试制式套解析
    if ($path -eq "/api/debug-zhishi" -and $method -eq "GET") {
        $dataDir = Join-Path $dir "data"
        $result = @()
        foreach ($f in (Get-ChildItem $dataDir -Filter "*.csv")) {
            $lines = Get-Content $f.FullName -Encoding UTF8
            $zhishiLevels = @("新兵","标准","精锐","特种","定制")
            $found = @()
            foreach ($line in $lines) {
                $fields = $line -split ","
                $col0 = if ($fields.Count -gt 0) { $fields[0].Trim() } else { "" }
                $col2 = if ($fields.Count -gt 2) { $fields[2].Trim() } else { "" }
                if ($col0 -match "[A-Z0-9]{10,}" -and $zhishiLevels -contains $col2) {
                    $found += "$col0 | level=$col2"
                }
            }
            $result += "$($f.Name): $($found.Count)条制式套"
            if ($found.Count -gt 0) { $result += $found[0..2] }
        }
        Send-Response $ctx 200 "application/json; charset=utf-8" ($result | ConvertTo-Json -Compress)
        continue
    }

    # API: 获取data目录下所有CSV数据
    if ($path -eq "/api/data" -and $method -eq "GET") {
        $dataDir = Join-Path $dir "data"
        if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
        $csvFiles = Get-ChildItem $dataDir -Filter "*.csv"
        if ($csvFiles.Count -eq 0) {
            Send-Response $ctx 200 "application/json; charset=utf-8" "[]"
        } else {
            $allRecords = @()
            foreach ($f in $csvFiles) {
                $json = Parse-CSV $f.FullName
                $records = $json | ConvertFrom-Json
                $allRecords += $records
            }
            $result = $allRecords | ConvertTo-Json -Compress
            if (-not $result) { $result = "[]" }
            Send-Response $ctx 200 "application/json; charset=utf-8" $result
        }
        continue
    }

    # API: 追加新数据到CSV
    if ($path -eq "/api/add" -and $method -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = $body | ConvertFrom-Json
            
            $dataDir = Join-Path $dir "data"
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
            $csvPath = Join-Path $dataDir "自定义.csv"
            
            # 如果CSV不存在，创建表头
            if (-not (Test-Path $csvPath)) {
                "改枪码（游戏内使用）,价格,弹夹,备注,日期,控枪编号（网页使用）" | Out-File $csvPath -Encoding UTF8
            }
            
            # 转义字段（含逗号的用引号包裹）
            function Escape-CSV($val) {
                if ($val -match ',|"') { return '"' + $val.Replace('"', '""') + '"' }
                return $val
            }
            
            $line = "$(Escape-CSV $data.code),$(Escape-CSV $data.price),$(Escape-CSV $data.ammo),$(Escape-CSV $data.note),$(Escape-CSV $data.date),$(Escape-CSV $data.gunId)"
            Add-Content $csvPath $line -Encoding UTF8
            
            Send-Response $ctx 200 "application/json; charset=utf-8" '{"ok":true}'
        } catch {
            Send-Response $ctx 500 "application/json; charset=utf-8" ('{"ok":false,"err":"' + $_.Exception.Message + '"}')
        }
        continue
    }

    # API: 保存前端解析好的数据为CSV
    if ($path -eq "/api/save-csv" -and $method -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = $body | ConvertFrom-Json
            $records = $data.records
            
            $dataDir = Join-Path $dir "data"
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
            $csvPath = Join-Path $dataDir "腾讯文档.csv"
            $lines = @("改枪码（游戏内使用）,价格,弹夹,备注,日期,控枪编号（网页使用）")
            foreach ($r in $records) {
                $line = "$(Escape-CSV-Field $r.code),$(Escape-CSV-Field $r.price),$(Escape-CSV-Field $r.ammo),$(Escape-CSV-Field $r.note),$(Escape-CSV-Field $r.date),$(Escape-CSV-Field $r.gunId)"
                $lines += $line
            }
            $lines | Out-File $csvPath -Encoding UTF8
            Send-Response $ctx 200 "application/json; charset=utf-8" '{"ok":true}'
        } catch {
            Send-Response $ctx 500 "application/json; charset=utf-8" ('{"ok":false}')
        }
        continue
    }


    # 静态文件
    $reqPath = $path.TrimStart('/')
    if ($reqPath -eq '') { $reqPath = 'gun_search.html' }
    $file = Join-Path $dir $reqPath

    if (Test-Path $file) {
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $mime = Get-MimeType $ext
        $content = [System.IO.File]::ReadAllBytes($file)
        $ctx.Response.ContentType = $mime
        $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $ctx.Response.OutputStream.Write($content, 0, $content.Length)
        $ctx.Response.Close()
    } else {
        Send-Response $ctx 404 "text/plain" "404 Not Found: $reqPath"
    }
}
