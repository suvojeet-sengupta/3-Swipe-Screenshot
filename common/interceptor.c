#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <errno.h>

#define MAX_SLOTS       16
#define CONFIG_PATH     "/data/adb/3swipe/config.prop"
#define DEFAULT_THRESHOLD 300
#define SCREENSHOT_CMD  "/system/bin/sh"
#define SCREENSHOT_ARG  "/data/adb/modules/three_swipe_screenshot/common/3swipe_daemon.sh"

/*
 * interceptor.c  –  v2.8
 *
 * Grabs the touch device, detects 3-finger swipe, triggers screenshot,
 * and forwards all other events through a virtual uinput device.
 *
 * Fixes over v2.7:
 *   - tracking_id[] fully initialised to -1 (was only index 0)
 *   - active_fingers underflow guard
 *   - y_start[] reset on finger lift
 *   - signal handler releases grab + destroys uinput
 *   - reads threshold & direction from config.prop
 *   - forwards all ABS event codes the real device advertises
 *   - uses fork()/exec() instead of system()
 *   - error checks on write()/ioctl()
 */

/* ── Global FDs for signal handler ─────────────────────────────────────────── */
static int g_fd   = -1;   /* real device */
static int g_uifd = -1;   /* virtual device */

static void cleanup_and_exit(int sig) {
    (void)sig;
    if (g_uifd >= 0) { ioctl(g_uifd, UI_DEV_DESTROY); close(g_uifd); }
    if (g_fd   >= 0) { ioctl(g_fd, EVIOCGRAB, 0);      close(g_fd);  }
    _exit(0);
}

/* ── Read config.prop for threshold & direction ────────────────────────────── */
static int  cfg_threshold = DEFAULT_THRESHOLD;
static int  cfg_dir_down  = 1;  /* 1 = down, 0 = up */

static void load_config(void) {
    FILE *fp = fopen(CONFIG_PATH, "r");
    if (!fp) return;
    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        char key[64], val[128];
        if (sscanf(line, "%63[^=]=%127s", key, val) == 2) {
            if (strcmp(key, "swipe_threshold") == 0) {
                int v = atoi(val);
                if (v >= 50 && v <= 2000) cfg_threshold = v;
            } else if (strcmp(key, "swipe_direction") == 0) {
                cfg_dir_down = (strcmp(val, "up") != 0);
            }
        }
    }
    fclose(fp);
}

/* ── Forward all ABS codes the real device supports ────────────────────────── */
static void mirror_abs_caps(int realfd, int uifd_local,
                            struct uinput_user_dev *uidev) {
    /* Standard ABS codes to try (covers all common touch axes) */
    static const int abs_codes[] = {
        ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID,
        ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_TOUCH_MINOR,
        ABS_MT_WIDTH_MAJOR, ABS_MT_WIDTH_MINOR, ABS_MT_ORIENTATION,
        ABS_MT_PRESSURE, ABS_MT_DISTANCE, ABS_MT_TOOL_TYPE,
        ABS_X, ABS_Y, ABS_PRESSURE,
        -1
    };
    for (int i = 0; abs_codes[i] >= 0; i++) {
        struct input_absinfo info;
        if (ioctl(realfd, EVIOCGABS(abs_codes[i]), &info) == 0) {
            ioctl(uifd_local, UI_SET_ABSBIT, abs_codes[i]);
            uidev->absmin[abs_codes[i]] = info.minimum;
            uidev->absmax[abs_codes[i]] = info.maximum;
        }
    }
}

