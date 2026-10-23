# RollCall

Make sure no one gets left behind. RollCall is a community emergency app for North Texas with two halves:

- **An incident map.** Residents report emergencies with a pin and a photo or video. Reports from the same area merge into one incident, AI checks the media for fire, smoke and people, and responders get a priority-ranked list with the evidence before they head out.
- **A roll call.** Households sign up ahead of time and say who lives there and what could make leaving hard: seniors living alone, oxygen or dialysis, no car, pets or livestock. When a tornado warning or flood hits, RollCall asks everyone in the area "Are you safe?". A volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help, most urgent first.

> RollCall supports emergency services. It doesn't replace 911 or contact it for you.

*This README grows with the project. The full version (how RollCall differs from Watch Duty, an architecture diagram, risk scoring, limitations and future work) comes with the final polish step.*

## The app's tabs

| Tab | What it's for |
|---|---|
| **Map** | Live hazards (diamonds) and community reports (circles) with their danger zones; tap one for details. **Incidents** (top left) unrolls the incident log: key numbers and every incident sorted by priority, with "Why this priority?". **Report incident** with a pin, address search, and a photo or video. Filters, legend, zoom, night mode. |
| **Roll Call** | **My household**: join the roll call (or choose **Not now**), type your address, accept or decline buddy offers, privacy and Delete my data. **I check on**: be a volunteer buddy. Responders see their own view. |
| **Community** | Find your neighborhood and ask to join, or start one and be its admin: approve members, and decide whether buddies from outside are allowed. |
| **About** | What RollCall does, who can see your information, credits, and your account (Sign out). |

**The look:** the Map keeps its blue map style. Every other screen looks like a paper roll-call sheet: warm paper, ink-black type and square buttons, ruled rows instead of floating cards, and color only on the "stamped" status labels (green safe, red needs help, amber waiting). Text never goes below 15 pt. The pieces live in `ios/RollCall/Design/Sheet.swift`.

You sign in once; the app remembers you until you sign out. There are no placeholder people or communities: everything in Roll Call and Community comes from real accounts made in the app.

## What works so far

- **Map and incident log:** live hazard data with danger zones, reporting with photo/video, merging, AI photo/video checks, priority scoring, responder status updates, timeline.
- **Accounts:** sign up, sign in, stay signed in, sign out. Passwords are hashed with scrypt; the sign-in token lives in the iPhone Keychain.
- **Roll Call, step 1 — household profile:** a five-step sign-up (home, who lives here, needs, contact, review) with a typed address checked on the map and by GPS, **Not now** for people who'd rather not, a clear "who can see this" privacy screen, and **Delete my data**, which really deletes everything.
- **Communities and buddies:** neighborhoods with admin approval; buddy offers from community neighbors or by exact address, always accepted or declined by the resident.
- *(Coming next)* Emergency events from National Weather Service alerts, responder-drawn zones, and demo events.
- *(Coming)* The roll call check-in in English and Spanish, escalation to buddies and responders, the responder roll-call dashboard with risk scores and routes, and buddy matching.

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

# 2. Load the demo data: 10 incidents (downloads sample photos/video the first
#    time, then runs the AI on them). There are no placeholder accounts.
python -m scripts.reset_demo

# 3. Start the server
uvicorn app.main:app --reload
```

Open http://localhost:8000/docs to see and try every endpoint in your browser.

In a new terminal, run `source .venv/bin/activate` again before using `python` or `uvicorn`.

| Command | What it does |
|---|---|
| `python -m scripts.reset_demo` | Wipes everything and reloads the demo incidents, households and volunteers |
| `python -m scripts.download_samples` | Downloads the sample media only |
| `python -m pytest` | Runs the automated tests |

## Running the iPhone app

1. Start the backend (above) and leave it running.
2. Open `ios/RollCall.xcodeproj` in Xcode.
3. Pick an iPhone simulator at the top of the window (for example, iPhone 18 Pro) and press **Run** (⌘R).

The first time, the app shows the sign-in screen: create an account (or sign in). After that it opens straight to the Map. To switch accounts, tap your name at the top left of the Roll Call or Community tab (or go to About) and choose **Sign out**.

The app reads the server address from `ios/RollCall/Config/AppConfig.swift` (`http://localhost:8000`). If the backend isn't running, the app shows "Can't reach RollCall" with a **Try again** button. New Swift files added anywhere inside `ios/RollCall/` are included in the project automatically.

**Testing in the simulator:**
- **Location:** the simulator starts out in California. Set a North Texas location in the simulator's menu (Features → Location → Custom Location), or run `xcrun simctl location booted set 33.0712,-96.1043` (next to the demo grass fire, so a fire report there merges into it).
- **Photos and videos:** add some to the simulator's Photos app by dragging files onto the simulator window, or run `xcrun simctl addmedia booted backend/sample_media/grass_fire_crew.jpg backend/sample_media/grass_fire_clip.mp4`. **Take photo or video** only appears on a real iPhone; the simulator has no camera.

## Live hazard data

The Map shows real, current hazards next to community reports, refreshed every few minutes:

