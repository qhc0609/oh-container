#Requires -Version 5.1
<#
.SYNOPSIS
    后台常驻：手机一插上，自动把 DeepSeek 网关和 USB 端口映射准备好

.DESCRIPTION
    解决的是「不想每次手动跑 ohc-gateway.ps1」这件事。
    它每 5 秒看一眼 hdc 有没有设备：
      - 设备出现  -> 起网关（node ohc-gw.mjs）+ 建 fport，VS Code 立刻可用
      - 设备消失  -> 收掉网关和映射，不留垃圾进程

    安装成开机自启：.\ohc-gateway-daemon.ps1 -Install
    卸载：          .\ohc-gateway-daemon.ps1 -Uninstall
    前台跑一次看日志：.\ohc-gateway-daemon.ps1 -Once

.PARAMETER Once
    只检查一轮就退出（排查用）

.PARAMETER Install
    安装成当前用户登录时自启的计划任务

.PARAMETER Uninstall
    删除计划任务
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [int]$Port = 18080,
    [int]$PollSeconds = 5,
    [string]$GwPath = "",
    [switch]$Once,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$TaskName = 'ohc-gateway-daemon'
$DataDir = Join-Path $env:LOCALAPPDATA 'ohc-gateway'
$LogFile = Join-Path $DataDir 'daemon.log'

if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

function Write-Log($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'MM-dd HH:mm:ss'), $m
    # 超过 1MB 就截掉前面一半，避免无限长大
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
        $tail = Get-Content $LogFile -Tail 500
        Set-Content -Path $LogFile -Value $tail -Encoding UTF8
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if (-not $Once) { } else { Write-Host $line }
}

# ---------------------------------------------------------------- 计划任务
$selfPath = $PSCommandPath
if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }

if ($Install) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$selfPath`""
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Description '手机插上后自动准备 DeepSeek 网关（ohc）' -Force | Out-Null
    Write-Host "[OK] 已安装计划任务 $TaskName（登录时自动启动）" -ForegroundColor Green
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[OK] 已立即启动" -ForegroundColor Green
    return
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] 已删除计划任务 $TaskName" -ForegroundColor Green
    return
}

if ($Status) {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        $i = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "[OK] 计划任务存在，状态 $($t.State)，上次运行 $($i.LastRunTime)" -ForegroundColor Green
    } else {
        Write-Host "[!] 计划任务不存在，跑 -Install 安装" -ForegroundColor Yellow
    }
    if (Test-Path $LogFile) { Write-Host "`n--- 最近 15 行日志 ---"; Get-Content $LogFile -Tail 15 }
    return
}

# ---------------------------------------------------------------- hdc
if (-not $Hdc) {
    foreach ($c in @(
        'C:\Tools\HarmonyOS\toolchains\hdc.exe',
        "$env:LOCALAPPDATA\Huawei\Sdk\openharmony\toolchains\hdc.exe",
        "$env:ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
    )) { if (Test-Path $c) { $Hdc = $c; break } }
    if (-not $Hdc) {
        $cmd = Get-Command hdc -ErrorAction SilentlyContinue
        if ($cmd) { $Hdc = $cmd.Source }
    }
}

# ---------------------------------------------------------------- 网关脚本位置
# 优先用仓库里的（改了就生效），仓库不在了就用本目录的副本（刷机恢复后仍能跑）
if (-not $GwPath) {
    $local = Join-Path $PSScriptRoot 'ohc-gw.mjs'
    $repo = Join-Path (Split-Path $PSScriptRoot -Parent) 'etc\ohc-gw.mjs'
    if (Test-Path $repo) { $GwPath = $repo }
    elseif (Test-Path $local) { $GwPath = $local }
}

$RemoteGw = '/data/ohc/rootfs/claude/usr/local/bin/ohc-gw.mjs'

function Get-DeviceList {
    try {
        $o = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
        return @($o)
    } catch { return @() }
}

function Get-GwPid {
    try {
        $o = (& $Hdc shell 'ps -ef 2>/dev/null | grep ohc-gw.mjs | grep -v grep' 2>&1) -join ' '
        if ($o -match '(\d+)\s') { return $Matches[1] }
    } catch { }
    return ''
}

function Test-Forward {
    try {
        $o = (& $Hdc fport ls 2>&1) -join "`n"
        return ($o -match [regex]::Escape("tcp:$Port"))
    } catch { return $false }
}

function Remove-Forward {
    # 坑：rm 和 add 一样，两个节点必须是两个独立参数。
    # 拼成一个字符串会回 "ruler is not exist" 但返回码仍是 0，静默失败。
    if (Test-Forward) { & $Hdc fport rm "tcp:$Port" "tcp:$Port" 2>&1 | Out-Null }
}

