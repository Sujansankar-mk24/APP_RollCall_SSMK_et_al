"""
Fire and smoke detection.

This is "pluggable": the rest of the app only calls get_fire_detector().detect(...)
and doesn't care which detector is behind it.

  * If a trained model exists at models/fire.pt, we use it (most accurate).
  * Otherwise we use BasicFireDetector, a hand-written OpenCV rule based on
    color and flicker. It is labeled "basic detector" in every result so nobody
    mistakes it for a trained model.
"""

from functools import lru_cache
from typing import Optional, Protocol, Sequence

import cv2
import numpy as np

from app.ai.detections import Detection, FireSmokeResult
from app.config import FIRE_MODEL_PATH

BASIC_DETECTOR_NAME = "basic detector"


class FireDetector(Protocol):
    """Anything with a `name` and this `detect` method can be used as the fire detector."""

    name: str

    def detect(self, frame: np.ndarray, next_frame: Optional[np.ndarray] = None,
               people: Sequence[Detection] = ()) -> FireSmokeResult:
        """
        frame: the image to check.
        next_frame: (videos only) a frame ~0.1 s later, used to see flames flicker.
        people: where YOLO found people, so flame-colored clothing can be ignored.
        """
        ...


# ---------------------------------------------------------------------------
# Option 1: the basic detector (no training needed)
# ---------------------------------------------------------------------------

