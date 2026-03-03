#!/system/bin/sh
# 3-Finger Swipe Screenshot Module
# service.sh - Late Start Service
# Developer: Suvojeet Sengupta
#
# This script runs during the late_start service mode,
# after all system services are up and storage is decrypted.

MODULE_DIR="${0%/*}"
DATA_DIR="/data/adb/3swipe"

# Wait for boot to complete
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done

# Extra wait for system services to stabilize
sleep 10

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Try to enable native 3-finger screenshot via system settings
# (Works on some ROMs like MIUI, ColorOS, Realme UI, etc.)
settings put system three_finger_screenshot 1 2>/dev/null
settings put system three_finger_screenshot_enabled 1 2>/dev/null
settings put secure three_finger_screenshot 1 2>/dev/null
settings put global three_finger_screenshot 1 2>/dev/null

# Some AOSP/LineageOS based ROMs
settings put system screenshot_gesture 1 2>/dev/null
settings put system three_finger_gesture_screenshot 1 2>/dev/null

# Log start
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Service starting daemon..." >> "$DATA_DIR/daemon.log"

# Kill any existing daemon
if [ -f "$DATA_DIR/daemon.pid" ]; then
  old_pid=$(cat "$DATA_DIR/daemon.pid" 2>/dev/null)
  if [ -n "$old_pid" ]; then
    kill "$old_pid" 2>/dev/null
    sleep 1
    kill -9 "$old_pid" 2>/dev/null
  fi
  rm -f "$DATA_DIR/daemon.pid"
fi

# Start the 3-finger swipe daemon in background
# Run with nohup to survive shell exit; redirect output to log
nohup sh "$MODULE_DIR/common/3swipe_daemon.sh" >> "$DATA_DIR/daemon.log" 2>&1 &

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daemon launched with PID: $!" >> "$DATA_DIR/daemon.log"
