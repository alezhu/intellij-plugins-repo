[CmdletBinding()]
param(
    [string]$BaseUrl = "https://alezhu.github.io/intellij-plugins-repo"
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$pluginsSrcDir = Join-Path $scriptDir "plugins"
$siteDir = Join-Path $scriptDir "site"
$sitePluginsDir = Join-Path $siteDir "plugins"

if (-not (Test-Path $pluginsSrcDir)) {
    New-Item -ItemType Directory -Force -Path $pluginsSrcDir | Out-Null
}

New-Item -ItemType Directory -Force -Path $sitePluginsDir | Out-Null

$xmlDoc = New-Object System.Xml.XmlDocument
$xmlDoc.AppendChild($xmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
$rootEl = $xmlDoc.CreateElement("plugins")
$xmlDoc.AppendChild($rootEl) | Out-Null

function Get-PluginXmlDoc([string]$zipPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        # Check direct
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith("META-INF/plugin.xml")) {
                $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
                $txt = $sr.ReadToEnd()
                $sr.Close()
                $doc = New-Object System.Xml.XmlDocument
                $doc.LoadXml($txt)
                return $doc
            }
        }
        # Check nested jar
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith(".jar")) {
                $ms = New-Object System.IO.MemoryStream
                $s = $entry.Open()
                $s.CopyTo($ms)
                $s.Close()
                $ms.Position = 0
                $jar = New-Object System.IO.Compression.ZipArchive($ms)
                try {
                    foreach ($jEntry in $jar.Entries) {
                        if ($jEntry.FullName.EndsWith("META-INF/plugin.xml")) {
                            $sr = New-Object System.IO.StreamReader($jEntry.Open(), [System.Text.Encoding]::UTF8)
                            $txt = $sr.ReadToEnd()
                            $sr.Close()
                            $doc = New-Object System.Xml.XmlDocument
                            $doc.LoadXml($txt)
                            return $doc
                        }
                    }
                }
                finally {
                    $jar.Dispose()
                    $ms.Dispose()
                }
            }
        }
    }
    finally {
        $zip.Dispose()
    }
    return $null
}

$zipFiles = Get-ChildItem -Path $pluginsSrcDir -Filter "*.zip" | Sort-Object Name
$pluginsList = [System.Collections.Generic.List[PSCustomObject]]::new()
$processed = 0

foreach ($z in $zipFiles) {
    try {
        $pluginDoc = Get-PluginXmlDoc -zipPath $z.FullName
        if ($null -eq $pluginDoc) {
            Write-Warning "Skipping $($z.Name): META-INF/plugin.xml not found."
            continue
        }

        $ideaPlugin = $pluginDoc.DocumentElement
        $pluginId = ($ideaPlugin.SelectSingleNode("id") | ForEach-Object { $_.InnerText })
        if (-not $pluginId) { $pluginId = ($ideaPlugin.SelectSingleNode("name") | ForEach-Object { $_.InnerText }) }
        $pVersion = ($ideaPlugin.SelectSingleNode("version") | ForEach-Object { $_.InnerText })
        $pName = ($ideaPlugin.SelectSingleNode("name") | ForEach-Object { $_.InnerText })
        $pDesc = ($ideaPlugin.SelectSingleNode("description") | ForEach-Object { $_.InnerText })
        $pNotes = ($ideaPlugin.SelectSingleNode("change-notes") | ForEach-Object { $_.InnerText })

        # Copy zip to site/plugins/
        Copy-Item $z.FullName -Destination $sitePluginsDir -Force

        $pluginUrl = "$($BaseUrl.TrimEnd('/'))/plugins/$($z.Name)"

        $pluginEl = $xmlDoc.CreateElement("plugin")
        $pluginEl.SetAttribute("id", $pluginId)
        $pluginEl.SetAttribute("url", $pluginUrl)
        $pluginEl.SetAttribute("version", $pVersion)

        $nameEl = $xmlDoc.CreateElement("name")
        $nameEl.InnerText = $pName
        $pluginEl.AppendChild($nameEl) | Out-Null

        if ($pDesc) {
            $descEl = $xmlDoc.CreateElement("description")
            $cdataDesc = $xmlDoc.CreateCDataSection($pDesc)
            $descEl.AppendChild($cdataDesc) | Out-Null
            $pluginEl.AppendChild($descEl) | Out-Null
        }

        if ($pNotes) {
            $notesEl = $xmlDoc.CreateElement("change-notes")
            $cdataNotes = $xmlDoc.CreateCDataSection($pNotes)
            $notesEl.AppendChild($cdataNotes) | Out-Null
            $pluginEl.AppendChild($notesEl) | Out-Null
        }

        $ideaVerText = ""
        $ideaVerNode = $ideaPlugin.SelectSingleNode("idea-version")
        if ($ideaVerNode) {
            $importedIdeaVer = $xmlDoc.ImportNode($ideaVerNode, $true)
            $pluginEl.AppendChild($importedIdeaVer) | Out-Null
            $parts = @()
            if ($ideaVerNode.Attributes["since-build"]) { $parts += "since " + $ideaVerNode.Attributes["since-build"].Value }
            if ($ideaVerNode.Attributes["until-build"]) { $parts += "until " + $ideaVerNode.Attributes["until-build"].Value }
            $ideaVerText = $parts -join ", "
        }

        $vendorText = ""
        $vendorNode = $ideaPlugin.SelectSingleNode("vendor")
        if ($vendorNode) {
            $importedVendor = $xmlDoc.ImportNode($vendorNode, $true)
            $pluginEl.AppendChild($importedVendor) | Out-Null
            $vendorText = $vendorNode.InnerText
        }

        $rootEl.AppendChild($pluginEl) | Out-Null

        $pluginsList.Add([PSCustomObject]@{
            Id = $pluginId
            Name = $pName
            Version = $pVersion
            Url = $pluginUrl
            FileName = $z.Name
            Description = $pDesc
            IdeaVersion = $ideaVerText
            Vendor = $vendorText
        })

        Write-Host "Added plugin: id=$pluginId, version=$pVersion, name='$pName', file=$($z.Name)"
        $processed++
    }
    catch {
        Write-Error "Failed to process $($z.Name): $_"
    }
}