class BasicFireDetector:
    """
    FIRE, in two passes:
      1. Find "flame-colored" pixels: bright, red/orange/yellow, with red > green > blue.
      2. Group them into patches and keep a patch only if it looks like flames:
         - very saturated (deep color): skin and sunlit grass are flame-colored
           but much paler, which is how we avoid flagging faces;
         - strongly red rather than blue (measured as Cr - Cb in YCrCb color);
         - uneven brightness: flames fade from bright to dim, while a painted
           orange surface is evenly lit.
      In video, flames also flicker, while an orange sign stays still.
      Firefighters wear bright yellow jackets and helmets, which are flame
      colored too. So a patch that sits mostly on top of a person YOLO found
      is treated as clothing and ignored.

    SMOKE: a large, smooth, grayish area (a little color, medium brightness,
    almost no texture) in the upper part of the picture, because smoke rises.

    These thresholds were tuned by measuring the sample photos in sample_media/.
    Limitations (also in the README): bright orange or yellow objects (road
    signs, vehicles) can still look like fire in a single photo, small or faint
    flames can be missed, and gray buildings or haze can look like smoke. That
    is why a trained model can be dropped in at models/fire.pt.
    """

    name = BASIC_DETECTOR_NAME

    # Pass 1: flame-colored pixels. OpenCV hue runs 0-180 (half of 0-360 degrees).
    FIRE_MAX_HUE = 35            # red (0) through orange to yellow (~30)
    FIRE_MIN_SATURATION = 70
    FIRE_MIN_VALUE = 150         # flames give off light, so they are bright
    FIRE_MIN_RED = 180
    # Pass 2: what a patch must look like to count as flames.
    PATCH_MIN_SATURATION = 125   # median saturation (sunlit grass ~115-120, flames 125+; skin is
                                 # also ~90-120, but patches on people are ignored anyway)
    PATCH_MIN_RED_VS_BLUE = 75   # median Cr - Cb (skin ~45-65, flames 75+)
    PATCH_MIN_BRIGHTNESS_SPREAD = 12  # standard deviation of brightness inside the patch
    PATCH_MAX_ON_PEOPLE = 0.6    # ignore a patch if 60%+ of it is on a detected person
    FIRE_MIN_AREA = 0.01         # flames must cover at least 1% of the frame in total

    SMOKE_BLOCK = 24             # smoke is judged on 24x24 pixel blocks
    SMOKE_MIN_SATURATION = 8     # overcast sky is almost perfectly colorless (~3)
    SMOKE_MAX_SATURATION = 60    # blue sky and plants are much more colorful
    SMOKE_MIN_VALUE = 80
    SMOKE_MAX_VALUE = 215        # overcast sky is brighter than this
    SMOKE_MAX_TEXTURE = 12       # smoke is smooth; trees, grass and buildings are busy
    SMOKE_TOP_SHARE = 0.6        # only look in the top 60% of the picture
    SMOKE_MIN_AREA = 0.06        # the smoky region must cover at least 6% of the frame

    def detect(self, frame: np.ndarray, next_frame: Optional[np.ndarray] = None,
               people: Sequence[Detection] = ()) -> FireSmokeResult:
        result = FireSmokeResult()
        people_mask = self._people_mask(frame, people)
        self._detect_fire(frame, next_frame, people_mask, result)
        self._detect_smoke(frame, result)
        return result

    @staticmethod
    def _people_mask(frame: np.ndarray, people: Sequence[Detection]) -> np.ndarray:
        """White inside every person's box, black elsewhere."""
        mask = np.zeros(frame.shape[:2], dtype=np.uint8)
        for person in people:
            x1, y1, x2, y2 = person.box
            mask[max(y1, 0):max(y2, 0), max(x1, 0):max(x2, 0)] = 255
        return mask

    # ---- fire --------------------------------------------------------------

    def _fire_mask(self, frame: np.ndarray) -> np.ndarray:
        """White (255) where a pixel looks like flame, black (0) elsewhere."""
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        hue, sat, val = cv2.split(hsv)
        blue, green, red = cv2.split(frame)

        flame_color = (hue <= self.FIRE_MAX_HUE) & (sat >= self.FIRE_MIN_SATURATION) & (val >= self.FIRE_MIN_VALUE)
        # Flame light is mostly red, then green, then a little blue.
        flame_order = (red >= self.FIRE_MIN_RED) & (red > green) & (green > blue)

        mask = (flame_color & flame_order).astype(np.uint8) * 255
        # Remove single-pixel noise, then fill small gaps inside flames.
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        return mask

    def _flame_patches(self, frame: np.ndarray,
                       people_mask: Optional[np.ndarray] = None) -> tuple[np.ndarray, list[tuple[int, int, int, int]]]:
        """
        Pass 2: group flame-colored pixels into patches and keep the ones that
        look like real flames. Returns (mask of kept pixels, box of each kept patch).
        """
        mask = self._fire_mask(frame)
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        saturation, brightness = hsv[:, :, 1], hsv[:, :, 2]
        ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb).astype(np.int16)
        red_vs_blue = ycrcb[:, :, 1] - ycrcb[:, :, 2]

        # Join flame pixels that are close together into one patch per flame.
        grouped = cv2.dilate(mask, np.ones((25, 25), np.uint8))
        count, labels, stats, _ = cv2.connectedComponentsWithStats(grouped)

        kept_mask = np.zeros_like(mask)
        boxes = []
        min_patch_pixels = mask.size * 0.0005
        for patch in range(1, count):  # label 0 is the background
            pixels = (labels == patch) & (mask > 0)
            if pixels.sum() < min_patch_pixels:
                continue
            if np.median(saturation[pixels]) < self.PATCH_MIN_SATURATION:
                continue
            if np.median(red_vs_blue[pixels]) < self.PATCH_MIN_RED_VS_BLUE:
                continue
            if brightness[pixels].std() < self.PATCH_MIN_BRIGHTNESS_SPREAD:
                continue
            if people_mask is not None and (people_mask[pixels] > 0).mean() >= self.PATCH_MAX_ON_PEOPLE:
                continue  # mostly on a person: probably a yellow jacket or helmet
            kept_mask[pixels] = 255
            x, y, w, h = (int(v) for v in stats[patch, :4])
            boxes.append((x, y, x + w, y + h))
        return kept_mask, boxes

    def _detect_fire(self, frame: np.ndarray, next_frame: Optional[np.ndarray],
                     people_mask: np.ndarray, result: FireSmokeResult) -> None:
        mask, boxes = self._flame_patches(frame, people_mask)
        fire_area = cv2.countNonZero(mask) / mask.size
        if fire_area < self.FIRE_MIN_AREA:
            return

        confidence = 0.55 + min(0.3, fire_area * 5)  # bigger flames: more confident

        # Flicker check (videos only): how much of the flame area changed shape?
        if next_frame is not None:
            next_mask, _ = self._flame_patches(next_frame, people_mask)
            changed = cv2.countNonZero(cv2.bitwise_xor(mask, next_mask))
            union = cv2.countNonZero(cv2.bitwise_or(mask, next_mask))
            flicker = changed / max(union, 1)
            if flicker >= 0.2:
                confidence += 0.1   # moving flames: more likely real fire
            elif flicker < 0.02:
                return              # perfectly still: probably an orange object, not flames

        result.fire_detected = True
        result.fire_confidence = round(min(confidence, 0.95), 2)
        result.fire_area = round(fire_area, 4)
        # Box the biggest patches (at most 5, to keep the picture readable).
        boxes.sort(key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)
        for box in boxes[:5]:
            result.boxes.append(Detection("fire", result.fire_confidence, box))

    # ---- smoke -------------------------------------------------------------

    def _detect_smoke(self, frame: np.ndarray, result: FireSmokeResult) -> None:
        height, width = frame.shape[:2]
        rows, cols = max(height // self.SMOKE_BLOCK, 1), max(width // self.SMOKE_BLOCK, 1)

        # Shrinking with INTER_AREA averages each block into one pixel, which
        # gives us the average saturation/brightness of every block at once.
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV).astype(np.float32)
        block_hsv = cv2.resize(hsv, (cols, rows), interpolation=cv2.INTER_AREA)
        block_sat, block_val = block_hsv[:, :, 1], block_hsv[:, :, 2]

        # Texture = how much brightness varies inside each block (standard deviation).
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
        mean = cv2.resize(gray, (cols, rows), interpolation=cv2.INTER_AREA)
        mean_of_squares = cv2.resize(gray * gray, (cols, rows), interpolation=cv2.INTER_AREA)
        texture = np.sqrt(np.maximum(mean_of_squares - mean * mean, 0))

        smoky = (
            (block_sat >= self.SMOKE_MIN_SATURATION)
            & (block_sat <= self.SMOKE_MAX_SATURATION)
            & (block_val >= self.SMOKE_MIN_VALUE)
            & (block_val <= self.SMOKE_MAX_VALUE)
            & (texture <= self.SMOKE_MAX_TEXTURE)
        ).astype(np.uint8)
        # Smoke rises: ignore the bottom of the picture (roads, water, ground).
        smoky[int(rows * self.SMOKE_TOP_SHARE):, :] = 0

        # Find the largest connected smoky region.
        count, _, stats, _ = cv2.connectedComponentsWithStats(smoky, connectivity=4)
        if count <= 1:
            return
        largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        area_share = stats[largest, cv2.CC_STAT_AREA] / (rows * cols)
        if area_share < self.SMOKE_MIN_AREA:
            return
        # Without flames, a smooth gray area is usually a wall, a ceiling or a
        # cloudy sky, and color alone can't tell them apart from smoke. So this
        # simple detector only reports smoke next to flames it found. (The
        # trained model in Option 2 recognizes smoke on its own.)
        if not result.fire_detected:
            return

        confidence = 0.55 + min(0.3, area_share)
        result.smoke_detected = True
        result.smoke_confidence = round(min(confidence, 0.9), 2)

        x, y, w, h = (int(stats[largest, i]) for i in
                      (cv2.CC_STAT_LEFT, cv2.CC_STAT_TOP, cv2.CC_STAT_WIDTH, cv2.CC_STAT_HEIGHT))
        scale_x, scale_y = width / cols, height / rows
        box = (int(x * scale_x), int(y * scale_y), int((x + w) * scale_x), int((y + h) * scale_y))
        result.boxes.append(Detection("smoke", result.smoke_confidence, box))


