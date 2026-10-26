#!/bin/bash
#
# Records the RollCall demo video.
#
#   1. sets up a made-up neighborhood on the running backend (fictional
#      people only: Rosa Martinez, Daniel Brooks, Lena Park in "Pecan Hollow")
#      and starts the demo Tornado Warning
#   2. records the iPhone simulator's screen while testDemoVideoTour taps
#      through the app, one scene per part of the script
#   3. builds the finished video (tools/make_demo_video.py): each part is cut
#      to the exact length of that speaker's lines
#   4. removes the made-up accounts again and ends the demo warning
#
# Before running: start the backend (cd backend && uvicorn app.main:app) and
# quit Xcode, so the build isn't blocked.
#
# Run from anywhere:   tools/record_demo.sh
# Results:             demo_video/RollCall-demo.mp4 (with the lines on screen)
#                      demo_video/RollCall-demo-clean.mp4 (no lines, for voice-over)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-iPhone 18 Pro}"
OUT_DIR="$ROOT/demo_video"
WORK="$OUT_DIR/work"
PY="$ROOT/backend/.venv/bin/python"
API="http://localhost:8000"
JSON="content-type: application/json"
mkdir -p "$WORK"

curl -sf "$API/health" > /dev/null || { echo "Start the backend first: cd backend && uvicorn app.main:app"; exit 1; }

# ---------------------------------------------------------------------------
# 1. The made-up neighborhood
# ---------------------------------------------------------------------------
(cd "$ROOT/backend" && "$PY" -m scripts.clear_test_data > /dev/null)
TAG=$RANDOM
signup() {   # name, email name -> "token id"
    curl -sf -XPOST "$API/auth/signup" -H "$JSON" \
        -d "{\"name\":\"$1\",\"email\":\"$2.$TAG@example.com\",\"password\":\"demo video password\"}" |
        "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['token'], d['me']['id'])"
}
read -r ROSA ROSA_ID <<< "$(signup "Rosa Martinez" rosa)"
read -r DAN DAN_ID <<< "$(signup "Daniel Brooks" daniel)"
read -r LENA LENA_ID <<< "$(signup "Lena Park" lena)"
auth() { echo "authorization: Bearer $1"; }

COMMUNITY=$(curl -sf -XPOST "$API/communities" -H "$(auth "$ROSA")" -H "$JSON" \
    -d '{"name":"Pecan Hollow","city":"Greenville"}' | "$PY" -c "import json,sys; print(json.load(sys.stdin)['id'])")
for pair in "$DAN $DAN_ID" "$LENA $LENA_ID"; do
    read -r token id <<< "$pair"
    curl -sf -XPOST "$API/communities/$COMMUNITY/join" -H "$(auth "$token")" > /dev/null
    curl -sf -XPOST "$API/communities/$COMMUNITY/requests/$id/approve" -H "$(auth "$ROSA")" > /dev/null
done

household() {   # token, name, street, phone, extra JSON fields
    curl -sf -XPOST "$API/households" -H "$(auth "$1")" -H "$JSON" -d "{\"contact_name\":\"$2\",\"phone\":\"$4\",
        \"address\":\"$3\",\"city\":\"Greenville\",\"zip_code\":\"75401\",\"latitude\":33.1372,\"longitude\":-96.1105,
        \"wants_buddy\":true $5}" > /dev/null
}
household "$ROSA" "Rosa Martinez" "1418 Pecan Hollow Dr" "(903) 555-0142" ',"seniors":1,"medical_equipment":["oxygen"],"no_vehicle":true'
household "$DAN" "Daniel Brooks" "1422 Pecan Hollow Dr" "(903) 555-0177" ',"adults":2,"children":1'
household "$LENA" "Lena Park" "1406 Pecan Hollow Dr" "(903) 555-0119" ',"seniors":1,"pets":true'

