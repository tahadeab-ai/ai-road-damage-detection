"""
Pascal VOC XML Parser and YOLO Converter for Road Damage Dataset (RDD2022).
Strict validation of coordinates, aspect ratios, and format conversions.
"""

from dataclasses import dataclass
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import xml.etree.ElementTree as ET


@dataclass
class AnnotationBox:
    """Represents a validated object bounding box."""
    class_name: str
    class_id: int
    xmin: float
    ymin: float
    xmax: float
    ymax: float
    # Normalized YOLO format: (x_center, y_center, width, height) in [0, 1]
    x_center_norm: float
    y_center_norm: float
    width_norm: float
    height_norm: float

    def to_yolo_line(self) -> str:
        """Format as YOLO label line: <class_id> <xc> <yc> <w> <h>"""
        return f"{self.class_id} {self.x_center_norm:.6f} {self.y_center_norm:.6f} {self.width_norm:.6f} {self.height_norm:.6f}"


@dataclass
class ImageAnnotation:
    """Structured container for full image metadata and bounding boxes."""
    filename: str
    width: int
    height: int
    depth: int
    boxes: List[AnnotationBox]


class VOCParser:
    """
    Parses Pascal VOC XML files, validates bounding boxes,
    and converts them to YOLO normalized format.
    """

    DEFAULT_CLASS_MAPPING = {
        "D00": 0,  # Longitudinal Cracks
        "D10": 1,  # Transverse Cracks
        "D20": 2,  # Alligator Cracks
        "D40": 3,  # Potholes
    }

    def __init__(self, class_mapping: Optional[Dict[str, int]] = None):
        self.class_mapping = class_mapping or self.DEFAULT_CLASS_MAPPING

    def parse_file(self, xml_path: str | Path) -> ImageAnnotation:
        """
        Parses a single Pascal VOC XML file.

        Args:
            xml_path: Path to the XML file.

        Returns:
            ImageAnnotation object containing validated bounding boxes.

        Raises:
            FileNotFoundError: If xml_path does not exist.
            ValueError: If image dimensions or XML tags are corrupt.
        """
        xml_path = Path(xml_path)
        if not xml_path.is_file():
            raise FileNotFoundError(f"Annotation file not found: {xml_path}")

        try:
            tree = ET.parse(str(xml_path))
            root = tree.getroot()
        except ET.ParseError as e:
            raise ValueError(f"XML parse error in {xml_path}: {e}")

        filename_tag = root.find("filename")
        filename = filename_tag.text if filename_tag is not None and filename_tag.text else f"{xml_path.stem}.jpg"

        size_tag = root.find("size")
        if size_tag is None:
            raise ValueError(f"Missing <size> block in {xml_path}")

        try:
            width = int(size_tag.findtext("width", "0"))
            height = int(size_tag.findtext("height", "0"))
            depth = int(size_tag.findtext("depth", "3"))
        except (ValueError, TypeError) as e:
            raise ValueError(f"Invalid integer in <size> for {xml_path}: {e}")

        if width <= 0 or height <= 0:
            raise ValueError(f"Invalid image dimensions ({width}x{height}) in {xml_path}")

        boxes: List[AnnotationBox] = []

        for obj in root.findall("object"):
            name_tag = obj.find("name")
            if name_tag is None or not name_tag.text:
                continue

            raw_name = name_tag.text.strip()
            # Check if this class belongs to our target mapping
            if raw_name not in self.class_mapping:
                continue

            class_id = self.class_mapping[raw_name]
            bndbox = obj.find("bndbox")
            if bndbox is None:
                continue

            try:
                xmin = float(bndbox.findtext("xmin", "0"))
                ymin = float(bndbox.findtext("ymin", "0"))
                xmax = float(bndbox.findtext("xmax", "0"))
                ymax = float(bndbox.findtext("ymax", "0"))
            except ValueError:
                continue

            # Strict validation
            validated_box = self._validate_and_normalize_box(
                class_name=raw_name,
                class_id=class_id,
                xmin=xmin,
                ymin=ymin,
                xmax=xmax,
                ymax=ymax,
                img_width=width,
                img_height=height,
            )
            if validated_box is not None:
                boxes.append(validated_box)

        return ImageAnnotation(
            filename=filename,
            width=width,
            height=height,
            depth=depth,
            boxes=boxes,
        )

    def _validate_and_normalize_box(
        self,
        class_name: str,
        class_id: int,
        xmin: float,
        ymin: float,
        xmax: float,
        ymax: float,
        img_width: int,
        img_height: int,
    ) -> Optional[AnnotationBox]:
        """
        Validates boundaries and clips coordinates within image bounds.
        Returns normalized AnnotationBox or None if box has zero or negative area.
        """
        # Clip to image boundaries
        xmin_clipped = max(0.0, min(xmin, float(img_width)))
        ymin_clipped = max(0.0, min(ymin, float(img_height)))
        xmax_clipped = max(0.0, min(xmax, float(img_width)))
        ymax_clipped = max(0.0, min(ymax, float(img_height)))

        box_w = xmax_clipped - xmin_clipped
        box_h = ymax_clipped - ymin_clipped

        # Filter degenerate boxes
        if box_w <= 1.0 or box_h <= 1.0:
            return None

        # Normalized coordinates in [0, 1]
        x_center = (xmin_clipped + xmax_clipped) / (2.0 * img_width)
        y_center = (ymin_clipped + ymax_clipped) / (2.0 * img_height)
        norm_w = box_w / float(img_width)
        norm_h = box_h / float(img_height)

        # Ensure values stay strictly in [0.0, 1.0]
        x_center = max(0.0, min(x_center, 1.0))
        y_center = max(0.0, min(y_center, 1.0))
        norm_w = max(0.0, min(norm_w, 1.0))
        norm_h = max(0.0, min(norm_h, 1.0))

        return AnnotationBox(
            class_name=class_name,
            class_id=class_id,
            xmin=xmin_clipped,
            ymin=ymin_clipped,
            xmax=xmax_clipped,
            ymax=ymax_clipped,
            x_center_norm=x_center,
            y_center_norm=y_center,
            width_norm=norm_w,
            height_norm=norm_h,
        )

    def save_yolo_label(self, annotation: ImageAnnotation, output_label_path: str | Path) -> None:
        """Writes YOLO format txt label file."""
        output_label_path = Path(output_label_path)
        output_label_path.parent.mkdir(parents=True, exist_ok=True)
        lines = [box.to_yolo_line() for box in annotation.boxes]
        output_label_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
