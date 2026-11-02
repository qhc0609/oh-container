#Requires -Version 5.1
<#
.SYNOPSIS
    OpenHarmony 容器 + claude(DeepSeek) 环境一键恢复

.DESCRIPTION
    手机刷机 / 清除数据后 /data 被清空，这套环境就没了。
    本脚本把 PC 上的整包备份推回设备并解压，**全程不联网安装任何东西**。
    完成后 hdc shell 进去敲 claude 即可使用。

    恢复内容：
      /data/ohc/                      容器运行时 + Alpine rootfs + Node + claude + 全部依赖
      /data/ohc/containers/claude/env   DeepSeek API Key 与模型配置
      /data/ohc/workspace/            工作目录（容器内 /work）
      /data/python/lib/python3.8/script/bin/claude   PATH 里的 claude 入口

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找。

.PARAMETER Archive
    备份包路径，默认为脚本同目录下的 ohc-backup.tar.gz。

.PARAMETER Force
    设备上已存在 /data/ohc 时仍覆盖（默认中止，避免误删）。

.PARAMETER NoTest
    跳过最后的真实调用测试（不想消耗 token 时用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\restore.ps1
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [string]$Archive = "",
    [switch]$Force,
    [switch]$NoTest
)

$ErrorActionPreference = 'Stop'

# 让控制台按 UTF-8 输出，避免中文乱码
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host "`n[失败] $m" -ForegroundColor Red; exit 1 }

# hdc file send 的两个坑：目标是已存在的文件会报 "Not a directory"，
# 目标不存在则会建一个同名**目录**。统一走「发到父目录 + 改名」。
function Push-File([string]$Local, [string]$RemoteDir, [string]$RemoteName) {
    if (-not (Test-Path $Local)) { return $false }
    $base = Split-Path $Local -Leaf
    & $Hdc shell "mkdir -p '$RemoteDir'" | Out-Null
    $out = (& $Hdc file send $Local "$RemoteDir/" 2>&1) -join "`n"
    if ($out -notmatch 'finish') { Write-Warn2 "推送失败 $Local : $out"; return $false }
    if ($base -ne $RemoteName) {
        & $Hdc shell "mv -f '$RemoteDir/$base' '$RemoteDir/$RemoteName'" | Out-Null
    }
    return $true
}

# ------------------------------------------------------------------ 0. 定位 hdc
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

# ------------------------------------------------------------------ 1. 备份包
Write-Step "检查备份包"
if (-not $Archive) { $Archive = Join-Path $PSScriptRoot "ohc-backup.tar.gz" }
if (-not (Test-Path $Archive)) { Fail "找不到备份包: $Archive" }
$sizeMB = [math]::Round((Get-Item $Archive).Length / 1MB, 1)
Write-Ok "$Archive  ($sizeMB MB)"

$sumFile = Join-Path (Split-Path $Archive) "SHA256SUMS.txt"
if (Test-Path $sumFile) {
    Write-Step "校验 SHA256"
    $expect = ((Get-Content $sumFile -Raw).Trim() -split '\s+')[0].ToUpper()
    $actual = (Get-FileHash -Path $Archive -Algorithm SHA256).Hash.ToUpper()
    if ($expect -ne $actual) { Fail "校验失败，备份包可能损坏`n  期望: $expect`n  实际: $actual" }
    Write-Ok "校验通过 $actual"
} else {
    Write-Warn2 "没有 SHA256SUMS.txt，跳过校验"
}

# ------------------------------------------------------------------ 2. 设备
Write-Step "检查设备连接"
$targets = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
if (-not $targets) {
    Fail "没有检测到可用设备。`n  请确认 USB 已连接；若显示 Unauthorized，在手机上点允许调试"
}
Write-Ok ("设备: " + ($targets -join ', '))

# ------------------------------------------------------------------ 3. 现状
Write-Step "检查设备现状"
$probe = (& $Hdc shell "if [ -d /data/ohc ]; then echo YES; else echo NO; fi" 2>&1) -join ' '
if ($probe -match 'YES') {
    if (-not $Force) {
        Fail "设备上已存在 /data/ohc。`n  确认要覆盖请加 -Force；想先备份现有环境请先跑 backup.ps1"
    }
    Write-Warn2 "已存在 /data/ohc，按 -Force 覆盖"
} else {
    Write-Ok "/data 是干净的，开始恢复"
}

