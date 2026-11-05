<#
  codm收集录管理端.ps1 —— 可视化：新建条目 / 删除条目 / 推送

  一个窗口搞定三件事，不用记命令。
  桌面快捷方式「codm管理端」指向这个脚本。
#>

param(
  [switch]$自检
)

$ErrorActionPreference = "Continue"

try {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Drawing | Out-Null
} catch {
  Write-Host "加载图形界面组件失败：$($_.Exception.Message)" -ForegroundColor Red
  Read-Host "按回车关闭"
  exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
$root = Split-Path $scriptDir -Parent
$codmDir = Join-Path $root "codm"
$dataPath = Join-Path $codmDir "assets\js\entries.js"
$indexPath = Join-Path $codmDir "index.html"
$imgDir = Join-Path $codmDir "assets\images"
$siteUrl = "https://politeelm.github.io/codm"

# ============================ 核心逻辑 ============================

function Log([string]$msg, [string]$color = "DarkGray") {
  $script:logBox.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "] " + $msg + "`r`n")
  $script:logBox.SelectionStart = $script:logBox.TextLength
  $script:logBox.ScrollToCaret()
  [System.Windows.Forms.Application]::DoEvents()
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

function Parse-Entries {
  $text = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)
  $start = $text.IndexOf("/* ENTRIES:START */")
  $end = $text.IndexOf("/* ENTRIES:END */")
  if ($start -lt 0 -or $end -le $start) { return @() }

  $region = $text.Substring($start, $end - $start)
  $out = @()
  foreach ($m in [regex]::Matches($region, '(?ms)^  \{\r?\n.*?^  \},')) {
    $slugM = [regex]::Match($m.Value, 'slug:\s*"([^"]*)"')
    $titleM = [regex]::Match($m.Value, 'title:\s*"((?:[^"\\]|\\.)*)"')
    $rawTitle = if ($titleM.Success) { $titleM.Groups[1].Value } else { "(无标题)" }
    $out += [pscustomobject]@{
      Slug  = if ($slugM.Success) { $slugM.Groups[1].Value } else { "" }
      Title = $rawTitle.Replace('\"', '"').Replace('\\', '\')
      Block = $m.Value
    }
  }
  return $out
}

function Convert-BodyToHtml($lines, [string]$sourceDir) {
  $out = New-Object System.Text.StringBuilder
  $inList = $false
  $map = @{}

  # 先处理图片：复制进仓库
  foreach ($raw in $lines) {
    $t = $raw.Trim()
    $m = [regex]::Match($t, '^!\[(.*?)\]\((.+?)\)$')
    if (-not $m.Success) { continue }

    $src = $m.Groups[2].Value.Trim()
    if ($src -match '^(https?:)?//' -or $src -match '^data:') { continue }
    if ($map.ContainsKey($src)) { continue }

    $candidate = if ([IO.Path]::IsPathRooted($src)) { $src } else { Join-Path $sourceDir $src }
    if (-not (Test-Path -LiteralPath $candidate)) {
      Log "  找不到图片：$candidate"
      $map[$src] = $src
      continue
    }

    if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
    $name = ([IO.Path]::GetFileName($candidate)) -replace '[^\w\.\-]', '_'
    $target = Join-Path $imgDir $name
    if ((Test-Path -LiteralPath $target) -and
        ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $candidate).Hash)) {
      $base = [IO.Path]::GetFileNameWithoutExtension($name)
      $ext = [IO.Path]::GetExtension($name)
      $name = $base + "-" + (Get-Date -Format "HHmmss") + $ext
      $target = Join-Path $imgDir $name
    }
    Copy-Item -LiteralPath $candidate -Destination $target -Force
    $map[$src] = "assets/images/$name"
    Log "  复制图片：$name"
  }

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
      $cap = $img.Groups[1].Value.Trim()
      $src = $img.Groups[2].Value.Trim()
      if ($map.ContainsKey($src)) { $src = $map[$src] }
      if ($cap) {
        [void]$out.AppendLine("      <figure><img src=`"$(Escape-Html $src)`" alt=`"$(Escape-Html $cap)`" loading=`"lazy`"><figcaption>$(Escape-Html $cap)</figcaption></figure>")
      } else {
        [void]$out.AppendLine("      <img src=`"$(Escape-Html $src)`" alt=`"`" loading=`"lazy`">")
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

function Bump-Version {
  $html = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
  $found = [regex]::Matches($html, '\?v=(\d+)')
  if ($found.Count -eq 0) { return }
  $cur = 0
  foreach ($m in $found) { if ([int]$m.Groups[1].Value -gt $cur) { $cur = [int]$m.Groups[1].Value } }
  $next = $cur + 1
  $html = [regex]::Replace($html, '\?v=\d+', ('?v=' + $next))
  [System.IO.File]::WriteAllText($indexPath, $html, (New-Object System.Text.UTF8Encoding($false)))
  Log "缓存版本号 v$cur → v$next"
}

function Publish-Changes([string]$message) {
  if (-not (Test-Path (Join-Path $root ".git"))) { Log "不是 git 仓库，跳过推送" "DarkOrange"; return $false }

  Push-Location $root
  try {
    git add -A 2>$null
    if ($LASTEXITCODE -ne 0) { Log "git add 失败" "Red"; return $false }

    $staged = git status --porcelain 2>$null
    if ([string]::IsNullOrWhiteSpace($staged)) { Log "没有需要提交的改动" "DarkOrange"; return $true }

    git commit -q -m $message 2>$null
    if ($LASTEXITCODE -ne 0) { Log "git commit 失败" "Red"; return $false }
    Log "已提交：$message"

    for ($i = 1; $i -le 4; $i++) {
      git push -u origin HEAD 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { Log "推送成功（第 $i 次）" "Green"; return $true }
      Log "第 $i 次推送失败，重试…" "DarkOrange"
      Start-Sleep -Seconds 4
    }
    Log "推送失败，改动已提交在本地" "Red"
    return $false
  } finally {
    Pop-Location
  }
}

function New-Entry([string]$file) {
  if (-not (Test-Path -LiteralPath $file)) { Log "找不到文件：$file" "Red"; return $false }

  $raw = (Read-TextSmart $file).TrimStart([char]0xFEFF)
  $lines = $raw -split "\r?\n"
  if ($lines.Count -lt 2) { Log "格式不对：至少要有 条目名 + 简单介绍 两行" "Red"; return $false }

  $title = $lines[0].Trim()
  $desc = $lines[1].Trim()
  $tagsLine = if ($lines.Count -gt 2) { $lines[2].Trim() } else { "" }
  $bodyLines = if ($lines.Count -gt 3) { $lines[3..($lines.Count - 1)] } else { @() }

  if ([string]::IsNullOrWhiteSpace($title)) { Log "第 1 行（条目名）是空的" "Red"; return $false }
  if ([string]::IsNullOrWhiteSpace($desc)) { Log "第 2 行（神人事迹）是必填的" "Red"; return $false }

  $bodyHtml = Convert-BodyToHtml $bodyLines (Split-Path -Parent $file)
  if ([string]::IsNullOrWhiteSpace($bodyHtml)) {
    $bodyHtml = ""
    Log "没有长篇大论，条目页会显示“暂时没有”"
  }

  $tags = @()
  if (-not [string]::IsNullOrWhiteSpace($tagsLine)) {
    $tags = @($tagsLine -split "[,，]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }

  $baseName = [IO.Path]::GetFileNameWithoutExtension($file)
  $slug = if ($baseName -match '^[A-Za-z0-9\-_]+$') { $baseName.ToLower() } else { "e-" + (Get-Date -Format "yyyyMMdd-HHmmss") }

  $existing = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)
  if ($existing.Contains('slug: "' + $slug + '"')) { Log "slug「$slug」已被占用，换个文件名" "Red"; return $false }

  $date = (Get-Item -LiteralPath $file).LastWriteTime.ToString("yyyy-MM-dd")
  $tagsJs = "[" + (($tags | ForEach-Object { Escape-Js $_ }) -join ", ") + "]"

  $block = @"
  {
    slug: "$slug",
    title: $(Escape-Js $title),
    tags: $tagsJs,
    date: "$date",
    desc: $(Escape-Js $desc),
    content: ``
$(Escape-Template $bodyHtml)
    ``
  },
"@

  $marker = "/* ENTRIES:START */"
  if (-not $existing.Contains($marker)) { Log "entries.js 里找不到插入标记" "Red"; return $false }
  $text = $existing.Replace($marker, $marker + "`r`n" + $block.TrimEnd() + "`r`n")
  [System.IO.File]::WriteAllText($dataPath, $text, (New-Object System.Text.UTF8Encoding($false)))

  Bump-Version
  Log "已写入条目：$title" "Green"
  $ok = Publish-Changes ("新增条目：" + $title)
  if ($ok) { Log "地址：$siteUrl/#/e/$slug" "Black" }
  return $ok
}

function Remove-Entry($entry) {
  $text = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)
  if (-not $text.Contains($entry.Block)) { Log "找不到了，可能已被删过" "Red"; return $false }
  $newText = $text.Replace($entry.Block, "")
  $newText = [regex]::Replace($newText, "(\r?\n){3,}", "`r`n`r`n")
  [System.IO.File]::WriteAllText($dataPath, $newText, (New-Object System.Text.UTF8Encoding($false)))
  Bump-Version
  Log "已删除：$($entry.Title)" "Green"
  return (Publish-Changes ("删除条目：" + $entry.Title))
}

# ============================ 界面 ============================

$form = New-Object System.Windows.Forms.Form
$form.Text = "codm神人收集录 · 管理端"
$form.ClientSize = New-Object System.Drawing.Size(760, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(680, 480)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "codm神人收集录"
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.SetBounds(20, 14, 400, 32)
$form.Controls.Add($titleLabel)

$siteLabel = New-Object System.Windows.Forms.LinkLabel
$siteLabel.Text = "politeelm.github.io/codm"
$siteLabel.SetBounds(20, 46, 400, 20)
$siteLabel.Add_LinkClicked({ Start-Process "https://politeelm.github.io/codm/" })
$form.Controls.Add($siteLabel)

$btnNew = New-Object System.Windows.Forms.Button
$btnNew.Text = "＋ 新建条目"
$btnNew.SetBounds(20, 78, 160, 40)
$form.Controls.Add($btnNew)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "－ 删除选中"
$btnDelete.SetBounds(190, 78, 160, 40)
$btnDelete.Enabled = $false
$form.Controls.Add($btnDelete)

$btnPush = New-Object System.Windows.Forms.Button
$btnPush.Text = "↑ 推送"
$btnPush.SetBounds(360, 78, 120, 40)
$form.Controls.Add($btnPush)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "打开文件夹"
$btnOpen.SetBounds(490, 78, 120, 40)
$form.Controls.Add($btnOpen)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "刷新列表"
$btnRefresh.SetBounds(620, 78, 110, 40)
$form.Controls.Add($btnRefresh)

$listLabel = New-Object System.Windows.Forms.Label
$listLabel.Text = "条目（点一下选中，再点删除）"
$listLabel.SetBounds(20, 130, 400, 20)
$form.Controls.Add($listLabel)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.SetBounds(20, 152, 720, 170)
$listBox.IntegralHeight = $false
$form.Controls.Add($listBox)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = "日志"
$logLabel.SetBounds(20, 332, 200, 20)
$form.Controls.Add($logLabel)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ScrollBars = "Vertical"
$script:logBox.ReadOnly = $true
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$script:logBox.SetBounds(20, 354, 720, 190)
$form.Controls.Add($script:logBox)

function Refresh-List {
  $listBox.Items.Clear()
  $script:entries = @(Parse-Entries)
  foreach ($e in $script:entries) {
    [void]$listBox.Items.Add($e.Title)
  }
  Log ("已加载条目：" + $script:entries.Count + " 条")
}

function Set-Busy([bool]$busy) {
  $btnNew.Enabled = -not $busy
  $btnDelete.Enabled = (-not $busy) -and ($listBox.SelectedIndex -ge 0)
  $btnPush.Enabled = -not $busy
  $btnRefresh.Enabled = -not $busy
  [System.Windows.Forms.Application]::DoEvents()
}

$btnNew.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "选择条目 txt（第 1 行条目名，第 2 行神人事迹，第 3 行分类，第 4 行起长篇大论）"
  $dlg.Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*"
  $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

  Set-Busy $true
  try { New-Entry $dlg.FileName | Out-Null; Refresh-List } finally { Set-Busy $false }
})

