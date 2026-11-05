#!/usr/bin/env python3
"""
Build and Release Automation Script for RoadGuard Mobile APK.
Attaches the compiled Android release APK to the official GitHub Release tag.
"""

import argparse
import mimetypes
import os
from pathlib import Path
import subprocess
import sys
import urllib.parse
import requests


def get_github_token() -> str:
    token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    if not token:
        try:
            # Fallback to gh auth token
            res = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True)
            token = res.stdout.strip()
        except Exception:
            pass
    if not token:
        raise ValueError("GITHUB_TOKEN is missing. Please set GITHUB_TOKEN or authenticate via 'gh auth login'.")
    return token


def get_repository() -> str:
    repo = os.getenv("GITHUB_REPOSITORY")
    if not repo:
        try:
            # Inspect git remote origin
            res = subprocess.run(["git", "config", "--get", "remote.origin.url"], capture_output=True, text=True)
            url = res.stdout.strip()
            if "github.com" in url:
                if url.startswith("git@github.com:"):
                    repo = url.replace("git@github.com:", "").replace(".git", "")
                elif url.startswith("https://github.com/"):
                    repo = url.replace("https://github.com/", "").replace(".git", "")
        except Exception:
            pass
    return repo or "tahadeab-ai/ai-road-damage-detection"


def upload_apk_to_release(
    apk_path: Path,
    repository: str,
    tag_name: str = "v1.0.0-weights",
    asset_name: str = "RoadGuard-Mobile-v1.0.0.apk"
) -> str:
    if not apk_path.is_file():
        raise FileNotFoundError(f"APK binary not found at: {apk_path}")

    token = get_github_token()
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    api_base = "https://api.github.com"

    # 1. Fetch release details for tag
    print(f"Fetching release for tag '{tag_name}' in '{repository}'...")
    rel_url = f"{api_base}/repos/{repository}/releases/tags/{tag_name}"
    res = requests.get(rel_url, headers=headers, timeout=30)
    res.raise_for_status()
    release_data = res.json()
    release_id = release_data["id"]

    # 2. Check if asset already exists and delete to overwrite
    list_url = f"{api_base}/repos/{repository}/releases/{release_id}/assets"
    assets_res = requests.get(list_url, headers=headers, timeout=30)
    if assets_res.status_code == 200:
        for asset in assets_res.json():
            if asset.get("name") == asset_name:
                print(f"Removing existing asset '{asset_name}' (ID {asset['id']})...")
                del_url = f"{api_base}/repos/{repository}/releases/assets/{asset['id']}"
                requests.delete(del_url, headers=headers, timeout=30)
                break

    # 3. Upload new APK asset
    apk_size_mb = apk_path.stat().st_size / (1024 * 1024)
    print(f"Uploading '{asset_name}' ({apk_size_mb:.2f} MB) to {tag_name}...")
    upload_url = f"https://uploads.github.com/repos/{repository}/releases/{release_id}/assets?name={urllib.parse.quote(asset_name)}"
    
    upload_headers = headers.copy()
    upload_headers["Content-Type"] = "application/vnd.android.package-archive"
    upload_headers["Content-Length"] = str(apk_path.stat().st_size)
    print(f"Uploading '{asset_name}' ({apk_size_mb:.2f} MB, {apk_path.stat().st_size} bytes) to {tag_name}...", flush=True)

    try:
        # Prefer gh CLI if available for robust streamed upload
        gh_cmd = ["gh", "release", "upload", tag_name, f"{apk_path}#{asset_name}", "--repo", repository, "--clobber"]
        print(f"Executing: {' '.join(gh_cmd)}", flush=True)
        subprocess.run(gh_cmd, check=True)
        download_url = f"https://github.com/{repository}/releases/download/{tag_name}/{asset_name}"
        print(f"\nSuccessfully attached APK to release via gh: {download_url}", flush=True)
        return download_url
    except Exception as e:
        print(f"gh CLI upload fallback to REST API: {e}", flush=True)
        with open(apk_path, "rb") as f:
            upload_res = requests.post(upload_url, headers=upload_headers, data=f, timeout=300)
        upload_res.raise_for_status()

    download_url = upload_res.json().get("browser_download_url")
    print(f"\nSuccessfully attached APK to release: {download_url}", flush=True)
    return download_url


def main():
    parser = argparse.ArgumentParser(description="Upload compiled RoadGuard Mobile APK to GitHub Releases.")
    parser.add_argument(
        "--apk-path",
        type=str,
        default="mobile_app/build/app/outputs/flutter-apk/app-release.apk",
        help="Path to compiled app-release.apk"
    )
    parser.add_argument(
        "--tag",
        type=str,
        default="v1.0.0-weights",
        help="Target GitHub Release tag name"
    )
    parser.add_argument(
        "--asset-name",
        type=str,
        default="RoadGuard-Mobile-v1.0.0.apk",
        help="Name of the asset when uploaded"
    )

    args = parser.parse_args()
    repo = get_repository()
    upload_apk_to_release(
        apk_path=Path(args.apk_path),
        repository=repo,
        tag_name=args.tag,
        asset_name=args.asset_name,
    )


if __name__ == "__main__":
    main()
