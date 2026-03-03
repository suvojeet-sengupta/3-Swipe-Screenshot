#!/system/bin/sh
# 3-Finger Swipe Screenshot Module
# uninstall.sh - Cleanup on module removal
# Developer: Suvojeet Sengupta

DATA_DIR="/data/adb/3swipe"
PID_FILE="$DATA_DIR/daemon.pid"

# Stop daemon
if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    sleep 1
    kill -9 "$pid" 2>/dev/null
  fi
fi

# Clean up data directory
rm -rf "$DATA_DIR" 2>/dev/null

# Reset system settings
settings delete system three_finger_screenshot 2>/dev/null
settings delete system three_finger_screenshot_enabled 2>/dev/null
settings delete secure three_finger_screenshot 2>/dev/null
settings delete global three_finger_screenshot 2>/dev/null
settings delete system screenshot_gesture 2>/dev/null
settings delete system three_finger_gesture_screenshot 2>/dev/null

# Reset properties
resetprop --delete persist.sys.three_finger_screenshot 2>/dev/null
resetprop --delete persist.sys.gesture.screenshot 2>/dev/null
resetprop --delete persist.sys.three_finger_gesture 2>/dev/null
