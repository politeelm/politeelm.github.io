<#
  新建条目.ps1 —— 读一个 txt，生成维基条目，自动推送

  txt 格式（和以前一样，前 3 行固定）：
    第 1 行：条目名（就是标题）
    第 2 行：一句话摘要
    第 3 行：分类，用逗号隔开（中英文逗号都行），如：奇异人士,devlog
    第 4 行起：正文

  正文支持的简易写法：
    ## 小标题        → <h2>
    > 引用的话       → <blockquote>
    - 列表项         → <ul><li>
    ![图注](图.png)  → 图片（图片和 txt 放同目录，会自动复制进仓库）
    [[另一个条目]]    → 双链，自动跳到那条

  用法：
    双击桌面「新建条目」→ 弹窗选 txt
    或：.\新建条目.ps1 -文件 "路径\xxx.txt"
    只生成不推送：加 -仅本地
#>

param(
  [string]$文件 = "",
  [switch]$仅本地,
  [switch]$不暂停
)

$ErrorActionPreference = "Continue"

try {
  chcp 65001 | Out-Null
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
$root = Split-Path $scriptDir -Parent
$codmDir = Join-Path $root "codm"
$dataPath = Join-Path $codmDir "assets\js\entries.js"
$indexPath = Join-Path $codmDir "index.html"
$imgDir = Join-Path $codmDir "assets\images"
$siteUrl = "https://politeelm.github.io/codm"

$nl = "`r`n"

function Pause-Exit([int]$code = 0) {
  if (-not $不暂停) { Read-Host "按回车关闭" | Out-Null }
  exit $code
}

function Escape-Html([string]$s) {
  if ($null -eq $s) { return "" }
  return $s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
}

function Escape-Template([string]$s) {
  if ($null -eq $s) { return "" }
  return $s.Replace('`', '\`').Replace('${', '\${')
}

function Escape-Js([string]$s) {
  if ($null -eq $s) { return '""' }
  $v = $s.Replace("\", "\\").Replace('"', '\"')
  $v = $v.Replace("`r", " ").Replace("`n", " ")
  return '"' + $v + '"'
}

function Read-TextSmart([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $utf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($utf8.IndexOf([char]0xFFFD) -ge 0) {
    try { return [System.Text.Encoding]::GetEncoding(936).GetString($bytes) } catch { return $utf8 }
  }
  return $utf8
}

$script:imageMap = @{}

function Resolve-Images($lines, [string]$sourceDir) {
  foreach ($raw in $lines) {
    $t = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { continue }

    $m = [regex]::Match($t, '^!\[(.*?)\]\((.+?)\)$')
    if (-not $m.Success) { continue }

    $src = $m.Groups[2].Value.Trim()
    if ($src -match '^(https?:)?//' -or $src -match '^data:') { continue }
    if ($script:imageMap.ContainsKey($src)) { continue }

    $candidate = if ([IO.Path]::IsPathRooted($src)) { $src } else { Join-Path $sourceDir $src }
    if (-not (Test-Path -LiteralPath $candidate)) {
      Write-Host "  ⚠ 找不到图片：$candidate" -ForegroundColor Yellow
      $script:imageMap[$src] = $src
      continue
    }

    if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }

    $name = ($name = [IO.Path]::GetFileName($candidate)) -replace '[^\w\.\-]', '_'
    $target = Join-Path $imgDir $name

    if ((Test-Path -LiteralPath $target) -and
        ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $candidate).Hash)) {
      $baseName = [IO.Path]::GetFileNameWithoutExtension($name)
      $ext = [IO.Path]::GetExtension($name)
      $name = $baseName + "-" + (Get-Date -Format "HHmmss") + $ext
      $target = Join-Path $imgDir $name
    }

    Copy-Item -LiteralPath $candidate -Destination $target -Force
    $script:imageMap[$src] = "assets/images/$name"

    $size = (Get-Item -LiteralPath $target).Length
    Write-Host ("  图片已复制：{0} → assets/images/{1}（{2:N0} KB）" -f $src, $name, ($size / 1KB)) -ForegroundColor DarkGray
    if ($size -gt 2MB) {
      Write-Host ("  ⚠ 这张图 {0} MB，建议压到 500KB 以内" -f [math]::Round($size / 1MB, 1)) -ForegroundColor Yellow
    }
  }
}

