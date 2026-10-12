"""
Reading videos for analysis.

Analyzing every frame of a 30 fps video would be slow and repetitive, so we
look at about one frame per second. For each of those frames we also grab a
"next frame" about 0.1 s later, which the fire detector uses to check whether
flames are flickering.
"""

from collections.abc import Iterator
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from app.config import VIDEO_MAX_SAMPLES, VIDEO_SAMPLES_PER_SECOND


def sample_frames(
    path: Path,
    samples_per_second: float = VIDEO_SAMPLES_PER_SECOND,
    max_samples: int = VIDEO_MAX_SAMPLES,
) -> Iterator[tuple[np.ndarray, Optional[np.ndarray]]]:
    """Yields (frame, next_frame) pairs, about one pair per second of video."""
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise ValueError("Could not open this video file.")

    try:
        fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
        step = max(1, round(fps / samples_per_second))  # frames between samples
        flicker_gap = max(1, round(fps / 10))           # ~0.1 seconds

        frame_index = 0
        next_sample_index = 0
        waiting_frame: Optional[np.ndarray] = None  # sampled frame waiting for its "next frame"
        next_frame_index = -1
        samples_taken = 0

        # grab() moves to the next frame cheaply; retrieve() decodes it only when we need it.
        while samples_taken < max_samples and capture.grab():
            if waiting_frame is None and frame_index >= next_sample_index:
                ok, frame = capture.retrieve()
                if ok:
                    waiting_frame = frame
                    next_frame_index = frame_index + flicker_gap
            elif waiting_frame is not None and frame_index >= next_frame_index:
                ok, later = capture.retrieve()
                yield waiting_frame, (later if ok else None)
                samples_taken += 1
                waiting_frame = None
                next_sample_index = max(next_sample_index + step, frame_index + 1)
            frame_index += 1

        # The video ended right after a sampled frame: use it without a next frame.
        if waiting_frame is not None and samples_taken < max_samples:
            yield waiting_frame, None
    finally:
        capture.release()
