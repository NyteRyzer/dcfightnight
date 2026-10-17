#!/usr/bin/env python3
"""Regenerates docs/MOVES.md from the fighter JSON files.

Usage: python3 tools/gen_move_list.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
ORDER = ["S", "fS", "bS", "dS", "jS", "throw", "L", "M", "H", "cL", "cM", "cH", "jL", "jM", "jH"]
INPUTS = {
    "L": "Light", "M": "Medium", "H": "Heavy",
    "cL": "Down + Light", "cM": "Down + Medium", "cH": "Down + Heavy",
    "jL": "Air Light", "jM": "Air Medium", "jH": "Air Heavy",
    "throw": "Medium + Heavy (close)", "S": "Special", "fS": "Forward + Special",
    "bS": "Back + Special", "dS": "Down + Special (full meter)", "jS": "Special (in air)",
}


def load(path):
    with open(path) as f:
        return json.load(f)


def main():
    base = load(os.path.join(DATA, "moves", "base_normals.json"))
    base.pop("_doc", None)
    roster = load(os.path.join(DATA, "roster.json"))["fighters"]
    out = ["# Move List", "", "Generated from `data/fighters/*.json` by `tools/gen_move_list.py`.",
           "Frame data is in 60 fps frames. Damage is before combo scaling.", ""]
    for fid in roster:
        f = load(os.path.join(DATA, "fighters", fid + ".json"))
        moves = {k: dict(v) for k, v in base.items()}
        for k, v in f.get("moves", {}).items():
            moves.setdefault(k, {}).update(v)
        out.append(f"## {f['name']} ({f.get('real_name', '')})")
        out.append("")
        out.append(f"*{f.get('archetype', '')}* - HP {f.get('health')}, walk speed {f.get('walk')}")
        out.append("")
        out.append("| Input | Move | Startup | Active | Recovery | Damage | Notes |")
        out.append("|---|---|---|---|---|---|---|")
        for k in ORDER:
            if k not in moves:
                continue
            m = moves[k]
            notes = []
            if m.get("super"):
                notes.append("Super (1 full bar)")
            if "projectile" in m:
                p = m["projectile"]
                n = p.get("count", 1)
                notes.append("projectile" + (f" x{n}" if n > 1 else ""))
            if m.get("level") in ("low", "overhead"):
                notes.append(m["level"])
            if "armor" in m:
                notes.append(f"armor ({m['armor'].get('hits', 1)} hit)")
            if "invuln" in m:
                notes.append("invulnerable start-up")
            if "teleport" in m:
                notes.append("teleport")
            if "counter" in m:
                notes.append("counter stance")
            if m.get("hits", 1) > 1:
                notes.append(f"{m['hits']} hits")
            if "launch" in m or "launch_last" in m:
                notes.append("launcher")
            if m.get("knockdown"):
                notes.append("knockdown")
            dmg = m.get("damage", m.get("projectile", {}).get("damage", "-"))
            out.append(f"| {m.get('input', INPUTS[k])} | {m.get('name', k)} | {m.get('startup', '-')} | {m.get('active', '-')} | {m.get('recovery', '-')} | {dmg} | {', '.join(notes)} |")
        out.append("")
    with open(os.path.join(ROOT, "docs", "MOVES.md"), "w") as fh:
        fh.write("\n".join(out))
    print("wrote docs/MOVES.md")


if __name__ == "__main__":
    main()
