"""
Adaptive low-light vision.

Many emergencies happen at night, and dark photos make AI detectors miss people.
So before detecting, we measure how bright the photo is. If it is dark, we
boost its contrast with CLAHE ("Contrast Limited Adaptive Histogram
Equalization"): the image is split into small tiles and each tile's contrast
is stretched separately, so dark areas get brighter without blowing out lights
like flames or headlights. We record that this happened so responders know.
"""

import cv2
import numpy as np

from app.config import LOW_LIGHT_BRIGHTNESS


def measure_brightness(frame: np.ndarray) -> float:
    """Average brightness of the image: 0 = black, 255 = white."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return float(gray.mean())


def enhance_low_light(frame: np.ndarray) -> np.ndarray:
    """
    Brighten a dark image with CLAHE.

    We convert to LAB color space, where "L" is lightness and "A"/"B" are color.
    Enhancing only L brightens the image without shifting its colors.
    """
    lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
    lightness, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    lab = cv2.merge((clahe.apply(lightness), a, b))
    return cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)


def prepare_for_detection(frame: np.ndarray) -> tuple[np.ndarray, float, bool]:
    """
    Returns (image to run detection on, brightness, whether enhancement was used).
    """
    brightness = measure_brightness(frame)
    if brightness < LOW_LIGHT_BRIGHTNESS:
        return enhance_low_light(frame), brightness, True
    return frame, brightness, False
