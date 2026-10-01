import csv
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(__file__).resolve().parents[1] / "LumaLex/Resources/OfflineDictionary.json"
with source.open(encoding="utf-8-sig", newline="") as stream:
    rows = [row for row in csv.DictReader(stream) if row.get("translation", "").strip()]

def rank(row):
    frequencies = [int(row[key]) for key in ("bnc", "frq") if row.get(key, "").isdigit() and int(row[key]) > 0]
    return (min(frequencies, default=9999999), row["word"])

rows.sort(key=rank)
entries = [{key: row.get(key, "") for key in ("word", "phonetic", "translation", "definition", "pos", "exchange")}
           for row in rows[:50000]]
target.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
assert len(entries) >= 40000
print(f"Built {len(entries)} offline entries ({target.stat().st_size} bytes)")
