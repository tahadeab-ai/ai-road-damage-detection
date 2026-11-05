"""
Unit tests for Pascal VOC XML parsing and YOLO label conversion.
"""

from pathlib import Path
import tempfile
import pytest
from road_damage.data.parser_voc import VOCParser


SAMPLE_VOC_XML = """<annotation>
    <folder>images</folder>
    <filename>Japan_000001.jpg</filename>
    <size>
        <width>600</width>
        <height>600</height>
        <depth>3</depth>
    </size>
    <object>
        <name>D00</name>
        <bndbox>
            <xmin>100</xmin>
            <ymin>150</ymin>
            <xmax>200</xmax>
            <ymax>350</ymax>
        </bndbox>
    </object>
    <object>
        <name>D40</name>
        <bndbox>
            <xmin>300</xmin>
            <ymin>400</ymin>
            <xmax>450</xmax>
            <ymax>550</ymax>
        </bndbox>
    </object>
    <object>
        <name>UnknownClass</name>
        <bndbox>
            <xmin>50</xmin>
            <ymin>50</ymin>
            <xmax>100</xmax>
            <ymax>100</ymax>
        </bndbox>
    </object>
</annotation>
"""

DEGENERATE_BOX_XML = """<annotation>
    <filename>invalid.jpg</filename>
    <size>
        <width>600</width>
        <height>600</height>
        <depth>3</depth>
    </size>
    <object>
        <name>D10</name>
        <bndbox>
            <xmin>100</xmin>
            <ymin>100</ymin>
            <xmax>100</xmax>
            <ymax>100</ymax>
        </bndbox>
    </object>
</annotation>
"""


def test_voc_parser_valid():
    parser = VOCParser()
    with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as f:
        f.write(SAMPLE_VOC_XML)
        temp_path = Path(f.name)

    try:
        annotation = parser.parse_file(temp_path)
        assert annotation.filename == "Japan_000001.jpg"
        assert annotation.width == 600
        assert annotation.height == 600
        # UnknownClass should be skipped, so 2 target boxes remain (D00 and D40)
        assert len(annotation.boxes) == 2

        # Check D00 box (class 0)
        box0 = annotation.boxes[0]
        assert box0.class_name == "D00"
        assert box0.class_id == 0
        # Check normalized coordinates
        assert 0.0 <= box0.x_center_norm <= 1.0
        assert 0.0 <= box0.y_center_norm <= 1.0
        assert 0.0 <= box0.width_norm <= 1.0
        assert 0.0 <= box0.height_norm <= 1.0
        # x_center = (100+200)/(2*600) = 150/600 = 0.25
        assert pytest.approx(box0.x_center_norm, 0.001) == 0.25
        # width = 100/600 = 0.166667
        assert pytest.approx(box0.width_norm, 0.001) == 0.166667

        # Test YOLO line formatting
        yolo_line = box0.to_yolo_line()
        parts = yolo_line.split()
        assert parts[0] == "0"
        assert len(parts) == 5

    finally:
        temp_path.unlink()


def test_voc_parser_degenerate_box_filtered():
    parser = VOCParser()
    with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as f:
        f.write(DEGENERATE_BOX_XML)
        temp_path = Path(f.name)

    try:
        annotation = parser.parse_file(temp_path)
        # Box with zero width/height should be rejected safely
        assert len(annotation.boxes) == 0
    finally:
        temp_path.unlink()
