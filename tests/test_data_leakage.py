"""
Unit tests for data leakage prevention across dataset splits.
"""

from pathlib import Path
import pytest
from road_damage.data.split_generator import SequenceSplitGenerator


def test_extract_sequence_key():
    # Test country numeric chunking (contiguous 100-frame chunks)
    key1 = SequenceSplitGenerator.extract_sequence_key("Japan_000105.jpg")
    key2 = SequenceSplitGenerator.extract_sequence_key("Japan_000199.jpg")
    key3 = SequenceSplitGenerator.extract_sequence_key("Japan_000201.jpg")

    assert key1 == key2 == "Japan_block_0001"
    assert key3 == "Japan_block_0002"
    assert key1 != key3

    # Test explicit named route formats
    key_route1 = SequenceSplitGenerator.extract_sequence_key("India_RouteA_001.jpg")
    key_route2 = SequenceSplitGenerator.extract_sequence_key("India_RouteA_099.jpg")
    key_route3 = SequenceSplitGenerator.extract_sequence_key("India_RouteB_001.jpg")

    assert key_route1 == key_route2 == "India_RouteA"
    assert key_route1 != key_route3


def test_sequence_partition_no_leakage():
    # Generate simulated dashcam frames across multiple routes
    simulated_files = []
    for route_id in range(10):
        for frame_idx in range(20):
            simulated_files.append(Path(f"Japan_{route_id:02d}_{frame_idx:04d}.jpg"))

    generator = SequenceSplitGenerator(train_ratio=0.7, val_ratio=0.15, test_ratio=0.15, seed=42)
    splits = generator.partition_files(simulated_files)

    assert "train" in splits
    assert "val" in splits
    assert "test" in splits

    # Total file count must match
    total_split_files = len(splits["train"]) + len(splits["val"]) + len(splits["test"])
    assert total_split_files == len(simulated_files)

    # Verification function must pass cleanly
    SequenceSplitGenerator.verify_no_leakage(splits["train"], splits["val"], splits["test"])


def test_leakage_detection_raises():
    # Create intentionally leaked splits
    train_files = [Path("Japan_000105.jpg"), Path("Japan_000150.jpg")]
    val_files = [Path("Japan_000188.jpg")]  # Belongs to same block as train!
    test_files = [Path("Japan_000500.jpg")]

    generator = SequenceSplitGenerator()
    with pytest.raises(AssertionError, match="Sequence leakage detected"):
        generator.verify_no_leakage(train_files, val_files, test_files)
