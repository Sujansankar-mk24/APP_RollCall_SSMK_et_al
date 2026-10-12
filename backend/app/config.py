"""
All of the backend's settings live in this one file, so there is a single
place to look when you want to change how RollCall behaves.

Paths can be overridden with environment variables. The tests use that to
point at a throwaway database and media folder so they never touch demo data.
"""

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Folders and files
# ---------------------------------------------------------------------------

# The "backend" folder (this file is backend/app/config.py, so go up two levels).
BACKEND_DIR = Path(__file__).resolve().parent.parent

# SQLite stores the whole database in a single file.
DATABASE_PATH = Path(os.environ.get("ROLLCALL_DB_PATH", BACKEND_DIR / "rollcall.db"))

# Everything users upload (and everything the AI draws) is saved under media/.
# The server shares this folder at http://localhost:8000/media/...
MEDIA_DIR = Path(os.environ.get("ROLLCALL_MEDIA_DIR", BACKEND_DIR / "media"))
UPLOADS_DIR = MEDIA_DIR / "uploads"      # original photos and videos
ANNOTATED_DIR = MEDIA_DIR / "annotated"  # copies with AI detection boxes drawn on
THUMBS_DIR = MEDIA_DIR / "thumbs"        # small previews for the app's gallery

# Royalty-free demo photos/videos (filled by scripts/download_samples.py).
SAMPLE_MEDIA_DIR = BACKEND_DIR / "sample_media"

# AI model weights.
MODELS_DIR = BACKEND_DIR / "models"
PEOPLE_MODEL_PATH = MODELS_DIR / "yolov8n.pt"  # downloaded automatically the first time
FIRE_MODEL_PATH = MODELS_DIR / "fire.pt"       # optional: drop a fire/smoke YOLO model here

# Make sure the folders exist before anything tries to save into them.
for folder in (UPLOADS_DIR, ANNOTATED_DIR, THUMBS_DIR, SAMPLE_MEDIA_DIR, MODELS_DIR):
    folder.mkdir(parents=True, exist_ok=True)

# Incidents are in North Texas, so "night" and times are judged on Central Time.
LOCAL_TIMEZONE = "America/Chicago"

# ---------------------------------------------------------------------------
# Incident reports (Map and Incidents tabs)
# A new report joins an existing incident when it is the same type, close by,
# and recent. Otherwise it starts a new incident.
# ---------------------------------------------------------------------------
MERGE_RADIUS_METERS = 300
MERGE_WINDOW_HOURS = 2

MAX_UPLOAD_BYTES = 200 * 1024 * 1024  # 200 MB, enough for a short phone video
MAX_DESCRIPTION_LENGTH = 500

# ---------------------------------------------------------------------------
# AI photo/video check
# ---------------------------------------------------------------------------
# Frames are shrunk so their longest side is at most this many pixels.
# Smaller frames = much faster on a laptop CPU, and detection still works well.
ANALYSIS_MAX_SIDE = 960

# Average brightness is measured from 0 (black) to 255 (white).
# Below this number we treat the photo as "low light" and enhance it first.
LOW_LIGHT_BRIGHTNESS = 70

# YOLO only counts a person if it is at least this confident (0 to 1).
PERSON_MIN_CONFIDENCE = 0.35

# For videos, look at about one frame per second, up to this many frames.
VIDEO_SAMPLES_PER_SECOND = 1
VIDEO_MAX_SAMPLES = 30

# ---------------------------------------------------------------------------
# Households (Roll Call tab)
# ---------------------------------------------------------------------------
MAX_PEOPLE_PER_HOUSEHOLD = 20
MAX_TEXT_LENGTH = 120          # names, addresses, phone numbers
MAX_NOTE_LENGTH = 500

# Kinds of powered medical equipment someone can list. If the power goes out,
# these people are in danger first.
MEDICAL_EQUIPMENT = ["oxygen", "dialysis", "cpap", "ventilator", "power_wheelchair", "other"]

# Buddy matching: only suggest volunteers this close.
BUDDY_MAX_DISTANCE_KM = 15
