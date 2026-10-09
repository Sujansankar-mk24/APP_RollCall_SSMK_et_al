# RescueSight

A community emergency map for North Texas. Residents report incidents with a pin and a photo or video. Reports from the same area merge into one incident, AI checks the media for fire, smoke and people, and responders get a priority-ranked list with visual evidence before they head out.

> RescueSight supports emergency services. It does not replace 911. **In an emergency, call 911 first.**

*This README grows with the project. The full version (screenshots, architecture diagram, future work) comes with the final polish step.*

## Project layout

```
backend/   Python FastAPI server, SQLite database, AI pipeline
ios/       SwiftUI iPhone app (iOS 17+, no third-party packages)
```

## Running the backend

You need Python 3.11 or newer. Run these from the `backend` folder:

```bash
cd backend

# 1. One-time setup: create a private Python environment and install packages
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. Load the demo data (downloads sample photos/video the first time, then runs the AI on them)
python -m scripts.reset_demo

# 3. Start the server
uvicorn app.main:app --reload
```

Open http://localhost:8000/docs to see and try every endpoint in your browser.

In a new terminal, run `source .venv/bin/activate` again before using `python` or `uvicorn`.

| Command | What it does |
|---|---|
| `python -m scripts.reset_demo` | Wipes everything and reloads the 8 demo incidents |
| `python -m scripts.download_samples` | Downloads the sample media only |
| `python -m pytest` | Runs the automated tests |

## Running the iPhone app

1. Start the backend (above) and leave it running.
2. Open `ios/RescueSight.xcodeproj` in Xcode.
3. Pick an iPhone simulator at the top of the window (for example, iPhone 18 Pro) and press **Run** (⌘R).

The app reads the server address from `ios/RescueSight/Config/AppConfig.swift` (`http://localhost:8000`). If the backend isn't running, the app shows "Can't reach RescueSight" with a **Try again** button.

New Swift files added anywhere inside `ios/RescueSight/` are included in the project automatically.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Is the server up? |
| `GET` | `/incidents` | List incidents. Filters: `type`, `status`, `since_hours`. Sort: `priority` (default) or `recent` |
| `GET` | `/incidents/{id}` | One incident with reports, media, AI results, timeline and priority breakdown |
| `PATCH` | `/incidents/{id}/status` | Set `active`, `responding` or `resolved` |
| `POST` | `/reports` | New report (form fields + optional photo/video). Merges into a nearby incident when it can |
| `GET` | `/media/...` | Uploaded files, thumbnails and AI-annotated images |

## How report merging works

A new report joins an existing incident if it is the same type, the incident isn't resolved, its newest report was within the last 2 hours, and it's within 300 meters. Otherwise it starts a new incident. See `backend/app/services/merging.py`.

## How the AI works

Every photo or video is analyzed in the background right after upload, so the app never waits:

1. **Low-light check.** The average brightness is measured. If the picture is dark, its contrast is boosted with CLAHE before detection, and that is recorded.
2. **People.** YOLOv8n, a small pretrained neural network, finds people. It runs on a normal laptop CPU.
3. **Fire and smoke.** If a trained model exists at `backend/models/fire.pt`, it is used. Otherwise a hand-written OpenCV rule (the **basic detector**) looks for deeply saturated, red-dominant, unevenly lit flame patches and, in video, flicker. Smoke is a large, smooth, grayish area in the upper part of the picture.
4. **Video.** About one frame per second is checked (up to 30 seconds). Fire or smoke must appear in at least 2 frames, and the most informative frame is saved with its boxes drawn on.

## How priority scoring works

Simple rules that anyone can check, not a black box. The app shows each one under "Why this priority?".

| Rule | Points |
|---|---|
| Starting points by type | fire +20, injury +20, flood +15, smoke +10, other +5 |
| Fire confirmed by AI | +40 |
| Smoke confirmed by AI | +20 |
| Each person detected | +15 (up to +45) |
| Each extra report | +5 (up to +25) |
| Low light / night (8 PM–6 AM) | +5 |
| Not yet verified by AI | −20 |

The total is kept between 0 and 100: 60+ is high, 30–59 medium, below 30 low. See `backend/app/services/priority.py`.

## Known limitations

- The basic fire detector was tuned on a small set of photos. In testing it mistook a yellow "Water over road" sign for fire, a gray indoor wall and a hazy overcast sky for smoke, and missed a distant smoke plume and some small flames. A trained model at `models/fire.pt` fixes most of this.
- The AI cannot confirm floods, injuries without visible people, or downed power lines, so those reports stay "not yet verified" until someone reviews them.

## Credits

Demo photos and video come from Wikimedia Commons (public domain and Creative Commons). Authors and licenses are listed in [backend/sample_media/CREDITS.md](backend/sample_media/CREDITS.md).
