"""
People detection with YOLO.

YOLO ("You Only Look Once") is a neural network that finds objects in an image
in a single pass. We use the smallest pretrained version, yolov8n ("nano"),
which already knows 80 everyday object types from the COCO dataset. Class 0 is
"person", so we ask it for people only. It runs fine on a laptop CPU.
"""

import threading
from functools import lru_cache

import numpy as np

from app.ai.detections import Detection
from app.config import PEOPLE_MODEL_PATH, PERSON_MIN_CONFIDENCE

PERSON_CLASS_ID = 0  # "person" in the COCO dataset


class PeopleDetector:
    def __init__(self) -> None:
        self._model = None
        # Uploads are analyzed in background threads; the lock makes sure two
        # threads don't use the model at the same moment.
        self._lock = threading.Lock()

    def _load_model(self):
        # Imported here (not at the top) because loading PyTorch takes a few
        # seconds; this way the server starts instantly.
        from ultralytics import YOLO

        # If models/yolov8n.pt is missing, Ultralytics downloads it (~6 MB) once.
        return YOLO(str(PEOPLE_MODEL_PATH))

    def detect(self, frame: np.ndarray) -> list[Detection]:
        with self._lock:
            if self._model is None:
                self._model = self._load_model()
            results = self._model.predict(
                frame,
                classes=[PERSON_CLASS_ID],
                conf=PERSON_MIN_CONFIDENCE,
                device="cpu",
                verbose=False,
            )

        detections = []
        for box in results[0].boxes:
            x1, y1, x2, y2 = (int(v) for v in box.xyxy[0].tolist())
            detections.append(Detection("person", float(box.conf[0]), (x1, y1, x2, y2)))
        return detections


@lru_cache(maxsize=1)
def get_people_detector() -> PeopleDetector:
    """One shared detector for the whole server, so the model loads only once."""
    return PeopleDetector()
