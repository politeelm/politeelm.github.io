<#
  发布.ps1 —— 一键上线：自动把缓存版本号 +1，提交并推送

  用法（在 D:\网站 里打开 PowerShell）：
    .\发布.ps1                      # 提交信息自动用时间
    .\发布.ps1 -消息 "新增：某天遇到的奇人"

  它做的事：
    1. 把 index.html 里所有 ?v=N 的数字 +1（这样访客不会看到旧缓存）
    2. git add -A && git commit
    3. git push（网络抖动会自动重试）

  只想本地看看、不想推送：.\发布.ps1 -NoPush
#>

param(
  [string]$消息 = "",
  [switch]$NoPush,
  [switch]$不暂停
)

# git 会把 warning 写到 stderr，Stop 模式下会被当成致命错误，所以这里用 Continue 手动判断
$ErrorActionPreference = "Continue"

try {
  chcp 65001 | Out-Null
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

function Pause-Exit([int]$code = 0) {
  if (-not $不暂停) { Read-Host "按回车关闭" | Out-Null }
  exit $code
}

$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
Set-Location $root

if (-not (Test-Path (Join-Path $root ".git"))) {
  Write-Host "这里不是 git 仓库：$root" -ForegroundColor Red
  Pause-Exit 1
}

# ---------- 1. 版本号 +1 ----------

# 维基页面带 ?v= 缓存版本号
$indexFiles = @()
$wikiIndex = Join-Path $root "wiki\index.html"
if (Test-Path $wikiIndex) { $indexFiles += $wikiIndex }

$current = 0
foreach ($f in $indexFiles) {
  $html = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($html, '\?v=(\d+)')) {
    $n = [int]$m.Groups[1].Value
    if ($n -gt $current) { $current = $n }
  }
}

if ($current -eq 0) {
  Write-Host "警告：页面里没找到 ?v= 版本号，跳过" -ForegroundColor Yellow
} else {
  $next = $current + 1
  foreach ($f in $indexFiles) {
    $html = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    $html = [regex]::Replace($html, '\?v=\d+', ('?v=' + $next))
    [System.IO.File]::WriteAllText($f, $html, (New-Object System.Text.UTF8Encoding($false)))
  }
  Write-Host "缓存版本号：v$current → v$next（$($indexFiles.Count) 个页面）" -ForegroundColor Cyan
}

# ---------- 2. 提交 ----------

git add -A 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "git add 失败，停在这里。" -ForegroundColor Red
  Pause-Exit 1
}

$staged = git status --porcelain 2>$null
if ([string]::IsNullOrWhiteSpace($staged)) {
  Write-Host "没有需要提交的改动。" -ForegroundColor Yellow
  Pause-Exit 0
}

if ([string]::IsNullOrWhiteSpace($消息) -and -not $不暂停) {
  try {
    Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null
    $answer = [Microsoft.VisualBasic.Interaction]::InputBox(
      "这次改了什么？（可以直接回车，用时间当说明）",
      "推送到 GitHub",
      "")
    if ($null -ne $answer) { $消息 = $answer.Trim() }
  } catch { }
}

if ([string]::IsNullOrWhiteSpace($消息)) {
  $消息 = "更新 " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

git commit -q -m $消息 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "git commit 失败，停在这里。" -ForegroundColor Red
  Pause-Exit 1
}
Write-Host "已提交：$消息" -ForegroundColor Green

if ($NoPush) {
  Write-Host "（-NoPush，没有推送）" -ForegroundColor Yellow
  Pause-Exit 0
}

# ---------- 3. 推送（失败自动重试） ----------

$ok = $false
for ($i = 1; $i -le 4; $i++) {
  $out = git push -u origin HEAD 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    $ok = $true
    Write-Host "推送成功（第 $i 次尝试）" -ForegroundColor Green
    break
  }
  Write-Host "第 $i 次推送失败（多半是网络），5 秒后重试…" -ForegroundColor Yellow
  Start-Sleep -Seconds 5
}

if (-not $ok) {
  Write-Host ""
  Write-Host "推送一直失败。改动已经提交在本地，网络好了再执行一次 git push 就行。" -ForegroundColor Red
  Pause-Exit 1
}

Write-Host ""
Write-Host "大约 1 分钟后生效：https://politeelm.github.io/wiki/" -ForegroundColor Cyan
Write-Host "如果看到的还是旧内容，按 Ctrl + F5 强刷一次。" -ForegroundColor Cyan