function Convert-BodyToHtml($lines) {
  $out = New-Object System.Text.StringBuilder
  $inList = $false

  foreach ($raw in $lines) {
    $line = $raw.TrimEnd()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $t = $line.Trim()

    if ($t.StartsWith("- ")) {
      if (-not $inList) { [void]$out.AppendLine("      <ul>"); $inList = $true }
      [void]$out.AppendLine("        <li>" + (Escape-Html $t.Substring(2).Trim()) + "</li>")
      continue
    }

    if ($inList) { [void]$out.AppendLine("      </ul>"); $inList = $false }

    $img = [regex]::Match($t, '^!\[(.*?)\]\((.+?)\)$')
    if ($img.Success) {
      $caption = $img.Groups[1].Value.Trim()
      $src = $img.Groups[2].Value.Trim()
      if ($script:imageMap.ContainsKey($src)) { $src = $script:imageMap[$src] }
      $srcAttr = Escape-Html $src
      $capAttr = Escape-Html $caption

      if ($caption) {
        [void]$out.AppendLine("      <figure><img src=`"$srcAttr`" alt=`"$capAttr`" loading=`"lazy`"><figcaption>$capAttr</figcaption></figure>")
      } else {
        [void]$out.AppendLine("      <img src=`"$srcAttr`" alt=`"`" loading=`"lazy`">")
      }
      continue
    }

    if ($t.StartsWith("## ")) {
      [void]$out.AppendLine("      <h2>" + (Escape-Html $t.Substring(3).Trim()) + "</h2>")
    } elseif ($t.StartsWith("> ")) {
      [void]$out.AppendLine("      <blockquote><p>" + (Escape-Html $t.Substring(2).Trim()) + "</p></blockquote>")
    } else {
      [void]$out.AppendLine("      <p>" + (Escape-Html $t) + "</p>")
    }
  }

  if ($inList) { [void]$out.AppendLine("      </ul>") }
  return $out.ToString().TrimEnd()
}

function Insert-AfterMarker([string]$path, [string]$marker, [string]$block) {
  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  if (-not $text.Contains($marker)) { throw "在 $path 里找不到插入标记：$marker" }
  $text = $text.Replace($marker, $marker + $nl + $block.TrimEnd() + $nl)
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Bump-Version([string]$path) {
  $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $found = [regex]::Matches($html, '\?v=(\d+)')
  if ($found.Count -eq 0) { return }
  $current = 0
  foreach ($m in $found) {
    $n = [int]$m.Groups[1].Value
    if ($n -gt $current) { $current = $n }
  }
  $next = $current + 1
  $html = [regex]::Replace($html, '\?v=\d+', ('?v=' + $next))
  [System.IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "缓存版本号：v$current → v$next" -ForegroundColor Cyan
}

function Step([string]$msg) { Write-Host $msg -ForegroundColor Cyan }

# ============================ 1. 选文件 ============================

if ([string]::IsNullOrWhiteSpace($文件)) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = "选择条目 txt"
  $dialog.Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*"
  $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "已取消。" -ForegroundColor Yellow
    Pause-Exit 0
  }
  $文件 = $dialog.FileName
}

if (-not (Test-Path -LiteralPath $文件)) {
  Write-Host "找不到文件：$文件" -ForegroundColor Red
  Pause-Exit 1
}

if ((Get-Item -LiteralPath $文件).PSIsContainer) {
  $folder = (Get-Item -LiteralPath $文件).FullName
  $txts = @(Get-ChildItem -LiteralPath $folder -Filter *.txt -File -ErrorAction SilentlyContinue)
  if ($txts.Count -eq 0) {
    Write-Host "这个文件夹里没有 .txt 文件。" -ForegroundColor Red
    Pause-Exit 1
  }
  $sameName = $txts | Where-Object { $_.BaseName -eq (Split-Path $folder -Leaf) } | Select-Object -First 1
  $文件 = if ($sameName) { $sameName.FullName } else { $txts[0].FullName }
  Write-Host "检测到文件夹，使用：$文件" -ForegroundColor Green
}

# ============================ 2. 解析 ============================

Step "读取：$文件"

try {
  $raw = Read-TextSmart $文件
} catch {
  Write-Host "读不了这个文件：$文件（可能被占用，或选错了文件夹）" -ForegroundColor Red
  Pause-Exit 1
}

$raw = $raw.TrimStart([char]0xFEFF)
$lines = $raw -split "\r?\n"

if ($lines.Count -lt 3) {
  Write-Host "格式不对：至少需要 3 行（条目名 / 摘要 / 分类）" -ForegroundColor Red
  Pause-Exit 1
}

$title = $lines[0].Trim()
$summary = $lines[1].Trim()
$tagsLine = $lines[2].Trim()
$restLines = if ($lines.Count -gt 3) { $lines[3..($lines.Count - 1)] } else { @() }

# 单独一行 --- 分隔：上面「简单回顾」（可多行），下面「长篇大论」
$splitAt = -1
for ($i = 0; $i -lt $restLines.Count; $i++) {
  if ($restLines[$i].Trim() -eq "---") { $splitAt = $i; break }
}
if ($splitAt -ge 0) {
  $recapLines = if ($splitAt -gt 0) { $restLines[0..($splitAt - 1)] } else { @() }
  $bodyLines = if ($splitAt + 1 -le $restLines.Count - 1) { $restLines[($splitAt + 1)..($restLines.Count - 1)] } else { @() }
} else {
  $recapLines = @()
  $bodyLines = $restLines
}

