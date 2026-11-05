"""
Sequence-Aware Split Generator for Road Damage Datasets.
Prevents data leakage by grouping continuous dashcam frames by route/sequence key.
"""

from collections import defaultdict
import math
from pathlib import Path
import random
import re
from typing import Dict, List, Set, Tuple


class SequenceSplitGenerator:
    """
    Splits dataset into Train, Val, and Test partitions grouped strictly
    by route or driving sequence to prevent temporal and spatial leakage.
    """

    def __init__(
        self,
        train_ratio: float = 0.70,
        val_ratio: float = 0.15,
        test_ratio: float = 0.15,
        seed: int = 42,
    ):
        total = train_ratio + val_ratio + test_ratio
        if not math.isclose(total, 1.0, rel_tol=1e-5):
            raise ValueError(f"Split ratios must sum to 1.0, got {total}")

        self.train_ratio = train_ratio
        self.val_ratio = val_ratio
        self.test_ratio = test_ratio
        self.seed = seed

    @staticmethod
    def extract_sequence_key(filename_or_path: str | Path) -> str:
        """
        Extracts a sequence / route grouping key from the filename.
        
        Examples:
            'Japan_001234.jpg' -> 'Japan_0012' (grouping chunks of ~100 contiguous frames)
            'India_RouteA_005.jpg' -> 'India_RouteA'
            'Czech_20220915_042.jpg' -> 'Czech_20220915'
        """
        stem = Path(filename_or_path).stem

        # Case 1: Explicit route/session token separated by underscore/hyphen
        # e.g., Country_RouteX_0001 -> Country_RouteX
        match_named_route = re.match(r"^([A-Za-z]+_[A-Za-z0-9]+)_[0-9]+$", stem)
        if match_named_route:
            return match_named_route.group(1)

        # Case 2: Country_Number format (RDD2022 standard e.g. Japan_005123)
        # Dashcam frames are captured sequentially. Group into contiguous blocks of 100 frames.
        match_country_num = re.match(r"^([A-Za-z]+)_(\d+)$", stem)
        if match_country_num:
            country = match_country_num.group(1)
            num_str = match_country_num.group(2)
            # Group by integer bucket of 100 consecutive frames
            num_val = int(num_str)
            bucket_id = num_val // 100
            return f"{country}_block_{bucket_id:04d}"

        # Fallback: Prefix before last delimiter
        parts = stem.split("_")
        if len(parts) > 1:
            return "_".join(parts[:-1])
        return stem

    def partition_files(
        self,
        file_list: List[str | Path],
    ) -> Dict[str, List[Path]]:
        """
        Partitions input file paths into 'train', 'val', 'test' sets without sequence leakage.
        """
        paths = [Path(p) for p in file_list]
        groups: Dict[str, List[Path]] = defaultdict(list)

        for p in paths:
            seq_key = self.extract_sequence_key(p)
            groups[seq_key].append(p)

        # Shuffle unique sequence keys deterministically
        rng = random.Random(self.seed)
        sequence_keys = sorted(list(groups.keys()))
        rng.shuffle(sequence_keys)

        total_files = len(paths)
        target_train_count = int(total_files * self.train_ratio)
        target_val_count = int(total_files * self.val_ratio)

        train_files: List[Path] = []
        val_files: List[Path] = []
        test_files: List[Path] = []

        for key in sequence_keys:
            key_files = groups[key]
            if len(train_files) < target_train_count:
                train_files.extend(key_files)
            elif len(val_files) < target_val_count:
                val_files.extend(key_files)
            else:
                test_files.extend(key_files)

        # Verify zero leakage
        self.verify_no_leakage(train_files, val_files, test_files)

        return {
            "train": sorted(train_files),
            "val": sorted(val_files),
            "test": sorted(test_files),
        }

    @classmethod
    def verify_no_leakage(
        cls,
        train_files: List[Path],
        val_files: List[Path],
        test_files: List[Path],
    ) -> None:
        """
        Asserts that train, val, and test share zero common files and zero common sequence keys.
        """
        train_stems = {p.stem for p in train_files}
        val_stems = {p.stem for p in val_files}
        test_stems = {p.stem for p in test_files}

        # Check file overlap
        tv_overlap = train_stems.intersection(val_stems)
        tt_overlap = train_stems.intersection(test_stems)
        vt_overlap = val_stems.intersection(test_stems)

        if tv_overlap or tt_overlap or vt_overlap:
            raise AssertionError(
                f"Data leakage detected! File overlaps: "
                f"Train/Val: {len(tv_overlap)}, Train/Test: {len(tt_overlap)}, Val/Test: {len(vt_overlap)}"
            )

        # Check sequence key overlap
        train_keys = {cls.extract_sequence_key(p) for p in train_files}
        val_keys = {cls.extract_sequence_key(p) for p in val_files}
        test_keys = {cls.extract_sequence_key(p) for p in test_files}

        key_tv = train_keys.intersection(val_keys)
        key_tt = train_keys.intersection(test_keys)
        key_vt = val_keys.intersection(test_keys)

        if key_tv or key_tt or key_vt:
            raise AssertionError(
                f"Sequence leakage detected! Sequence groups overlap between partitions: "
                f"Train/Val: {key_tv}, Train/Test: {key_tt}, Val/Test: {key_vt}"
            )
