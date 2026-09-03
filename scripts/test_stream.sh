#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT=19350
RTMP_URL="rtmp://127.0.0.1:$PORT/live/test"
OUTPUT_FILE="/tmp/livestreamer_test_out.flv"
rm -f "$OUTPUT_FILE"

echo "========================================"
echo " Livestreamer End-to-End Push Stream Test"
echo "========================================"
echo "Target URL: $RTMP_URL"

echo "1. Building Livestreamer..."
swift build -c debug

BIN="$ROOT_DIR/.build/debug/Livestreamer"

echo "2. Starting local RTMP ingest server (ffmpeg)..."
ffmpeg -v info -listen 1 -i "$RTMP_URL" -t 5 -c copy -f flv "$OUTPUT_FILE" -y > /tmp/ffmpeg_rtmp.log 2>&1 &
FFMPEG_PID=$!

cleanup() {
    if kill -0 "$FFMPEG_PID" 2>/dev/null; then
        kill -9 "$FFMPEG_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait a moment for ffmpeg to bind port
sleep 1

echo "3. Launching Livestreamer in test-stream mode (duration: 3s)..."
"$BIN" --test-stream "$RTMP_URL" --duration 3

echo "4. Waiting for stream ingest to finish..."
wait "$FFMPEG_PID" 2>/dev/null || true

echo "5. Verifying ingested stream..."
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$OUTPUT_FILE")
    echo "SUCCESS: Recorded stream file size = $FILE_SIZE bytes"
    ffprobe -v error -show_entries stream=codec_name,codec_type,width,height,r_frame_rate -of default=noprint_wrappers=1 "$OUTPUT_FILE"
    echo "========================================"
    echo " END-TO-END LIVE STREAMING TEST PASSED!"
    echo "========================================"
    exit 0
else
    echo "ERROR: Output file is missing or empty!"
    echo "FFmpeg Log:"
    cat /tmp/ffmpeg_rtmp.log
    exit 1
fi
