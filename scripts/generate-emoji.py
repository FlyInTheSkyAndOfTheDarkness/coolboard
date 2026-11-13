"""Rebuild the offline Unicode 16 / CLDR 46 emoji catalog (no image assets)."""
import concurrent.futures
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
URLS = {
    "emoji": "https://unicode.org/Public/emoji/16.0/emoji-test.txt",
    "ru": "https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/annotations/ru.xml",
    "kk": "https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/annotations/kk.xml",
    "license": "https://www.unicode.org/license.txt",
}

def download(item):
    key, url = item
    with urllib.request.urlopen(url, timeout=45) as response:
        return key, response.read().decode("utf-8")

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    sources = dict(pool.map(download, URLS.items()))

annotations = {}
for lang in ("ru", "kk"):
    for node in ET.fromstring(sources[lang]).iter("annotation"):
        annotations.setdefault(node.attrib["cp"].replace("\ufe0f", ""), []).append(node.text or "")

groups = [
    ("Smileys & Emotion", "smileys", "Эмоции", "😀"),
    ("People & Body", "people", "Люди", "👋"),
    ("Animals & Nature", "nature", "Природа", "🐻"),
    ("Food & Drink", "food", "Еда", "🍎"),
    ("Travel & Places", "travel", "Места", "🚗"),
    ("Activities", "activities", "Занятия", "⚽"),
    ("Objects", "objects", "Предметы", "💡"),
    ("Symbols", "symbols", "Символы", "❤️"),
    ("Flags", "flags", "Флаги", "🏁"),
]
catalog = {"version": "16.0", "source": URLS["emoji"], "categories": []}
categories = {}
for original, key, title, icon in groups:
    category = {"id": key, "title": title, "icon": icon, "entries": []}
    categories[original] = category
    catalog["categories"].append(category)

current = None
entries = []
for line in sources["emoji"].splitlines():
    if line.startswith("# group:"):
        current = categories.get(line.split(":", 1)[1].strip())
    match = re.match(r"^([0-9A-F ]+)\s*; fully-qualified\s*# \S+ E[0-9.]+ (.+)$", line)
    if not match or current is None:
        continue
    text = "".join(chr(int(code, 16)) for code in match[1].split())
    keywords = annotations.get(text.replace("\ufe0f", ""), [])
    entry = {"text": text, "name": match[2], "keywords": " | ".join(keywords), "variants": []}
    current["entries"].append(entry)
    entries.append(entry)

def strip_tone(text):
    return "".join(c for c in text if not 0x1F3FB <= ord(c) <= 0x1F3FF).replace("\ufe0f", "")

bases = {strip_tone(e["text"]): e for e in entries if not any(0x1F3FB <= ord(c) <= 0x1F3FF for c in e["text"])}
removed = set()
for entry in entries:
    if any(0x1F3FB <= ord(c) <= 0x1F3FF for c in entry["text"]):
        base = bases.get(strip_tone(entry["text"]))
        if base:
            base["variants"].append(entry["text"])
            removed.add(entry["text"])
for category in catalog["categories"]:
    category["entries"] = [e for e in category["entries"] if e["text"] not in removed]

catalog["sequenceCount"] = len(entries)
(ROOT / "shared/emoji.json").write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
license_dir = ROOT / "third_party/unicode"
license_dir.mkdir(parents=True, exist_ok=True)
(license_dir / "LICENSE.txt").write_text(sources["license"], encoding="utf-8")
print(f"Generated {len(entries)} emoji sequences across {len(categories)} categories.")