$siteXml = Join-Path $siteDir "updatePlugins.xml"
$rootXml = Join-Path $scriptDir "updatePlugins.xml"

$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = [System.Text.Encoding]::UTF8

$writer = [System.Xml.XmlWriter]::Create($siteXml, $settings)
$xmlDoc.Save($writer)
$writer.Close()

Copy-Item $siteXml -Destination $rootXml -Force

# Generate HTML Cards
$cardsHtml = ""
foreach ($p in $pluginsList) {
    $vendorBadge = if ($p.Vendor) { "<span class='badge vendor'>$([System.Net.WebUtility]::HtmlEncode($p.Vendor))</span>" } else { "" }
    $compatBadge = if ($p.IdeaVersion) { "<span class='badge compat'>$([System.Net.WebUtility]::HtmlEncode($p.IdeaVersion))</span>" } else { "" }
    $cardsHtml += @"
    <div class="card">
      <div class="card-header">
        <div>
          <h3>$([System.Net.WebUtility]::HtmlEncode($p.Name))</h3>
          <span class="plugin-id">$([System.Net.WebUtility]::HtmlEncode($p.Id))</span>
        </div>
        <span class="badge version">v$([System.Net.WebUtility]::HtmlEncode($p.Version))</span>
      </div>
      <div class="badges">
        $vendorBadge
        $compatBadge
      </div>
      <div class="desc">$($p.Description)</div>
      <div class="card-footer">
        <a href="$($p.Url)" class="btn download-btn">Download .zip ($([System.Net.WebUtility]::HtmlEncode($p.FileName)))</a>
      </div>
    </div>
"@
}

