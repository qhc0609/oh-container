#Requires -Version 5.1
<#
.SYNOPSIS
    带「窗口尺寸跟随」的 hdc shell 启动器

.DESCRIPTION
    hdc 给设备 pty 的尺寸是写死的（环境里 COLUMNS=80 LINES=24），
    PowerShell 窗口拖动时 hdc 也不会通知设备，所以 claude / opencode
    的 TUI 永远按 80x24 画，窗口再大也只用到左上角。

    本脚本做两件事：
      1. 把 PowerShell 窗口的「行 列」写到设备的 /data/ohc/run/tty，
         设备侧 ohc-tty 用 busybox stty 应用到 pty；
         窗口变化时再写一次（stty 触发 SIGWINCH，TUI 自己重画）。
      2. 把控制台缓冲区调高，让滚出屏幕的历史输出能翻页（conhost 有效）。

    启动后你在里面照常敲 claude 或 opencode。

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找。

.PARAMETER BufferHeight
    控制台缓冲区行数，默认 9001。设为 0 可跳过。

.PARAMETER NoBuffer
    不调整控制台缓冲区（Windows Terminal 下本来也不需要）。

.PARAMETER NoWatcher
    只在启动时同步一次尺寸，不跟随窗口变化。

.EXAMPLE
    .\bin\ohc-term.ps1

.EXAMPLE
    .\bin\ohc-term.ps1 -NoBuffer
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [int]$BufferHeight = 9001,
    [switch]$NoBuffer,
    [switch]$NoWatcher
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host "[失败] $m" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ 1. hdc
Write-Step "检查 hdc"
if (-not $Hdc) {
    foreach ($c in @(
        "C:\Tools\HarmonyOS\toolchains\hdc.exe",
        "$env:LOCALAPPDATA\Huawei\Sdk\openharmony\toolchains\hdc.exe",
        "$env:ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
    )) { if (Test-Path $c) { $Hdc = $c; break } }
    if (-not $Hdc) {
        $cmd = Get-Command hdc -ErrorAction SilentlyContinue
        if ($cmd) { $Hdc = $cmd.Source }
    }
}
if (-not $Hdc -or -not (Test-Path $Hdc)) { Fail "找不到 hdc.exe，请用 -Hdc 指定路径" }
Write-Ok $Hdc

# ------------------------------------------------------------------ 2. 设备
Write-Step "检查设备连接"
$targets = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
if (-not $targets) {
    Fail "没有检测到可用设备。请确认 USB 已连接；若显示 Unauthorized，在手机上点允许调试"
}
Write-Ok ("设备: " + ($targets -join ', '))

& $Hdc shell "mkdir -p /data/ohc/run" 2>&1 | Out-Null

$hasTty = (& $Hdc shell "test -x /data/ohc/bin/ohc-tty && echo YES || echo NO" 2>&1) -join ''
if ($hasTty -notmatch 'YES') {
    Write-Warn2 "设备上缺 /data/ohc/bin/ohc-tty，尺寸同步不会生效"
    Write-Warn2 "先跑一次 .\deploy.ps1 把运行时补齐"
}

# ------------------------------------------------------------------ 3. 缓冲区（为了能翻页）
if (-not $NoBuffer -and $BufferHeight -gt 0) {
    Write-Step "调整控制台缓冲区（翻页用）"
    try {
        $before = [Console]::BufferHeight
        if ($before -lt $BufferHeight) {
            [Console]::BufferHeight = $BufferHeight
            Write-Ok ("缓冲区 " + $before + " -> " + [Console]::BufferHeight + " 行")
        } else {
            Write-Ok ("缓冲区已是 " + $before + " 行，无需调整")
        }
    } catch {
        Write-Warn2 "当前终端不支持改缓冲区（Windows Terminal 常见），跳过"
        Write-Warn2 "翻页用 Shift+PgUp / 鼠标滚轮；WT 里可在设置里调大 scrollback"
    }
}