# 只查 fport ls 是不够的：实测出现过「映射记录在、但本机 18080 根本没监听」
# 的情况（hdc server 重启/设备重新枚举后，ruler 还在，listener 没了）。
# 这时 Continue 会报 "Error handling model response"，看着像模型出错，
# 其实是连不上。必须真的去连一下端口。
function Test-GatewayPort {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1500)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $c.Close()
    }
}

function Add-Forward {
    # 旧 ruler 占着端口时 add 会失败，先拆；再失败就退避重试
    for ($i = 1; $i -le 3; $i++) {
        $fp = (& $Hdc fport "tcp:$Port" "tcp:$Port" 2>&1) -join ' '
        Start-Sleep -Milliseconds 400
        if (Test-GatewayPort) { return $true }
        Write-Log "第 $i 次建映射没通（$fp），拆掉重试"
        Remove-Forward
        Start-Sleep -Milliseconds 800
    }
    return $false
}

function Start-Gateway {
    if (-not $GwPath -or -not (Test-Path $GwPath)) { Write-Log "找不到 ohc-gw.mjs，跳过"; return $false }

    $out = (& $Hdc file send $GwPath '/data/ohc/rootfs/claude/usr/local/bin/' 2>&1) -join ' '
    if ($out -notmatch 'finish') { Write-Log "推送网关失败: $out"; return $false }
    & $Hdc shell "chmod 644 $RemoteGw 2>/dev/null" | Out-Null

    $old = Get-GwPid
    if ($old) { & $Hdc shell "kill $old 2>/dev/null" | Out-Null; Start-Sleep -Milliseconds 400 }

    $cmd = "/data/ohc/bin/ohc run claude -- /bin/sh -c 'cd /work && nohup node /usr/local/bin/ohc-gw.mjs >> /work/ohc-gw.log 2>&1 & echo started'"
    & $Hdc shell $cmd 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    $gwPid = Get-GwPid
    if (-not $gwPid) { Write-Log '网关进程没起来'; return $false }
    Write-Log "网关已启动 pid=$gwPid"

    # 映射可能是"假活"，先无条件拆掉重建
    Remove-Forward
    if (-not (Add-Forward)) { Write-Log "端口映射建不起来，放弃本轮"; return $false }
    Write-Log "端口映射已建立且可连通 tcp:$Port"
    return $true
}

function Stop-Gateway {
    $gwPid = Get-GwPid
    if ($gwPid) { & $Hdc shell "kill $gwPid 2>/dev/null" | Out-Null; Write-Log "网关已停止 pid=$gwPid" }
    Remove-Forward
}

# ---------------------------------------------------------------- 主循环
if (-not $Hdc -or -not (Test-Path $Hdc)) {
    Write-Log "找不到 hdc.exe（$Hdc），守护进程退出"
    return
}

# 单实例：计划任务被重复触发、或者手动又跑一次时，不要出现两个守护进程
# 同时去起网关（会起出两个 node，抢同一个 18080）。
# -Once 是排查用的单轮模式，不参与抢锁，否则守护进程在跑时就查不了。
if (-not $Once) {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\ohc-gateway-daemon')
    if (-not $mutex.WaitOne(0)) {
        Write-Log '已有一个守护进程在跑，本次退出'
        return
    }
}

Write-Log "守护进程启动，hdc=$Hdc，轮询 ${PollSeconds}s，网关脚本=$GwPath"

$wasUp = $false
while ($true) {
    try {
        $dev = Get-DeviceList
        $hasDev = $dev.Count -gt 0

        if ($hasDev) {
            $up = (Get-GwPid) -ne ''
            # 三条都要过：进程在、ruler 在、本机端口真的能连上。
            # 只看前两条会漏掉「ruler 在但没监听」这种假活状态。
            $live = $up -and (Test-Forward) -and (Test-GatewayPort)

            if (-not $live) {
                if ($wasUp) { Write-Log "检测到网关/映射失效（进程=$up），重建" }
                else { Write-Log "检测到设备 $($dev -join ',')，开始准备网关" }
                if (Start-Gateway) {
                    if (-not $wasUp) { Write-Log '就绪，VS Code 现在可以用了' }
                    $wasUp = $true
                } else {
                    # 建不起来就别每 5 秒硬撞一次，缓一轮
                    Write-Log '本轮没建起来，10 秒后重试'
                    Start-Sleep -Seconds 10
                }
            } elseif (-not $wasUp) {
                Write-Log '网关已在运行，无需重复启动'
                $wasUp = $true
            }
        } else {
            if ($wasUp) {
                Write-Log '设备已断开，收掉网关'
                Stop-Gateway
                $wasUp = $false
            }
        }
    } catch {
        Write-Log ("轮询异常: " + $_.Exception.Message)
    }

    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
}
