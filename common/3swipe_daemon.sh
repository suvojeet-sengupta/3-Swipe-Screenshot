#!/system/bin/sh
###############################################################################
#  3-Finger Swipe Screenshot Daemon  v2.1
#  Developer: Suvojeet Sengupta
#
#  Monitors touchscreen input via getevent and detects 3-finger swipe
#  gestures. Triggers screencap on detection.
#
#  Compatible: Android 11-16+ (API 30+), Magisk 20.4+, KernelSU
###############################################################################

DATA_DIR="/data/adb/3swipe"
CONFIG="$DATA_DIR/config.prop"
LOG_FILE="$DATA_DIR/daemon.log"
PID_FILE="$DATA_DIR/daemon.pid"

# ── Defaults ─────────────────────────────────────────────────────────────────
ENABLED=1
SWIPE_DIRECTION="down"
SWIPE_THRESHOLD=300
VIBRATION=1
VIBRATION_DURATION=50
SCREENSHOT_DELAY=0
SHOW_NOTIFICATION=1
SAVE_DIRECTORY="/sdcard/Pictures/Screenshots"
COOLDOWN=2
DEBUG_LOG=0

# ── Logging ──────────────────────────────────────────────────────────────────
log() {
  [ "$DEBUG_LOG" = "1" ] || return
  echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
  # rotate when > 512 KB
  if [ -f "$LOG_FILE" ]; then
    sz=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$sz" -gt 524288 ] && tail -n 300 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

# ── Load config ──────────────────────────────────────────────────────────────
load_config() {
  [ -f "$CONFIG" ] || return
  while IFS='=' read -r key val; do
    case "$key" in '#'*|'') continue ;; esac
    val=$(echo "$val" | tr -d '[:space:]')
    case "$key" in
      enabled)             ENABLED=$val ;;
      swipe_direction)     SWIPE_DIRECTION=$val ;;
      swipe_threshold)     SWIPE_THRESHOLD=$val ;;
      vibration)           VIBRATION=$val ;;
      vibration_duration)  VIBRATION_DURATION=$val ;;
      screenshot_delay)    SCREENSHOT_DELAY=$val ;;
      show_notification)   SHOW_NOTIFICATION=$val ;;
      save_directory)      SAVE_DIRECTORY=$val ;;
      cooldown)            COOLDOWN=$val ;;
      debug_log)           DEBUG_LOG=$val ;;
    esac
  done < "$CONFIG"
}