# ---------------------------------------------------------------------------
# Option 2: a trained YOLO fire/smoke model (used automatically if present)
# ---------------------------------------------------------------------------

class ModelFireDetector:
    """
    Uses any Ultralytics YOLO model whose class names include "fire"/"flame"
    and/or "smoke" (many free fire-detection models are trained this way).
    """

    MIN_CONFIDENCE = 0.45   # below this, D-Fire-trained models make too many mistakes

    def __init__(self, model_path) -> None:
        from ultralytics import YOLO

        self._model = YOLO(str(model_path))
        self.name = f"model: {model_path.name}"

    def detect(self, frame: np.ndarray, next_frame: Optional[np.ndarray] = None,
               people: Sequence[Detection] = ()) -> FireSmokeResult:
        result = FireSmokeResult()
        prediction = self._model.predict(frame, conf=self.MIN_CONFIDENCE, device="cpu", verbose=False)[0]
        for box in prediction.boxes:
            class_name = prediction.names[int(box.cls[0])].lower()
            confidence = float(box.conf[0])
            x1, y1, x2, y2 = (int(v) for v in box.xyxy[0].tolist())
            if "fire" in class_name or "flame" in class_name:
                result.fire_detected = True
                result.fire_area += (x2 - x1) * (y2 - y1) / (frame.shape[0] * frame.shape[1])
                result.fire_confidence = max(result.fire_confidence, round(confidence, 2))
                result.boxes.append(Detection("fire", confidence, (x1, y1, x2, y2)))
            elif "smoke" in class_name:
                result.smoke_detected = True
                result.smoke_confidence = max(result.smoke_confidence, round(confidence, 2))
                result.boxes.append(Detection("smoke", confidence, (x1, y1, x2, y2)))
        return result


@lru_cache(maxsize=1)
def get_fire_detector() -> FireDetector:
    """Pick the best available detector once, when it's first needed."""
    if FIRE_MODEL_PATH.exists():
        return ModelFireDetector(FIRE_MODEL_PATH)
    return BasicFireDetector()
