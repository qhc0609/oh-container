#Requires -Version 5.1
<#
.SYNOPSIS
    带「窗口尺寸跟随」的 hdc shell 启动器

.DESCRIPTION
    hdc 给设备 pty 的尺寸是写死的（环境里 COLUMNS=80 LINES=24），
    PowerShell 窗口拖动时 hdc 也不会通知设备，所以 claude / opencode
    的 TUI 永远按 80x24 画。

    本脚本只做一件事：把**宿主机控制台**（PowerShell / cmd 窗口）的
    「行 列」写到设备的 /data/ohc/run/tty，设备侧 ohc-tty 用 busybox stty
    应用到 pty；窗口变化时再写一次（stty 触发 SIGWINCH，TUI 自己重画）。

    注意这里**故意不碰控制台缓冲区**（以前设过 BufferHeight = 9001）：
      - 它救不了 claude 的翻屏。hdc 用 SetConsoleCursorPosition 在控制台上
        自己模拟一块固定尺寸的屏幕，超屏的行压根没写进缓冲区。
        翻屏靠容器内的 tmux，见 etc/ohc-tmux。
      - 它会**把窗口搞崩**。窗口放大后 WindowWidth 会超过原来的 80，
        而缓冲区宽度还是 80，此时再设 BufferHeight 就是非法状态，
        conhost 会直接把整个窗口干掉（表现就是"放大缩小后必闪退"）。

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找。

.PARAMETER NoWatcher
    只在启动时同步一次尺寸，不跟随窗口变化。

.PARAMETER DryRun
    只做检查和尺寸同步，不进入交互会话。用来确认配置对不对。

.PARAMETER Quiet
    只报错误，不打印过程。供 ohc-profile.ps1 装的 hdc 包装函数使用。

.EXAMPLE
    .\bin\ohc-term.ps1

.EXAMPLE
    .\bin\ohc-term.ps1 -NoWatcher

.EXAMPLE
    .\bin\ohc-term.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [switch]$NoWatcher,
    [switch]$NoBigBuffer,
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# 想彻底关掉后台跟随（怀疑它影响稳定性时）：$env:OHC_NO_WATCHER = "1"
if ($env:OHC_NO_WATCHER -eq '1') { $NoWatcher = $true }
if ($env:OHC_NO_BIGBUFFER -eq '1') { $NoBigBuffer = $true }

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Step($m) { if (-not $Quiet) { Write-Host "==> $m" -ForegroundColor Cyan } }
function Write-Ok($m)   { if (-not $Quiet) { Write-Host "    [OK] $m" -ForegroundColor Green } }
function Write-Warn2($m){ if (-not $Quiet) { Write-Host "    [!]  $m" -ForegroundColor Yellow } }
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

# ------------------------------------------------------------------ 3. 尺寸同步
# 用 hdc file send 推一个内容为「行 列」的小文件，而不是 hdc shell "echo >"：
# file send 不碰控制台的 mode / 缓冲区，对前台会话干扰最小。
# 本地文件名必须叫 tty，因为 hdc 只会按原名把文件放进目标目录。
$sizeDir = Join-Path $env:TEMP "ohc-size"
if (-not (Test-Path $sizeDir)) { New-Item -ItemType Directory -Force -Path $sizeDir | Out-Null }
$sizeFile = Join-Path $sizeDir "tty"

