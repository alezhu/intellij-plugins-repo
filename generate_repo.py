import io
import os
import sys
import zipfile
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
        # Check if META-INF/plugin.xml exists directly in zip
        for name in z.namelist():
            if name.endswith("META-INF/plugin.xml"):
                return z.read(name)
        # Check inside nested .jar files (Gradle IntelliJ plugin standard distribution structure)
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
        if idea_ver is not None:
            idea_node = doc.createElement("idea-version")
            for k, v in idea_ver.attrib.items():
                idea_node.setAttribute(k, v)
            plugin_node.appendChild(idea_node)

        vendor = pxml.find("vendor")
        if vendor is not None:
            vendor_node = doc.createElement("vendor")
            for k, v in vendor.attrib.items():
                vendor_node.setAttribute(k, v)
            if vendor.text:
                vendor_node.appendChild(doc.createTextNode(vendor.text))
            plugin_node.appendChild(vendor_node)

        print(f"Added plugin: id={p_id}, version={p_version}, name='{p_name}', file={zip_path.name}")
        plugins_found += 1
    except Exception as e:
        print(f"Error processing {zip_path}: {e}", file=sys.stderr)

xml_content = doc.toprettyxml(indent="  ", encoding="utf-8")

# Write to site/updatePlugins.xml
(SITE_DIR / "updatePlugins.xml").write_bytes(xml_content)
# Also write to root for local inspection
Path("updatePlugins.xml").write_bytes(xml_content)

print(f"\nSuccessfully generated updatePlugins.xml with {plugins_found} plugin(s).")
