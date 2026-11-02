#Requires -Version 5.1
<#
.SYNOPSIS
    把 ohc 容器运行时 + claude/opencode 配置部署到已连接的 OpenHarmony 设备

.DESCRIPTION
    本脚本只负责「运行时 + 配置 + PATH 入口」这一层，
    要求设备上已经有 rootfs（来自 backup/restore.ps1，或者你自己按 docs/ 里的步骤建）。

    部署内容：
      /data/ohc/bin/                        容器运行时与工具（5 个脚本）
      /data/ohc/containers/claude/env       DeepSeek Key 与模型配置（600 权限）
      /data/ohc/rootfs/claude/root/.config/opencode/opencode.json
      /data/ohc/rootfs/claude/root/.claude.json
      /data/python/lib/python3.8/script/bin/claude     PATH 入口
      /data/python/lib/python3.8/script/bin/opencode   PATH 入口

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找。

.PARAMETER Key
    DeepSeek API Key（sk- 开头）。不填则保留设备上现有的 key。

.PARAMETER OcKey
    OpenCode API Key（oc_sk_ 开头）。不填则保留设备上现有的登录状态。

.PARAMETER SkipVerify
    跳过最后的端到端验证（不想消耗 token 时用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Key sk-xxxxxxxx

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Key sk-xxx -OcKey oc_sk_xxx
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [string]$Key = "",
    [string]$OcKey = "",
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host "`n[失败] $m" -ForegroundColor Red; exit 1 }

$RepoRoot = $PSScriptRoot
$TmpDir   = Join-Path $env:TEMP "ohc-deploy"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

# ------------------------------------------------------------------ 0. hdc
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

# ------------------------------------------------------------------ 1. 设备
Write-Step "检查设备连接"
$targets = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
if (-not $targets) {
    Fail "没有检测到可用设备。`n  请确认 USB 已连接；若显示 Unauthorized，在手机上点允许调试"
}
Write-Ok ("设备: " + ($targets -join ', '))

# ------------------------------------------------------------------ 2. rootfs
Write-Step "检查 rootfs"
$probe = (& $Hdc shell "if [ -x /data/ohc/rootfs/claude/bin/sh ]; then echo YES; else echo NO; fi" 2>&1) -join ' '
if ($probe -notmatch 'YES') {
    Write-Warn2 "设备上没有可用的 rootfs：/data/ohc/rootfs/claude/bin/sh 不存在"
    Write-Warn2 "两种办法："
    Write-Warn2 "  1) 用备份恢复：powershell -File .\backup\restore.ps1"
    Write-Warn2 "  2) 按 docs/build-rootfs.md 从 Alpine 自己建一个"
    Fail "缺少 rootfs，中止"
}
Write-Ok "rootfs 就绪"

# ------------------------------------------------------------------ 3. 目录
Write-Step "创建目录"
& $Hdc shell "mkdir -p /data/ohc/bin /data/ohc/containers/claude /data/ohc/workspace /data/ohc/logs /data/ohc/run" | Out-Null
& $Hdc shell "mkdir -p /data/ohc/rootfs/claude/root/.config/opencode" | Out-Null
& $Hdc shell "mkdir -p /data/python/lib/python3.8/script/bin" | Out-Null
Write-Ok "/data/ohc 结构就绪"

# ------------------------------------------------------------------ 4. 运行时
Write-Step "推送容器运行时"
$binFiles = @("ohc", "ohc-claude", "ohc-setkey", "ohc-verify", "oc-setkey", "ohc-tty")
foreach ($f in $binFiles) {
    $src = Join-Path $RepoRoot "bin\$f"
    if (-not (Test-Path $src)) { Fail "缺文件: $src" }
    & $Hdc file send $src "/data/ohc/bin/$f" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "推送失败: $f" }
}
& $Hdc shell "chmod 755 /data/ohc/bin/*" | Out-Null
Write-Ok ("已推送 " + $binFiles.Count + " 个文件")

# ------------------------------------------------------------------ 5. env
Write-Step "写入容器环境变量"
$envSrc = Join-Path $RepoRoot "etc\claude.env"
$lines = (Get-Content $envSrc) | Where-Object { $_ -notmatch '^\s*$' }

if ($Key) {
    if ($Key -notmatch '^sk-') { Fail "DeepSeek Key 应该以 sk- 开头" }
    $lines = $lines | ForEach-Object {
        if ($_ -match '^ANTHROPIC_AUTH_TOKEN=') { "ANTHROPIC_AUTH_TOKEN=$Key" } else { $_ }
    }
    Write-Ok "使用新的 DeepSeek Key"
} else {
    # 没给 key 就沿用设备上已有的
    $old = (& $Hdc shell "grep '^ANTHROPIC_AUTH_TOKEN=' /data/ohc/containers/claude/env 2>/dev/null" 2>&1) -join ''
    if ($old -match 'sk-') {
        $lines = $lines | ForEach-Object {
            if ($_ -match '^ANTHROPIC_AUTH_TOKEN=') { $old.Trim() } else { $_ }
        }
        Write-Ok "沿用设备上已有的 DeepSeek Key"
    } else {
        Write-Warn2 "没有提供 -Key，设备上也没有旧 key，稍后请执行: /data/ohc/bin/ohc-setkey sk-xxx"
    }
}

