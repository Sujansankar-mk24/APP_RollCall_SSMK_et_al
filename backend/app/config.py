"""
All of the backend's settings live in this one file, so there is a single
place to look when you want to change how RescueSight behaves.

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
DATABASE_PATH = Path(os.environ.get("RESCUESIGHT_DB_PATH", BACKEND_DIR / "rescuesight.db"))

# Everything users upload (and everything the AI draws) is saved under media/.
# The server shares this folder at http://localhost:8000/media/...
MEDIA_DIR = Path(os.environ.get("RESCUESIGHT_MEDIA_DIR", BACKEND_DIR / "media"))
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

# ---------------------------------------------------------------------------
# Report merging
# A new report joins an existing incident when it is the same type, close by,
# and recent. Otherwise it starts a new incident.
# ---------------------------------------------------------------------------
MERGE_RADIUS_METERS = 300
MERGE_WINDOW_HOURS = 2

# ---------------------------------------------------------------------------
# Uploads
# ---------------------------------------------------------------------------
MAX_UPLOAD_BYTES = 200 * 1024 * 1024  # 200 MB, enough for a short phone video
MAX_DESCRIPTION_LENGTH = 500

# ---------------------------------------------------------------------------
# AI pipeline
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

# Incidents are in North Texas, so "night" is judged on Central Time.
LOCAL_TIMEZONE = "America/Chicago"

# ---------------------------------------------------------------------------
# Drone / camera feed
# ---------------------------------------------------------------------------
# When your drone (or an ESP32-CAM, or a phone running an IP-camera app) is
# streaming, put its address here, for example:
#     export RESCUESIGHT_CAMERA_URL="http://192.168.1.50:81/stream"
# then restart the server. Without it, the feed plays the demo clips below,
# so everything works with no hardware.
CAMERA_STREAM_URL = os.environ.get("RESCUESIGHT_CAMERA_URL") or None

# Demo "drone footage": real public-domain fire videos played one after
# another, as if a drone were flying over the crew at the staging area and
# then over the fire. Always labeled "Simulated" in the app.
DRONE_DEMO_CLIPS = ["drone_crew.mp4", "grass_fire_clip.mp4", "drone_fire_line.mp4"]

LIVE_ANALYSES_PER_SECOND = 2.5   # how often the live feed is checked by the AI
LIVE_SNAPSHOT_SECONDS = 20       # save a snapshot to the incident at most this often
LIVE_MAX_MINUTES = 10            # stop a feed automatically after this long