$manifestUrl = "$($BaseUrl.TrimEnd('/'))/updatePlugins.xml"
$indexHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>IntelliJ Custom Plugins Repository</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --accent-hover: #0284c7;
      --code-bg: #090d16;
      --badge-bg: #334155;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 40px 20px;
    }
    .container {
      max-width: 900px;
      margin: 0 auto;
    }
    header {
      text-align: center;
      margin-bottom: 40px;
    }
    h1 {
      font-size: 2.2rem;
      margin-bottom: 12px;
      background: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    p.subtitle {
      color: var(--text-muted);
      font-size: 1.1rem;
    }
    .repo-box {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 40px;
    }
    .repo-box h2 {
      font-size: 1.2rem;
      margin-bottom: 12px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .url-container {
      display: flex;
      gap: 10px;
      background: var(--code-bg);
      padding: 8px 12px;
      border-radius: 8px;
      border: 1px solid var(--border);
      align-items: center;
    }
    .url-text {
      flex-grow: 1;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      color: var(--accent);
      font-size: 0.95rem;
      word-break: break-all;
    }
    .copy-btn {
      background: var(--accent);
      color: #0f172a;
      border: none;
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      white-space: nowrap;
      transition: background 0.2s;
    }
    .copy-btn:hover {
      background: var(--accent-hover);
    }
    .instructions {
      margin-top: 16px;
      font-size: 0.95rem;
      color: var(--text-muted);
    }
    .instructions ol {
      margin-left: 20px;
      margin-top: 8px;
    }
    .instructions li {
      margin-bottom: 4px;
    }
    .section-title {
      font-size: 1.5rem;
      margin-bottom: 20px;
    }
    .cards-grid {
      display: grid;
      gap: 20px;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 24px;
      transition: transform 0.2s, border-color 0.2s;
    }
    .card:hover {
      border-color: var(--accent);
      transform: translateY(-2px);
    }
    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 12px;
    }
    .card-header h3 {
      font-size: 1.3rem;
      color: var(--text);
    }
    .plugin-id {
      font-size: 0.85rem;
      color: var(--text-muted);
      font-family: monospace;
    }
    .badges {
      display: flex;
      gap: 8px;
      margin-bottom: 16px;
      flex-wrap: wrap;
    }
    .badge {
      font-size: 0.8rem;
      padding: 3px 8px;
      border-radius: 6px;
      font-weight: 500;
    }
    .badge.version {
      background: #0284c7;
      color: white;
    }
    .badge.vendor {
      background: var(--badge-bg);
      color: var(--text-muted);
    }
    .badge.compat {
      background: #334155;
      color: #94a3b8;
    }
    .desc {
      color: #cbd5e1;
      font-size: 0.95rem;
      margin-bottom: 20px;
    }
    .desc p { margin-bottom: 8px; }
    .desc a { color: var(--accent); }
    .desc ul { margin-left: 20px; margin-bottom: 8px; }
    .card-footer {
      display: flex;
      justify-content: flex-end;
    }
    .btn {
      display: inline-block;
      text-decoration: none;
      font-size: 0.9rem;
      font-weight: 500;
      padding: 8px 16px;
      border-radius: 6px;
      transition: background 0.2s;
    }
    .download-btn {
      background: #334155;
      color: var(--text);
    }
    .download-btn:hover {
      background: #475569;
    }
    footer {
      margin-top: 60px;
      text-align: center;
      color: var(--text-muted);
      font-size: 0.85rem;
    }
    footer a { color: var(--accent); text-decoration: none; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Custom IntelliJ Plugins Repository</h1>
      <p class="subtitle">Independent update channel for IntelliJ Platform IDEs</p>
    </header>

    <div class="repo-box">
      <h2>🔌 Repository URL for IntelliJ IDEA</h2>
      <div class="url-container">
        <span class="url-text" id="repo-url">$manifestUrl</span>
        <button class="copy-btn" onclick="copyUrl()">Copy URL</button>
      </div>
      <div class="instructions">
        <strong>How to use in your IDE:</strong>
        <ol>
          <li>Open <b>Settings / Preferences</b> (<code>Ctrl + Alt + S</code> or <code>Cmd + ,</code>) &rarr; <b>Plugins</b>.</li>
          <li>Click the gear icon ⚙️ &rarr; <b>Manage Plugin Repositories...</b>.</li>
          <li>Click <b>+</b> and paste the URL above.</li>
        </ol>
      </div>
    </div>

    <h2 class="section-title">📦 Available Plugins ($($pluginsList.Count))</h2>
    <div class="cards-grid">
      $cardsHtml
    </div>

    <footer>
      Powered by <a href="https://github.com/alezhu/intellij-plugins-repo" target="_blank">intellij-plugins-repo</a> & GitHub Pages
    </footer>
  </div>

  <script>
    function copyUrl() {
      const text = document.getElementById('repo-url').innerText;
      navigator.clipboard.writeText(text).then(() => {
        const btn = document.querySelector('.copy-btn');
        btn.innerText = 'Copied!';
        setTimeout(() => { btn.innerText = 'Copy URL'; }, 2000);
      });
    }
  </script>
</body>
</html>
"@

$siteHtml = Join-Path $siteDir "index.html"
$rootHtml = Join-Path $scriptDir "index.html"
[System.IO.File]::WriteAllText($siteHtml, $indexHtml, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($rootHtml, $indexHtml, [System.Text.Encoding]::UTF8)

Write-Host "`nGenerated updatePlugins.xml and index.html with $processed plugin(s)." -ForegroundColor Green