# Daniel checks on Rosa.
curl -sf -XPUT "$API/me/volunteer" -H "$(auth "$DAN")" -H "$JSON" -d '{"city":"Greenville"}' > /dev/null
curl -sf -XPOST "$API/people/$ROSA_ID/buddy-offer" -H "$(auth "$DAN")" > /dev/null
REQUEST=$(curl -sf "$API/me/buddy-requests" -H "$(auth "$ROSA")" | "$PY" -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
curl -sf -XPOST "$API/me/buddy-requests/$REQUEST/accept" -H "$(auth "$ROSA")" > /dev/null
curl -sf -XPATCH "$API/me/profile" -H "$(auth "$LENA")" -H "$JSON" -d '{"away_from_home":true}' > /dev/null

# Weekly Recap photos (public domain / Creative Commons, see backend/sample_media/CREDITS.md).
recap() {   # token, file, caption
    curl -sf -XPOST "$API/communities/$COMMUNITY/recap" -H "$(auth "$1")" \
        -F "file=@$ROOT/backend/sample_media/$2" -F "caption=$3" > /dev/null
}
recap "$ROSA" downed_power_lines.jpg "Crews had the lines back up by Sunday"
recap "$ROSA" flooded_intersection.jpg "Stay off Lee St until the water goes down"
recap "$ROSA" controlled_burn_smoke.jpg "The prescribed burn east of town, from our porch"
PHOTO=$(curl -sf "$API/communities/$COMMUNITY" -H "$(auth "$ROSA")" | "$PY" -c "import json,sys; print(json.load(sys.stdin)['recap'][0]['id'])")
curl -sf -XPOST "$API/communities/$COMMUNITY/recap/$PHOTO/react" -H "$(auth "$DAN")" -H "$JSON" -d '{"emoji":"🙏"}' > /dev/null
curl -sf -XPOST "$API/communities/$COMMUNITY/recap/$PHOTO/react" -H "$(auth "$LENA")" -H "$JSON" -d '{"emoji":"❤️"}' > /dev/null

# The demo Tornado Warning, so a warning is on the map even on a clear day.
curl -sf -XPOST "$API/demo/tornado-warning" -H "$(auth "$ROSA")" > /dev/null

# A fire photo in the simulator's library, for the report scene.
xcrun simctl boot "$DEVICE" 2> /dev/null || true
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl addmedia "$DEVICE" "$ROOT/backend/sample_media/grass_fire_line.jpg"

# ---------------------------------------------------------------------------
# 2. Record while the tour taps through the app
# ---------------------------------------------------------------------------
EVENTS="$WORK/events.jsonl"
VIDEO="$WORK/screen.mov"
rm -f "$EVENTS" "$VIDEO" "$WORK/rec.err"
echo "Building the app and starting the tour..."
(cd "$ROOT/ios" && xcodebuild -project RollCall.xcodeproj -scheme RollCall \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$WORK/DerivedData" \
    build-for-testing > "$WORK/build.log" 2>&1) || { echo "Build failed, see $WORK/build.log"; exit 1; }

xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO" 2> "$WORK/rec.err" &
REC_PID=$!
for _ in $(seq 1 300); do grep -q "Recording started" "$WORK/rec.err" 2> /dev/null && break; sleep 0.05; done
REC_START=$("$PY" -c "import time; print(f'{time.time():.3f}')")
trap 'kill -INT $REC_PID 2> /dev/null || true' EXIT

(cd "$ROOT/ios" && TEST_RUNNER_RC_DEMO_TOKEN="$ROSA" TEST_RUNNER_RC_DEMO_EVENTS="$EVENTS" xcodebuild \
    -project RollCall.xcodeproj -scheme RollCall -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$WORK/DerivedData" -only-testing:RollCallUITests/RollCallUITests/testDemoVideoTour \
    test-without-building > "$WORK/tour.log" 2>&1) || echo "The tour reported a problem, see $WORK/tour.log"

kill -INT $REC_PID; wait $REC_PID || true
trap - EXIT

# Screenshots for the design slides, in light and dark mode.
shot() {   # tab, appearance, file
    xcrun simctl ui "$DEVICE" appearance "$2"
    xcrun simctl launch --terminate-running-process "$DEVICE" com.sujansankar.RollCall -RCSignOut YES -RSSkipIntro YES \
        -RCToken "$ROSA" -RCServerURL "$API" -RSTab "$1" > /dev/null
    sleep 9
    xcrun simctl io "$DEVICE" screenshot "$WORK/shot_$3.png" > /dev/null 2>&1
}
shot rollCall light rollcall_light
shot community light community_light
shot rollCall dark rollcall_dark
xcrun simctl ui "$DEVICE" appearance light

# ---------------------------------------------------------------------------
# 3. Build the video, 4. clean up
# ---------------------------------------------------------------------------
BUILT=yes
"$PY" "$ROOT/tools/make_demo_video.py" --video "$VIDEO" --events "$EVENTS" --start "$REC_START" --out "$OUT_DIR" || BUILT=no

curl -sf -XDELETE "$API/demo/tornado-warning" -H "$(auth "$ROSA")" > /dev/null || true
(cd "$ROOT/backend" && "$PY" -m scripts.clear_test_data > /dev/null)
[ "$BUILT" = yes ] || { echo "The video couldn't be built (see above). The demo accounts were removed."; exit 1; }
echo "Done: $OUT_DIR/RollCall-demo.mp4 and $OUT_DIR/RollCall-demo-clean.mp4"
