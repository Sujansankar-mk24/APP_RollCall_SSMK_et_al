# RollCall

Make sure no one gets left behind. RollCall is a community emergency app for North Texas with two halves:

- **An incident map.** Residents report emergencies with a pin and a photo or video. Reports from the same area merge into one incident, AI checks the media for fire, smoke and people, and responders get a priority-ranked list with the evidence before they head out.
- **A roll call.** Households sign up ahead of time and say who lives there and what could make leaving hard: seniors living alone, oxygen or dialysis, no car, pets or livestock. When a tornado warning or flood hits, RollCall asks everyone in the area "Are you safe?". A volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help, most urgent first.

> RollCall supports emergency services. It doesn't replace 911 or contact it for you.

*This README grows with the project. The full version (how RollCall differs from Watch Duty, an architecture diagram, risk scoring, limitations and future work) comes with the final polish step.*

## The app's tabs

| Tab | What it's for |
|---|---|
| **Map** | Live hazards (diamonds) and community reports (circles) with their danger zones. Tap one for details. **Incidents** (top left) unrolls the incident log: key numbers and every incident sorted by priority, with "Why this priority?". **Report incident** needs a recent photo you took and a short description. **Use my location** works like Google Maps: a blue dot with a cone for the way you face, follow and compass modes, and an always-on compass. A warning appears when you're near an active fire, storm or flood, and **↻** asks NASA, NOAA and the Weather Service for new data right away. The **Source** chip shows everything, only community reports, or only live data. **My community** shows where your community's members live, as small house markers with each person's picture floating above (only when zoomed in closer than about a quarter mile). Tap a house for the profile, or tap a picture bubble to pop it (it comes back after 5 seconds). |
| **Roll Call** | **My household**: a **How are you?** card with **I'm safe** and **I need help** (your buddy sees it right away), join the roll call (or choose **Not now**), type your address, accept or decline buddy offers, call or text your buddy, privacy and Delete my data. **I check on**: the neighbors you check on, with Call, Text, Directions and **They need help**, which calls 911 and shows everything the dispatcher will ask for. Responders see their own view. |
| **Community** | The **Weekly Recap**, a stacked photo deck like Locket: swipe or tap through neighborhood photos, each with the poster's name in bold above their caption, and add emoji stickers (❤️ 🙏 👏 😂 😮 💪). Photos are approved by the admin and gone after a week unless pinned, and pinned ones come first. **Connections** shows a small preview of the web, and **View connections** opens it full screen: everyone as floating Liquid Glass bubbles with lines for who checks on whom. Rings mark who has no buddy yet (orange), the admin (yellow), new members (blue, joined in the last hour for the demo) and people away from home (dashed). Drag bubbles, tap one for the name and profile, or press and hold to pop it (it comes back after 5 seconds). Member tags say **Checks on 2** or **Ready to help** only for people who really signed up as volunteers. Also: members split by who has a buddy, **Away from home**, first responders in your town, and other communities to browse. Start one and be its admin. |

The **gear** at the top of every tab opens **Your profile** (your picture, bio, phone, badges, the first responder application, and **Sign out**), **About RollCall** (what the app does, who can see your information, credits) and **Display** (light, dark or match the iPhone, each with a preview, plus six color themes shown with their colors). The pill in the tab bar turns green on the Map, red on Roll Call and orange on Community.

**The logo** is a circle with "RollCall" in the middle and a ring of people around it (`Assets.xcassets/Logo`). In dark mode the center swaps black and white. The app icon uses the same logo, with light, dark and tinted versions. While something loads, the ring of people spins once around the center, settles, pauses about a second and goes again (`LoadingLogo` in `Views/Components/BrandMark.swift`). The very first launch opens on **Welcome to RollCall**, with a photo of a real Hurricane Harvey rescue, then three short intro pages, then sign-up. All text uses the iPhone's system font, SF Pro (SF Pro Text at small sizes and SF Pro Display at large sizes, chosen automatically). It isn't bundled into the app, because iOS already has it and Apple's license doesn't allow copying it.

