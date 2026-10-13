#!/bin/bash
#
# Share this Mac's RollCall server with other people (like a teammate running
# the app on their own Mac), so everyone uses the SAME accounts and data.
#
#   cd backend
#   scripts/share_server.sh
#
# It starts the server (if it isn't running), then opens a free Cloudflare
# "quick tunnel": a temporary web address like https://abc-def.trycloudflare.com
# that forwards to this Mac. Send that address to your teammate; in the app's
# sign-in screen they tap Server > Change and paste it in.
#
#   * Keep this window open. Sharing stops when you press Ctrl+C or close it.
#   * The address changes every time you run this script.
#   * Everyone's data lives in backend/rollcall.db on THIS Mac, so running
#     python -m scripts.reset_demo wipes everyone's accounts.
#   * Anyone with the address can reach the server. Real accounts still need
#     their password; demo accounts are fictional.
#
# The first run downloads cloudflared (Cloudflare's official tunnel program)
# into backend/tools/. No Cloudflare account is needed.

set -e
cd "$(dirname "$0")/.."            # the backend folder
TOOLS="tools"
CLOUDFLARED="$TOOLS/cloudflared"
PORT=8000

# 1. Get cloudflared the first time.
if [ ! -x "$CLOUDFLARED" ]; then
    case "$(uname -m)" in
        arm64) ARCH="arm64" ;;
        *)     ARCH="amd64" ;;
    esac
    echo "Downloading cloudflared (first time only)..."
    mkdir -p "$TOOLS"
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-$ARCH.tgz" -o "$TOOLS/cloudflared.tgz"
    tar -xzf "$TOOLS/cloudflared.tgz" -C "$TOOLS"
    rm "$TOOLS/cloudflared.tgz"
    chmod +x "$CLOUDFLARED"
fi

# 2. Start the server, unless it's already running.
STARTED_SERVER=""
if curl -fs "http://localhost:$PORT/health" > /dev/null 2>&1; then
    echo "The RollCall server is already running."
else
    echo "Starting the RollCall server..."
    source .venv/bin/activate
    uvicorn app.main:app --port "$PORT" > server.log 2>&1 &
    STARTED_SERVER=$!
    for _ in $(seq 1 30); do
        curl -fs "http://localhost:$PORT/health" > /dev/null 2>&1 && break
        sleep 1
    done
    if ! curl -fs "http://localhost:$PORT/health" > /dev/null 2>&1; then
        echo "The server didn't start. See backend/server.log for the error."
        exit 1
    fi
fi

# 3. Open the tunnel, and stop everything we started when this script ends.
LOG="$TOOLS/tunnel.log"
"$CLOUDFLARED" tunnel --no-autoupdate --url "http://localhost:$PORT" > "$LOG" 2>&1 &
TUNNEL=$!
cleanup() {
    echo
    echo "Stopping sharing..."
    kill "$TUNNEL" 2> /dev/null || true
    [ -n "$STARTED_SERVER" ] && kill "$STARTED_SERVER" 2> /dev/null || true
}
trap cleanup EXIT

# 4. Wait for the address, then wait until it actually answers.
ADDRESS=""
for _ in $(seq 1 60); do
    ADDRESS=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1 || true)
    [ -n "$ADDRESS" ] && break
    sleep 1
done
if [ -z "$ADDRESS" ]; then
    echo "Couldn't open a tunnel. Details are in backend/$LOG"
    exit 1
fi
# (Checked through Cloudflare's own DNS: asking this Mac's DNS too early makes
# it remember "not found" for a few minutes.)
for _ in $(seq 1 30); do
    curl -fs --doh-url https://1.1.1.1/dns-query "$ADDRESS/health" > /dev/null 2>&1 && break
    sleep 1
done

echo
echo "================================================================"
echo "  RollCall is shared at:"
echo
echo "      $ADDRESS"
echo
echo "  Send this to your teammate. In the app: sign-in screen >"
echo "  Server > Change > paste it > Connect."
echo "  Keep this window open. Press Ctrl+C to stop sharing."
echo "================================================================"
wait "$TUNNEL"
