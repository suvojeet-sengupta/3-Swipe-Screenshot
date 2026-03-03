#!/system/bin/sh
# 3-Finger Swipe Screenshot Module
# post-fs-data.sh - Post FS Data Mode
# Developer: Suvojeet Sengupta
#
# Runs after /data is decrypted and mounted.
# Used for early initialization that doesn't depend on boot completion.

MODULE_DIR="${0%/*}"

# Create data directory early  
mkdir -p /data/adb/3swipe 2>/dev/null

# Set system properties for 3-finger screenshot support
# These properties may help enable native support on some ROMs
resetprop persist.sys.three_finger_screenshot 1 2>/dev/null
resetprop persist.sys.gesture.screenshot 1 2>/dev/null
resetprop persist.sys.three_finger_gesture 1 2>/dev/null
resetprop ro.config.three_finger_screenshot true 2>/dev/null
