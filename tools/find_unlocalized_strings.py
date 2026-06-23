#!/usr/bin/env python3
"""Detect potentially non-localized string literals in lib/ and app/.

The heuristic follows the user's rules:
- Only consider literals longer than 3 chars within single/double quotes.
- Skip strings that start with package:/dart: or belong to import/from clauses.
- Skip literals containing underscores but no spaces, or those entirely uppercase.
- Skip literals immediately inside [] containers.
- Skip literals whose preceding token is `case` or `==`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List

STRING_RE = re.compile(r"('([^'\\]|\\.)*'|\"([^\"\\]|\\.)*\")")
VALID_SUFFIXES = {".dart", ".py"}


def is_all_upper(text: str) -> bool:
    letters = [ch for ch in text if ch.isalpha()]
    return bool(letters) and all(ch.isupper() for ch in letters)


def should_skip(body: str, prefix: str) -> bool:
    trimmed_prefix = prefix.rstrip()
    if len(body) <= 3:
        return True
    if body.startswith(("package:", "dart:")):
        return True
    if re.search(r"\b(import|from)\s*$", trimmed_prefix):
        return True
    if "_" in body and " " not in body:
        return True
    if is_all_upper(body):
        return True
    if trimmed_prefix.endswith("["):
        return True
    if re.search(r"(case|==)\s*$", trimmed_prefix):
        return True
    return False


@dataclass
class Finding:
    path: Path
    line: int
    literal: str

    def to_dict(self) -> Dict[str, object]:
        return {"path": str(self.path), "line": self.line, "literal": self.literal}


def iter_files(root_dirs: Iterable[Path]) -> Iterator[Path]:
    for root in root_dirs:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix in VALID_SUFFIXES and path.is_file():
                yield path


def scan_file(path: Path) -> List[Finding]:
    findings: List[Finding] = []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return findings
    for lineno, line in enumerate(text.splitlines(), 1):
        for match in STRING_RE.finditer(line):
            literal = match.group(0)
            body = literal[1:-1]
            prefix = line[: match.start()]
            if should_skip(body, prefix):
                continue
            if body.strip() == "":
                continue
            findings.append(Finding(path=path, line=lineno, literal=body))
    return findings


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[Path("lib"), Path("app")],
        help="Directories to scan (default: lib and app)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON array instead of plain text",
    )
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parents[1]
    roots = [repo_root / rel for rel in args.paths]

    findings: List[Finding] = []
    for file_path in iter_files(roots):
        findings.extend(scan_file(file_path))

    findings.sort(key=lambda f: (str(f.path), f.line, f.literal))

    if args.json:
        json.dump([f.to_dict() for f in findings], sys.stdout, indent=2)
    else:
        for finding in findings:
            rel_path = finding.path.relative_to(repo_root)
            print(f"{rel_path}:{finding.line}: {finding.literal}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
