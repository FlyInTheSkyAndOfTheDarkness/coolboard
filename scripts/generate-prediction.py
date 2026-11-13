"""Bundle filtered FrequencyWords/OpenSubtitles vocabulary for offline glide typing.
The generated data remains CC BY-SA 4.0; app source code has a separate license.
"""
import concurrent.futures
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "CoolBoard-personal-build"})
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.read().decode("utf-8")

commit = json.loads(get("https://api.github.com/repos/hermitdave/FrequencyWords/commits/master"))["sha"]
layouts = json.loads((ROOT / "shared/layouts.json").read_text(encoding="utf-8"))
starter = json.loads((ROOT / "shared/lexicon.json").read_text(encoding="utf-8"))
def pack(language):
    lang = language["id"]
    base = f"https://raw.githubusercontent.com/hermitdave/FrequencyWords/{commit}/content/2018/{lang}/{lang}"
    try:
        raw = get(base + "_50k.txt")
    except urllib.error.HTTPError:
        raw = get(base + "_full.txt")
    alphabet = set("".join(language["rows"]))
    words = list(starter[lang]["words"])
    for line in raw.splitlines():
        word = line.rsplit(" ", 1)[0].strip().lower()
        if 2 <= len(word) <= 24 and set(word) <= alphabet:
            words.append(word)
    words = list(dict.fromkeys(words))[:6000]
    return lang, words

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    languages = dict(pool.map(pack, layouts["languages"]))
data = {"version": 1, "source": f"https://github.com/hermitdave/FrequencyWords/tree/{commit}", "license": "CC-BY-SA-4.0", "languages": languages}
(ROOT / "shared/prediction.json").write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
directory = ROOT / "third_party/frequencywords"
directory.mkdir(parents=True, exist_ok=True)
(directory / "FrequencyWords-NOTICE.txt").write_text(
    "FrequencyWords by Hermit Dave, derived from OpenSubtitles 2018 (OPUS).\n"
    + f"Source commit: {commit}\nhttps://github.com/hermitdave/FrequencyWords\n"
    + "Adaptation by CoolBoard: lower-case vocabulary filtered to each supported layout; up to 6000 words per language, merged with local starter words.\n"
    + "This adapted word-list data is licensed under CC BY-SA 4.0.\nhttps://creativecommons.org/licenses/by-sa/4.0/\n"
    + "This data license does not apply to the separately authored application source code.\n", encoding="utf-8")
(directory / "FrequencyWords-LICENSE.txt").write_text(get("https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt"), encoding="utf-8")
print(json.dumps({language: len(words) for language, words in languages.items()}))