# ------------------------------------------------------------------ 4. 推送
Write-Step "推送备份包到设备（约 540MB，视 USB 速度 20~60 秒）"
& $Hdc shell "mkdir -p /data/local/tmp"
& $Hdc file send $Archive /data/local/tmp/ohc-backup.tar.gz
if ($LASTEXITCODE -ne 0) { Fail "推送失败" }
Write-Ok "推送完成"

# ------------------------------------------------------------------ 5. 设备端恢复脚本
# 注意：这段以 ASCII 写到设备，里面的提示文字只能是英文，中文会变成问号。
Write-Step "下发恢复脚本"
$devScript = @'
#!/bin/sh
# device-side restore script (pushed by restore.ps1)
set -e
PKG=/data/local/tmp/ohc-backup.tar.gz
[ -f "$PKG" ] || { echo "NO_PACKAGE"; exit 1; }

echo "--- extracting ---"
cd /data
tar -xzf "$PKG"

echo "--- fixing permissions ---"
chmod 755 /data/ohc/bin/ohc
chmod 755 /data/ohc/bin/ohc-claude
chmod 755 /data/ohc/bin/ohc-setkey
chmod 755 /data/ohc/bin/ohc-verify
chmod 755 /data/python/lib/python3.8/script/bin/claude
chmod 600 /data/ohc/containers/claude/env 2>/dev/null || true
mkdir -p /data/ohc/workspace

echo "--- cleaning temp package ---"
rm -f "$PKG"
rm -f /data/local/tmp/tarlist.txt /data/local/tmp/tarerr.txt

echo "EXTRACT_OK"

if [ "$1" = "test" ]; then
    echo "--- live test ---"
    claude -p "Reply with exactly this token and nothing else: RESTORE_OK"
fi
'@
$devScriptPath = Join-Path $env:TEMP "ohc-restore-device.sh"
Set-Content -Path $devScriptPath -Value ($devScript -replace "`r`n","`n") -Encoding ASCII -NoNewline
& $Hdc file send $devScriptPath /data/local/tmp/ohc-restore-device.sh | Out-Null
& $Hdc shell "chmod 755 /data/local/tmp/ohc-restore-device.sh"
Write-Ok "已下发"

# ------------------------------------------------------------------ 6. 执行恢复
Write-Step "在设备上解压（约 550MB，1~3 分钟，请勿断开 USB）"
if ($NoTest) {
    $out = (& $Hdc shell "/data/local/tmp/ohc-restore-device.sh" 2>&1) -join "`n"
} else {
    $out = (& $Hdc shell "/data/local/tmp/ohc-restore-device.sh test" 2>&1) -join "`n"
}
Write-Host $out -ForegroundColor DarkGray
if ($out -notmatch 'EXTRACT_OK') { Fail "解压失败，见上方输出" }
Write-Ok "解压完成"

# ------------------------------------------------------------------ 7. 验证
Write-Step "验证 claude"
$which = (& $Hdc shell "command -v claude" 2>&1) -join ' '
if ($which -match 'claude') {
    Write-Ok "claude 在 PATH 中: $($which.Trim())"
} else {
    Write-Warn2 "claude 不在 PATH 中——这个 ROM 的默认 PATH 可能变了"
    Write-Warn2 "临时可用: /data/ohc/bin/ohc-claude"
    Write-Warn2 "永久修复: 把 device-bin\claude 放到 PATH 中任意可写目录"
}

$ver = (& $Hdc shell "claude --version" 2>&1) -join ' '
if ($ver -match 'Claude Code') { Write-Ok "版本: $($ver.Trim())" } else { Write-Warn2 "版本检查异常: $ver" }

if (-not $NoTest) {
    if ($out -match 'RESTORE_OK') { Write-Ok "DeepSeek 真实调用正常" }
    else { Write-Warn2 "真实调用未见预期标记，请看上方输出" }
}

& $Hdc shell "rm -f /data/local/tmp/ohc-restore-device.sh" | Out-Null

