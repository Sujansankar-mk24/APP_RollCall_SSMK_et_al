"""
Camera sources: where live footage comes from.

This is the plug-in point for hardware. The live feed (live.py) only asks a
source for frames, so it doesn't care whether they come from:

  * UploadedClipSource: video files played at real speed, like a live camera.
    Used for the demo, so everything works with no hardware.
  * StreamSource: a real live stream (an ESP32-CAM, a drone's video link, or a
    phone running an IP-camera app) read with OpenCV.

To connect a drone later, set RESCUESIGHT_CAMERA_URL (see config.py).
"""

import time
from abc import ABC, abstractmethod
from collections.abc import Iterator
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from app.config import CAMERA_STREAM_URL, DRONE_DEMO_CLIPS, SAMPLE_MEDIA_DIR


class CameraSource(ABC):
    """Anything that can hand out video frames, one after another."""

    label: str      # shown in the app, e.g. "Demo drone feed"
    is_demo: bool   # True if this is recorded footage, not a live camera

    @abstractmethod
    def frames(self) -> Iterator[np.ndarray]:
        """Yield frames until the source ends (or forever, for live streams)."""


class UploadedClipSource(CameraSource):
    """Plays video files in a loop at their normal speed, like a live camera would."""

    def __init__(self, paths: list[Path], label: str = "Demo drone feed"):
        self.paths = [p for p in paths if p.exists()]
        if not self.paths:
            raise FileNotFoundError("No demo clips found. Run: python -m scripts.download_samples")
        self.label = label
        self.is_demo = True

    def frames(self) -> Iterator[np.ndarray]:
        while True:  # loop the playlist; the live feed decides when to stop
            for path in self.paths:
                capture = cv2.VideoCapture(str(path))
                frame_seconds = 1 / (capture.get(cv2.CAP_PROP_FPS) or 30)
                next_time = time.monotonic()
                try:
                    while True:
                        ok, frame = capture.read()
                        if not ok:
                            break
                        yield frame
                        # Wait so frames come out at real speed, not as fast as possible.
                        next_time += frame_seconds
                        delay = next_time - time.monotonic()
                        if delay > 0:
                            time.sleep(delay)
                finally:
                    capture.release()


class StreamSource(CameraSource):
    """
    A live stream read by OpenCV. Works with MJPEG over HTTP (what an
    ESP32-CAM sends, e.g. http://192.168.1.50:81/stream) and RTSP.
    """

    RECONNECT_TRIES = 5

    def __init__(self, url: str, label: str = "Live drone camera"):
        self.url = url
        self.label = label
        self.is_demo = False

    def frames(self) -> Iterator[np.ndarray]:
        failures = 0
        while failures < self.RECONNECT_TRIES:
            capture = cv2.VideoCapture(self.url)
            try:
                while True:
                    ok, frame = capture.read()
                    if not ok:
                        break
                    failures = 0
                    yield frame
            finally:
                capture.release()
            failures += 1
            time.sleep(1)  # the drone may have dropped out briefly; try again
        raise ConnectionError(f"Lost the camera stream at {self.url}")


def default_source(stream_url: Optional[str] = CAMERA_STREAM_URL) -> CameraSource:
    """The real camera if one is configured, otherwise the demo clips."""
    if stream_url:
        return StreamSource(stream_url)
    return UploadedClipSource([SAMPLE_MEDIA_DIR / name for name in DRONE_DEMO_CLIPS])