# ------------------------------------------------------------------ 4. 尺寸同步
# 关键：把子进程的 stdin/stdout/stderr 全部重定向到管道，
# 它就拿不到控制台句柄，不会把前台会话的 raw 模式改回去。
function Send-Size([int]$r, [int]$c) {
    if ($r -lt 5 -or $c -lt 20) { return }
    $arg = "echo '$r $c' > /data/ohc/run/tty"
    try {
        $pi = New-Object System.Diagnostics.ProcessStartInfo
        $pi.FileName = $Hdc
        $pi.Arguments = "shell `"$arg`""
        $pi.UseShellExecute = $false
        $pi.CreateNoWindow = $true
        $pi.RedirectStandardInput = $true
        $pi.RedirectStandardOutput = $true
        $pi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($pi)
        try { $p.StandardInput.Close() } catch { }
        if (-not $p.WaitForExit(3000)) { try { $p.Kill() } catch { } }
        try { $p.Dispose() } catch { }
    } catch {
        # 退路：直接调，出错也不影响会话
        try { & $Hdc shell "$arg" 2>&1 | Out-Null } catch { }
    }
}

Write-Step "同步终端尺寸"
$initR = 30
$initC = 80
try {
    $initR = [Console]::WindowHeight
    $initC = [Console]::WindowWidth
} catch { }
Send-Size $initR $initC
Write-Ok ("已写入 ${initC}x${initR}（列x行）")

$bufTarget = 0
if (-not $NoBuffer) { $bufTarget = $BufferHeight }

$watcher = $null
if (-not $NoWatcher) {
    $watcher = [PowerShell]::Create()
    $null = $watcher.AddScript({
        param($hdcPath, $lastR, $lastC, $bufTarget)
        $r = $lastR
        $c = $lastC
        $tick = 0
        while ($true) {
            try {
                $nr = [Console]::WindowHeight
                $nc = [Console]::WindowWidth
                if (($nr -ne $r -or $nc -ne $c) -and $nr -ge 5 -and $nc -ge 20) {
                    $r = $nr
                    $c = $nc
                    $arg = "echo '$r $c' > /data/ohc/run/tty"
                    $pi = New-Object System.Diagnostics.ProcessStartInfo
                    $pi.FileName = $hdcPath
                    $pi.Arguments = "shell `"$arg`""
                    $pi.UseShellExecute = $false
                    $pi.CreateNoWindow = $true
                    $pi.RedirectStandardInput = $true
                    $pi.RedirectStandardOutput = $true
                    $pi.RedirectStandardError = $true
                    $p = [System.Diagnostics.Process]::Start($pi)
                    try { $p.StandardInput.Close() } catch { }
                    $null = $p.WaitForExit(2000)
                    if (-not $p.HasExited) { try { $p.Kill() } catch { } }
                    try { $p.Dispose() } catch { }
                }
                # hdc 起会话时可能把缓冲区压回窗口高度，导致翻页失效，这里定期纠正
                $tick++
                if ($bufTarget -gt 0 -and ($tick % 4) -eq 0) {
                    try {
                        if ([Console]::BufferHeight -lt $bufTarget) {
                            [Console]::BufferHeight = $bufTarget
                        }
                    } catch { }
                }
            } catch { }
            Start-Sleep -Milliseconds 500
        }
    }).AddArgument($Hdc).AddArgument($initR).AddArgument($initC).AddArgument($bufTarget)
    $null = $watcher.BeginInvoke()
    Write-Ok "窗口尺寸跟随已开启（拖动窗口后约 1 秒生效）"
}

# ------------------------------------------------------------------ 5. 交互会话
Write-Host ""
Write-Host "  进去后直接敲 claude 或 opencode" -ForegroundColor Gray
Write-Host "  手动再同步一次尺寸：  /data/ohc/bin/ohc-tty" -ForegroundColor Gray
Write-Host "  退出会话（exit 或 Ctrl+D）后，尺寸跟随自动停止" -ForegroundColor Gray
Write-Host ""

try {
    & $Hdc shell
} finally {
    if ($watcher) { try { $watcher.Stop() } catch { }; try { $watcher.Dispose() } catch { } }
}
