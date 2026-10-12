# RollCall

Emergency roll call for North Texas. Households sign up ahead of time and say who lives there and what could make leaving hard: seniors living alone, oxygen or dialysis, no car, pets or livestock. When a tornado warning or flood hits, RollCall asks everyone in the area "Are you safe?". A volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help, most urgent first.

> RollCall helps responders find you. It is not a 911 service. **In a life-threatening emergency, call 911.**

*This README grows with the project. The full version (how RollCall differs from Watch Duty, an architecture diagram, risk scoring, limitations and future work) comes with the final polish step.*

## What works so far

1. **Household profile.** A five-step sign-up (home, who lives here, needs, contact, review), a clear "who can see this" privacy screen, and **Delete my data**, which really deletes everything.
2. *(Coming next)* Emergency events from National Weather Service alerts, responder-drawn zones, and demo events.
3. *(Coming)* The roll call check-in, in English and Spanish.
4. *(Coming)* Escalation to buddies and responders.
5. *(Coming)* Responder dashboard with risk scores and routes.
6. *(Coming)* Volunteer buddy view and matching.

## Project layout

```
backend/   Python FastAPI server and SQLite database
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

# 2. Load the fictional demo data (40 households, 8 volunteers)
python -m scripts.reset_demo

# 3. Start the server
uvicorn app.main:app --reload
```

Open http://localhost:8000/docs to see and try every endpoint in your browser.

In a new terminal, run `source .venv/bin/activate` again before using `python` or `uvicorn`.

| Command | What it does |
|---|---|
| `python -m scripts.reset_demo` | Wipes everything and reloads the demo households and volunteers |
| `python -m pytest` | Runs the automated tests |

## Running the iPhone app

1. Start the backend (above) and leave it running.
2. Open `ios/RollCall.xcodeproj` in Xcode.
3. Pick an iPhone simulator at the top of the window (for example, iPhone 18 Pro) and press **Run** (⌘R).
4. On the welcome screen, choose who you are: a resident, a volunteer buddy, or a responder. To change roles later, tap your name at the top left, then **Switch role**.

The app reads the server address from `ios/RollCall/Config/AppConfig.swift` (`http://localhost:8000`). New Swift files added anywhere inside `ios/RollCall/` are included in the project automatically.

**Location in the simulator:** the simulator starts out in California. Set a North Texas location in the simulator's menu (Features → Location → Custom Location), or run `xcrun simctl location booted set 33.1385,-96.1108` (Greenville).

## Privacy model

- Joining is opt-in, and nothing is shared until you agree on the last sign-up step.
- **You** can always see, edit or delete your household.
- **Your volunteer buddy** sees only the households assigned to them.
- **Responders** see a household only during an active emergency, and only if it's inside the emergency zone.
- **Nobody else** sees anything.

These rules are enforced by the server (`backend/app/privacy.py`), not just hidden in the app, and the tests check them.

The demo has no real accounts. The app says who you're acting as with two headers (`X-Demo-Role`, `X-Demo-Id`). A real version would use proper sign-in.

All demo households and volunteers are fictional: made-up names, made-up street numbers, and `555-01xx` phone numbers.

## Automated tests

- **Backend:** `cd backend && python -m pytest`. Covers sign-up checks, the privacy rules for each role, Delete my data, and the demo data.
- **iPhone app (UI tests):** start the backend with fresh demo data (`python -m scripts.reset_demo`, then `uvicorn app.main:app`), then press **⌘U** in Xcode. The tests tap through the real app: registering a household step by step and deleting it, acting as a demo household, a buddy seeing only their neighbors, and a responder seeing nothing without an emergency.
