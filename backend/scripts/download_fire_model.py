"""
Download the trained fire and smoke model used to check report photos.

It's a free YOLOv8n model trained on D-Fire, a public collection of more
than 21,000 real fire and smoke photos:
    https://huggingface.co/rabahdev/fire-smoke-yolov8n   (license AGPL-3.0,
    the same as the Ultralytics YOLO library RollCall already uses)

It's saved as backend/models/fire.pt. When that file exists, the AI uses it
instead of the simple color-based detector (see app/ai/fire.py). The file
is about 6 MB and isn't committed to git.

Run from the backend folder:
    python -m scripts.download_fire_model
"""

import shutil
import urllib.request

from app.config import FIRE_MODEL_PATH

URL = "https://huggingface.co/rabahdev/fire-smoke-yolov8n/resolve/main/best.pt"


def download() -> None:
    if FIRE_MODEL_PATH.exists():
        print(f"Already downloaded: {FIRE_MODEL_PATH}")
        return
    partial = FIRE_MODEL_PATH.with_suffix(".part")
    request = urllib.request.Request(URL, headers={"User-Agent": "RollCall student project"})
    with urllib.request.urlopen(request, timeout=60) as response, open(partial, "wb") as out:
        shutil.copyfileobj(response, out)
    partial.rename(FIRE_MODEL_PATH)   # only a complete download gets the real name
    print(f"Saved the fire and smoke model to {FIRE_MODEL_PATH}")


if __name__ == "__main__":
    download()
