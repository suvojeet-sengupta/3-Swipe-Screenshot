#!/system/bin/sh
###############################################################################
#  3-Finger Swipe Screenshot Daemon
#  Developer: Suvojeet Sengupta
#  Version: 2.0.0
#
#  Monitors touchscreen input events and detects 3-finger swipe gestures.
#  When a 3-finger downward (or upward) swipe is detected, captures a
#  screenshot and saves it to the configured directory.
#
#  Compatible: Android 11+ (API 30+), Magisk 20.4+, KernelSU
#  Tested on: Infinity-X SE / LineageOS 23.x based ROMs
###############################################################################

# ─── Paths ───────────────────────────────────────────────────────────────────
MODULE_DIR="/data/adb/modules/three_swipe_screenshot"
DATA_DIR="/data/adb/3swipe"
CONFIG="$DATA_DIR/config.prop"
LOG_FILE="$DATA_DIR/daemon.log"
PID_FILE="$DATA_DIR/daemon.pid"
STATE_DIR="$DATA_DIR/state"

# ─── Defaults ────────────────────────────────────────────────────────────────
ENABLED=1
SWIPE_DIRECTION="down"
SWIPE_THRESHOLD=300
VIBRATION=1
VIBRATION_DURATION=50
SCREENSHOT_DELAY=0
SCREENSHOT_FORMAT="png"
SCREENSHOT_QUALITY=95
SHOW_NOTIFICATION=1
SAVE_DIRECTORY="/sdcard/Pictures/Screenshots"
COOLDOWN=2
DEBUG_LOG=0

# ─── Event codes (hex) ──────────────────────────────────────────────────────
# Using raw hex codes for faster parsing (no -l flag)
EV_ABS="0003"
ABS_MT_SLOT="002f"
ABS_MT_TRACKING_ID="0039"
ABS_MT_POSITION_X="0035"
ABS_MT_POSITION_Y="0036"
EV_SYN="0000"
SYN_REPORT="0000"

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  if [ "$DEBUG_LOG" = "1" ]; then
    echo "$msg" >> "$LOG_FILE"
    # Keep log file under 1MB
    if [ -f "$LOG_FILE" ]; then
      local size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
      [ "$size" -gt 1048576 ] && tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
  fi
}

