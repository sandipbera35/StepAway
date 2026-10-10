#!/usr/bin/env python3
"""Regenerates PRIVACY.md from ui/lib/src/legal.dart so the repository copy and the in-app
policy cannot drift apart. Run from the repository root: python3 tools/gen-privacy-md.py"""
import re
from pathlib import Path

src = Path("ui/lib/src/legal.dart").read_text()


def const_str(name):
    m = re.search(r"const %s\s*=\s*((?:\s*'(?:[^'\\]|\\.)*'\s*)+);" % name, src)
    return m.group(1) if m else None


def dart_literal(chunk):
    """Joins adjacent Dart string literals and resolves the escapes and $interpolations we use."""
    parts = re.findall(r"'((?:[^'\\]|\\.)*)'", chunk)
    text = "".join(parts)
    text = text.replace("\\'", "'").replace("\\\\", "\\").replace("\\u00a9", "©").replace("\\u2192", "→")
    return text


consts = {}
for name in ["kIssuesUrl", "kSecurityUrl", "kPrivacyUrl", "kPrivacyUpdated", "kHomepageUrl"]:
    m = re.search(r"const %s\s*=\s*\n?\s*'([^']*)';" % name, src)
    consts[name] = m.group(1)


def resolve(text):
    for k, v in consts.items():
        text = text.replace("$" + k, v)
    return text


summary = resolve(dart_literal(const_str("privacySummary")))
sections = []
for m in re.finditer(r"LegalSection\('((?:[^'\\]|\\.)*)',\s*\[(.*?)\]\),", src, re.S):
    title = dart_literal("'" + m.group(1) + "'")
    paras = [resolve(dart_literal(p)) for p in re.findall(r"((?:\s*'(?:[^'\\]|\\.)*'\s*)+),", m.group(2) + ",")]
    sections.append((title, paras))

out = ["# StepAway privacy policy", "", f"_Last updated: {consts['kPrivacyUpdated']}_", "", f"**{summary}**", ""]
for i, (title, paras) in enumerate(sections, 1):
    out += [f"## {i}. {title}", ""]
    for p in paras:
        out += [p, ""]
out += ["---", "", "This file is generated from `ui/lib/src/legal.dart`, the same text shown inside the apps (About → Privacy policy). Edit that file and run `python3 tools/gen-privacy-md.py`.", ""]
Path("PRIVACY.md").write_text("\n".join(out))
print(f"PRIVACY.md written with {len(sections)} sections")
