<#
  删除条目.ps1 —— 输入条目名（可以只输一部分），删除并推送

  用法：
    双击桌面「删除条目」→ 输入名字 → 确认 → 自动删除并推送
    或：.\删除条目.ps1 -标题 "某人"
    只删本地不推送：-仅本地
#>

param(
  [string]$标题 = "",
  [switch]$仅本地,
  [switch]$不暂停,
  [switch]$跳过确认
)

$ErrorActionPreference = "Continue"

try {
  chcp 65001 | Out-Null
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
$root = Split-Path $scriptDir -Parent
$wikiDir = Join-Path $root "wiki"

function Pause-Exit([int]$code = 0) {
  if (-not $不暂停) { Read-Host "按回车关闭" | Out-Null }
  exit $code
}

function Show-Msg([string]$text, [string]$title = "删除条目") {
  if ($不暂停) { Write-Host $text; return }
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    [System.Windows.Forms.MessageBox]::Show($text, $title) | Out-Null
  } catch {
    Write-Host $text
  }
}

function Ask-Text([string]$prompt, [string]$title = "删除条目") {
  try {
    Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null
    return [Microsoft.VisualBasic.Interaction]::InputBox($prompt, $title, "")
  } catch {
    return (Read-Host $prompt)
  }
}

function Step([string]$msg) { Write-Host $msg -ForegroundColor Cyan }

$dataPath = Join-Path $wikiDir "assets\js\entries.js"
$indexPath = Join-Path $wikiDir "index.html"

foreach ($p in @($dataPath, $indexPath)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Show-Msg "仓库文件缺失：$p"
    Pause-Exit 1
  }
}

# ============================ 1. 要删哪条 ============================

if ([string]::IsNullOrWhiteSpace($标题)) {
  $标题 = Ask-Text "输入条目名，可以只输其中几个字："
  if ([string]::IsNullOrWhiteSpace($标题)) {
    Write-Host "已取消。" -ForegroundColor Yellow
    Pause-Exit 0
  }
}
$标题 = $标题.Trim()

# ============================ 2. 解析 ============================

$text = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)

$startMarker = "/* ENTRIES:START */"
$endMarker = "/* ENTRIES:END */"
$startIdx = $text.IndexOf($startMarker)
$endIdx = $text.IndexOf($endMarker)

if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) {
  Show-Msg "entries.js 里找不到 ENTRIES:START / ENTRIES:END 标记。"
  Pause-Exit 1
}

$prefix = $text.Substring(0, $startIdx + $startMarker.Length)
$region = $text.Substring($startIdx + $startMarker.Length, $endIdx - ($startIdx + $startMarker.Length))
$suffix = $text.Substring($endIdx)

$entryMatches = [regex]::Matches($region, '(?ms)^  \{\r?\n.*?^  \},')

if ($entryMatches.Count -eq 0) {
  Show-Msg "现在一条条目都没有。"
  Pause-Exit 0
}

$items = @()
foreach ($m in $entryMatches) {
  $blk = $m.Value
  $slugM = [regex]::Match($blk, 'slug:\s*"([^"]*)"')
  $titleM = [regex]::Match($blk, 'title:\s*"((?:[^"\\]|\\.)*)"')
  $rawTitle = if ($titleM.Success) { $titleM.Groups[1].Value } else { "(无标题)" }
  $rawTitle = $rawTitle.Replace('\"', '"').Replace('\\', '\')
  $items += [pscustomobject]@{
    Block = $blk
    Slug  = if ($slugM.Success) { $slugM.Groups[1].Value } else { "" }
    Title = $rawTitle
  }
}

# ============================ 3. 匹配 ============================

$hits = @($items | Where-Object { $_.Title.IndexOf($标题, [StringComparison]::OrdinalIgnoreCase) -ge 0 })

if ($hits.Count -eq 0) {
  $list = ($items | ForEach-Object { "· " + $_.Title }) -join "`n"
  Show-Msg "没有找到名字包含「$标题」的条目。`n`n现有条目：`n$list"
  Pause-Exit 0
}

if ($hits.Count -gt 1) {
  $list = ($hits | ForEach-Object { "· " + $_.Title }) -join "`n"
  $answer = Ask-Text "匹配到 $($hits.Count) 条，输入序号（从 1 开始）：`n`n$list"
  $n = 0
  if (-not [int]::TryParse($answer, [ref]$n) -or $n -lt 1 -or $n -gt $hits.Count) {
    Show-Msg "序号不对，已取消。"
    Pause-Exit 0
  }
  $hits = @($hits[$n - 1])
}

$target = $hits[0]

if (-not $跳过确认) {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $confirm = [System.Windows.Forms.MessageBox]::Show(
      "确定删除这条吗？`n`n$($target.Title)`n`n（删除后会立即推送）",
      "删除条目",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
      Show-Msg "已取消，什么都没删。"
      Pause-Exit 0
    }
  } catch { }
}

# ============================ 4. 删除 ============================

$newRegion = $region.Replace($target.Block, "")
$newRegion = [regex]::Replace($newRegion, "(\r?\n){3,}", "`r`n`r`n")
if ($newRegion -notmatch '\S') { $newRegion = "`r`n  " }

[System.IO.File]::WriteAllText($dataPath, $prefix + $newRegion + $suffix, (New-Object System.Text.UTF8Encoding($false)))
Step "已删除：$($target.Title)"

# 版本号 +1
$html = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
$found = [regex]::Matches($html, '\?v=(\d+)')
if ($found.Count -gt 0) {
  $current = 0
  foreach ($m in $found) {
    $n2 = [int]$m.Groups[1].Value
    if ($n2 -gt $current) { $current = $n2 }
  }
  $next = $current + 1
  $html = [regex]::Replace($html, '\?v=\d+', ('?v=' + $next))
  [System.IO.File]::WriteAllText($indexPath, $html, (New-Object System.Text.UTF8Encoding($false)))
  Step "缓存版本号：v$current → v$next"
}

$剩余 = @($items | Where-Object { $_.Slug -ne $target.Slug }).Count
Write-Host ""
Write-Host "剩余条目：$剩余 条"

if (-not (Test-Path (Join-Path $root ".git"))) {
  Show-Msg "不是 git 仓库，只删了本地文件。"
  Pause-Exit 0
}

if ($仅本地) {
  Show-Msg "已删除（-仅本地，没提交）。"
  Pause-Exit 0
}

Set-Location $root
git add -A 2>$null
if ($LASTEXITCODE -ne 0) { Show-Msg "git add 失败"; Pause-Exit 1 }

$message = "删除条目：$($target.Title)"
git commit -q -m $message 2>$null
if ($LASTEXITCODE -ne 0) { Show-Msg "git commit 失败"; Pause-Exit 1 }
Step "已提交：$message"

$ok = $false
for ($i = 1; $i -le 4; $i++) {
  git push -u origin HEAD 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { $ok = $true; Step "推送成功（第 $i 次）"; break }
  Write-Host "第 $i 次推送失败，5 秒后重试…" -ForegroundColor Yellow
  Start-Sleep -Seconds 5
}

if (-not $ok) {
  Show-Msg "推送失败，删除已提交在本地，网络好了执行 git push。"
  Pause-Exit 1
}

Show-Msg "已删除并推送：`n`n$($target.Title)`n`n还剩 $剩余 条。大约 1 分钟后生效。"
Pause-Exit 0
