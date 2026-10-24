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


def _load_private_settings() -> None:
    """
    Read backend/.env (KEY=value lines) into the environment. It holds private
    things like the NASA FIRMS key and is never committed (see .gitignore).
    Real environment variables win over the file.
    """
    path = BACKEND_DIR / ".env"
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


_load_private_settings()

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
# Every new report needs a photo and a short description of what's happening,
# so responders can trust it and the AI can check it.
MIN_DESCRIPTION_LENGTH = 10

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

# ---------------------------------------------------------------------------
# Live hazard data (Map tab)
# ---------------------------------------------------------------------------
# Every request to a data source says who we are (the Weather Service asks for this).
DATA_USER_AGENT = "RollCall/1.0 (Congressional App Challenge student project)"

# Ask the sources again at most this often; in between, the saved copy is used.
HAZARD_REFRESH_SECONDS = 300
# The refresh button can ask sooner, but no more than once this often.
HAZARD_FORCE_MIN_SECONDS = 30

# Texas, as (west, south, east, north). Live hazards outside it are left out.
HAZARD_AREA = (-106.7, 25.8, -93.5, 36.6)
HAZARD_STATE = "TX"

# NASA FIRMS satellite fire data needs a free key (in backend/.env). Without
# it, fires still come from NASA EONET.
FIRMS_MAP_KEY = os.environ.get("FIRMS_MAP_KEY") or None
FIRMS_DAYS = 2   # look back this many days (1 to 10)

# NWS forecast-zone shapes never change, so they're saved here after the first download.
HAZARD_CACHE_DIR = Path(os.environ.get("ROLLCALL_CACHE_DIR", BACKEND_DIR / "cache"))
HAZARD_CACHE_DIR.mkdir(parents=True, exist_ok=True)
