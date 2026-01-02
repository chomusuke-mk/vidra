#!/usr/bin/env python3
"""Resolve latest yt-dlp/yt-dlp-ejs versions and emit CI-friendly outputs.

The script prints key=value lines and can also append them to the GitHub
Actions output file when --github-output is provided. It additionally checks
whether the currently pinned versions in a requirements file match the latest
PyPI releases to decide if a rebuild should be triggered.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any, Optional, Sequence, Tuple


def fetch_latest(package: str) -> str:
    url = f"https://pypi.org/pypi/{package}/json"
    with urllib.request.urlopen(url, timeout=20) as resp:
        data = json.load(resp)
    return data["info"]["version"]


def github_json(url: str, token: Optional[str]) -> Optional[Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "vidra-version-check",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:  # pragma: no cover - network behavior
        if exc.code == 404:
            return None
        raise


def release_has_assets(repo: Optional[str], tag: str, token: Optional[str]) -> bool:
    if not repo or not tag:
        return False
    url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    data = github_json(url, token)
    if not data:
        return False
    assets = data.get("assets") or []
    names = {a.get("name") for a in assets if isinstance(a, dict)}
    required = {
        "_update",
        "SHA2-256SUMS",
        "SHA2-256SUMS.sig",
        "SHA2-512SUMS",
        "SHA2-512SUMS.sig",
    }
    return required.issubset(names)


def fetch_update_asset(
    repo: Optional[str], token: Optional[str]
) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str]]:
    """Return (tag, app_version, yt_dlp, yt_dlp_ejs) from newest release that has _update asset."""
    if not repo:
        return None, None, None, None

    def download_asset_text(asset: dict) -> Optional[str]:
        # Prefer the GitHub API asset URL so the Authorization header is honored
        # (browser_download_url often redirects and urllib can drop auth headers).
        asset_api_url = asset.get("url")
        if token and asset_api_url:
            req = urllib.request.Request(
                asset_api_url,
                headers={
                    "Accept": "application/octet-stream",
                    "Authorization": f"Bearer {token}",
                    "User-Agent": "vidra-version-check",
                    "X-GitHub-Api-Version": "2022-11-28",
                },
            )
        else:
            dl_url = asset.get("browser_download_url")
            if not dl_url:
                return None
            req = urllib.request.Request(
                dl_url,
                headers={"User-Agent": "vidra-version-check"},
            )

        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return resp.read().decode("utf-8", errors="ignore")
        except Exception:
            return None

    url = f"https://api.github.com/repos/{repo}/releases?per_page=20"
    releases: list[dict] = github_json(url, token) or []  # type: ignore[assignment]
    for rel in releases:
        # Prefer published releases; drafts may have incomplete assets.
        if rel.get("draft") is True:
            continue
        tag = rel.get("tag_name") or ""
        assets = rel.get("assets") or []
        for asset in assets:
            if asset.get("name") == "_update":
                content = download_asset_text(asset)
                if not content:
                    continue
                version_match = re.search(
                    r"^version=([^\n]+)$", content, flags=re.MULTILINE
                )
                ytdlp_match = re.search(
                    r"^yt-dlp=([^\n]+)$", content, flags=re.MULTILINE
                )
                ytdlpejs_match = re.search(
                    r"^yt-dlp-ejs=([^\n]+)$", content, flags=re.MULTILINE
                )
                if version_match:
                    return (
                        tag,
                        version_match.group(1).strip(),
                        ytdlp_match.group(1).strip() if ytdlp_match else None,
                        ytdlpejs_match.group(1).strip() if ytdlpejs_match else None,
                    )
    return None, None, None, None


def list_release_versions(repo: Optional[str], token: Optional[str]) -> Sequence[str]:
    if not repo:
        return []
    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
    data: list[dict] = github_json(url, token) or []  # type: ignore[assignment]
    versions = []
    for entry in data:
        tag = entry.get("tag_name") or ""
        if re.match(r"^\d+\.\d+\.\d+$", tag):
            versions.append(tag)
    return versions


def read_pinned(requirements_path: pathlib.Path) -> Tuple[Optional[str], Optional[str]]:
    text = requirements_path.read_text(encoding="utf-8")

    def find(pkg: str) -> Optional[str]:
        pattern = rf"^{re.escape(pkg)}==([\w.-]+)$"
        match = re.search(pattern, text, flags=re.MULTILINE)
        return match.group(1) if match else None

    return find("yt-dlp"), find("yt-dlp-ejs")


def read_app_version(pubspec_path: pathlib.Path) -> str:
    text = pubspec_path.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([\w.-]+)", text, flags=re.MULTILINE)
    return match.group(1) if match else "0.0.0"


def normalize_version(version_str: str) -> Tuple[int, int, int]:
    base = version_str.split("+")[0]
    parts = base.split(".")
    if len(parts) != 3:
        return (0, 0, 0)
    return tuple(int(x) for x in parts)  # type: ignore[return-value]


def format_version(parts: Tuple[int, int, int]) -> str:
    return f"{parts[0]}.{parts[1]}.{parts[2]}"


def parse_build(version_str: str) -> int:
    if "+" not in version_str:
        return 0
    try:
        return int(version_str.split("+")[1])
    except ValueError:
        return 0


def next_patch(base: Tuple[int, int, int], existing: Sequence[str]) -> str:
    major, minor, patch = base
    max_patch = patch
    for ver in existing:
        m2, n2, p2 = normalize_version(ver)
        if m2 == major and n2 == minor and p2 > max_patch:
            max_patch = p2
    return format_version((major, minor, max_patch + 1))


def write_outputs(outputs: dict, github_output: Optional[pathlib.Path]) -> None:
    lines = [f"{k}={v}" for k, v in outputs.items()]
    sys.stdout.write("\n".join(lines) + "\n")
    if github_output:
        with github_output.open("a", encoding="utf-8", errors="ignore") as fh:
            fh.write("\n".join(lines) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve yt-dlp versions for CI")
    parser.add_argument(
        "--requirements",
        type=pathlib.Path,
        default=pathlib.Path("app/requirements.txt"),
    )
    parser.add_argument(
        "--pubspec", type=pathlib.Path, default=pathlib.Path("pubspec.yaml")
    )
    parser.add_argument(
        "--github-output",
        type=pathlib.Path,
        default=None,
        help="Path from GITHUB_OUTPUT env",
    )
    parser.add_argument(
        "--github-repo",
        type=str,
        default=os.environ.get("GITHUB_REPOSITORY"),
        help="owner/repo string; defaults to GITHUB_REPOSITORY env",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    github_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

    latest_ytdlp = fetch_latest("yt-dlp")
    latest_ytdlpejs = fetch_latest("yt-dlp-ejs")

    pinned_ytdlp, pinned_ytdlpejs = read_pinned(args.requirements)
    pubspec_version_str = read_app_version(args.pubspec)
    base_version_parts = normalize_version(pubspec_version_str)
    pubspec_build = parse_build(pubspec_version_str)

    existing_versions = list_release_versions(args.github_repo, github_token)

    prev_tag, prev_version_with_build, prev_ytdlp, prev_ytdlpejs = fetch_update_asset(
        args.github_repo, github_token
    )

    # Primary signal: compare against the versions actually used in the most
    # recent published release (from the `_update` asset).
    deps_changed_vs_release = (
        prev_ytdlp is not None and prev_ytdlp != latest_ytdlp
    ) or (prev_ytdlpejs is not None and prev_ytdlpejs != latest_ytdlpejs)

    # Fallback: compare pinned requirements (useful when no previous release exists
    # or when older releases didn't include yt-dlp keys in `_update`).
    deps_changed_vs_pins = (pinned_ytdlp != latest_ytdlp) or (
        pinned_ytdlpejs != latest_ytdlpejs
    )

    deps_changed = deps_changed_vs_release or deps_changed_vs_pins

    if deps_changed:
        candidate_version = next_patch(base_version_parts, existing_versions)
    else:
        base_formatted = format_version(base_version_parts)
        if base_formatted in existing_versions:
            candidate_version = next_patch(base_version_parts, existing_versions)
        else:
            candidate_version = base_formatted

    prev_build = parse_build(prev_version_with_build or "")
    build_number = max(pubspec_build, prev_build + 1)
    app_version_full = f"{candidate_version}+{build_number}"

    release_assets_present = release_has_assets(
        args.github_repo, candidate_version, github_token
    )

    should_build = (
        deps_changed
        or not release_assets_present
        or candidate_version not in existing_versions
    )

    timestamp = datetime.now(timezone.utc).isoformat()

    outputs = {
        "ytdlp": latest_ytdlp,
        "ytdlpejs": latest_ytdlpejs,
        "prev_release_tag": prev_tag or "",
        "prev_release_ytdlp": prev_ytdlp or "",
        "prev_release_ytdlpejs": prev_ytdlpejs or "",
        "app_version": app_version_full,
        "tag": candidate_version,
        "timestamp": timestamp,
        "build_number": str(build_number),
        "should_build": "true" if should_build else "false",
        "release_assets_present": "true" if release_assets_present else "false",
    }

    write_outputs(outputs, args.github_output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