# ─── Load Configuration ─────────────────────────────────────────────────────
load_config() {
  if [ -f "$CONFIG" ]; then
    ENABLED=$(grep "^enabled=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SWIPE_DIRECTION=$(grep "^swipe_direction=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SWIPE_THRESHOLD=$(grep "^swipe_threshold=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    VIBRATION=$(grep "^vibration=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    VIBRATION_DURATION=$(grep "^vibration_duration=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SCREENSHOT_DELAY=$(grep "^screenshot_delay=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SCREENSHOT_FORMAT=$(grep "^screenshot_format=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SCREENSHOT_QUALITY=$(grep "^screenshot_quality=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SHOW_NOTIFICATION=$(grep "^show_notification=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    SAVE_DIRECTORY=$(grep "^save_directory=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    COOLDOWN=$(grep "^cooldown=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    DEBUG_LOG=$(grep "^debug_log=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')

    # Apply defaults for empty values
    : "${ENABLED:=1}"
    : "${SWIPE_DIRECTION:=down}"
    : "${SWIPE_THRESHOLD:=300}"
    : "${VIBRATION:=1}"
    : "${VIBRATION_DURATION:=50}"
    : "${SCREENSHOT_DELAY:=0}"
    : "${SCREENSHOT_FORMAT:=png}"
    : "${SCREENSHOT_QUALITY:=95}"
    : "${SHOW_NOTIFICATION:=1}"
    : "${SAVE_DIRECTORY:=/sdcard/Pictures/Screenshots}"
    : "${COOLDOWN:=2}"
    : "${DEBUG_LOG:=0}"
  fi
}

# ─── Find Touchscreen Device ────────────────────────────────────────────────
find_touch_device() {
  local dev=""
  for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    # Look for multi-touch device with slot support
    if getevent -p "$d" 2>/dev/null | grep -q "ABS_MT_POSITION"; then
      dev="$d"
      log "Found touch device: $dev"
      echo "$dev"
      return 0
    fi
  done
  log "ERROR: No touchscreen device found!"
  return 1
}

# ─── Check if another instance is running ────────────────────────────────────
check_running() {
  if [ -f "$PID_FILE" ]; then
    local old_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log "Another daemon instance (PID: $old_pid) is running. Killing it."
      kill "$old_pid" 2>/dev/null
      sleep 1
      kill -9 "$old_pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
  fi
}

# ─── Vibrate ─────────────────────────────────────────────────────────────────
do_vibrate() {
  [ "$VIBRATION" != "1" ] && return
  # Try Android 11+ vibrator manager
  cmd vibrator_manager vibrate -d 0 -f "$VIBRATION_DURATION" oneshot 2>/dev/null && return
  # Try legacy service call
  service call vibrator 2 i32 "$VIBRATION_DURATION" 2>/dev/null && return
  # Try input keyevent approach (simulate haptic)
  true
}

# ─── Show Notification ───────────────────────────────────────────────────────
show_notification() {
  local filepath="$1"
  local filename=$(basename "$filepath")
  [ "$SHOW_NOTIFICATION" != "1" ] && return

  # Use cmd notification (Android 10+)
  cmd notification post -S bigtext \
    -t "Screenshot Captured" \
    --icon "android.resource://com.android.systemui/drawable/ic_screenshot" \
    "3swipe_screenshot" \
    "Saved: $filename" 2>/dev/null || true
}

# ─── Take Screenshot ────────────────────────────────────────────────────────
take_screenshot() {
  log "Taking screenshot..."

  # Optional delay
  if [ "$SCREENSHOT_DELAY" -gt 0 ] 2>/dev/null; then
    local delay_sec=$(awk "BEGIN {printf \"%.1f\", $SCREENSHOT_DELAY / 1000}")
    sleep "$delay_sec" 2>/dev/null || usleep "$((SCREENSHOT_DELAY * 1000))" 2>/dev/null
  fi

  # Ensure save directory exists
  mkdir -p "$SAVE_DIRECTORY" 2>/dev/null

  local timestamp=$(date +%Y%m%d_%H%M%S)
  local filename=""
  local filepath=""

  if [ "$SCREENSHOT_FORMAT" = "jpg" ] || [ "$SCREENSHOT_FORMAT" = "jpeg" ]; then
    filename="Screenshot_3swipe_${timestamp}.jpg"
    filepath="${SAVE_DIRECTORY}/${filename}"
    # Capture as PNG first, then convert
    local tmp_png="/data/local/tmp/3swipe_tmp.png"
    screencap -p "$tmp_png" 2>/dev/null
    if [ -f "$tmp_png" ]; then
      # Try to use Android's built-in tools for conversion
      # If unavailable, just save as PNG
      if command -v convert >/dev/null 2>&1; then
        convert "$tmp_png" -quality "$SCREENSHOT_QUALITY" "$filepath" 2>/dev/null
        rm -f "$tmp_png"
      else
        # Fall back to PNG
        filename="Screenshot_3swipe_${timestamp}.png"
        filepath="${SAVE_DIRECTORY}/${filename}"
        mv "$tmp_png" "$filepath"
      fi
    fi
  else
    filename="Screenshot_3swipe_${timestamp}.png"
    filepath="${SAVE_DIRECTORY}/${filename}"
    screencap -p "$filepath" 2>/dev/null
  fi

  if [ -f "$filepath" ]; then
    log "Screenshot saved: $filepath"
    chmod 0644 "$filepath" 2>/dev/null

    # Trigger media scanner
    am broadcast \
      -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file://${filepath}" \
      --user 0 >/dev/null 2>&1 &

    # Vibrate
    do_vibrate &

    # Notification
    show_notification "$filepath" &

    return 0
  else
    log "ERROR: Failed to capture screenshot!"
    return 1
  fi
}

# ─── Convert hex string to decimal ──────────────────────────────────────────
hex2dec() {
  # Remove leading 0x if present, handle potential issues
  local hex="${1#0x}"
  hex="${hex#0X}"
  printf '%d' "0x${hex}" 2>/dev/null || echo 0
}

# ─── Main Gesture Detection Loop ────────────────────────────────────────────
run_daemon() {
  local touch_dev="$1"
  log "Starting gesture detection on $touch_dev"

  # State variables for tracking up to 10 fingers (slots 0-9)
  local slot=0
  local last_screenshot_time=0

  # Per-slot tracking using positional variables
  # active_N: whether slot N has a finger (0/1)
  # sy_N: start Y position of slot N
  # cy_N: current Y position of slot N
  local active_0=0 active_1=0 active_2=0 active_3=0 active_4=0
  local active_5=0 active_6=0 active_7=0 active_8=0 active_9=0
  local sy_0=0 sy_1=0 sy_2=0 sy_3=0 sy_4=0
  local sy_5=0 sy_6=0 sy_7=0 sy_8=0 sy_9=0
  local cy_0=0 cy_1=0 cy_2=0 cy_3=0 cy_4=0
  local cy_5=0 cy_6=0 cy_7=0 cy_8=0 cy_9=0

  local config_reload_counter=0

  # Read raw events (no -l flag for performance)
  # Format: /dev/input/eventN: TYPE CODE VALUE
  getevent -q "$touch_dev" 2>/dev/null | while IFS=': ' read -r devpath type code value; do
    # Periodically reload config (every ~500 events)
    config_reload_counter=$((config_reload_counter + 1))
    if [ $config_reload_counter -ge 500 ]; then
      config_reload_counter=0
      load_config
      [ "$ENABLED" != "1" ] && continue
    fi

    [ "$ENABLED" != "1" ] && continue

    # Only process EV_ABS events
    [ "$type" != "$EV_ABS" ] && continue

    case "$code" in
      "$ABS_MT_SLOT")
        slot=$(hex2dec "$value")
        # Clamp to 0-9
        [ "$slot" -gt 9 ] && slot=9
        ;;

      "$ABS_MT_TRACKING_ID")
        local dec_val=$(hex2dec "$value")
        if [ "$value" = "ffffffff" ] || [ "$dec_val" = "4294967295" ]; then
          # Finger lifted from this slot
          eval "active_${slot}=0"
          eval "sy_${slot}=0"
          eval "cy_${slot}=0"
        else
          # New finger in this slot
          eval "active_${slot}=1"
          eval "sy_${slot}=-1"
        fi
        ;;

      "$ABS_MT_POSITION_Y")
        local yval=$(hex2dec "$value")

        # Set start Y if not set yet
        eval "local cur_sy=\$sy_${slot}"
        if [ "$cur_sy" = "-1" ]; then
          eval "sy_${slot}=$yval"
          cur_sy=$yval
        fi
        eval "cy_${slot}=$yval"

        # Count active fingers
        local finger_count=0
        local i=0
        while [ $i -le 9 ]; do
          eval "local a=\$active_${i}"
          [ "$a" = "1" ] && finger_count=$((finger_count + 1))
          i=$((i + 1))
        done

        # Need at least 3 fingers
        if [ $finger_count -ge 3 ]; then
          # Check cooldown
          local now=$(date +%s)
          local time_diff=$((now - last_screenshot_time))

          if [ $time_diff -ge $COOLDOWN ]; then
            # Count how many active fingers have swiped enough
            local swipe_count=0
            i=0
            while [ $i -le 9 ]; do
              eval "local fa=\$active_${i}"
              if [ "$fa" = "1" ]; then
                eval "local fs=\$sy_${i}"
                eval "local fc=\$cy_${i}"
                if [ "$fs" != "-1" ] && [ "$fs" != "0" ]; then
                  local diff=0
                  if [ "$SWIPE_DIRECTION" = "down" ]; then
                    diff=$((fc - fs))
                  else
                    diff=$((fs - fc))
                  fi
                  [ $diff -ge $SWIPE_THRESHOLD ] && swipe_count=$((swipe_count + 1))
                fi
              fi
              i=$((i + 1))
            done

            # Trigger screenshot if 3+ fingers swiped
            if [ $swipe_count -ge 3 ]; then
              log "3-finger swipe detected! ($swipe_count fingers swiped)"
              take_screenshot
              last_screenshot_time=$(date +%s)

              # Reset all slots to prevent re-triggering
              i=0
              while [ $i -le 9 ]; do
                eval "active_${i}=0; sy_${i}=0; cy_${i}=0"
                i=$((i + 1))
              done
            fi
          fi
        fi
        ;;
    esac
  done
}

# ─── Cleanup handler ────────────────────────────────────────────────────────
cleanup() {
  log "Daemon stopping (PID: $$)"
  rm -f "$PID_FILE"
  exit 0
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
main() {
  # Setup
  mkdir -p "$DATA_DIR"
  trap cleanup INT TERM HUP

  # Check for existing instance
  check_running

  # Save our PID
  echo $$ > "$PID_FILE"
  log "Daemon started (PID: $$)"

  # Load configuration
  load_config
  log "Configuration loaded: enabled=$ENABLED, direction=$SWIPE_DIRECTION, threshold=$SWIPE_THRESHOLD"

  if [ "$ENABLED" != "1" ]; then
    log "Module is disabled. Waiting for enable..."
    # Still run but check periodically
    while true; do
      load_config
      if [ "$ENABLED" = "1" ]; then
        log "Module enabled! Starting gesture detection."
        break
      fi
      sleep 5
    done
  fi

  # Find touch device
  local touch_dev=""
  local retry=0
  while [ -z "$touch_dev" ] && [ $retry -lt 30 ]; do
    touch_dev=$(find_touch_device)
    if [ -z "$touch_dev" ]; then
      retry=$((retry + 1))
      log "Waiting for touch device... (attempt $retry/30)"
      sleep 2
    fi
  done

  if [ -z "$touch_dev" ]; then
    log "FATAL: Could not find touchscreen device after 30 attempts!"
    rm -f "$PID_FILE"
    exit 1
  fi

  log "Using touch device: $touch_dev"

  # Run the gesture detection loop
  # Auto-restart on crash
  while true; do
    load_config
    if [ "$ENABLED" = "1" ]; then
      run_daemon "$touch_dev"
      log "Daemon loop exited unexpectedly. Restarting in 3s..."
      sleep 3
    else
      sleep 5
    fi
  done
}

main "$@"