**The look**, inspired by Phantom and WHOOP: dark first (a near-black page in dark mode, soft gray in light mode), big bold titles, small uppercase labels with wide letter spacing, full-width pill buttons, related rows grouped on rounded cards, capsule chips, a big "Saved ✓" confirmation, a splash screen, and three intro pages on first launch. Nothing uses see-through glass except the connections bubbles, where Liquid Glass makes them feel like real bubbles. Color only appears on status badges (green safe, red needs help, amber waiting), always next to a word. Text never goes below 15 pt. The color theme you pick in Display applies everywhere, the Map's buttons included. The pieces live in `ios/RollCall/Design/Sheet.swift`, `Design/Kit.swift` and `Design/Appearance.swift`.

You sign in once, and the app remembers you until you sign out. There are no placeholder people or communities: everything in Roll Call and Community comes from real accounts made in the app.

## What works so far

- **Map and incident log:** live hazard data with danger zones, a follow-me blue dot and compass, nearby-danger warnings, reporting with a required photo and description, merging, AI photo checks, priority scoring, responder status updates, timeline.
- **Verified first responders:** apply in the app with your agency, role, badge number and a photo of your ID. A person approves it, and only then can you mark incidents responding or resolved. Nobody can mark a tornado, hurricane or storm resolved. Residents can see responders in their town and report one who's fake, abusing the role or reckless.
- **Profiles:** a picture from the camera or library, a bio, a phone, and badges (Volunteer buddy, Looking for a buddy, Away from home, Verified responder).
- **Accounts:** sign up, sign in, stay signed in, sign out. Passwords are hashed with scrypt, and the sign-in token lives in the iPhone Keychain.
- **Roll Call, step 1, household profile:** a five-step sign-up (home, who lives here, needs, contact, review) with a typed address checked on the map and by GPS, **Not now** for people who'd rather not, a clear "who can see this" privacy screen, and **Delete my data**, which really deletes everything.
- **Communities and buddies:** neighborhoods with admin approval, a community picture, the Weekly Recap, and buddy offers from community neighbors (or, for people not in a community, by exact address), always accepted or declined by the resident.
- *(Coming next)* Emergency events from National Weather Service alerts, responder-drawn zones, and demo events.
- *(Coming)* The roll call check-in in English and Spanish, escalation to buddies and responders, the responder roll-call dashboard with risk scores and routes, and buddy matching.

## Notifications and the Lock Screen

Settings (the gear) > **Notifications** has two switches, both off until you turn them on:

- **Danger near me** sends a notification when a fire, storm or flood comes close to you, with **I'm safe** and **I need help** buttons right on it.
- **Live status on the Lock Screen** keeps a live status on the Lock Screen and in the Dynamic Island, the way live sports scores work: "All clear near you" or what's nearby and how far, with the same two buttons. It uses ActivityKit (a Live Activity) and lives in the `RollCallWidgets` extension.

A check-in from any of these goes to `POST /me/check-in`, shows on your household, and your buddy sees **Safe** or **Needs help** next to your name.

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
| `python -m scripts.reset_demo` | Wipes everything (accounts too) and reloads the demo incidents |
| `python -m scripts.clear_test_data` | Removes the UI tests' accounts (`@example.com`) and reloads the demo incidents, keeping real accounts |
| `python -m scripts.download_fire_model` | Downloads the trained fire and smoke model (about 6 MB) |
| `python -m scripts.review_responders` | Reviews first responder applications and reports about responders |
| `python -m scripts.download_samples` | Downloads the sample media only |
| `python -m pytest` | Runs the automated tests |

## Running the iPhone app

1. Start the backend (above) and leave it running.
2. Open `ios/RollCall.xcodeproj` in Xcode.
3. Pick an iPhone simulator at the top of the window (for example, iPhone 18 Pro) and press **Run** (⌘R).

The first time, the app shows the sign-in screen: create an account (or sign in). After that it opens straight to the Map. To switch accounts, tap the gear at the top of any tab, choose **Your profile**, then **Sign out**.

The app reads the server address from `ios/RollCall/Config/AppConfig.swift` (`http://localhost:8000`). If the backend isn't running, the app shows "Can't reach RollCall" with a **Try again** button. New Swift files added anywhere inside `ios/RollCall/` are included in the project automatically.