$btnDelete.Add_Click({
  if ($listBox.SelectedIndex -lt 0) { return }
  $entry = $script:entries[$listBox.SelectedIndex]

  $ans = [System.Windows.Forms.MessageBox]::Show(
    "确定删除这条吗？`n`n$($entry.Title)`n`n删除后会立即推送。",
    "删除条目",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning)
  if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  Set-Busy $true
  try { Remove-Entry $entry | Out-Null; Refresh-List } finally { Set-Busy $false }
})

$btnPush.Add_Click({
  Set-Busy $true
  try {
    $msg = [Microsoft.VisualBasic.Interaction]::InputBox("这次改了什么？（留空用时间）", "推送", "")
    if ($null -eq $msg) { return }
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "更新 " + (Get-Date -Format "yyyy-MM-dd HH:mm") }
    Bump-Version
    Publish-Changes $msg | Out-Null
  } finally { Set-Busy $false }
})

$btnOpen.Add_Click({ Start-Process explorer.exe $root })

$btnRefresh.Add_Click({ Refresh-List })

$listBox.Add_SelectedIndexChanged({
  $btnDelete.Enabled = ($listBox.SelectedIndex -ge 0)
})

try { Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null } catch { }

Log "管理端已启动，仓库：$root"
Refresh-List

if ($自检) {
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = 1500
  $timer.Add_Tick({ $form.Close() })
  $timer.Start()
}

[void]$form.ShowDialog()

if ($自检) { Write-Host "UI OK" }
