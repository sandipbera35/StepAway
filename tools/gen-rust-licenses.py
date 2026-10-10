#!/usr/bin/env python3
"""Writes THIRD_PARTY_LICENSES.txt: every Rust crate the daemon is built from (Linux and Windows
targets), with its license and the license/notice files shipped in the crate. Flutter's own
packages are listed at run time by the apps' "Open-source licenses" page.
Run from the repository root after `cargo fetch`: python3 tools/gen-rust-licenses.py"""
import json
import subprocess
from pathlib import Path

LICENSE_NAMES = ("LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE")


def metadata(target):
    out = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--filter-platform", target],
        cwd="daemon", check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


packages = {}
for target in ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "x86_64-pc-windows-gnu"):
    md = metadata(target)
    ids = {n["id"] for n in md["resolve"]["nodes"]}
    workspace = set(md["workspace_members"])
    for p in md["packages"]:
        if p["id"] in ids and p["id"] not in workspace:
            packages[(p["name"], p["version"])] = p

lines = [
    "StepAway third-party software",
    "=============================",
    "",
    "StepAway's background service is built from the Rust crates below. Each is used under the",
    "license shown. The license texts shipped with each crate follow.",
    "",
]
texts = {}
for (name, version), p in sorted(packages.items()):
    lic = p.get("license") or p.get("license_file") or "see crate"
    lines.append(f"- {name} {version} ({lic}) {p.get('repository') or ''}".rstrip())
    root = Path(p["manifest_path"]).parent
    for f in sorted(root.iterdir()):
        if f.is_file() and f.name.upper().startswith(LICENSE_NAMES):
            try:
                t = f.read_text(errors="replace").strip()
            except OSError:
                continue
            texts.setdefault(t, []).append(f"{name} {version}")

lines += ["", "", "License texts", "-------------", ""]
for t, owners in sorted(texts.items(), key=lambda kv: kv[1][0]):
    lines += ["=" * 78, "Used by: " + ", ".join(sorted(set(owners))[:12]) + (" ..." if len(set(owners)) > 12 else ""), "=" * 78, t, ""]
Path("THIRD_PARTY_LICENSES.txt").write_text("\n".join(lines))
Path("desktop/assets").mkdir(exist_ok=True)
Path("desktop/assets/THIRD_PARTY_LICENSES.txt").write_text("\n".join(lines))
print(f"{len(packages)} crates, {len(texts)} distinct license texts")