# ── Find multitouch input device ─────────────────────────────────────────────
find_touch_device() {
  for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    if getevent -p "$d" 2>/dev/null | grep -q "ABS_MT_POSITION"; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# ── Vibrate ──────────────────────────────────────────────────────────────────
do_vibrate() {
  [ "$VIBRATION" != "1" ] && return
  cmd vibrator_manager vibrate -d 0 -f "$VIBRATION_DURATION" oneshot 2>/dev/null && return
  service call vibrator 2 i32 "$VIBRATION_DURATION" 2>/dev/null
}

# ── Take screenshot ──────────────────────────────────────────────────────────
take_screenshot() {
  log ">>> Taking screenshot"

  if [ "$SCREENSHOT_DELAY" -gt 0 ] 2>/dev/null; then
    sleep "$(awk "BEGIN{printf \"%.2f\",$SCREENSHOT_DELAY/1000}")" 2>/dev/null
  fi

  mkdir -p "$SAVE_DIRECTORY" 2>/dev/null
  fname="Screenshot_3swipe_$(date +%Y%m%d_%H%M%S).png"
  fpath="${SAVE_DIRECTORY}/${fname}"

  screencap -p "$fpath" 2>/dev/null

  if [ -f "$fpath" ]; then
    chmod 0644 "$fpath"
    log "Saved: $fpath"
    am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file://${fpath}" --user 0 >/dev/null 2>&1 &
    do_vibrate &
    if [ "$SHOW_NOTIFICATION" = "1" ]; then
      cmd notification post -S bigtext -t "Screenshot Captured" \
        "3swipe_ss" "Saved: $fname" 2>/dev/null &
    fi
  else
    log "ERROR: screencap failed"
  fi
}

# ── Kill previous instance ───────────────────────────────────────────────────
kill_old() {
  if [ -f "$PID_FILE" ]; then
    old=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old" ]; then
      kill "$old" 2>/dev/null
      sleep 1
      kill -9 "$old" 2>/dev/null
    fi
    rm -f "$PID_FILE"
  fi
}

cleanup() { rm -f "$PID_FILE"; exit 0; }

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
  mkdir -p "$DATA_DIR"
  trap cleanup INT TERM HUP
  kill_old
  echo $$ > "$PID_FILE"

  load_config
  log "Daemon started (PID $$) enabled=$ENABLED threshold=$SWIPE_THRESHOLD"

  # wait for enable
  while [ "$ENABLED" != "1" ]; do
    sleep 5
    load_config
  done

  # find touch device (retry up to 30 times)
  DEV=""
  tries=0
  while [ -z "$DEV" ] && [ $tries -lt 30 ]; do
    DEV=$(find_touch_device)
    [ -z "$DEV" ] && { tries=$((tries+1)); sleep 2; }
  done
  [ -z "$DEV" ] && { log "FATAL: no touch device"; exit 1; }
  log "Touch device: $DEV"

  # ── State variables ────────────────────────────────────────────────────────
  # These persist across loop iterations inside the pipe subshell
  SLOT=0
  LAST_SS=0
  # per-slot: a=active, s=startY, c=currentY  (slots 0-9)
  a0=0; a1=0; a2=0; a3=0; a4=0; a5=0; a6=0; a7=0; a8=0; a9=0
  s0=0; s1=0; s2=0; s3=0; s4=0; s5=0; s6=0; s7=0; s8=0; s9=0
  c0=0; c1=0; c2=0; c3=0; c4=0; c5=0; c6=0; c7=0; c8=0; c9=0
  CFG_CTR=0

  # ── Read raw events ────────────────────────────────────────────────────────
  # CRITICAL: getevent -q <device> outputs THREE fields (no device prefix):
  #   TYPE CODE VALUE   (all hex, space-separated)
  # Example: 0003 0036 000003e8
  getevent -q "$DEV" 2>/dev/null | while read -r etype ecode evalue; do

    # periodic config reload (~every 1000 events)
    CFG_CTR=$((CFG_CTR + 1))
    if [ $CFG_CTR -ge 1000 ]; then
      CFG_CTR=0
      load_config
    fi
    [ "$ENABLED" != "1" ] && continue

    # only EV_ABS (0003)
    [ "$etype" != "0003" ] && continue

    case "$ecode" in

      002f)  # ABS_MT_SLOT
        SLOT=$(printf '%d' "0x${evalue}" 2>/dev/null || echo 0)
        [ $SLOT -gt 9 ] && SLOT=9
        ;;

      0039)  # ABS_MT_TRACKING_ID
        if [ "$evalue" = "ffffffff" ]; then
          eval "a${SLOT}=0; s${SLOT}=0; c${SLOT}=0"
        else
          eval "a${SLOT}=1; s${SLOT}=-1; c${SLOT}=0"
        fi
        ;;

      0036)  # ABS_MT_POSITION_Y
        yval=$(printf '%d' "0x${evalue}" 2>/dev/null || echo 0)

        eval "sy=\$s${SLOT}"
        if [ "$sy" = "-1" ]; then
          eval "s${SLOT}=$yval"
          sy=$yval
        fi
        eval "c${SLOT}=$yval"

        # ── Check gesture ────────────────────────────────────────────────
        fc=0; sc=0; i=0
        while [ $i -le 9 ]; do
          eval "ia=\$a${i}"
          if [ "$ia" = "1" ]; then
            fc=$((fc + 1))
            eval "is=\$s${i}; ic=\$c${i}"
            if [ "$is" != "-1" ] && [ "$is" != "0" ]; then
              if [ "$SWIPE_DIRECTION" = "down" ]; then
                d=$((ic - is))
              else
                d=$((is - ic))
              fi
              [ $d -ge $SWIPE_THRESHOLD ] && sc=$((sc + 1))
            fi
          fi
          i=$((i + 1))
        done

        if [ $fc -ge 3 ] && [ $sc -ge 3 ]; then
          now=$(date +%s)
          elapsed=$((now - LAST_SS))
          if [ $elapsed -ge $COOLDOWN ]; then
            log "3-finger swipe! fingers=$fc swipes=$sc"
            take_screenshot &
            LAST_SS=$now
            i=0
            while [ $i -le 9 ]; do
              eval "a${i}=0; s${i}=0; c${i}=0"
              i=$((i + 1))
            done
          fi
        fi
        ;;
    esac
  done

  log "Event loop exited — restarting in 3s"
  sleep 3
  exec "$0"
}

main
