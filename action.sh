#!/system/bin/sh
# 3-Finger Swipe Screenshot Module
# action.sh - Magisk Manager Action Button
# Developer: Suvojeet Sengupta
#
# This script is executed when tapping the module's action
# button in Magisk Manager. It toggles the feature on/off.

MODULE_DIR="${0%/*}"
DATA_DIR="/data/adb/3swipe"
CONFIG="$DATA_DIR/config.prop"
PID_FILE="$DATA_DIR/daemon.pid"
DAEMON_SCRIPT="$MODULE_DIR/common/3swipe_daemon.sh"

# Initialize config if missing
mkdir -p "$DATA_DIR"
if [ ! -f "$CONFIG" ]; then
  echo "enabled=1" > "$CONFIG"
fi

# Read current state
CURRENT=$(grep "^enabled=" "$CONFIG" 2>/dev/null | cut -d= -f2)

if [ "$CURRENT" = "1" ]; then
  # ── Disable ──
  sed -i 's/^enabled=.*/enabled=0/' "$CONFIG"

  # Stop daemon
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 1
    kill -9 "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
  fi

  echo ""
  echo "╔═══════════════════════════════════╗"
  echo "║  3-Finger Screenshot: DISABLED    ║"
  echo "╚═══════════════════════════════════╝"
  echo ""
  echo "  Gesture detection stopped."
  echo "  Tap again to re-enable."
  echo ""
else
  # ── Enable ──
  sed -i 's/^enabled=.*/enabled=1/' "$CONFIG"

  # Kill existing daemon if any
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 1
    rm -f "$PID_FILE"
  fi

  # Start daemon
  nohup sh "$DAEMON_SCRIPT" >> "$DATA_DIR/daemon.log" 2>&1 &

  echo ""
  echo "╔═══════════════════════════════════╗"
  echo "║  3-Finger Screenshot: ENABLED     ║"
  echo "╚═══════════════════════════════════╝"
  echo ""
  echo "  Gesture detection started."
  echo "  Swipe down with 3 fingers to"
  echo "  capture a screenshot."
  echo ""
  echo "  Daemon PID: $!"
  echo ""
fi
