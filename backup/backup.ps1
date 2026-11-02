#Requires -Version 5.1
<#
.SYNOPSIS
    把设备上现成的容器 + claude 环境打包备份到 PC

.DESCRIPTION
    在设备上生成 tar.gz，拉回 PC 保存，并生成 SHA256SUMS.txt。
    之后刷机清空 /data，用 restore.ps1 一条命令即可还原（无需联网安装）。

.PARAMETER Hdc
    hdc.exe 路径，默认自动查找。

.PARAMETER OutDir
    备份输出目录，默认为脚本所在目录。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\backup.ps1
#>
[CmdletBinding()]
param(
    [string]$Hdc = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = 'Stop'

# 让控制台按 UTF-8 输出，避免中文乱码
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Write-Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m)       { Write-Host ""; Write-Host "[失败] $m" -ForegroundColor Red; exit 1 }

if (-not $OutDir) { $OutDir = $PSScriptRoot }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# hdc
Write-Step "检查 hdc"
if (-not $Hdc) {
    foreach ($c in @("C:\Tools\HarmonyOS\toolchains\hdc.exe")) {
        if (Test-Path $c) { $Hdc = $c; break }
    }
    if (-not $Hdc) {
        $cmd = Get-Command hdc -ErrorAction SilentlyContinue
        if ($cmd) { $Hdc = $cmd.Source }
    }
}
if (-not $Hdc -or -not (Test-Path $Hdc)) { Fail "找不到 hdc.exe，请用 -Hdc 指定" }
Write-Ok $Hdc

Write-Step "检查设备"
$t = (& $Hdc list targets 2>&1) | Where-Object { $_ -and $_ -notmatch '\[Empty\]' }
if (-not $t) { Fail "没有检测到设备" }
Write-Ok ("设备: " + ($t -join ', '))

Write-Step "在设备上打包（约 550MB，1~3 分钟）"
$script = @'
#!/bin/sh
set -e
OUT=/data/local/tmp/ohc-backup.tar.gz
R=/data/ohc/rootfs/claude
rm -f "$OUT"
rm -rf "$R/var/cache/apk"/* 2>/dev/null
# socket 不能进 tar（tar 会报 unknown file type '140000'）。除了 rootfs，
# /work/.tmux 下也有 tmux 的 socket，所以整个 /data/ohc 都扫一遍。
busybox find /data/ohc /data/python -type s 2>/dev/null | while read -r f; do rm -f "$f"; done
cd /data
tar -czf "$OUT" ohc python
tar -tzf "$OUT" > /data/local/tmp/tl.txt
echo "ENTRIES=$(wc -l < /data/local/tmp/tl.txt)"
rm -f /data/local/tmp/tl.txt
ls -lh "$OUT"
'@
$tmp = Join-Path $env:TEMP "ohc-backup-gen.sh"
Set-Content -Path $tmp -Value ($script -replace "`r`n","`n") -Encoding ASCII -NoNewline
& $Hdc file send $tmp /data/local/tmp/ohc-backup-gen.sh | Out-Null
& $Hdc shell "chmod 755 /data/local/tmp/ohc-backup-gen.sh"
& $Hdc shell "/data/local/tmp/ohc-backup-gen.sh"
if ($LASTEXITCODE -ne 0) { Fail "设备端打包失败" }

Write-Step "拉回 PC"
$dest = Join-Path $OutDir "ohc-backup.tar.gz"
& $Hdc file recv /data/local/tmp/ohc-backup.tar.gz $dest
if ($LASTEXITCODE -ne 0) { Fail "拉取失败" }
$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
Write-Ok "$dest  ($sizeMB MB)"

Write-Step "生成 SHA256"
$hash = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToUpper()
Set-Content -Path (Join-Path $OutDir "SHA256SUMS.txt") -Value "$hash  ohc-backup.tar.gz" -Encoding ASCII
Write-Ok $hash

Write-Step "清理设备上的临时文件"
& $Hdc shell "rm -f /data/local/tmp/ohc-backup.tar.gz /data/local/tmp/ohc-backup-gen.sh"
Write-Ok "已清理"

Write-Host "`n备份完成。恢复时运行: .\restore.ps1`n" -ForegroundColor Green
