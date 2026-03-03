# 3-Finger Swipe Screenshot — Magisk/KernelSU Module

### Developer: **Suvojeet Sengupta**
### Version: **v2.0.0**

---

## 📸 Overview

This Magisk/KernelSU module adds **3-finger swipe down screenshot** functionality to any Android ROM that lacks it — including **Infinity-X SE**, **LineageOS 23.x**, and other AOSP-based ROMs.

Simply swipe down on your screen with **3 fingers simultaneously** to instantly capture a screenshot.

---

## ✅ Features

- **3-finger swipe down** gesture to take screenshots
- **Beautiful WebUI** for KernelSU — configure everything from module settings
- **Magisk action button** — toggle enable/disable with one tap
- **Configurable settings:**
  - Swipe direction (up/down)
  - Sensitivity/threshold
  - Vibration feedback & duration
  - Screenshot delay
  - Screenshot format (PNG/JPG)
  - Notification on capture
  - Cooldown between screenshots
- **Auto-restart** daemon on crash
- **Multi-method approach:**
  - Sets system properties for native support
  - Sets Android settings database entries
  - Runs efficient touch gesture detection daemon
- **Lightweight** — minimal battery impact
- **Clean uninstall** — removes all data and resets settings

---

## 📱 Compatibility

| Feature | Supported |
|---------|-----------|
| Android Version | 11, 12, 13, 14, 15+ |
| Magisk | v20.4+ |
| KernelSU | All versions |
| Root Manager | Magisk Manager / KernelSU Manager |
| ROM | Infinity-X SE, LineageOS, AOSP, and all derivatives |

---

## 📦 Installation

1. Download the module ZIP
2. Open **Magisk Manager** or **KernelSU Manager**
3. Go to **Modules** → **Install from storage**
4. Select the downloaded ZIP
5. **Reboot** your device

---

## ⚙️ Usage

### Taking Screenshots
- Place **3 fingers** on the screen
- **Swipe downward** smoothly
- Screenshot is captured with vibration feedback
- Saved to `/sdcard/Pictures/Screenshots/`

### Managing the Module

#### KernelSU Users:
- Open **KernelSU Manager** → **Modules** → **3-Finger Swipe Screenshot**
- Tap the **settings icon** to open the WebUI
- Configure all settings from the beautiful UI

#### Magisk Users:
- Open **Magisk Manager** → **Modules**
- Tap the **action button** (▶) on the module to toggle enable/disable

### Manual Configuration:
Edit the config file directly:
```
/data/adb/3swipe/config.prop
```

---

## 🗂️ File Structure

```
three_swipe_screenshot/
├── module.prop              # Module metadata
├── META-INF/                # Magisk installer
│   └── com/google/android/
│       ├── update-binary
│       └── updater-script
├── customize.sh             # Installation script
├── service.sh               # Boot service (starts daemon)
├── post-fs-data.sh          # Early boot (sets properties)
├── system.prop              # System properties
├── action.sh                # Magisk action button
├── uninstall.sh             # Cleanup script
├── common/
│   └── 3swipe_daemon.sh     # Gesture detection daemon
└── webroot/
    └── index.html           # KernelSU WebUI
```

---

## 📋 Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `1` | Enable/disable the module |
| `swipe_direction` | `down` | Swipe direction (down/up) |
| `swipe_threshold` | `300` | Sensitivity (100-800, lower = more sensitive) |
| `vibration` | `1` | Haptic feedback on screenshot |
| `vibration_duration` | `50` | Vibration length in ms |
| `screenshot_delay` | `0` | Delay before capture in ms |
| `screenshot_format` | `png` | Image format (png/jpg) |
| `screenshot_quality` | `95` | JPG quality (1-100) |
| `show_notification` | `1` | Show notification after capture |
| `save_directory` | `/sdcard/Pictures/Screenshots` | Save location |
| `cooldown` | `2` | Seconds between screenshots |
| `debug_log` | `0` | Enable debug logging |

---

## 🔧 Troubleshooting

**Module not working after install?**
- Make sure you rebooted after installation
- Check if the module is enabled in Magisk/KernelSU Manager

**Screenshots not being captured?**
- Try adjusting the sensitivity (lower value = more sensitive)
- Make sure you're swiping with exactly 3 fingers simultaneously
- Check daemon status in WebUI or run: `cat /data/adb/3swipe/daemon.pid`

**Daemon not running?**
- Restart manually: `sh /data/adb/modules/3swipe/common/3swipe_daemon.sh &`
- Check logs: `cat /data/adb/3swipe/daemon.log`

**Battery drain?**
- The daemon is lightweight and only processes touch events
- If concerned, increase the cooldown value

---

## 📄 Changelog

### v2.0.0
- Initial release
- 3-finger swipe gesture detection
- KernelSU WebUI with modern dark theme
- Magisk action button support
- Configurable settings
- Multi-method screenshot support
- Auto-restart daemon
- Clean uninstall

---

## 📜 License

This module is provided as-is for personal use.

**Developer:** Suvojeet Sengupta

---