**Testing in the simulator:**
- **Location:** the simulator starts out in California. Set a North Texas location in the simulator's menu (Features → Location → Custom Location), or run `xcrun simctl location booted set 33.0712,-96.1043` (next to the demo grass fire, so a fire report there merges into it).
- **Photos and videos:** add some to the simulator's Photos app by dragging files onto the simulator window, or run `xcrun simctl addmedia booted backend/sample_media/grass_fire_crew.jpg backend/sample_media/grass_fire_clip.mp4`. **Take photo or video** only appears on a real iPhone, because the simulator has no camera.

## Live hazard data

The Map shows real, current hazards next to community reports, refreshed every few minutes:

| Source | What it adds | Key |
|---|---|---|
| National Weather Service (api.weather.gov) | Official warnings, watches and advisories, with the exact area each covers | none |
| National Hurricane Center (nhc.noaa.gov) | Active hurricanes and tropical storms within 1,500 km of Texas | none |
| NASA FIRMS | Fires seen by the VIIRS satellites in the last 2 days (nearby hot spots joined into one fire) | free key in `backend/.env` |
| NASA EONET | Every kind of natural event NASA tracks in Texas (updated in the last week): wildfires, severe storms and hurricanes, floods, dust, snow and ice, heat and cold, drought, earthquakes, landslides, volcanoes | none |
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

The **Incidents** button at the top left of the Map unrolls the incident log over the top left of the screen (the map stays usable around it, and the X closes it). It's for responders. At the top are four numbers, each a simple count you can check:

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
- **A volunteer buddy** sees your household only after you accept their offer. Neighbors in your community who volunteer see only your first name and street (and only if you asked for a buddy). If you're in a community, your buddy comes from it (a neighbor can get there fast). If you're not, a volunteer can offer by typing your exact address, and the app gives them the same answer whether or not anyone lives there.
- **Profiles:** people in your community can see your profile and your address. Your phone is shown only to your buddy. Anyone can see verified first responders, so residents know who is helping.
- **First responder ID photos** are kept outside the server's shared folder (`backend/private/`), never shown in the app, and deleted as soon as the application is reviewed.
- **Responders** see a household only during an active emergency, and only if it's inside the emergency zone.
- **Nobody else** sees anything. Incident reports on the map don't show who sent them.

These rules are enforced by the server (`backend/app/privacy.py`), not just hidden in the app, and the tests check them.

**Accounts:** passwords are never stored, only a salted scrypt hash. Signing in gives the app a random token, kept in the iPhone Keychain and sent with each request; the server stores only a hash of it.