function Send-Size([int]$r, [int]$c) {
    if ($r -lt 5 -or $c -lt 20) { return $false }
    try {
        [System.IO.File]::WriteAllText($sizeFile, "$r $c`n", [System.Text.Encoding]::ASCII)
        $pi = New-Object System.Diagnostics.ProcessStartInfo
        $pi.FileName = $Hdc
        $pi.Arguments = "file send `"$sizeFile`" /data/ohc/run/"
        $pi.UseShellExecute = $false
        $pi.CreateNoWindow = $true
        $pi.RedirectStandardInput = $true
        $pi.RedirectStandardOutput = $true
        $pi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($pi)
        try { $p.StandardInput.Close() } catch { }
        $ok = $p.WaitForExit(3000)
        if (-not $ok) { try { $p.Kill() } catch { } }
        $rc = if ($ok) { $p.ExitCode } else { -1 }
        try { $p.Dispose() } catch { }
        return ($rc -eq 0)
    } catch {
        return $false
    }
}

Write-Step "同步终端尺寸"
$initR = 30
$initC = 80
try {
    $initR = [Console]::WindowHeight
    $initC = [Console]::WindowWidth
} catch { }
$null = Send-Size $initR $initC
Write-Ok ("已写入 ${initC}x${initR}（列x行）")

$watcher = $null
if (-not $NoWatcher) {
    $watcher = [PowerShell]::Create()
    $null = $watcher.AddScript({
        param($hdcPath, $sizeFile, $lastR, $lastC)
        $r = $lastR
        $c = $lastC
        $fail = 0
        $pending = $false
        $urgent = $false        # 缩小时要立刻推
        $dirtyAt = 0
        $stableMs = 400         # 放大时等窗口停稳再推
        while ($true) {
            try {
                # 只读控制台，绝不写（写缓冲区会让 conhost 直接 fail-fast）
                $nr = [Console]::WindowHeight
                $nc = [Console]::WindowWidth
                if ($nr -ne $r -or $nc -ne $c) {
                    # 变小 = 危险方向：claude 还在按旧尺寸画，hdc 就可能写到缓冲区外面，
                    # 把 conhost 打崩（0xc0000409）。所以缩小时立刻推，让 claude 马上重画。
                    # 变大是安全方向，等窗口停稳再推，免得拖动过程中疯狂重画。
                    $urgent = ($nc -lt $c) -or ($nr -lt $r)
                    $r = $nr
                    $c = $nc
                    $pending = $true
                    $dirtyAt = [Environment]::TickCount
                }
                $due = $pending -and ($urgent -or (([Environment]::TickCount - $dirtyAt) -ge $stableMs))
                if ($due) {
                    $pending = $false
                    $urgent = $false
                    if ($r -ge 10 -and $c -ge 40) {
                        [System.IO.File]::WriteAllText($sizeFile, "$r $c`n", [System.Text.Encoding]::ASCII)
                        $pi = New-Object System.Diagnostics.ProcessStartInfo
                        $pi.FileName = $hdcPath
                        $pi.Arguments = "file send `"$sizeFile`" /data/ohc/run/"
                        $pi.UseShellExecute = $false
                        $pi.CreateNoWindow = $true
                        $pi.RedirectStandardInput = $true
                        $pi.RedirectStandardOutput = $true
                        $pi.RedirectStandardError = $true
                        $p = [System.Diagnostics.Process]::Start($pi)
                        try { $p.StandardInput.Close() } catch { }
                        if (-not $p.WaitForExit(3000)) { try { $p.Kill() } catch { } }
                        $rc = $p.ExitCode
                        try { $p.Dispose() } catch { }
                        if ($rc -ne 0) { $fail++ } else { $fail = 0 }
                        if ($fail -ge 5) { break }
                    }
                }
            } catch {
                $fail++
                if ($fail -ge 5) { break }
            }
            Start-Sleep -Milliseconds 250
        }
    }).AddArgument($Hdc).AddArgument($sizeFile).AddArgument($initR).AddArgument($initC)
    $null = $watcher.BeginInvoke()
    Write-Ok "窗口尺寸跟随已开启（缩小时立刻生效，放大时等窗口停稳）"
}

# ------------------------------------------------------------------ 4. 交互会话
if ($DryRun) {
    Start-Sleep -Milliseconds 900
    Write-Step "DryRun 校验"
    $got = (& $Hdc shell "cat /data/ohc/run/tty 2>/dev/null" 2>&1) -join ''
    Write-Ok ("设备侧 /data/ohc/run/tty = " + $got.Trim())
    Write-Ok ("本机窗口 = " + [Console]::WindowWidth + "x" + [Console]::WindowHeight + "（列x行）")
    if ($watcher) { try { $watcher.Stop() } catch { }; try { $watcher.Dispose() } catch { } }
    Write-Host ""
    Write-Host "  DryRun 结束，没有进入交互会话" -ForegroundColor Gray
    return
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "  进去后直接敲 claude 或 opencode" -ForegroundColor Gray
    Write-Host "  翻屏：直接拖滚动条 / 滚鼠标滚轮（claude 已切回顺序输出，行会进宿主回滚区）" -ForegroundColor Gray
    Write-Host "  退出会话（exit 或 Ctrl+D）后，尺寸跟随自动停止" -ForegroundColor Gray
    Write-Host "  提示：先把窗口拉到合适大小再进来。hdc 自己处理缩放有 bug，" -ForegroundColor DarkGray
    Write-Host "        会话进行中反复缩放可能让整个窗口崩掉（conhost 0xc0000409）" -ForegroundColor DarkGray
    Write-Host ""
}

# ------------------------------------------------------------------ 5. 放大控制台缓冲区
#
# 崩溃机理（有事件日志和崩溃转储撑腰）：
#   hdc 用**绝对坐标**往控制台写（SetConsoleCursorPosition），而且从不调
#   SetConsoleScreenBufferSize / SetConsoleWindowInfo 去跟着窗口调整。
#   窗口被拖小以后，它仍按原来的坐标写 -> 越界 -> conhost 直接 fail-fast
#   （Application Error 1000：conhost.exe 0xc0000409，WER 事件 BEX64）。
#   裸 hdc shell 不崩，是因为它缩放时没东西可写；claude 一直在重画，所以必崩。
#
# 对策：进会话之前把缓冲区一次性放大到「不小于窗口、且留足余量」。
# 只要缓冲区不缩回窗口大小，hdc 那些旧坐标就仍然落在合法范围内。
# 必须保证 buffer 宽 >= 窗口宽、buffer 高 >= 窗口高，否则就是非法状态
# —— 之前把 conhost 写崩过，就是栽在这一条上（宽 80 < 窗口宽 120）。
if (-not $NoBigBuffer) {
    try {
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
        $tw = [Math]::Max($w, 120)
        $th = [Math]::Max($h, 600)
        if ([Console]::BufferWidth -lt $tw -or [Console]::BufferHeight -lt $th) {
            [Console]::SetBufferSize([Math]::Max($tw, [Console]::BufferWidth),
                                     [Math]::Max($th, [Console]::BufferHeight))
            Write-Ok ("控制台缓冲区 -> " + [Console]::BufferWidth + "x" + [Console]::BufferHeight + "（窗口 " + $w + "x" + $h + "）")
        }
    } catch {
        Write-Warn2 ("放大控制台缓冲区失败（不影响使用）：" + $_.Exception.Message)
    }
}

try {
    & $Hdc shell
} finally {
    if ($watcher) { try { $watcher.Stop() } catch { }; try { $watcher.Dispose() } catch { } }
}