/* ── Trigger screenshot via fork+exec (non-blocking) ──────────────────────── */
static void trigger_screenshot(void) {
    pid_t pid = fork();
    if (pid == 0) {
        /* child — detach and exec */
        setsid();
        execl(SCREENSHOT_CMD, SCREENSHOT_CMD, SCREENSHOT_ARG, "--trigger", NULL);
        _exit(127);   /* exec failed */
    }
    /* parent returns immediately; child is reaped by init */
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <device_path>\n", argv[0]);
        return 1;
    }

    load_config();

    /* ── Install signal handlers before opening devices ────────────────────── */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = cleanup_and_exit;
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP,  &sa, NULL);

    const char *dev_path = argv[1];
    int fd = open(dev_path, O_RDONLY);
    if (fd < 0) { perror("Could not open device"); return 1; }
    g_fd = fd;

    if (ioctl(fd, EVIOCGRAB, 1) < 0) {
        perror("Could not grab device");
        close(fd);
        return 1;
    }

    int uifd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (uifd < 0) {
        perror("Could not open uinput");
        ioctl(fd, EVIOCGRAB, 0);
        close(fd);
        return 1;
    }
    g_uifd = uifd;

    /* ── Enable event types ────────────────────────────────────────────────── */
    if (ioctl(uifd, UI_SET_EVBIT, EV_KEY) < 0) perror("UI_SET_EVBIT EV_KEY");
    if (ioctl(uifd, UI_SET_KEYBIT, BTN_TOUCH) < 0) perror("UI_SET_KEYBIT BTN_TOUCH");
    if (ioctl(uifd, UI_SET_EVBIT, EV_ABS) < 0) perror("UI_SET_EVBIT EV_ABS");
    if (ioctl(uifd, UI_SET_EVBIT, EV_SYN) < 0) perror("UI_SET_EVBIT EV_SYN");

    struct uinput_user_dev uidev;
    memset(&uidev, 0, sizeof(uidev));
    snprintf(uidev.name, UINPUT_MAX_NAME_SIZE, "3-Swipe Virtual Touchscreen");
    uidev.id.bustype = BUS_USB;
    uidev.id.vendor  = 0x1;
    uidev.id.product = 0x1;
    uidev.id.version = 1;

    /* Mirror every ABS axis the real device supports */
    mirror_abs_caps(fd, uifd, &uidev);

    if (write(uifd, &uidev, sizeof(uidev)) < 0) {
        perror("write uinput_user_dev");
        cleanup_and_exit(0);
    }
    if (ioctl(uifd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        cleanup_and_exit(0);
    }

    /* ── State ─────────────────────────────────────────────────────────────── */
    struct input_event ev;
    int slot = 0;
    int tracking_id[MAX_SLOTS];
    int y_start[MAX_SLOTS];
    int y_curr[MAX_SLOTS];
    int active_fingers = 0;
    int triggered = 0;

    /* Initialise tracking_id to -1 for ALL slots */
    for (int i = 0; i < MAX_SLOTS; i++) {
        tracking_id[i] = -1;
        y_start[i]     = 0;
        y_curr[i]      = 0;
    }

    printf("Interceptor running on %s  (threshold=%d dir=%s)\n",
           dev_path, cfg_threshold, cfg_dir_down ? "down" : "up");

    /* ── Event loop ────────────────────────────────────────────────────────── */
    while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_SLOT) {
                slot = ev.value;
                if (slot < 0)              slot = 0;
                if (slot >= MAX_SLOTS)      slot = MAX_SLOTS - 1;
            } else if (ev.code == ABS_MT_TRACKING_ID) {
                if (ev.value != -1) {
                    /* Finger down — only increment if slot was inactive */
                    if (tracking_id[slot] == -1)
                        active_fingers++;
                    tracking_id[slot] = ev.value;
                    y_start[slot] = 0;   /* fresh start on new touch */
                    y_curr[slot]  = 0;
                } else {
                    /* Finger up — only decrement if slot was active */
                    if (tracking_id[slot] != -1 && active_fingers > 0)
                        active_fingers--;
                    tracking_id[slot] = -1;
                    y_start[slot] = 0;   /* reset on lift */
                    y_curr[slot]  = 0;
                    if (active_fingers == 0) triggered = 0;
                }
            } else if (ev.code == ABS_MT_POSITION_Y) {
                if (y_start[slot] == 0) y_start[slot] = ev.value;
                y_curr[slot] = ev.value;

                if (active_fingers >= 3 && !triggered) {
                    int swipes = 0;
                    for (int i = 0; i < MAX_SLOTS; i++) {
                        if (tracking_id[i] == -1) continue;
                        int delta = cfg_dir_down
                                    ? (y_curr[i] - y_start[i])
                                    : (y_start[i] - y_curr[i]);
                        if (delta > cfg_threshold)
                            swipes++;
                    }
                    if (swipes >= 3) {
                        triggered = 1;
                        trigger_screenshot();
                    }
                }
            }
        }

        /* Forward events to virtual device (drop during active 3-finger swipe) */
        if (!triggered || active_fingers < 3) {
            if (write(uifd, &ev, sizeof(ev)) < 0 && errno != EAGAIN) {
                perror("write uinput event");
            }
        }
    }

    cleanup_and_exit(0);
    return 0;
}
