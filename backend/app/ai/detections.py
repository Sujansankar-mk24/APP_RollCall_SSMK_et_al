"""
Small data containers shared by the AI modules.
"""

from dataclasses import dataclass, field


@dataclass
class Detection:
    """One thing found in an image, with a box around it."""

    label: str         # "person", "fire" or "smoke"
    confidence: float  # 0.0 to 1.0
    box: tuple[int, int, int, int]  # (x1, y1, x2, y2) in pixels: top-left and bottom-right corners


@dataclass
class FireSmokeResult:
    """What a fire detector reports for one frame."""

    fire_detected: bool = False
    fire_confidence: float = 0.0
    smoke_detected: bool = False
    smoke_confidence: float = 0.0
    fire_area: float = 0.0  # share of the picture covered by flames, 0.0 to 1.0
    boxes: list[Detection] = field(default_factory=list)