if ([string]::IsNullOrWhiteSpace($title)) {
  Write-Host "第 1 行（条目名）是空的。" -ForegroundColor Red
  Pause-Exit 1
}

if ([string]::IsNullOrWhiteSpace($summary)) {
  Write-Host "第 2 行（神人事迹）是必填的。" -ForegroundColor Red
  Pause-Exit 1
}

$recapSb = New-Object System.Text.StringBuilder
foreach ($rl in $recapLines) {
  if ([string]::IsNullOrWhiteSpace($rl)) { continue }
  [void]$recapSb.AppendLine("      <p>" + (Escape-Html $rl.Trim()) + "</p>")
}
$recapHtml = $recapSb.ToString().TrimEnd()
if ([string]::IsNullOrWhiteSpace($recapHtml)) {
  Write-Host "  （没有简单回顾，条目页会显示“暂时没有”）" -ForegroundColor DarkGray
  $recapHtml = ""
}

$sourceDir = (Get-Item -LiteralPath $文件).DirectoryName
Resolve-Images $bodyLines $sourceDir
$bodyHtml = Convert-BodyToHtml $bodyLines

if ([string]::IsNullOrWhiteSpace($bodyHtml)) {
  Write-Host "  （没有长篇大论，条目页会显示“暂时没有”）" -ForegroundColor DarkGray
  $bodyHtml = ""
}

$tags = @()
if (-not [string]::IsNullOrWhiteSpace($tagsLine)) {
  $tags = @($tagsLine -split "[,，]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# ============================ 3. 生成信息 ============================

$date = (Get-Item -LiteralPath $文件).LastWriteTime.ToString("yyyy-MM-dd")

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($文件)
if ($baseName -match '^[A-Za-z0-9\-_]+$') {
  $slug = $baseName.ToLower()
} else {
  $slug = "e-" + (Get-Date -Format "yyyyMMdd-HHmmss")
  Write-Host "提示：文件名不是纯英文，条目地址用 $slug" -ForegroundColor Yellow
}

foreach ($p in @($dataPath, $indexPath)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Host "仓库文件缺失：$p" -ForegroundColor Red
    Pause-Exit 1
  }
}

$existing = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)
if ($existing.Contains('slug: "' + $slug + '"')) {
  Write-Host "已经有 slug 为「$slug」的条目了，换个文件名。" -ForegroundColor Red
  Pause-Exit 1
}

$tagsJs = "[" + (($tags | ForEach-Object { Escape-Js $_ }) -join ", ") + "]"

# ============================ 4. 写入 entries.js ============================

$block = @"
  {
    slug: "$slug",
    title: $(Escape-Js $title),
    tags: $tagsJs,
    date: "$date",
    desc: $(Escape-Js $summary),
    recap: ``
$(Escape-Template $recapHtml)
    ``,
    content: ``
$(Escape-Template $bodyHtml)
    ``
  },
"@

try {
  Insert-AfterMarker $dataPath "/* ENTRIES:START */" $block
} catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  Pause-Exit 1
}
Step "条目已写入 entries.js"

Bump-Version $indexPath

# ============================ 5. 提交并推送 ============================

Write-Host ""
Write-Host "条目：$title"
Write-Host "分类：$($tags -join ' / ')"
Write-Host "地址：$siteUrl/#/e/$slug"
Write-Host ""

if (-not (Test-Path (Join-Path $root ".git"))) {
  Write-Host "（不是 git 仓库，只生成没推送）" -ForegroundColor Yellow
  Pause-Exit 0
}

if ($仅本地) {
  Write-Host "（-仅本地，没提交）" -ForegroundColor Yellow
  Pause-Exit 0
}

Set-Location $root
git add -A 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "git add 失败" -ForegroundColor Red; Pause-Exit 1 }

$message = "新增条目：$title"
git commit -q -m $message 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "git commit 失败" -ForegroundColor Red; Pause-Exit 1 }
Step "已提交：$message"

$ok = $false
for ($i = 1; $i -le 4; $i++) {
  git push -u origin HEAD 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { $ok = $true; Step "推送成功（第 $i 次）"; break }
  Write-Host "第 $i 次推送失败，5 秒后重试…" -ForegroundColor Yellow
  Start-Sleep -Seconds 5
}

if (-not $ok) {
  Write-Host "推送失败，改动已提交在本地，网络好了执行 git push 即可。" -ForegroundColor Red
  Pause-Exit 1
}

Write-Host ""
Write-Host "大约 1 分钟后生效：$siteUrl/#/e/$slug" -ForegroundColor Green
Pause-Exit 0
