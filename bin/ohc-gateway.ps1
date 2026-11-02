#Requires -Version 5.1
<#
.SYNOPSIS
    在手机上起一个 OpenAI 兼容网关，让宿主机 VS Code 的对话插件用上 DeepSeek

.DESCRIPTION
    适用场景：**PC 不能上网**，但 USB 连着手机、手机能上网。
    手机（容器内）跑一个小网关去连 api.deepseek.com，再用 hdc fport
    把端口映射到 PC 的 127.0.0.1，VS Code 里填这个地址就能对话。

    通道：
      VS Code ──http──▶ 127.0.0.1:18080 ──hdc fport(USB)──▶ 容器内 ohc-gw ──https──▶ api.deepseek.com

.PARAMETER Start
    启动网关并建立端口映射（默认动作）

.PARAMETER Stop
    停掉网关、拆除端口映射

.PARAMETER Status
    只看状态

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\ohc-gateway.ps1
    powershell -ExecutionPolicy Bypass -File .\ohc-gateway.ps1 -Stop
#>
[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Status,
    [string]$Hdc = "",
    [int]$Port = 18080
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
# Invoke-WebRequest 的进度条会往控制台乱写，把输出搅成乱码，关掉
$ProgressPreference = 'SilentlyContinue'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host "`n[失败] $m" -ForegroundColor Red; exit 1 }

$RepoRoot = Split-Path $PSScriptRoot -Parent
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot }

# ------------------------------------------------------------------ 0. hdc
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
if (-not $Hdc -or -not (Test-Path $Hdc)) { Fail "找不到 hdc.exe，用 -Hdc 指定" }

$taskStr = "tcp:$Port tcp:$Port"

function Get-GwPid {
    $o = (& $Hdc shell "ps -ef 2>/dev/null | grep ohc-gw.mjs | grep -v grep" 2>&1) -join ' '
    if ($o -match '(\d+)\s') { return $Matches[1] }
    return ""
}

# 只在映射确实存在时才 rm，否则 hdc 会吐一句
# "Remove forward ruler failed, ruler is not exist"，看着像出错，其实是无事可做
#
# ★ 坑：hdc fport 的 rm 和 add 一样，两个节点必须是**两个独立参数**。
#   写成 "tcp:18080 tcp:18080" 一个字符串，它会回
#   "ruler is not exist"，但**不会真的删掉**，而返回值仍是 0 —— 静默失败。
#   删不掉的后果是下一次 add 报 "TCP Port listen failed at 18080"，
#   你以为映射是新建的，其实是上一次残留的那个在干活。
function Remove-Forward {
    $ls = (& $Hdc fport ls 2>&1) -join "`n"
    if ($ls -match [regex]::Escape("tcp:$Port")) {
        $o = (& $Hdc fport rm "tcp:$Port" "tcp:$Port" 2>&1) -join ' '
        return ($o -match 'success')
    }
    return $false
}

# ------------------------------------------------------------------ 1. Stop
if ($Stop) {
    Write-Step "停掉网关"
    $gwPid = Get-GwPid
    if ($gwPid) { & $Hdc shell "kill $gwPid 2>/dev/null" | Out-Null; Write-Ok "已结束进程 $gwPid" }
    else { Write-Ok "网关没在跑" }
    if (Remove-Forward) { Write-Ok "已拆除端口映射 tcp:$Port" }
    else { Write-Ok "端口映射本来就没有" }
    return
}

# ------------------------------------------------------------------ 2. Status
if ($Status) {
    $gwPid = Get-GwPid
    if ($gwPid) { Write-Ok "网关进程: $gwPid" } else { Write-Warn2 "网关没在跑" }
    $ls = (& $Hdc fport ls 2>&1) -join "`n"
    if ($ls -match [regex]::Escape($Port)) { Write-Ok "端口映射在: $taskStr" } else { Write-Warn2 "端口映射不在" }
    return
}

# ------------------------------------------------------------------ 3. Start
Write-Step "检查设备"
$t = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' -and $_ -notmatch 'Unauthorized' }
if (-not $t) { Fail "没有检测到设备" }
Write-Ok ("设备: " + ($t -join ', '))

