import io
import os
import sys
import zipfile
import html
import xml.etree.ElementTree as ET
import xml.dom.minidom as minidom
from pathlib import Path

# Base URL of GitHub Pages
BASE_URL = os.environ.get("BASE_URL", "https://alezhu.github.io/intellij-plugins-repo").rstrip("/")
SITE_DIR = Path("site")
PLUGINS_SRC_DIR = Path("plugins")

SITE_DIR.mkdir(exist_ok=True)
(SITE_DIR / "plugins").mkdir(exist_ok=True)

doc = minidom.Document()
root_node = doc.createElement("plugins")
doc.appendChild(root_node)

def get_plugin_xml_bytes(zip_path: Path):
    with zipfile.ZipFile(zip_path, 'r') as z:
        for name in z.namelist():
            if name.endswith("META-INF/plugin.xml"):
                return z.read(name)
        for name in z.namelist():
            if name.endswith(".jar"):
                jar_bytes = z.read(name)
                try:
                    with zipfile.ZipFile(io.BytesIO(jar_bytes)) as jar:
                        for jar_entry in jar.namelist():
                            if jar_entry.endswith("META-INF/plugin.xml"):
                                return jar.read(jar_entry)
                except Exception:
                    continue
    return None

plugins_data = []
plugins_found = 0

for zip_path in sorted(PLUGINS_SRC_DIR.glob("*.zip")):
    try:
        xml_bytes = get_plugin_xml_bytes(zip_path)
        if not xml_bytes:
            print(f"Skipping {zip_path.name}: META-INF/plugin.xml not found")
            continue

        pxml = ET.fromstring(xml_bytes)
        p_id = pxml.findtext("id") or pxml.findtext("name")
        p_version = pxml.findtext("version")
        p_name = pxml.findtext("name") or zip_path.stem
        p_desc = pxml.findtext("description") or ""
        p_notes = pxml.findtext("change-notes") or ""

        # Copy zip into site/plugins directory
        dest_zip = SITE_DIR / "plugins" / zip_path.name
        dest_zip.write_bytes(zip_path.read_bytes())

        plugin_url = f"{BASE_URL}/plugins/{zip_path.name}"
        plugin_node = doc.createElement("plugin")
        plugin_node.setAttribute("id", p_id)
        plugin_node.setAttribute("url", plugin_url)
        plugin_node.setAttribute("version", p_version)
        root_node.appendChild(plugin_node)

        name_node = doc.createElement("name")
        name_node.appendChild(doc.createTextNode(p_name))
        plugin_node.appendChild(name_node)

        if p_desc:
            desc_node = doc.createElement("description")
            desc_node.appendChild(doc.createCDATASection(p_desc))
            plugin_node.appendChild(desc_node)

        if p_notes:
            notes_node = doc.createElement("change-notes")
            notes_node.appendChild(doc.createCDATASection(p_notes))
            plugin_node.appendChild(notes_node)

        idea_ver = pxml.find("idea-version")
        idea_ver_text = ""
        if idea_ver is not None:
            idea_node = doc.createElement("idea-version")
            for k, v in idea_ver.attrib.items():
                idea_node.setAttribute(k, v)
            plugin_node.appendChild(idea_node)
            parts = []
            if "since-build" in idea_ver.attrib:
                parts.append(f"since {idea_ver.attrib['since-build']}")
            if "until-build" in idea_ver.attrib:
                parts.append(f"until {idea_ver.attrib['until-build']}")
            idea_ver_text = ", ".join(parts)

        vendor = pxml.find("vendor")
        vendor_name = ""
        if vendor is not None:
            vendor_node = doc.createElement("vendor")
            for k, v in vendor.attrib.items():
                vendor_node.setAttribute(k, v)
            if vendor.text:
                vendor_node.appendChild(doc.createTextNode(vendor.text))
                vendor_name = vendor.text
            plugin_node.appendChild(vendor_node)

        plugins_data.append({
            "id": p_id,
            "name": p_name,
            "version": p_version,
            "url": plugin_url,
            "file_name": zip_path.name,
            "desc": p_desc,
            "idea_ver": idea_ver_text,
            "vendor": vendor_name
        })

        print(f"Added plugin: id={p_id}, version={p_version}, name='{p_name}', file={zip_path.name}")
        plugins_found += 1
    except Exception as e:
        print(f"Error processing {zip_path}: {e}", file=sys.stderr)

# Save updatePlugins.xml
xml_content = doc.toprettyxml(indent="  ", encoding="utf-8")
(SITE_DIR / "updatePlugins.xml").write_bytes(xml_content)
Path("updatePlugins.xml").write_bytes(xml_content)

# Generate index.html
manifest_url = f"{BASE_URL}/updatePlugins.xml"

cards_html = ""
for p in plugins_data:
    vendor_badge = f'<span class="badge vendor">{html.escape(p["vendor"])}</span>' if p["vendor"] else ""
    compat_badge = f'<span class="badge compat">{html.escape(p["idea_ver"])}</span>' if p["idea_ver"] else ""
    cards_html += f"""
    <div class="card">
      <div class="card-header">
        <div>
          <h3>{html.escape(p["name"])}</h3>
          <span class="plugin-id">{html.escape(p["id"])}</span>
        </div>
        <span class="badge version">v{html.escape(p["version"])}</span>
      </div>
      <div class="badges">
        {vendor_badge}
        {compat_badge}
      </div>
      <div class="desc">{p["desc"]}</div>
      <div class="card-footer">
        <a href="{p["url"]}" class="btn download-btn">Download .zip ({html.escape(p["file_name"])})</a>
      </div>
    </div>
    """