| Source | What it adds | Key |
|---|---|---|
| National Weather Service (api.weather.gov) | Official warnings, watches and advisories, with the exact area each covers | none |
| NASA FIRMS | Fires seen by the VIIRS satellites in the last 2 days (nearby hot spots joined into one fire) | free key in `backend/.env` |
| NASA EONET | Named wildfires NASA is tracking (updated in the last week) | none |
| NOAA Storm Prediction Center | Today's confirmed tornado, wind and hail reports in Texas | none |

Live data is a **diamond** on the map, a community report a **circle**. The color is the kind of hazard: fire red-orange, tornado purple, severe storm amber, flood blue, hurricane magenta, winter storm icy cyan, smoke and air quality gray or brown, injury pink. Tap one for details, its zones and a link to the official source.

Each hazard has a level (`backend/app/hazards/zones.py`): **Immediate danger**, **Evacuate** or **Be cautious**, shown in its details with what to do. Official alerts also shade the exact area the Weather Service drew (a Tornado Warning is Immediate danger, a Tornado Watch Be cautious). The server still works out ring sizes around points (a tornado report 1 / 3 / 8 km, ...), but the map doesn't draw them, to keep it clean. These levels are estimates to help people plan, not official evacuation orders, and the app says so.

**Setup:** put your free NASA FIRMS key (from firms.modaps.eosdis.nasa.gov/api/map_key) in `backend/.env` as `FIRMS_MAP_KEY=...`. That file is never committed. Without it, everything else still works.

**Demo:** the **Live** pill on the map opens the sources and a **Start a demo Tornado Warning** button: a realistic warning near Greenville for 40 minutes, labeled Demo everywhere. Use it for the demo video or on a quiet weather day.

## Sharing one server between Macs

Each Mac normally runs its own server with its own data. To test together (for example, you create an account and your teammate sees your community on their Mac), one Mac shares its server and everyone else connects to it:

1. **On the sharing Mac**, from the `backend` folder:
   ```bash
   scripts/share_server.sh
   ```
   It starts the server if needed, opens a free Cloudflare tunnel (it downloads Cloudflare's `cloudflared` the first time, no account needed) and prints an address like `https://some-words.trycloudflare.com`. Keep that window open; Ctrl+C stops sharing.
2. **On the other Mac**, in the app's sign-in screen: **Server → Change**, paste the address, **Connect**, then sign in. The app checks there's really a RollCall server there before switching.

Things to know:
- The address changes every time sharing restarts, so send the new one.
- Everyone's data lives on the sharing Mac (`backend/rollcall.db`). Running `reset_demo` there wipes everyone's accounts.
- It only works while the sharing Mac is awake with the script running.
- Anyone with the address can reach the server. Accounts still need their password.
- To go back, choose **Server → Use the server on this Mac**.

## Map and the incident log

### Incident log

The **Incidents** button at the top left of the Map unrolls the incident log over the top left of the screen (the map stays usable around it; the X closes it). It's for responders. At the top are four numbers, each a simple count you can check:

| Card | What it counts |
|---|---|
| Active incidents | Incidents nobody is responding to yet (and how many are responding) |
| People detected | The most people the AI has seen at each open incident, added up (and how many may be down) |
| Unverified | Open incidents with no AI evidence yet. Weather reports count here too, since the AI can't recognize a tornado |
| Response time | Average time from the first report to a responder tapping "Mark responding" |

Below them, every incident is listed by priority (highest first), with Open / Resolved / All filters. Tap one and the log folds up, the map flies to it, and its detail sheet opens, including "Why this priority?". Pull down to refresh. The red number on the button counts incidents that are active and high priority. The map and the log share one copy of the data, so a status change shows up on both immediately.

### Incident types

Reports can be about any of these, grouped into "modes" so the map can show one kind of disaster at a time:

| Mode | Types |
|---|---|
| Fire & smoke | Fire, Smoke |
| Severe weather | Tornado, Severe storm (wind, hail, downed lines), Heavy rain, Flood, Hurricane, Winter storm |
| Medical & other | Injury, Other |

## Roll Call privacy model

- Joining is opt-in ("Not now" is always an option), and nothing is shared until you agree on the last sign-up step.
- **You** can always see, edit or delete your household.
- **A volunteer buddy** sees your household only after you accept their offer. Neighbors in your community who volunteer see only your first name and street (and only if you asked for a buddy). A volunteer outside your community can only offer by typing your exact address, only if your community's admin allows outside buddies, and the app gives them the same answer whether or not anyone lives there.
- **Responders** see a household only during an active emergency, and only if it's inside the emergency zone.
- **Nobody else** sees anything. Incident reports on the map don't show who sent them.

These rules are enforced by the server (`backend/app/privacy.py`), not just hidden in the app, and the tests check them.

**Accounts:** passwords are never stored, only a salted scrypt hash. Signing in gives the app a random token, kept in the iPhone Keychain and sent with each request; the server stores only a hash of it.

**Responder accounts** can see households during an emergency, so they aren't made through sign-up. Issue one from the `backend` folder:

```bash
python -m scripts.make_responder chief@example.com "a long password" "Alex Rivera"
```

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Is the server up? |
| `GET` | `/incidents` | List incidents. Filters: `type`, `status`, `since_hours`. Sort: `priority` (default) or `recent` |
| `GET` | `/incidents/{id}` | One incident with reports, media, AI results, timeline and priority breakdown |
| `PATCH` | `/incidents/{id}/status` | Set `active`, `responding` or `resolved` |
| `POST` | `/reports` | New report (form fields + optional photo/video). Merges into a nearby incident when it can |
| `GET` | `/media/...` | Uploaded files, thumbnails and AI-annotated images |
| `POST` | `/households` | Register a household (Roll Call) |
| `GET` `PUT` `DELETE` | `/households/{id}` | See, edit or delete a household, if the privacy rules allow it |
| `GET` | `/volunteers/{id}/households` | A buddy's assigned households (only for that buddy) |
| `POST` | `/auth/signup`, `/auth/signin`, `/auth/signout` | Accounts |
| `GET` `PATCH` | `/me` | The signed-in account (household, volunteer, community); "Not now" |
| `PUT` `DELETE` | `/me/volunteer` | Become (or stop being) a volunteer buddy |
| `GET` | `/me/buddy-requests` | Volunteers offering to check on you; `POST .../{id}/accept` or `/decline` |
| `GET` | `/buddy/residents`, `/buddy/neighbors`, `/buddy/requests` | A volunteer's lists |
| `POST` | `/buddy/requests/community`, `/buddy/requests/address` | Offer to check on a neighbor, or someone by exact address |
| `GET` `POST` | `/communities` | Search or create a community |
| `GET` `PATCH` | `/communities/{id}` | Details; the admin allows or blocks outside buddies |
| `POST` | `/communities/{id}/join`, `/leave`, `/requests/{user}/approve`, `/decline` | Joining and admin approval |

Every Roll Call and Community request must be signed in (`Authorization: Bearer <token>`).

## How report merging works

A new report joins an existing incident if it is the same type, the incident isn't resolved, its newest report was within the last 2 hours, and it's within 300 meters. Otherwise it starts a new incident. See `backend/app/services/merging.py`.

## How the AI works

Every photo or video is analyzed in the background right after upload, so the app never waits:

1. **Low-light check.** The average brightness is measured. If the picture is dark, its contrast is boosted with CLAHE before detection, and that is recorded.
2. **People.** YOLOv8n, a small pretrained neural network, finds people. It runs on a normal laptop CPU.
3. **Fire and smoke.** If a trained model exists at `backend/models/fire.pt`, it is used. Otherwise a hand-written OpenCV rule (the **basic detector**) looks for deeply saturated, red-dominant, unevenly lit flame patches and, in video, flicker. Flame-colored patches that sit on a detected person are ignored, because firefighters' yellow jackets and helmets are flame colored. Smoke is a large, smooth, grayish area in the upper part of the picture.
4. **Who might need help.** People lying down ("may be down") and people close to the flames are flagged from YOLO's boxes (`backend/app/ai/scene.py`).
5. **Video.** About one frame per second is checked (up to 30 seconds). Fire or smoke must appear in at least 2 frames, and the most informative frame is saved with its boxes drawn on.

## How incident priority works

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

## Automated tests

- **Backend:** `cd backend && python -m pytest`. Covers report merging, priority scoring, the AI's scene rules, the incident API, accounts and password safety, household sign-up checks, the privacy rules, buddy offers (including that a typed address reveals nothing), communities and admin approval, Delete my data, and the demo data.
- **iPhone app (UI tests):** start the backend with fresh demo data and the test responder (`python -m scripts.reset_demo`, then `python -m scripts.make_responder test-responder@example.com "responder password"`, then `uvicorn app.main:app`), and press **⌘U** in Xcode. Each test makes the accounts it needs and taps through the real app: the map, the incident log, live data and the demo Tornado Warning, reporting (including Use my location and attaching a photo the AI checks), signing up, in and out, joining the roll call and deleting it, buddy offers, a responder's view, communities and admin approval, and a light/dark screenshot tour of every screen.

## Known limitations

- The app logs one intermittent SwiftUI layout warning ("Invalid frame dimension") while using the address search in the report form. It doesn't affect how anything works, and its source is still being tracked down.
- "May be down" is a hint, not a diagnosis: someone resting on the ground looks the same, and a camera angle can make distances look shorter than they are.
- The basic fire detector was tuned on a small set of photos. In testing it mistook a yellow "Water over road" sign for fire, a gray indoor wall and a hazy overcast sky for smoke, and missed a distant smoke plume and some small flames. A trained model at `models/fire.pt` fixes most of this.
- The AI cannot recognize tornadoes, floods, storms or ice. For those reports it can still count people in the photo, but the weather itself is confirmed by how many people report it.

## Credits

Demo photos and video come from Wikimedia Commons (public domain and Creative Commons). Authors and licenses are listed in [backend/sample_media/CREDITS.md](backend/sample_media/CREDITS.md).