Write-Step "下发网关到容器"
$gwSrc = Join-Path $RepoRoot "etc\ohc-gw.mjs"
if (-not (Test-Path $gwSrc)) { Fail "找不到 etc\ohc-gw.mjs" }
$out = (& $Hdc file send $gwSrc "/data/ohc/rootfs/claude/usr/local/bin/" 2>&1) -join "`n"
if ($out -notmatch 'finish') { Fail "推送失败: $out" }
& $Hdc shell "chmod 644 /data/ohc/rootfs/claude/usr/local/bin/ohc-gw.mjs" | Out-Null
Write-Ok "已下发 ohc-gw.mjs"

$oldPid = Get-GwPid
if ($oldPid) {
    & $Hdc shell "kill $oldPid 2>/dev/null" | Out-Null
    Start-Sleep -Milliseconds 500
}

Write-Step "在容器里启动网关"
# nohup + 后台：hdc shell 命令返回后进程要能活下来
$cmd = "/data/ohc/bin/ohc run claude -- /bin/sh -c 'cd /work && nohup node /usr/local/bin/ohc-gw.mjs >> /work/ohc-gw.log 2>&1 & echo started'"
$r = (& $Hdc shell $cmd 2>&1) -join "`n"
Start-Sleep -Seconds 2

$gwPid = Get-GwPid
if (-not $gwPid) {
    Write-Warn2 "网关没起来，日志如下："
    & $Hdc shell "tail -20 /data/ohc/workspace/ohc-gw.log 2>/dev/null"
    Fail "启动失败"
}
Write-Ok "网关进程 $gwPid"

Write-Step "建立端口映射（USB 转发）"
# 注意：fport 的两个节点必须是**两个独立参数**，
# 拼成 "tcp:18080 tcp:18080" 一个字符串传进去会报 Incorrect forward command
$removed = Remove-Forward
if ($removed) { Write-Ok "清掉了旧映射" }
$fp = (& $Hdc fport "tcp:$Port" "tcp:$Port" 2>&1) -join ' '
Write-Host "    $fp" -ForegroundColor DarkGray
Start-Sleep -Milliseconds 500
$ls = (& $Hdc fport ls 2>&1) -join "`n"
if ($ls -notmatch [regex]::Escape($Port)) { Fail "fport 没建立成功：$fp" }
Write-Ok "127.0.0.1:$Port -> 设备 $Port"

Write-Step "验证通道"
$base = "http://127.0.0.1:$Port"
try {
    $h = Invoke-WebRequest -Uri "$base/healthz" -UseBasicParsing -TimeoutSec 8
    Write-Ok ("healthz: " + $h.Content.Trim())
} catch {
    Fail ("healthz 失败：" + $_.Exception.Message)
}

try {
    # 注意两点：
    #   1) 必须把 JSON 转成 UTF-8 字节再发。PowerShell 5.1 直接把字符串丢给
    #      -Body 时按 ASCII 编码，中文会变成 '?'，模型就看不懂你说什么了。
    #   2) max_tokens 不能给小。deepseek-flash 是推理模型，思考也占额度，
    #      给 16 的结果是 content 空字符串（看着像"模型不回话"）。
    $payload = @{
        model      = 'deepseek-flash'
        messages   = @(@{ role = 'user'; content = '只回复两个字：收到' })
        max_tokens = 800
    } | ConvertTo-Json -Depth 6
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $r2 = Invoke-RestMethod -Uri "$base/v1/chat/completions" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 120
    $txt = "$($r2.choices[0].message.content)".Trim()
    if ($txt) { Write-Ok ("真实对话: " + $txt) }
    else { Write-Warn2 "对话通了，但 content 为空（推理模型把额度都花在思考上了）" }
} catch {
    Write-Warn2 ("对话测试失败：" + $_.Exception.Message)
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " 网关已就绪" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host @"

VS Code 里装 Continue（或 Cline / Roo Code），配置：

  Provider : OpenAI（或 "OpenAI Compatible"）
  Base URL : $base/v1
  API Key  : sk-any-nonempty        # 网关会替换成真 Key，随便填个非空值
  Model    : deepseek-flash         # 或 deepseek-v4-pro

Continue 的 config.json 片段：

  "models": [{
    "title": "DeepSeek (via phone)",
    "provider": "openai",
    "model": "deepseek-flash",
    "apiBase": "$base/v1",
    "apiKey": "sk-any-nonempty",
    "completionOptions": { "maxTokens": 4096 }
  }]

注意：maxTokens 别设太小。deepseek-flash 是推理模型，思考过程也占额度，
设成 64/128 会出现「有回复但内容是空的」。

停掉：  .\ohc-gateway.ps1 -Stop
看状态：.\ohc-gateway.ps1 -Status
"@ -ForegroundColor Gray
