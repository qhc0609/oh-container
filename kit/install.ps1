#Requires -Version 5.1
<#
.SYNOPSIS
    在一台「不能上网」的 Windows 电脑上，把 VS Code 接上手机里的 DeepSeek

.DESCRIPTION
    场景：这台 PC 连不上外网，但 USB 口是通的，手机有流量。
    手机里已经装好了 ohc 容器（claude + DeepSeek Key）。

    这个脚本干六件事，全部自动，不需要手工配置：
      1. 找到 VS Code 和 hdc（hdc 就在本包的 payload 里，不用装 SDK）
      2. 确认手机里的网关进程在跑，不在就拉起来
      3. 建立 USB 端口转发 127.0.0.1:18080 -> 手机:18080
      4. 离线安装 Continue 扩展（从 payload/continue.vsix，不联网）
      5. 写好 Continue 的模型配置，指向本机网关
      6. 装一个开机自启的守护进程，以后手机一插上就自动就绪

    用完 VS Code 里按 Ctrl+L 就是聊天框。

.PARAMETER Hdc
    指定 hdc.exe 路径。默认用 payload 里自带的。

.PARAMETER Port
    本机监听端口，默认 18080。

.PARAMETER ApiBase
    手工指定网关地址（例如走 USB 网络共享时填 http://192.168.42.129:18080）。
    默认走 hdc 端口转发 http://127.0.0.1:18080。

.PARAMETER Tether
    不用 hdc，自动在局域网里找手机的 18080（USB 网络共享模式）。

.PARAMETER ExtensionsDir
    把扩展装到指定目录（测试用，正常不用填）。

.PARAMETER SkipExtension
    跳过扩展安装（已经装过 Continue 时用）。

.PARAMETER SkipConfig
    跳过模型配置写入（不想覆盖已有配置时用）。

.PARAMETER NoDaemon
    不装开机自启守护进程。

.PARAMETER Check
    只体检，不改任何东西。

.EXAMPLE
    .\run.cmd
    双击 run.cmd 就是完整安装。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Check
    先看看哪里有问题，不动手。
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [int]$Port = 18080,
    [string]$ApiBase = "",
    [switch]$Tether,
    [string]$ExtensionsDir = "",
    [switch]$SkipExtension,
    [switch]$SkipConfig,
    [switch]$NoDaemon,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest 默认会画进度条，在控制台里会把已经打出来的中文覆盖成乱码
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Root    = $PSScriptRoot
$Payload = Join-Path $Root 'payload'
$RemoteGw = '/data/ohc/rootfs/claude/usr/local/bin/ohc-gw.mjs'

