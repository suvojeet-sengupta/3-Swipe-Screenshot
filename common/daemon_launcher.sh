#!/system/bin/sh
# 3-Finger Swipe Screenshot — Daemon Launcher
# Developer: Suvojeet Sengupta
#
# This script launches the daemon in a fully detached process.
# Safe to call from service.sh, action.sh, or KernelSU WebUI exec().

DATA_DIR="/data/adb/3swipe"
PID_FILE="$DATA_DIR/daemon.pid"
LOG_FILE="$DATA_DIR/daemon.log"
DAEMON="/data/adb/modules/three_swipe_screenshot/common/3swipe_daemon.sh"

ACTION="${1:-restart}"

mkdir -p "$DATA_DIR"

# Kill existing daemon
if [ -f "$PID_FILE" ]; then
  old=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$old" ]; then
    kill "$old" 2>/dev/null
    sleep 1
    kill -9 "$old" 2>/dev/null
  fi
  rm -f "$PID_FILE"
fi

if [ "$ACTION" = "stop" ]; then
  echo "[$(date '+%m-%d %H:%M:%S')] Daemon stopped by user" >> "$LOG_FILE"
  echo "stopped"
  exit 0
fi

# Ensure enabled=1 in config before starting
CONFIG="$DATA_DIR/config.prop"
if [ -f "$CONFIG" ]; then
  if grep -q '^enabled=0' "$CONFIG" 2>/dev/null; then
    sed -i 's/^enabled=0/enabled=1/' "$CONFIG"
    echo "[$(date '+%m-%d %H:%M:%S')] Launcher: set enabled=1 in config" >> "$LOG_FILE"
  fi
else
  mkdir -p "$DATA_DIR"
  echo "enabled=1" > "$CONFIG"
fi

# Launch daemon fully detached using multiple methods
echo "[$(date '+%m-%d %H:%M:%S')] Launcher: starting daemon..." >> "$LOG_FILE"

# Method: use daemonize via sh -c with double-fork
(sh "$DAEMON" >> "$LOG_FILE" 2>&1 &) &

# Wait a moment and verify
sleep 2

if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "[$(date '+%m-%d %H:%M:%S')] Launcher: daemon confirmed running (PID $pid)" >> "$LOG_FILE"
    echo "running:$pid"
    exit 0
  fi
fi

echo "[$(date '+%m-%d %H:%M:%S')] Launcher: WARNING daemon may not have started" >> "$LOG_FILE"
echo "failed"
exit 1
