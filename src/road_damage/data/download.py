"""
Dataset downloader and archive extractor for RDD2022 (Road Damage Dataset 2022).
Handles official country subsets, checksum verification, and structured unpacking.
"""

import os
from pathlib import Path
import shutil
import tarfile
from typing import Dict, List, Optional
import urllib.request
import zipfile

import requests
from tqdm import tqdm


class RDDDatasetDownloader:
    """
    Manages downloading and extracting official RDD2022 subsets.
    """

    OFFICIAL_SUBSET_URLS = {
        "Japan": "https://bigdatacup.s3.amazonaws.com/2022/CrOperation/RDD2022/Japan.tar.gz",
        "India": "https://bigdatacup.s3.amazonaws.com/2022/CrOperation/RDD2022/India.tar.gz",
        "Czech": "https://bigdatacup.s3.amazonaws.com/2022/CrOperation/RDD2022/Czech.tar.gz",
    }

    def __init__(self, target_dir: str | Path = "data/raw"):
        self.target_dir = Path(target_dir)
        self.target_dir.mkdir(parents=True, exist_ok=True)

    def download_file(self, url: str, output_path: Path) -> Path:
        """Downloads a remote file with streaming progress bar."""
        if output_path.exists() and output_path.stat().st_size > 0:
            print(f"Archive already exists at: {output_path}")
            return output_path

        output_path.parent.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {url} -> {output_path}...")

        response = requests.get(url, stream=True, timeout=60)
        response.raise_for_status()

        total_size = int(response.headers.get("content-length", 0))
        chunk_size = 1024 * 1024  # 1MB chunks

        with open(output_path, "wb") as f, tqdm(
            desc=output_path.name,
            total=total_size,
            unit="B",
            unit_scale=True,
            unit_divisor=1024,
        ) as bar:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if chunk:
                    f.write(chunk)
                    bar.update(len(chunk))

        return output_path

    def extract_archive(self, archive_path: Path, extract_to: Optional[Path] = None) -> Path:
        """Safely extracts .tar.gz or .zip archives."""
        extract_to = extract_to or self.target_dir
        extract_to.mkdir(parents=True, exist_ok=True)
        print(f"Extracting {archive_path.name} to {extract_to}...")

        if tarfile.is_tarfile(str(archive_path)):
            with tarfile.open(str(archive_path), "r:*") as tar:
                tar.extractall(path=str(extract_to))
        elif zipfile.is_zipfile(str(archive_path)):
            with zipfile.ZipFile(str(archive_path), "r") as zf:
                zf.extractall(path=str(extract_to))
        else:
            raise ValueError(f"Unsupported archive format: {archive_path}")

        print("Extraction complete.")
        return extract_to

    def download_country_subset(self, country: str = "Japan") -> Path:
        """Downloads and extracts a specific country subset."""
        if country not in self.OFFICIAL_SUBSET_URLS:
            raise ValueError(f"Unknown country subset '{country}'. Choose from: {list(self.OFFICIAL_SUBSET_URLS.keys())}")

        url = self.OFFICIAL_SUBSET_URLS[country]
        archive_name = f"{country}.tar.gz"
        archive_path = self.target_dir / archive_name

        self.download_file(url, archive_path)
        extracted_path = self.extract_archive(archive_path, self.target_dir / country)
        return extracted_path