# ------------------------------------------------------------------ 输出
# 注意：不要用 Write-Host "" 打空行。PS 5.1 在输出被重定向/管道时会把
# 空字符串的 Write-Host 吞掉，导致下一行直接粘在上一行末尾。
# 用 Write-Host " "（一个空格）就稳定了。
function Write-Step($m) { Write-Host " "; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info($m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Write-Warn2($m){ Write-Host "    [!] $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host " "; Write-Host "[失败] $m" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ 通用工具
function Test-Tcp {
    param([string]$Target, [int]$P, [int]$TimeoutMs = 1200)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($Target, $P, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Get-Health([string]$Base) {
    try {
        return (Invoke-WebRequest -Uri "$Base/healthz" -UseBasicParsing -TimeoutSec 6).Content.Trim()
    } catch { return "" }
}

function Get-GwPid {
    # 不在设备上跑 `ps | grep`：这台手机的 toybox grep 在管道里会间歇性
    # 报 "Invalid argument"。整段拿回来在 PC 侧过滤更稳。
    try {
        $lines = & $Hdc shell "ps -ef" 2>&1
        foreach ($l in $lines) {
            $s = "$l"
            if ($s -match 'ohc-gw\.mjs' -and $s -notmatch 'grep') {
                if ($s -match '^\S+\s+(\d+)') { return $Matches[1] }
            }
        }
    } catch { }
    return ''
}

# ------------------------------------------------------------------ 0. 抬头
Write-Host " "
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  ohc VS Code 离线套件 —— 让这台电脑用上手机里的 DeepSeek" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Info "安装包位置: $Root"
if ($Check) { Write-Warn2 "体检模式：只看不改" }

if (-not (Test-Path $Payload)) { Fail "找不到 payload 目录，压缩包是不是没解压完整？" }

# ------------------------------------------------------------------ 1. 找 VS Code
Write-Step "定位 VS Code"

$codeCli = ""
$cands = New-Object System.Collections.Generic.List[string]

$c = Get-Command code.cmd -ErrorAction SilentlyContinue
if ($c) { $cands.Add($c.Source) }
$c = Get-Command code -ErrorAction SilentlyContinue
if ($c -and $c.Source -like '*.cmd') { $cands.Add($c.Source) }

foreach ($k in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe')) {
    try {
        $exe = (Get-ItemProperty -Path $k -ErrorAction Stop).'(default)'
        if ($exe) { $cands.Add((Join-Path (Split-Path $exe) 'bin\code.cmd')) }
    } catch { }
}

foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
    "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
    "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd")) { $cands.Add($p) }

# 装在别的盘（D:\Program Files\... 之类）的情况：扫一遍固定磁盘
try {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($sub in @('Program Files\Microsoft VS Code', 'Program Files (x86)\Microsoft VS Code')) {
            $cands.Add((Join-Path (Join-Path $d.Root $sub) 'bin\code.cmd'))
        }
    }
} catch { }

foreach ($p in $cands) {
    if ($p -and (Test-Path $p)) { $codeCli = $p; break }
}

if (-not $codeCli) {
    Fail @"
没找到 VS Code 的命令行入口 code.cmd。

这台电脑装了 VS Code 吗？如果装了但还是找不到，手动跑：

  powershell -ExecutionPolicy Bypass -File install.ps1 -ExtensionsDir "你的扩展目录"

或者把 VS Code 重装一遍（勾上"添加到 PATH"）。
"@
}
Write-Ok "VS Code: $codeCli"

# 版本
try {
    $vOut = (& $codeCli --version 2>&1) -join ' '
    if ($vOut -match '(\d+\.\d+\.\d+)') { Write-Ok "版本 $($Matches[1])" }
} catch { }

# ------------------------------------------------------------------ 2. 找 hdc
Write-Step "定位 hdc"

if (-not $Hdc) {
    $bundled = Join-Path $Payload 'hdc.exe'
    if (Test-Path $bundled) { $Hdc = $bundled }
}
if (-not $Hdc) {
    foreach ($p in @(
        'C:\Tools\HarmonyOS\toolchains\hdc.exe',
        "$env:LOCALAPPDATA\Huawei\Sdk\openharmony\toolchains\hdc.exe",
        "$env:ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe")) {
        if (Test-Path $p) { $Hdc = $p; break }
    }
}
if (-not $Hdc) {
    $c = Get-Command hdc -ErrorAction SilentlyContinue
    if ($c) { $Hdc = $c.Source }
}
if (-not $Hdc) {
    if ($Tether -or $ApiBase) {
        Write-Warn2 "没有 hdc，但你指定了网络模式，继续"
    } else {
        Fail "找不到 hdc.exe（payload 里也没有），也没指定 -Tether / -ApiBase"
    }
}
if ($Hdc) { Write-Ok "hdc: $Hdc" }

# ------------------------------------------------------------------ 3. 确定网关地址
$Base = ""
$Devices = @()

if (-not $Tether) {
    Write-Step "等待手机接入"
    $waited = 0
    while ($waited -lt 30) {
        try {
            $out = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
            $Devices = @($out)
        } catch { $Devices = @() }
        if ($Devices.Count -gt 0) { break }
        Start-Sleep -Seconds 2
        $waited += 2
        Write-Host "    ... 已等 $waited 秒" -ForegroundColor DarkGray
    }
    if ($Devices.Count -eq 0) {
        Write-Warn2 "hdc 看不到设备"
        Write-Info "常见原因："
        Write-Info "  1) 手机没插好，或 USB 线只能充电"
        Write-Info "  2) 手机上没允许 USB 调试"
        Write-Info "  3) 这台电脑缺 HarmonyOS USB 驱动（首次连接才会遇到）"
        Write-Info ""
        Write-Info "绕开的办法：手机打开「USB 网络共享」，然后跑"
        Write-Info "  powershell -ExecutionPolicy Bypass -File install.ps1 -Tether"
    } else {
        Write-Ok "设备: $($Devices -join ', ')"
    }
}

if ($ApiBase) {
    $Base = $ApiBase.TrimEnd('/')
    Write-Ok "用指定地址: $Base"
} elseif ($Devices.Count -gt 0) {
    $Base = "http://127.0.0.1:$Port"
} elseif ($Tether) {
    Write-Step "在局域网里找手机"
    $tries = New-Object System.Collections.Generic.List[string]
    try {
        Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            ForEach-Object { if ($_.NextHop) { $tries.Add($_.NextHop) } }
    } catch { }
    try {
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' } |
            ForEach-Object {
                $pre = (($_.IPAddress -split '\.')[0..2]) -join '.'
                $tries.Add("$pre.1"); $tries.Add("$pre.129"); $tries.Add("$pre.2")
            }
    } catch { }
    $found = ""
    foreach ($ip in ($tries | Select-Object -Unique)) {
        $b = "http://${ip}:$Port"
        if ((Get-Health $b) -match 'ohc-gw ok') { $found = $b; break }
    }
    if (-not $found) { Fail "没找到手机上的网关。确认手机开了 USB 网络共享，且容器在跑。" }
    $Base = $found
    Write-Ok "找到网关: $Base"
} else {
    Fail "没有可用通路（既没有 hdc 设备，也没指定 -Tether）"
}

# ------------------------------------------------------------------ 4. 确认手机里的网关
if ($Devices.Count -gt 0 -and -not $Check) {
    Write-Step "确认手机里的网关进程"

    $hasOhc = ((& $Hdc shell "ls /data/ohc/bin/ohc 2>/dev/null" 2>&1) -join ' ')
    if ($hasOhc -notmatch '/data/ohc/bin/ohc') {
        Fail @"
手机里没有 ohc 容器（/data/ohc/bin/ohc 不存在）。

先把容器恢复到手机上：在原来的电脑上跑 backup\restore.ps1，
或者按 README 第 8 章重建。容器在，这个套件才有东西可转发。
"@
    }
    Write-Ok "容器在"

    $gwPid = Get-GwPid
    if ($gwPid) {
        Write-Ok "网关在跑，pid=$gwPid"
    } else {
        Write-Warn2 "网关没在跑，现在拉起来"

        $localGw = Join-Path $Payload 'ohc-gw.mjs'
        if (Test-Path $localGw) {
            $out = (& $Hdc file send $localGw '/data/ohc/rootfs/claude/usr/local/bin/' 2>&1) -join ' '
            if ($out -notmatch 'finish') { Write-Warn2 "推送网关脚本失败: $out" }
            else { Write-Ok "网关脚本已推送" }
            & $Hdc shell "chmod 644 $RemoteGw 2>/dev/null" | Out-Null
        }

        $cmd = "/data/ohc/bin/ohc run claude -- /bin/sh -c 'cd /work && nohup node /usr/local/bin/ohc-gw.mjs >> /work/ohc-gw.log 2>&1 & echo started'"
        & $Hdc shell $cmd 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        $gwPid = Get-GwPid
        if (-not $gwPid) {
            Write-Warn2 "网关没起来，看手机日志："
            & $Hdc shell "tail -15 /data/ohc/workspace/ohc-gw.log 2>/dev/null" 2>&1 | ForEach-Object { Write-Info $_ }
            Fail "网关启动失败。多半是手机里没有 DeepSeek Key，跑 /data/ohc/bin/ohc-setkey sk-xxx 补上。"
        }
        Write-Ok "网关已启动 pid=$gwPid"
    }
}

# ------------------------------------------------------------------ 5. 建立端口转发
if ($Devices.Count -gt 0 -and -not $Check) {
    Write-Step "建立 USB 端口转发"
    $task = "tcp:$Port tcp:$Port"

    # 坑：fport 的 rm 和 add 一样，两个节点必须是两个独立参数。
    # 拼成一个字符串会回 "ruler is not exist" 但返回码仍是 0，静默失败。
    & $Hdc fport rm "tcp:$Port" "tcp:$Port" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 400

    $fp = ""
    for ($i = 1; $i -le 3; $i++) {
        $fp = (& $Hdc fport "tcp:$Port" "tcp:$Port" 2>&1) -join ' '
        if (Test-Tcp '127.0.0.1' $Port) { break }
        Start-Sleep -Milliseconds 800
    }

    if (-not (Test-Tcp '127.0.0.1' $Port)) { Fail "端口转发没建起来（$fp）" }
    Write-Ok "127.0.0.1:$Port -> 手机 $Port"

    $hz = Get-Health $Base
    if ($hz -match 'ohc-gw ok') { Write-Ok "通道验证: $hz" }
    else { Write-Warn2 "端口通了但 healthz 没回应，稍后守护进程会再修一次" }
} elseif ($Check) {
    if (Test-Tcp '127.0.0.1' $Port) { Write-Ok "端口 $Port 可连通" } else { Write-Warn2 "端口 $Port 不通" }
}

# ------------------------------------------------------------------ 6. 装扩展
if (-not $SkipExtension -and -not $Check) {
    Write-Step "安装 Continue 扩展（离线）"

    $vsix = Join-Path $Payload 'continue.vsix'
    if (-not (Test-Path $vsix)) { Fail "payload 里没有 continue.vsix" }

    $extra = @()
    if ($ExtensionsDir) { $extra += @('--extensions-dir', $ExtensionsDir) }

    $installed = $false
    try {
        $list = (& $codeCli @extra --list-extensions 2>&1) -join "`n"
        if ($list -match '(?im)^\s*continue\.continue') { $installed = $true }
    } catch { }

    if ($installed) {
        Write-Ok "Continue 已经装过了"
    } else {
        Write-Info "从本地 vsix 安装，不需要联网..."
        $r = (& $codeCli @extra --install-extension $vsix --force 2>&1) -join "`n"
        if ($r -match 'successfully installed|already installed') {
            Write-Ok "Continue 安装完成"
        } else {
            Write-Warn2 "安装返回：$r"
            Fail "扩展安装失败。可以手动装：VS Code 里 Ctrl+Shift+P -> Install from VSIX -> 选 payload\continue.vsix"
        }
    }
} elseif ($Check) {
    try {
        $list = (& $codeCli --list-extensions 2>&1) -join "`n"
        if ($list -match '(?im)^\s*continue\.continue') { Write-Ok "Continue 已安装" }
        else { Write-Warn2 "Continue 没装" }
    } catch { }
}

# ------------------------------------------------------------------ 7. 写配置
if (-not $SkipConfig -and -not $Check) {
    Write-Step "写入 Continue 模型配置"

    $cfgDir = Join-Path $env:USERPROFILE '.continue'
    if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
    $cfg = Join-Path $cfgDir 'config.yaml'

    if (Test-Path $cfg) {
        $bak = "$cfg.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item $cfg $bak -Force
        Write-Info "已有配置已备份到 $(Split-Path $bak -Leaf)"
    }

    $tmpl = Join-Path $Payload 'continue-config.yaml'
    if (-not (Test-Path $tmpl)) { Fail "payload 里没有 continue-config.yaml" }

    $txt = Get-Content $tmpl -Raw -Encoding UTF8
    $txt = $txt -replace 'http://127\.0\.0\.1:18080/v1', "$Base/v1"
    [System.IO.File]::WriteAllText($cfg, $txt, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "已写入 $cfg"
    Write-Ok "模型地址: $Base/v1"
}

# ------------------------------------------------------------------ 8. 真实对话验证
if (-not $Check) {
    Write-Step "验证模型真的能用"
    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            $p = @{
                model      = 'deepseek-flash'
                messages   = @(@{ role = 'user'; content = '只回复两个字：收到' })
                max_tokens = 800
            } | ConvertTo-Json -Depth 6
            $b = [System.Text.Encoding]::UTF8.GetBytes($p)
            $r = Invoke-RestMethod -Uri "$Base/v1/chat/completions" -Method Post `
                    -ContentType 'application/json; charset=utf-8' -Body $b -TimeoutSec 90
            $c = "$($r.choices[0].message.content)".Trim()
            Write-Ok "模型回话: [$c]   tokens=$($r.usage.total_tokens)"
            $ok = $true
            break
        } catch {
            Write-Warn2 "第 $i 次失败: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
    if (-not $ok) {
        Write-Warn2 "验证没通过，但配置已写好。看手机日志排查："
        if ($Devices.Count -gt 0) {
            & $Hdc shell "tail -15 /data/ohc/workspace/ohc-gw.log 2>/dev/null" 2>&1 | ForEach-Object { Write-Info $_ }
        }
    }
}

# ------------------------------------------------------------------ 9. 守护进程
if (-not $NoDaemon -and -not $Check -and $Devices.Count -gt 0) {
    Write-Step "安装开机自启的守护进程"

    $inst = Join-Path $env:LOCALAPPDATA 'ohc-gateway'
    if (-not (Test-Path $inst)) { New-Item -ItemType Directory -Path $inst -Force | Out-Null }

    foreach ($f in @('ohc-gateway-daemon.ps1', 'ohc-gw.mjs', 'hdc.exe', 'libusb_shared.dll')) {
        $src = Join-Path $Payload $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $inst $f) -Force }
    }
    Write-Ok "文件已就位: $inst"

    $daemon = Join-Path $inst 'ohc-gateway-daemon.ps1'
    if (Test-Path $daemon) {
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $r = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $daemon -Install 2>&1) -join "`n"
        if ($r -match 'OK') { Write-Ok "守护进程已装好（登录即启动，5 秒巡检一次）" }
        else { Write-Warn2 "守护进程安装返回: $r" }
    }
}

# ------------------------------------------------------------------ 10. 收尾
Write-Host " "
Write-Host "==============================================================" -ForegroundColor Green
if ($Check) {
    Write-Host "  体检结束" -ForegroundColor Green
} else {
    Write-Host "  装完了" -ForegroundColor Green
}
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " "
Write-Host "接下来："
Write-Host "  1. 打开（或重启）VS Code"
Write-Host "  2. 按 Ctrl+L 打开 Continue 聊天框" -ForegroundColor Yellow
Write-Host "  3. 直接问，模型显示为「DeepSeek V4.1 Flash（手机中转）」"
Write-Host " "
Write-Host "注意：Continue 要有工作区才能写文件。"
Write-Host "     先 File -> Open Folder 打开一个目录，别停在空窗口。"
Write-Host " "
Write-Host "网关地址: $Base/v1"
Write-Host "排查命令: hdc shell `"tail -20 /data/ohc/workspace/ohc-gw.log`""
Write-Host " "
