#!/bin/bash
#
# Records the walkthrough video of RescueSight.
#
#   1. resets the demo data and starts the backend
#   2. reinstalls the app on the iPhone simulator (so it starts in light mode)
#   3. records the screen while DemoWalkthrough taps through the whole app
#   4. records a second short clip with the backend switched off (offline state)
#   5. builds the final video with captions, tap rings and a voice-over
#
# Run from anywhere:   tools/record_demo.sh
# Results:             demo_video/RescueSight-2min.mp4 (short) and RescueSight-walkthrough.mp4 (full, ~14 min)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-iPhone 18 Pro}"
BUNDLE="com.sujansankar.RescueSight"
OUT_DIR="$ROOT/demo_video"
WORK="$OUT_DIR/work"
PY="$ROOT/backend/.venv/bin/python"
DERIVED="$WORK/DerivedData"
SIGNAL="/private/tmp/rs_signal_start_backend"
PHOTO_LABEL="Photo, October 09, 7:07 AM"

now() { "$PY" -c "import time; print(f'{time.time():.3f}')"; }

start_backend() {
    (cd "$ROOT/backend" && "$PY" -m uvicorn app.main:app --port 8000 >> "$WORK/server.log" 2>&1 &)
    until curl -s localhost:8000/health > /dev/null; do sleep 0.5; done
}
stop_backend() { pkill -f "uvicorn app.main:app" || true; sleep 1; }

# Start recording and wait until the simulator says it has really started.
# Sets REC_START to the wall-clock time the recording began.
REC_PID=""
start_recording() {   # $1 = video file
    rm -f "$WORK/rec.err"
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$1" 2> "$WORK/rec.err" &
    REC_PID=$!
    for _ in $(seq 1 300); do
        grep -q "Recording started" "$WORK/rec.err" 2> /dev/null && break
        sleep 0.05
    done
    grep -q "Recording started" "$WORK/rec.err" || { echo "The screen recording didn't start:"; cat "$WORK/rec.err"; exit 1; }
    REC_START=$(now)
}
stop_recording() {
    if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2> /dev/null; then
        REC_STOP=$(now)
        kill -INT "$REC_PID"
        wait "$REC_PID" || true
    fi
    REC_PID=""
}
# Whatever happens (even a failure), never leave a recording running.
trap stop_recording EXIT

run_test() {   # $1 = test name, $2 = events file
    rm -f "$2"
    TEST_RUNNER_RS_DEMO=1 TEST_RUNNER_RS_EVENTS_FILE="$2" TEST_RUNNER_RS_PHOTO_LABEL="$PHOTO_LABEL" \
    xcodebuild -project "$ROOT/ios/RescueSight.xcodeproj" -scheme RescueSight \
        -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED" \
        test-without-building -only-testing:"RescueSightUITests/DemoWalkthrough/$1" > "$WORK/$1.log" 2>&1 \
        || { echo "The $1 run failed; see $WORK/$1.log"; return 1; }
}

mkdir -p "$WORK"
rm -f "$WORK"/*.mov "$WORK"/*.mov.* "$WORK"/*.jsonl "$WORK/server.log"  # (also removes old *_fixed.mov)
pkill -INT -f "simctl io .* recordVideo" 2> /dev/null || true   # a leftover recording from an earlier run

echo "1/6  Resetting demo data and starting the backend"
stop_backend
(cd "$ROOT/backend" && "$PY" -m scripts.reset_demo > /dev/null)
start_backend

echo "2/6  Building the app and its UI tests"
xcrun simctl boot "$DEVICE" 2> /dev/null || true
xcodebuild -project "$ROOT/ios/RescueSight.xcodeproj" -scheme RescueSight \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED" build-for-testing > "$WORK/build.log" 2>&1

echo "3/6  Preparing the simulator (fresh app, light mode, location, a photo of the fire)"
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2> /dev/null || true
xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/RescueSight.app"
xcrun simctl privacy "$DEVICE" grant location "$BUNDLE"
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl location "$DEVICE" set 33.0712,-96.1043
# A copy of the fire photo with its own date, so the walkthrough can find it in the picker.
"$PY" -c "import cv2, sys; cv2.imwrite(sys.argv[2], cv2.imread(sys.argv[1]), [cv2.IMWRITE_JPEG_QUALITY, 93])" \
    "$ROOT/backend/sample_media/grass_fire_line.jpg" "$WORK/fire_photo.jpg"
touch -t 202610090707 "$WORK/fire_photo.jpg"
xcrun simctl addmedia "$DEVICE" "$WORK/fire_photo.jpg"

echo "4/6  Recording the walkthrough (about 9 minutes)"
start_recording "$WORK/clip1.mov"
run_test testWalkthrough "$WORK/events1.jsonl"
stop_recording
STOP1=$REC_STOP

echo "5/6  Recording the offline state"
stop_backend
rm -f "$SIGNAL"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2> /dev/null || true
start_recording "$WORK/clip2.mov"
run_test testOfflineState "$WORK/events2.jsonl" &
TEST_PID=$!
until [ -f "$SIGNAL" ] || ! kill -0 "$TEST_PID" 2> /dev/null; do sleep 0.2; done
[ -f "$SIGNAL" ] && start_backend
wait "$TEST_PID"
stop_recording
STOP2=$REC_STOP

echo "6/6  Building the video (captions, tap rings, voice-over)"
# The simulator's recordings confuse ffmpeg when it reads them start to
# finish (scenes come out minutes early). Re-saving them with macOS's own
# converter (the engine QuickTime uses) fixes the timing.
for clip in clip1 clip2; do
    avconvert --source "$WORK/$clip.mov" --preset Preset1920x1080 --output "$WORK/${clip}_fixed.mov" --replace > /dev/null
done
echo "$STOP1" > "$WORK/stop1.txt"
echo "$STOP2" > "$WORK/stop2.txt"
"$PY" "$ROOT/tools/make_demo_video.py" \
    --clip "$WORK/clip1_fixed.mov" "$WORK/events1.jsonl" "$STOP1" \
    --clip "$WORK/clip2_fixed.mov" "$WORK/events2.jsonl" "$STOP2" \
    --out "$OUT_DIR/RescueSight-walkthrough.mp4"

# The ~2 minute version, cut from the same recordings.
"$PY" "$ROOT/tools/make_short_video.py"

# Leave the demo data clean for next time.
(cd "$ROOT/backend" && "$PY" -m scripts.reset_demo > /dev/null)
echo "Finished: $OUT_DIR/RescueSight-walkthrough.mp4"
