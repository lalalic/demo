#!/usr/bin/env python3
import json
import sys
from pathlib import Path

FORBIDDEN = {"actions", "coordinates", "selector", "selectors", "xpath", "click_sequence", "keypress_sequence"}

def walk(value, path="doc"):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN:
                raise ValueError(f"{path}.{key} is runtime automation detail")
            walk(child, f"{path}.{key}")
    elif isinstance(value, list):
        for i, child in enumerate(value):
            walk(child, f"{path}[{i}]")

def main(path):
    doc = json.loads(Path(path).read_text())
    if doc.get("schema_version") != 1 or not isinstance(doc.get("items"), list):
        raise ValueError("expected demo execution lane v1")
    for item in doc["items"]:
        for field in ("id", "type", "scene_id", "output", "identity", "intent", "required_visible_evidence", "success", "presentation", "autonomy"):
            if field not in item:
                raise ValueError(f"item missing {field}")
        if item["type"] != "demo":
            raise ValueError("item.type must be demo")
        if item["success"].get("fresh_ui_required") is not True:
            raise ValueError("success.fresh_ui_required must be true")
        walk(item)
    print(json.dumps({"valid": True, "items": len(doc["items"])}))

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} execution/demo.json")
    try:
        main(sys.argv[1])
    except Exception as exc:
        print(f"invalid demo execution: {exc}", file=sys.stderr)
        raise SystemExit(1)
