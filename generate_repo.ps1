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
$processed = 0

foreach ($z in $zipFiles) {
    try {
        $pDoc = Get-PluginXmlDoc -zipPath $z.FullName
        if ($null -eq $pDoc) {
            Write-Warning "Skipping $($z.Name): META-INF/plugin.xml not found."
            continue
        }

        $ideaPlugin = $pDoc.DocumentElement
        $pluginId = ($ideaPlugin.SelectSingleNode("id") | ForEach-Object { $_.InnerText })
        if (-not $pluginId) { $pluginId = ($ideaPlugin.SelectSingleNode("name") | ForEach-Object { $_.InnerText }) }
        $pVersion = ($ideaPlugin.SelectSingleNode("version") | ForEach-Object { $_.InnerText })
        $pName = ($ideaPlugin.SelectSingleNode("name") | ForEach-Object { $_.InnerText })
        $pDesc = ($ideaPlugin.SelectSingleNode("description") | ForEach-Object { $_.InnerText })
        $pNotes = ($ideaPlugin.SelectSingleNode("change-notes") | ForEach-Object { $_.InnerText })

        # Copy zip to site/plugins/
        Copy-Item $z.FullName -Destination $sitePluginsDir -Force

        $pluginEl = $xmlDoc.CreateElement("plugin")
        $pluginEl.SetAttribute("id", $pluginId)
        $pluginEl.SetAttribute("url", "$($BaseUrl.TrimEnd('/'))/plugins/$($z.Name)")
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

        $ideaVerNode = $ideaPlugin.SelectSingleNode("idea-version")
        if ($ideaVerNode) {
            $importedIdeaVer = $xmlDoc.ImportNode($ideaVerNode, $true)
            $pluginEl.AppendChild($importedIdeaVer) | Out-Null
        }

        $vendorNode = $ideaPlugin.SelectSingleNode("vendor")
        if ($vendorNode) {
            $importedVendor = $xmlDoc.ImportNode($vendorNode, $true)
            $pluginEl.AppendChild($importedVendor) | Out-Null
        }

        $rootEl.AppendChild($pluginEl) | Out-Null
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

Write-Host "`nGenerated updatePlugins.xml with $processed plugin(s)." -ForegroundColor Green
