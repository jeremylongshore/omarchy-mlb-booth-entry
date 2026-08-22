#!/usr/bin/env python3
"""Backfill a Keep a Changelog CHANGELOG.md from a repo's real commit history.

Written because seven plugin repos shipped v1.0.0 with no changelog at all. The
entries are derived from actual commit subjects rather than invented, so the
file is a record and not a story: if a line is here, a commit says so.

Conventional-commit type decides the section. `fix` whose scope or subject is
about a credential, a bound, an injection or an SSRF goes under Security rather
than Fixed, because "what did this fix protect me from" is the question a reader
of a plugin changelog is actually asking.
"""
import re
import subprocess
import sys
from pathlib import Path

SECURITY_HINT = re.compile(
    r"secur|token|credential|argv|ssrf|inject|unbounded|bound |leak|proc/|memory",
    re.I,
)


def commits(repo: Path):
    out = subprocess.run(
        ["git", "-C", str(repo), "log", "--reverse", "--pretty=%H%x1f%s%x1f%cI"],
        capture_output=True, text=True, check=True,
    ).stdout.strip().split("\n")
    for line in out:
        if not line:
            continue
        sha, subject, date = line.split("\x1f")
        yield sha, subject, date[:10]


def classify(subject: str):
    m = re.match(r"^(\w+)(?:\(([^)]*)\))?!?:\s*(.+)$", subject)
    if not m:
        return None, subject
    typ, scope, rest = m.group(1).lower(), (m.group(2) or ""), m.group(3)
    # Strip a trailing PR reference; the section is a record, not a link farm.
    rest = re.sub(r"\s*\(#\d+\)$", "", rest).strip()
    # Commit subjects predate the no-dash rule, but a CHANGELOG is shipped prose
    # and gate c28 blocks em and en dashes in it. Normalise here so a backfill
    # can never reintroduce them into a file the lane will refuse.
    rest = rest.replace(" — ", ": ").replace(" – ", ": ")
    rest = rest.replace("—", ", ").replace("–", ", ")
    if typ == "fix" and (SECURITY_HINT.search(scope) or SECURITY_HINT.search(rest)):
        return "Security", rest
    if typ == "feat":
        return "Added", rest
    if typ == "fix":
        return "Fixed", rest
    if typ in ("perf", "refactor", "style"):
        return "Changed", rest
    if typ in ("ci", "build", "chore", "test", "docs"):
        return "Internal", rest
    return "Changed", rest


def build(repo: Path, name: str, version: str) -> str:
    buckets = {k: [] for k in ("Added", "Changed", "Fixed", "Security", "Internal")}
    last_date = ""
    for _sha, subject, date in commits(repo):
        section, text = classify(subject)
        if section is None:
            continue
        last_date = date
        if text and text not in buckets[section]:
            buckets[section].append(text)

    lines = [
        "# Changelog",
        "",
        f"Notable changes to {name}.",
        "",
        "Entries are derived from this repository's commit history, so every line",
        "corresponds to a real change. The format follows Keep a Changelog and the",
        "project uses Semantic Versioning.",
        "",
        "## [Unreleased]",
        "",
        "Nothing yet.",
        "",
        f"## [{version}] - {last_date}",
        "",
    ]

    # Security first: on a desktop plugin it is the section a reader scans for.
    order = ["Security", "Added", "Changed", "Fixed", "Internal"]
    headings = {
        "Security": "### Security",
        "Added": "### Added",
        "Changed": "### Changed",
        "Fixed": "### Fixed",
        "Internal": "### Internal\n\nTooling and repository changes with no effect on the shipped plugin.",
    }
    for key in order:
        items = buckets[key]
        if not items:
            continue
        lines.append(headings[key])
        lines.append("")
        for it in items:
            lines.append(f"- {it[0].upper()}{it[1:]}" if it else "")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


if __name__ == "__main__":
    repo = Path(sys.argv[1])
    name = sys.argv[2]
    version = sys.argv[3]
    (repo / "CHANGELOG.md").write_text(build(repo, name, version), encoding="utf-8")
    print(f"wrote {repo.name}/CHANGELOG.md")