# 必须是 LF，CRLF 会让 key 末尾多一个 \r，导致 401
$envTmp = Join-Path $TmpDir "env"
[System.IO.File]::WriteAllText($envTmp, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
& $Hdc file send $envTmp "/data/ohc/containers/claude/env" | Out-Null
& $Hdc shell "chmod 600 /data/ohc/containers/claude/env" | Out-Null
Write-Ok "/data/ohc/containers/claude/env (600)"

# ------------------------------------------------------------------ 6. 容器内配置
Write-Step "推送容器内配置"
& $Hdc file send (Join-Path $RepoRoot "etc\opencode.json") "/data/ohc/rootfs/claude/root/.config/opencode/opencode.json" | Out-Null
& $Hdc file send (Join-Path $RepoRoot "etc\claude.json")   "/data/ohc/rootfs/claude/root/.claude.json" | Out-Null
& $Hdc shell "chmod 644 /data/ohc/rootfs/claude/root/.claude.json /data/ohc/rootfs/claude/root/.config/opencode/opencode.json" | Out-Null
Write-Ok "opencode.json + .claude.json"

# ------------------------------------------------------------------ 7. OpenCode key
if ($OcKey) {
    Write-Step "写入 OpenCode Key"
    if ($OcKey -notmatch '^oc_sk_') { Fail "OpenCode Key 应该以 oc_sk_ 开头" }
    $authTmp = Join-Path $TmpDir "auth.json"
    $authJson = '{"opencode":{"type":"api","key":"' + $OcKey + '"}}'
    [System.IO.File]::WriteAllText($authTmp, $authJson, (New-Object System.Text.UTF8Encoding($false)))
    & $Hdc shell "mkdir -p /data/ohc/rootfs/claude/root/.local/share/opencode" | Out-Null
    & $Hdc file send $authTmp "/data/ohc/rootfs/claude/root/.local/share/opencode/auth.json" | Out-Null
    & $Hdc shell "chmod 600 /data/ohc/rootfs/claude/root/.local/share/opencode/auth.json" | Out-Null
    Write-Ok "auth.json (600)"
} else {
    Write-Warn2 "没有提供 -OcKey，opencode 需要设备上已有登录状态"
}

# ------------------------------------------------------------------ 8. PATH 入口
Write-Step "安装 PATH 入口"
$pathDir = "/data/python/lib/python3.8/script/bin"
foreach ($f in @("claude", "opencode")) {
    & $Hdc file send (Join-Path $RepoRoot "device-bin\$f") "$pathDir/$f" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "推送失败: $f" }
}
& $Hdc shell "chmod 755 $pathDir/claude $pathDir/opencode" | Out-Null
$inPath = (& $Hdc shell "echo `$PATH" 2>&1) -join ''
if ($inPath -match [regex]::Escape($pathDir)) {
    Write-Ok "$pathDir 已在设备 PATH 中"
} else {
    Write-Warn2 "$pathDir 不在设备 PATH 中，这个 ROM 的默认 PATH 变了"
    Write-Warn2 "临时用 /data/ohc/bin/ohc-claude 代替"
}

# ------------------------------------------------------------------ 9. 验证
if (-not $SkipVerify) {
    Write-Step "验证"
    $which = (& $Hdc shell "command -v claude" 2>&1) -join ' '
    if ($which -match 'claude') { Write-Ok "claude -> $($which.Trim())" } else { Write-Warn2 "claude 不在 PATH 中" }

    $ver = (& $Hdc shell "claude --version" 2>&1) -join ' '
    if ($ver -match 'Claude Code') { Write-Ok "版本: $($ver.Trim())" } else { Write-Warn2 "版本检查异常: $ver" }

    Write-Step "真实调用 DeepSeek（约 5 秒）"
    $out = (& $Hdc shell "claude -p 'Reply with exactly: DEPLOY_OK'" 2>&1) -join "`n"
    if ($out -match 'DEPLOY_OK') { Write-Ok "DeepSeek 调用正常" }
    else { Write-Warn2 "调用未见预期标记，输出如下："; Write-Host $out -ForegroundColor DarkGray }
}

Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " 部署完成" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host @"

用法：
  hdc shell
  claude                 # DeepSeek V4.1-Flash（你自己的 DeepSeek Key）
  opencode               # OpenCode Zen 免费 DeepSeek V4.1-Flash Free

其它：
  /data/ohc/bin/ohc doctor            # 环境自检
  /data/ohc/bin/ohc net               # 修复默认路由
  /data/ohc/bin/ohc-setkey sk-xxx     # 换 DeepSeek Key
  /data/ohc/bin/oc-setkey oc_sk-xxx   # 换 OpenCode Key
"@ -ForegroundColor Gray
