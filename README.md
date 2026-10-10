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

**Testing reports in the simulator:**
- **Address search:** type an address or place in the report form and pick a suggestion to move the pin. **Take photo or video** only appears on a real iPhone; the simulator has no camera.
- **Location:** the simulator starts out in California. Set a North Texas location in the simulator's menu (Features → Location → Custom Location), or run `xcrun simctl location booted set 33.0712,-96.1043` (next to the demo grass fire, so a fire report there merges into it).
- **Photos and videos:** add some to the simulator's Photos app by dragging files onto the simulator window, or run `xcrun simctl addmedia booted backend/sample_media/grass_fire_crew.jpg backend/sample_media/grass_fire_clip.mp4`.

## The Incidents tab (responder view)

The second tab is for responders. At the top are four numbers, each a simple count you can check:

| Card | What it counts |
|---|---|
| Active incidents | Incidents nobody is responding to yet (and how many are responding) |
| People detected | The most people the AI has seen at each open incident, added up (and how many may be down) |
| Unverified | Open incidents with no AI evidence yet. Weather reports count here too, since the AI can't recognize a tornado |
| Avg. response time | Average time from the first report to a responder tapping "Mark responding" |

Below them, every incident is listed by priority (highest first), with Open / Resolved / All filters. Tap one to open the same detail sheet as on the map, including "Why this priority?". Pull down to refresh. The tab badge shows how many incidents are active and high priority. The Map and Incidents tabs share one copy of the data, so a status change shows up on both immediately.

## Drone feed

Once the AI confirms fire, the incident's sheet offers **Launch drone feed**. While it's live, the app shows the AI-annotated video and live counts:

- **People in view**
- **May be down:** a person whose outline is much wider than it is tall is probably lying on the ground and could be injured
- **Near the flames:** a person whose outline touches the area around a fire
- **Fire in view:** how much of the picture is flames

The feed saves a snapshot to the incident (with a timeline entry) when something important changes and every 20 seconds, so there's a record after it stops.

**Connecting real hardware.** The backend reads any MJPEG or RTSP stream with OpenCV, such as an ESP32-CAM on a drone or a phone running an IP-camera app. Set the stream address, then restart the server:

```bash
export RESCUESIGHT_CAMERA_URL="http://192.168.1.50:81/stream"
uvicorn app.main:app --reload
```

Without it, the feed plays demo footage of real fires (public domain, labeled "Demo footage" in the app), and the AI results are real. See `backend/app/camera/sources.py`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/incidents/{id}/camera` | Is a feed running, and what does the AI see right now? |
| `POST` | `/incidents/{id}/camera/start` | Launch the feed |
| `POST` | `/incidents/{id}/camera/stop` | Stop it |
| `GET` | `/incidents/{id}/camera/frame.jpg` | The newest picture with AI boxes |

## Automated tests

- **Backend:** `cd backend && python -m pytest`
- **iPhone app (UI tests):** start the backend with fresh demo data (`python -m scripts.reset_demo`, then `uvicorn app.main:app`), then press **⌘U** in Xcode. The tests tap through the real app: zooming the map, reporting a fire that merges into an existing one, searching an address, attaching a photo and waiting for the AI result, and launching the drone feed.

## Recording the walkthrough video

`tools/record_demo.sh` records a narrated walkthrough of the whole app on the iPhone simulator, with no screen-recording software needed:

```bash
tools/record_demo.sh        # about 25 minutes; results: demo_video/RescueSight-2min.mp4 and RescueSight-walkthrough.mp4 (full, ~14 min)
```

It resets the demo data, then runs `ios/RescueSightUITests/DemoWalkthrough.swift`, a UI test that taps through every feature while the simulator's screen is recorded. Next it records the offline state with the backend switched off. Finally, `tools/make_demo_video.py` adds captions ("what is being shown" and "what I'm doing"), a ring wherever something is tapped, a progress strip, chapter markers and a voice-over (macOS's built-in Samantha voice). The walkthrough test is skipped in normal test runs. Close other heavy apps first: the simulator, recording and AI all run at once.

## Incident types

Reports can be about any of these, grouped into "modes" so the map can show one kind of disaster at a time:

| Mode | Types |
|---|---|
| Fire & smoke | Fire, Smoke |
| Severe weather | Tornado, Severe storm (wind, hail, downed lines), Heavy rain, Flood, Hurricane, Winter storm |
| Medical & other | Injury, Other |

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
3. **Fire and smoke.** If a trained model exists at `backend/models/fire.pt`, it is used. Otherwise a hand-written OpenCV rule (the **basic detector**) looks for deeply saturated, red-dominant, unevenly lit flame patches and, in video, flicker. Flame-colored patches that sit on a detected person are ignored, because firefighters' yellow jackets and helmets are flame colored. Smoke is a large, smooth, grayish area in the upper part of the picture.
4. **Who might need help.** People lying down ("may be down") and people close to the flames are flagged from YOLO's boxes (`backend/app/ai/scene.py`).
5. **Video.** About one frame per second is checked (up to 30 seconds). Fire or smoke must appear in at least 2 frames, and the most informative frame is saved with its boxes drawn on.

## How priority scoring works

Simple rules that anyone can check, not a black box. The app shows each one under "Why this priority?".

| Rule | Points |
|---|---|
| Starting points by type | tornado +40, hurricane +40, fire +20, injury +20, flood +20, severe storm +20, winter storm +20, heavy rain +10, smoke +10, other +5 |
| Fire confirmed by AI | +40 |
| Smoke confirmed by AI | +20 |
| Each person detected | +15 (up to +45) |
| Someone may be down (lying on the ground) | +15 |
| People close to the flames | +10 |
| Each extra report | +5 (up to +25) |
| Low light / night (8 PM–6 AM) | +5 |
| Not yet verified by AI (fire, smoke and injury reports only) | −20 |

The total is kept between 0 and 100: 60+ is high, 30–59 medium, below 30 low. See `backend/app/services/priority.py`.

The −20 only applies to types the AI can check. It looks for flames, smoke and people, so for a fire report "no evidence yet" means something. It can't recognize a tornado or a flooded road, so weather reports aren't marked down for that; the number of independent reports counts instead.

## Known limitations

- The app logs one intermittent SwiftUI layout warning ("Invalid frame dimension") while using the address search in the report form. It doesn't affect how anything works, and its source is still being tracked down.
- "May be down" is a hint, not a diagnosis: someone resting on the ground looks the same, and a camera angle can make distances look shorter than they are.
- The basic fire detector was tuned on a small set of photos. In testing it mistook a yellow "Water over road" sign for fire, a gray indoor wall and a hazy overcast sky for smoke, and missed a distant smoke plume and some small flames. A trained model at `models/fire.pt` fixes most of this.
- The AI cannot recognize tornadoes, floods, storms or ice. For those reports it can still count people in the photo, but the weather itself is confirmed by how many people report it.

## Credits

Demo photos and video come from Wikimedia Commons (public domain and Creative Commons). Authors and licenses are listed in [backend/sample_media/CREDITS.md](backend/sample_media/CREDITS.md).
