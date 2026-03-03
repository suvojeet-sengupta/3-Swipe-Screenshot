#!/system/bin/sh
# 3-Finger Swipe Screenshot Module
# Customize Installation Script
# Developer: Suvojeet Sengupta

SKIPUNZIP=0

# Minimum API level check (Android 11 = API 30)
if [ "$API" -lt 30 ]; then
  abort "! This module requires Android 11 (API 30) or higher. Your API level: $API"
fi

ui_print ""
ui_print "╔═══════════════════════════════════════╗"
ui_print "║  3-Finger Swipe Screenshot            ║"
ui_print "║  Developer: Suvojeet Sengupta          ║"
ui_print "║  Version: v2.5.0                       ║"
ui_print "╚═══════════════════════════════════════╝"
ui_print ""
ui_print "- Device: $(getprop ro.product.model)"
ui_print "- Android: $(getprop ro.build.version.release) (API $API)"
ui_print "- ROM: $(getprop ro.build.display.id)"
ui_print ""

# Create necessary directories
ui_print "- Setting up module directories..."
mkdir -p "$MODPATH/common"
mkdir -p "$MODPATH/webroot"
mkdir -p "/data/adb/3swipe"

# Copy daemon and config
ui_print "- Installing 3-finger swipe daemon..."
cp -af "$MODPATH/common/3swipe_daemon.sh" "$MODPATH/common/"
chmod 0755 "$MODPATH/common/3swipe_daemon.sh"

# Initialize config — force enabled on dirty flash
if [ -f "/data/adb/3swipe/config.prop" ]; then
  ui_print "- Existing config found (dirty flash) — enabling..."
  sed -i 's/^enabled=.*/enabled=1/' "/data/adb/3swipe/config.prop"
else
  ui_print "- Creating default configuration..."
  cat > "/data/adb/3swipe/config.prop" << 'CONFIGEOF'
# 3-Finger Swipe Screenshot Configuration
# Developer: Suvojeet Sengupta

# Enable/disable the 3-finger swipe screenshot feature
# 1 = enabled, 0 = disabled
enabled=1

# Swipe direction: down, up
swipe_direction=down

# Sensitivity threshold (lower = more sensitive, higher = less sensitive)
# Range: 100 - 800 (default: 300)
swipe_threshold=300

# Vibration feedback on screenshot (1 = on, 0 = off)
vibration=1

# Vibration duration in milliseconds
vibration_duration=50

# Screenshot delay in milliseconds (0 = instant)
screenshot_delay=0

# Screenshot format: png, jpg
screenshot_format=png

# Screenshot quality (1-100, only for jpg)
screenshot_quality=95

# Show notification after screenshot (1 = yes, 0 = no)
show_notification=1

# Screenshot save directory
save_directory=/sdcard/Pictures/Screenshots

# Cooldown between screenshots in seconds
cooldown=2

# Log daemon activity (1 = yes, 0 = no)
debug_log=0
CONFIGEOF
  chmod 0644 "/data/adb/3swipe/config.prop"
fi
# Ensure enabled=1 is set regardless
grep -q '^enabled=' "/data/adb/3swipe/config.prop" 2>/dev/null || echo 'enabled=1' >> "/data/adb/3swipe/config.prop"

# Set permissions
ui_print "- Setting permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/common/3swipe_daemon.sh" 0 0 0755
set_perm "$MODPATH/common/daemon_launcher.sh" 0 0 0755
[ -f "$MODPATH/action.sh" ] && set_perm "$MODPATH/action.sh" 0 0 0755
[ -f "$MODPATH/uninstall.sh" ] && set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print ""
ui_print "- Installation complete!"
ui_print "- The daemon will start after reboot"
ui_print ""
ui_print "  Manage via:"
ui_print "  • KernelSU: WebUI in module settings"
ui_print "  • Magisk: Action button in module list"
ui_print ""
ui_print "  Config: /data/adb/3swipe/config.prop"
ui_print ""
