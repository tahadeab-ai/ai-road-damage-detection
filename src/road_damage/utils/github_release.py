"""
Automated GitHub Releases asset delivery pipeline.
Publishes trained weights, ONNX exports, and evaluation reports directly to GitHub Releases.
"""

import json
import mimetypes
import os
from pathlib import Path
from typing import Any, Dict, List, Optional
import urllib.parse
import requests


class GitHubReleasePublisher:
    """
    Automates GitHub Release creation and asset uploads via the GitHub REST API.
    """

    def __init__(
        self,
        token: Optional[str] = None,
        repository: Optional[str] = None,
        tag_name: str = "v1.0.0-weights",
        release_name: Optional[str] = None,
        description: Optional[str] = None,
    ):
        # 1. Fetch token securely from environment or Colab userdata
        self.token = token or os.getenv("GITHUB_TOKEN")
        if not self.token:
            try:
                from google.colab import userdata
                self.token = userdata.get("GITHUB_TOKEN")
            except Exception:
                pass

        # 2. Fetch repository securely
        self.repository = repository or os.getenv("GITHUB_REPOSITORY")
        if not self.repository:
            try:
                from google.colab import userdata
                self.repository = userdata.get("GITHUB_REPOSITORY")
            except Exception:
                pass

        self.tag_name = tag_name
        self.release_name = release_name or f"AI Road Damage Detection - Weights & Benchmarks ({tag_name})"
        self.description = description or (
            "Automated artifact release containing best YOLO checkpoints (best.pt), "
            "ONNX export, confusion matrix, PR curves, and evaluation metrics summary."
        )

        self.api_base = "https://api.github.com"
        self.headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if self.token:
            self.headers["Authorization"] = f"Bearer {self.token}"

    def verify_credentials(self) -> bool:
        """Verifies if token and repository are available and valid."""
        if not self.token or not self.repository:
            print(
                "Notice: GITHUB_TOKEN or GITHUB_REPOSITORY is missing. "
                "Set these environment variables or Colab Secrets to enable direct Release asset publishing."
            )
            return False
        return True

    def get_or_create_release(self) -> Dict[str, Any]:
        """
        Retrieves existing release for tag or creates a new one.
        """
        if not self.verify_credentials():
            raise ValueError("GitHub credentials missing.")

        url = f"{self.api_base}/repos/{self.repository}/releases/tags/{self.tag_name}"
        res = requests.get(url, headers=self.headers, timeout=30)

        if res.status_code == 200:
            print(f"Found existing release for tag '{self.tag_name}'.")
            return res.json()

        # Create new release
        print(f"Creating new GitHub Release '{self.tag_name}' in repository '{self.repository}'...")
        create_url = f"{self.api_base}/repos/{self.repository}/releases"
        payload = {
            "tag_name": self.tag_name,
            "target_commitish": "main",
            "name": self.release_name,
            "body": self.description,
            "draft": False,
            "prerelease": False,
        }

        create_res = requests.post(create_url, headers=self.headers, json=payload, timeout=30)
        create_res.raise_for_status()
        release_data = create_res.json()
        print(f"Successfully created release: {release_data.get('html_url')}")
        return release_data

    def upload_asset(self, release_id: int, file_path: str | Path) -> Optional[Dict[str, Any]]:
        """
        Uploads an asset file to a GitHub release.
        """
        path = Path(file_path)
        if not path.is_file():
            print(f"Warning: File to upload does not exist: {path}")
            return None

        # Clean existing asset with same name if already present
        self._delete_asset_if_exists(release_id, path.name)

        upload_url = f"https://uploads.github.com/repos/{self.repository}/releases/{release_id}/assets?name={urllib.parse.quote(path.name)}"
        content_type, _ = mimetypes.guess_type(str(path))
        content_type = content_type or "application/octet-stream"

        headers = self.headers.copy()
        headers["Content-Type"] = content_type

        print(f"Uploading asset '{path.name}' ({path.stat().st_size / (1024*1024):.2f} MB)...")
        with open(path, "rb") as f:
            res = requests.post(upload_url, headers=headers, data=f, timeout=120)

        if res.status_code in (200, 201):
            asset_info = res.json()
            print(f"Uploaded {path.name}: {asset_info.get('browser_download_url')}")
            return asset_info
        else:
            print(f"Failed to upload {path.name} (Status {res.status_code}): {res.text}")
            return None

    def _delete_asset_if_exists(self, release_id: int, asset_name: str) -> None:
        """Removes existing asset with matching name to allow overwriting."""
        list_url = f"{self.api_base}/repos/{self.repository}/releases/{release_id}/assets"
        res = requests.get(list_url, headers=self.headers, timeout=30)
        if res.status_code == 200:
            for asset in res.json():
                if asset.get("name") == asset_name:
                    del_url = f"{self.api_base}/repos/{self.repository}/releases/assets/{asset.get('id')}"
                    requests.delete(del_url, headers=self.headers, timeout=30)
                    break

    def publish_bundle(
        self,
        best_pt: Optional[str | Path] = None,
        model_onnx: Optional[str | Path] = None,
        confusion_matrix: Optional[str | Path] = None,
        results_curves: Optional[str | Path] = None,
        evaluation_summary: Optional[str | Path] = None,
    ) -> Dict[str, Any]:
        """
        Publishes the standard artifact bundle to GitHub Releases.
        """
        if not self.verify_credentials():
            return {"status": "skipped", "reason": "No credentials supplied"}

        release = self.get_or_create_release()
        release_id = release["id"]

        uploaded_assets = {}
        files_to_upload = {
            "best.pt": best_pt,
            "model.onnx": model_onnx,
            "confusion_matrix.png": confusion_matrix,
            "results.png": results_curves,
            "evaluation_summary.json": evaluation_summary,
        }

        for name, fpath in files_to_upload.items():
            if fpath and Path(fpath).exists():
                asset_data = self.upload_asset(release_id, fpath)
                if asset_data:
                    uploaded_assets[name] = asset_data.get("browser_download_url")

        return {
            "status": "success",
            "release_url": release.get("html_url"),
            "assets": uploaded_assets,
        }
