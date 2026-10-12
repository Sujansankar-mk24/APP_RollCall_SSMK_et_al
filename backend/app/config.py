"""
All of the backend's settings live in this one file, so there is a single
place to look when you want to change how RollCall behaves.

Paths can be overridden with environment variables. The tests use that to
point at a throwaway database so they never touch the demo data.
"""

import os
from pathlib import Path

# The "backend" folder (this file is backend/app/config.py, so go up two levels).
BACKEND_DIR = Path(__file__).resolve().parent.parent

# SQLite stores the whole database in a single file.
DATABASE_PATH = Path(os.environ.get("ROLLCALL_DB_PATH", BACKEND_DIR / "rollcall.db"))

# Photos residents attach to a check-in are saved here and served at /media/...
MEDIA_DIR = Path(os.environ.get("ROLLCALL_MEDIA_DIR", BACKEND_DIR / "media"))
MEDIA_DIR.mkdir(parents=True, exist_ok=True)

# Incidents are in North Texas, so times are shown in Central Time.
LOCAL_TIMEZONE = "America/Chicago"

# ---------------------------------------------------------------------------
# Households
# ---------------------------------------------------------------------------
MAX_PEOPLE_PER_HOUSEHOLD = 20
MAX_TEXT_LENGTH = 120          # names, addresses, phone numbers
MAX_NOTE_LENGTH = 500

# Kinds of powered medical equipment someone can list. If the power goes out,
# these people are in danger first.
MEDICAL_EQUIPMENT = ["oxygen", "dialysis", "cpap", "ventilator", "power_wheelchair", "other"]

# ---------------------------------------------------------------------------
# Buddy matching
# ---------------------------------------------------------------------------
BUDDY_MAX_DISTANCE_KM = 15     # only suggest volunteers this close