index_html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>IntelliJ Custom Plugins Repository</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #0f172a;
      --card-bg: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --accent-hover: #0284c7;
      --code-bg: #090d16;
      --badge-bg: #334155;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 40px 20px;
    }}
    .container {{
      max-width: 900px;
      margin: 0 auto;
    }}
    header {{
      text-align: center;
      margin-bottom: 40px;
    }}
    h1 {{
      font-size: 2.2rem;
      margin-bottom: 12px;
      background: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }}
    p.subtitle {{
      color: var(--text-muted);
      font-size: 1.1rem;
    }}
    .repo-box {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 40px;
    }}
    .repo-box h2 {{
      font-size: 1.2rem;
      margin-bottom: 12px;
      display: flex;
      align-items: center;
      gap: 8px;
    }}
    .url-container {{
      display: flex;
      gap: 10px;
      background: var(--code-bg);
      padding: 8px 12px;
      border-radius: 8px;
      border: 1px solid var(--border);
      align-items: center;
    }}
    .url-text {{
      flex-grow: 1;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      color: var(--accent);
      font-size: 0.95rem;
      word-break: break-all;
    }}
    .copy-btn {{
      background: var(--accent);
      color: #0f172a;
      border: none;
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      white-space: nowrap;
      transition: background 0.2s;
    }}
    .copy-btn:hover {{
      background: var(--accent-hover);
    }}
    .instructions {{
      margin-top: 16px;
      font-size: 0.95rem;
      color: var(--text-muted);
    }}
    .instructions ol {{
      margin-left: 20px;
      margin-top: 8px;
    }}
    .instructions li {{
      margin-bottom: 4px;
    }}
    .section-title {{
      font-size: 1.5rem;
      margin-bottom: 20px;
    }}
    .cards-grid {{
      display: grid;
      gap: 20px;
    }}
    .card {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 24px;
      transition: transform 0.2s, border-color 0.2s;
    }}
    .card:hover {{
      border-color: var(--accent);
      transform: translateY(-2px);
    }}
    .card-header {{
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 12px;
    }}
    .card-header h3 {{
      font-size: 1.3rem;
      color: var(--text);
    }}
    .plugin-id {{
      font-size: 0.85rem;
      color: var(--text-muted);
      font-family: monospace;
    }}
    .badges {{
      display: flex;
      gap: 8px;
      margin-bottom: 16px;
      flex-wrap: wrap;
    }}
    .badge {{
      font-size: 0.8rem;
      padding: 3px 8px;
      border-radius: 6px;
      font-weight: 500;
    }}
    .badge.version {{
      background: #0284c7;
      color: white;
    }}
    .badge.vendor {{
      background: var(--badge-bg);
      color: var(--text-muted);
    }}
    .badge.compat {{
      background: #334155;
      color: #94a3b8;
    }}
    .desc {{
      color: #cbd5e1;
      font-size: 0.95rem;
      margin-bottom: 20px;
    }}
    .desc p {{ margin-bottom: 8px; }}
    .desc a {{ color: var(--accent); }}
    .desc ul {{ margin-left: 20px; margin-bottom: 8px; }}
    .card-footer {{
      display: flex;
      justify-content: flex-end;
    }}
    .btn {{
      display: inline-block;
      text-decoration: none;
      font-size: 0.9rem;
      font-weight: 500;
      padding: 8px 16px;
      border-radius: 6px;
      transition: background 0.2s;
    }}
    .download-btn {{
      background: #334155;
      color: var(--text);
    }}
    .download-btn:hover {{
      background: #475569;
    }}
    footer {{
      margin-top: 60px;
      text-align: center;
      color: var(--text-muted);
      font-size: 0.85rem;
    }}
    footer a {{ color: var(--accent); text-decoration: none; }}
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
        <span class="url-text" id="repo-url">{manifest_url}</span>
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

    <h2 class="section-title">📦 Available Plugins ({len(plugins_data)})</h2>
    <div class="cards-grid">
      {cards_html}
    </div>

    <footer>
      Powered by <a href="https://github.com/alezhu/intellij-plugins-repo" target="_blank">intellij-plugins-repo</a> & GitHub Pages
    </footer>
  </div>

  <script>
    function copyUrl() {{
      const text = document.getElementById('repo-url').innerText;
      navigator.clipboard.writeText(text).then(() => {{
        const btn = document.querySelector('.copy-btn');
        btn.innerText = 'Copied!';
        setTimeout(() => {{ btn.innerText = 'Copy URL'; }}, 2000);
      }});
    }}
  </script>
</body>
</html>
"""

(SITE_DIR / "index.html").write_text(index_html_content, encoding="utf-8")
Path("index.html").write_text(index_html_content, encoding="utf-8")

print(f"\nSuccessfully generated updatePlugins.xml and index.html with {plugins_found} plugin(s).")
