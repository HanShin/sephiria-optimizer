#!/usr/bin/env python3
"""Extract the public artifact catalog embedded in sephiria.wiki/simulator HTML."""

from __future__ import annotations

import json
import pathlib
import re
import sys


def extract_artifacts(html: str) -> list[dict]:
    pattern = re.compile(r"self\.__next_f\.push\(\[1,(\"(?:\\.|[^\"\\])*\")\]\)")
    for encoded in pattern.findall(html):
        decoded = json.loads(encoded)
        if '"label_kor"' not in decoded or not decoded.startswith("a:"):
            continue
        root = json.loads(decoded[2:])
        data = root[3]["children"][3]["data"]
        artifacts = []
        for item in data:
            if item.get("disabled") is True:
                continue
            artifacts.append(
                {
                    "id": int(item["id"]),
                    "value": item["value"],
                    "label_kor": item["label_kor"],
                    "label_eng": item.get("label_eng") or item["value"],
                    "tier": item["tier"],
                    "image": item["image"],
                    "level": int(item.get("level") or 0),
                }
            )
        return artifacts
    raise RuntimeError("artifact payload was not found in simulator HTML")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sync_catalog.py SIMULATOR_HTML OUTPUT_JSON", file=sys.stderr)
        return 2
    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    artifacts = extract_artifacts(source.read_text(encoding="utf-8"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(artifacts, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(artifacts)} artifacts to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