# ------------------------------------------------------------------ 8. 用仓库里的最新运行时覆盖
# 备份包可能是几天前打的，而运行时（翻屏、防崩、尺寸同步）一直在改。
# 这里把仓库里的版本再推一遍，保证「恢复出来的就是最新那一版」。
$repoRoot = Split-Path $PSScriptRoot -Parent
if (Test-Path (Join-Path $repoRoot "bin\ohc-tty")) {
    Write-Step "同步仓库里的最新运行时"
    foreach ($f in @("ohc", "ohc-claude", "ohc-tty", "ohc-setkey", "oc-setkey", "ohc-verify")) {
        $null = Push-File (Join-Path $repoRoot "bin\$f") "/data/ohc/bin" $f
    }
    & $Hdc shell "chmod 755 /data/ohc/bin/ohc /data/ohc/bin/ohc-claude /data/ohc/bin/ohc-tty /data/ohc/bin/ohc-setkey /data/ohc/bin/oc-setkey /data/ohc/bin/ohc-verify 2>/dev/null" | Out-Null

    foreach ($f in @("claude", "opencode")) {
        $null = Push-File (Join-Path $repoRoot "device-bin\$f") "/data/python/lib/python3.8/script/bin" $f
        & $Hdc shell "chmod 755 /data/python/lib/python3.8/script/bin/$f 2>/dev/null" | Out-Null
    }

    $null = Push-File (Join-Path $repoRoot "etc\tmux.conf") "/data/ohc/rootfs/claude/root" ".tmux.conf"
    Write-Ok "运行时已更新到仓库版本"
} else {
    Write-Warn2 "没找到仓库目录，跳过运行时更新（只用备份包里的版本）"
}

# ------------------------------------------------------------------ 9. PC 侧收尾
# 这两件事不在备份包里，但缺了「能翻屏、不闪退」就复现不出来。
Write-Step "PC 侧设置"

# 9.1 关掉控制台「调整窗口大小时重排文本」。
# 这台机器的控制台缓冲区是 120x9001；最大化时 conhost 要把 9001 行按 1904 列
# 重排一遍，claude 的彩色/框线内容正好把它压垮 -> conhost.exe 0xc0000409。
# 现象：点一次最大化就闪退，而 claude 画面还停在原来的大小。
try {
    $lw = (Get-ItemProperty 'HKCU:\Console' -Name LineWrap -ErrorAction SilentlyContinue).LineWrap
    if ($null -ne $lw -and $lw -ne 0) {
        Set-ItemProperty 'HKCU:\Console' -Name LineWrap -Value 0 -Type DWord
        Write-Ok "已关闭控制台缩放重排（LineWrap=0，新开的窗口才生效）"
    } else {
        Write-Ok "控制台缩放重排已是关闭状态"
    }
} catch {
    Write-Warn2 ("设置 LineWrap 失败：" + $_.Exception.Message)
}

# 9.2 装 hdc 包装：让 `hdc shell` 走带尺寸同步的启动器，
# 否则设备那边永远按 80x24 排版（窗口再大也只用到左上角）。
$prof = Join-Path $repoRoot "bin\ohc-profile.ps1"
if (Test-Path $prof) {
    try {
        # 用子进程跑：ohc-profile.ps1 里若有 exit，不会把本脚本一起终止
        $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $null = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prof 2>&1
        Write-Ok "已安装 hdc 包装（新开窗口生效）"
    } catch {
        Write-Warn2 ("安装 hdc 包装失败：" + $_.Exception.Message)
    }
} else {
    Write-Warn2 "没找到 bin\ohc-profile.ps1，跳过 hdc 包装"
}

# ------------------------------------------------------------------ 完成
Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " 恢复完成" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host @"

用法（**先关掉当前 PowerShell，重新开一个**，PC 侧设置才生效）：
  hdc shell
  claude                 # DeepSeek V4.1-Flash（你自己的 DeepSeek Key）
  opencode               # OpenCode Zen 免费 DeepSeek V4.1-Flash Free

翻屏：
  直接拖 PowerShell 的滚动条 / 滚鼠标滚轮（claude 用 classic renderer 顺序输出）
  想要会话续接：OHC_TMUX=1 claude   （Ctrl+B [ 翻页，q 退出）

其它：
  claude -p "你好"                    # 单次提问
  opencode run "你好"                 # opencode 单次提问
  /data/ohc/bin/ohc doctor            # 环境自检
  /data/ohc/bin/ohc net               # 修复默认路由（出不了网时用）
  /data/ohc/bin/ohc-setkey sk-xxx     # 换 DeepSeek Key
  /data/ohc/bin/oc-setkey oc_sk-xxx   # 换 OpenCode Key

说明：
  容器内工作目录是 /work，对应设备上的 /data/ohc/workspace
  窗口缩放闪退已修：HKCU:\Console\LineWrap=0（想还原就改回 1）
"@ -ForegroundColor Gray
