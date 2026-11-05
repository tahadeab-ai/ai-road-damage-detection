"""
Visualizer utility for Road Damage Bounding Boxes.
Draws color-coded bounding boxes, labels, and generates comparison panels.
"""

from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

import cv2
import numpy as np

from road_damage.inference.predictor import InferenceResult


class RoadDamageVisualizer:
    """
    Renders styled bounding boxes and labels for Road Damage classes.
    """

    CLASS_COLORS: Dict[int, Tuple[int, int, int]] = {
        0: (255, 191, 0),   # D00: Deep Sky Blue / Cyan (BGR)
        1: (50, 205, 50),   # D10: Lime Green (BGR)
        2: (0, 140, 255),   # D20: Orange (BGR)
        3: (34, 34, 220),   # D40: Crimson Red (BGR)
    }

    @classmethod
    def draw_detections(
        cls,
        image: Union[str, Path, np.ndarray],
        inference_result: InferenceResult,
        output_path: Optional[Union[str, Path]] = None,
        line_thickness: int = 2,
    ) -> np.ndarray:
        """
        Overlays detection bounding boxes and confidence tags onto the image.
        """
        if isinstance(image, (str, Path)):
            canvas = cv2.imread(str(image))
            if canvas is None:
                raise ValueError(f"Unable to read image at: {image}")
        else:
            canvas = image.copy()

        for det in inference_result.detections:
            color = cls.CLASS_COLORS.get(det.class_id, (0, 255, 255))
            x1, y1, x2, y2 = det.bbox_xyxy

            # Draw rectangle
            cv2.rectangle(canvas, (x1, y1), (x2, y2), color, line_thickness)

            # Draw label banner
            label = f"{det.class_name} {det.confidence:.2f}"
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.5
            thickness = 1
            (text_w, text_h), baseline = cv2.getTextSize(label, font, font_scale, thickness)

            tag_y1 = max(0, y1 - text_h - baseline - 4)
            tag_y2 = y1
            tag_x2 = min(canvas.shape[1], x1 + text_w + 6)

            cv2.rectangle(canvas, (x1, tag_y1), (tag_x2, tag_y2), color, -1)
            cv2.putText(
                canvas,
                label,
                (x1 + 3, y1 - 4),
                font,
                font_scale,
                (255, 255, 255),
                thickness,
                lineType=cv2.LINE_AA,
            )

        if output_path is not None:
            out_p = Path(output_path)
            out_p.parent.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out_p), canvas)
            print(f"Annotated image saved to: {out_p}")

        return canvas