**First responder accounts.** People apply in the app (sign up with **I'm a first responder**, or Profile > **Are you a first responder?**). There's no government database to check IDs against, so a person reviews each application from the `backend` folder:

```bash
python -m scripts.review_responders              # list applications waiting, and reports about responders
python -m scripts.review_responders approve 12   # approve account 12 (its ID photo is deleted)
python -m scripts.review_responders reject 12
python -m scripts.review_responders revoke 12    # take a responder's access away
```

For test and demo accounts, `python -m scripts.make_responder chief@example.com "a long password" "Alex Rivera"` makes a verified responder directly.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Is the server up? |
| `GET` | `/incidents` | List incidents. Filters: `type`, `status`, `since_hours`. Sort: `priority` (default) or `recent` |
| `GET` | `/incidents/{id}` | One incident with reports, media, AI results, timeline and priority breakdown |
| `PATCH` | `/incidents/{id}/status` | A verified first responder sets `active`, `responding` or `resolved` (not for weather nobody can stop) |
| `POST` | `/reports` | New report (form fields, a description of 10+ characters and a photo). Merges into a nearby incident when it can. A new fire, smoke or injury report is **under review** (not on the map, nobody alerted) until the AI finds what was reported |
| `POST` | `/incidents/{id}/review` | A verified first responder confirms a report under review (`real: true`) or dismisses it |
| `GET` | `/hazards?refresh=true` | Live hazards. `refresh` asks the sources again right away (at most every 30 seconds) |
| `GET` | `/media/...` | Uploaded files, thumbnails and AI-annotated images |
| `POST` | `/households` | Register a household (Roll Call) |
| `GET` `PUT` `DELETE` | `/households/{id}` | See, edit or delete a household, if the privacy rules allow it |
| `GET` | `/volunteers/{id}/households` | A buddy's assigned households (only for that buddy) |
| `POST` | `/auth/signup`, `/auth/signin`, `/auth/signout` | Accounts |
| `GET` `PATCH` | `/me` | The signed-in account (household, volunteer, community), and "Not now" |
| `PUT` `DELETE` | `/me/volunteer` | Become (or stop being) a volunteer buddy |
| `GET` | `/me/buddy-requests` | Volunteers offering to check on you. `POST .../{id}/accept` or `/decline` |
| `GET` | `/buddy/residents`, `/buddy/neighbors`, `/buddy/requests` | A volunteer's lists |
| `POST` | `/buddy/requests/community`, `/buddy/requests/address` | Offer to check on a neighbor, or someone by exact address |
| `GET` `POST` | `/communities` | Search or create a community |
| `GET` `PATCH` | `/communities/{id}` | Details, members (for members), the Weekly Recap (for everyone). The admin can rename it |
| `PUT` | `/communities/{id}/photo` | The admin sets the community picture |
| `POST` `DELETE` | `/communities/{id}/recap`, `/recap/{photo}/approve`, `/reject`, `/pin`, `/unpin` | Weekly Recap photos |
| `POST` | `/me/check-in` | "I'm safe" or "I need help" (`status: safe` or `needs_help`), from the app, a notification or the Lock Screen |
| `POST` | `/communities/{id}/recap/{photo}/react` | Add, change or remove your emoji sticker on a recap photo |
| `GET` | `/communities/{id}/homes` | Where members live, for **My community** on the map (members only, and only people who joined the roll call) |
| `PATCH` | `/me/profile` | Your name, bio, phone and "away from home" |
| `PUT` `DELETE` | `/me/photo` | Your profile picture |
| `GET` | `/people/{id}` | Someone's profile, if you're allowed to see it |
| `POST` | `/me/responder-application` | Apply as a first responder (agency, role, badge, town, ID photo) |
| `GET` | `/responders?city=` | Verified first responders |
| `POST` | `/responders/{id}/report` | Report a responder as fake, abusive or reckless |
| `POST` | `/communities/{id}/join`, `/leave`, `/requests/{user}/approve`, `/decline` | Joining and admin approval |

Every Roll Call and Community request must be signed in (`Authorization: Bearer <token>`).

## Reports under review

No new report goes on the map right away. The AI checks the photo first (a few seconds), and it has to see **the disaster that was reported**, not just people. Seeing people is never enough: a selfie in a bedroom labeled "winter storm" stays off the map. The rules are in `backend/app/ai/verify.py`:

- **Fire or smoke:** the trained fire model finds flames or smoke, or the iPhone's scene check sees fire or smoke outdoors. A fireplace, candle or grill doesn't count.
- **Weather** (tornado, flood, storm, winter storm, heavy rain): the iPhone's scene check (Apple's Vision framework, run on the phone) has to see it, for example snow or ice for a winter storm and water over the ground for a flood. A photo taken indoors never confirms weather.
- **Injury:** a person, and not a normal indoor room.

If the AI confirms it, the incident appears on the map and nearby people are warned. If it doesn't, the report stays **under review**: hidden from the map, nobody alerted, and the person who sent it is told why ("The AI couldn't see snow or ice in the photo"). Verified first responders see it in the incident log marked **Needs review**, with **It's real, show it** and **Not real**. A report that joins an incident already on the map stays with it.

## How report merging works

A new report joins an existing incident if it is the same type, the incident isn't resolved, its newest report was within the last 2 hours, and it's within 300 meters. Otherwise it starts a new incident. See `backend/app/services/merging.py`.

## How the AI works

Every photo or video is analyzed in the background right after upload, so the app never waits:

1. **Low-light check.** The average brightness is measured. If the picture is dark, its contrast is boosted with CLAHE before detection, and that is recorded.
2. **People.** YOLOv8n, a small pretrained neural network, finds people. It runs on a normal laptop CPU.
3. **Fire and smoke.** A trained YOLOv8n model ([rabahdev/fire-smoke-yolov8n](https://huggingface.co/rabahdev/fire-smoke-yolov8n), trained on D-Fire, a public set of 21,000+ real fire and smoke photos, AGPL-3.0) is used when it's at `backend/models/fire.pt`. Download it once with `python -m scripts.download_fire_model`. It only counts a detection at 45% confidence or more. Without it, a hand-written OpenCV rule (the **basic detector**) looks for deeply saturated, red-dominant, unevenly lit flame patches and, in video, flicker. Flame-colored patches that sit on a detected person are ignored, because firefighters' yellow jackets and helmets are flame colored. The basic detector only reports smoke next to flames it found, because a gray wall looks like smoke to a color rule.
4. **Scene check.** Before the photo is sent, the iPhone labels the scene on the device with Apple's Vision framework (snow, water, fire, indoor room, and so on). Only the labels are sent with the report, and `verify.py` uses them to confirm weather (see Reports under review).
5. **Who might need help.** People lying down ("may be down") and people close to the flames are flagged from YOLO's boxes (`backend/app/ai/scene.py`).
6. **Video.** About one frame per second is checked (up to 30 seconds). Fire or smoke must appear in at least 2 frames, and the clearest frame is saved with its boxes drawn on.

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

The −20 only applies to types the AI can check. It looks for flames, smoke and people, so for a fire report "no evidence yet" means something. It can't recognize a tornado or a flooded road, so weather reports aren't marked down for that. The number of independent reports counts instead.

## Automated tests

- **Backend:** `cd backend && python -m pytest`. Covers report merging, priority scoring, the AI's scene rules, the incident API, accounts and password safety, household sign-up checks, the privacy rules, buddy offers (including that a typed address reveals nothing), communities and admin approval, Delete my data, and the demo data.
- **iPhone app (UI tests):** start the backend with fresh demo data and the test responder (`python -m scripts.clear_test_data`, which keeps real accounts, then `python -m scripts.make_responder test-responder@example.com "responder password"`, then `uvicorn app.main:app`), and press **⌘U** in Xcode. Each test makes the accounts it needs and taps through the real app: the map, the incident log, live data and the demo Tornado Warning, reporting (including Use my location and attaching a photo the AI checks), signing up, in and out, joining the roll call and deleting it, buddy offers, a responder's view, communities and admin approval, and a light/dark screenshot tour of every screen. Run `python -m scripts.clear_test_data` again afterwards to remove the accounts the tests made.

## Known limitations

- The app logs one intermittent SwiftUI layout warning ("Invalid frame dimension") while using the address search in the report form. It doesn't affect how anything works, and its source is still being tracked down.
- "May be down" is a hint, not a diagnosis: someone resting on the ground looks the same, and a camera angle can make distances look shorter than they are.
- The basic fire detector was tuned on a small set of photos. In testing it mistook a yellow "Water over road" sign for fire and missed some small flames. It no longer reports smoke without flames. The trained model (`python -m scripts.download_fire_model`) fixes most of this.
- Report photos must carry a camera's name and a date from the last 2 days. That blocks screenshots, most saved images and old photos, but someone could still edit that information on purpose.
- First responder IDs are checked by a person, not against a government database.
- The scene check recognizes snow, water, storms and fire from general labels, not a model trained on disasters. It can miss a real one (the report then waits for a responder) and could be fooled by a photo of a snowy picture on a screen, which the recent-camera-photo rule mostly blocks.
- Notifications and the Lock Screen status only update while RollCall is open or was used recently. Waking a closed app needs push messages from a server, which this project doesn't have.

## Credits

The Welcome screen photo is "Support during Hurricane Harvey" (South Carolina National Guard rescuing residents in Port Arthur, Texas, 2017), public domain, from Wikimedia Commons. About > Sources lists every map, data source and model the app uses, with links. Demo photos and video come from Wikimedia Commons (public domain and Creative Commons). Authors and licenses are listed in [backend/sample_media/CREDITS.md](backend/sample_media/CREDITS.md).
