#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <errno.h>

#define THRESHOLD 300
#define SCREENSHOT_CMD "/system/bin/sh /data/adb/modules/three_swipe_screenshot/common/3swipe_daemon.sh --trigger"

/*
 * interceptor.c
 * This program grabs the touch device and filters events to prevent scrolling
 * when a 3-finger swipe is detected.
 */

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <device_path>\n", argv[0]);
        return 1;
    }

    const char *dev_path = argv[1];
    int fd = open(dev_path, O_RDONLY);
    if (fd < 0) {
        perror("Could not open device");
        return 1;
    }

    // Grab the device
    if (ioctl(fd, EVIOCGRAB, 1) < 0) {
        perror("Could not grab device");
        close(fd);
        return 1;
    }

    // Setup uinput
    int uifd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (uifd < 0) {
        perror("Could not open uinput");
        ioctl(fd, EVIOCGRAB, 0);
        close(fd);
        return 1;
    }

    // We need to enable the events we want to pass through
    ioctl(uifd, UI_SET_EVBIT, EV_KEY);
    ioctl(uifd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(uifd, UI_SET_EVBIT, EV_ABS);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_POSITION_X);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_POSITION_Y);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_SLOT);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_TOUCH_MAJOR);
    ioctl(uifd, UI_SET_ABSBIT, ABS_MT_WIDTH_MAJOR);
    ioctl(uifd, UI_SET_EVBIT, EV_SYN);

    struct uinput_user_dev uidev;
    memset(&uidev, 0, sizeof(uidev));
    snprintf(uidev.name, UINPUT_MAX_NAME_SIZE, "3-Swipe Virtual Touchscreen");
    uidev.id.bustype = BUS_USB;
    uidev.id.vendor  = 0x1;
    uidev.id.product = 0x1;
    uidev.id.version = 1;

    // Get ranges from the real device to match the virtual one
    struct input_absinfo abs;
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &abs) == 0) {
        uidev.absmin[ABS_MT_POSITION_X] = abs.minimum;
        uidev.absmax[ABS_MT_POSITION_X] = abs.maximum;
    }
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &abs) == 0) {
        uidev.absmin[ABS_MT_POSITION_Y] = abs.minimum;
        uidev.absmax[ABS_MT_POSITION_Y] = abs.maximum;
    }
    if (ioctl(fd, EVIOCGABS(ABS_MT_SLOT), &abs) == 0) {
        uidev.absmin[ABS_MT_SLOT] = abs.minimum;
        uidev.absmax[ABS_MT_SLOT] = abs.maximum;
    }

    write(uifd, &uidev, sizeof(uidev));
    ioctl(uifd, UI_DEV_CREATE);

    struct input_event ev;
    int slot = 0;
    int tracking_id[16] = {-1};
    int y_start[16] = {0};
    int y_curr[16] = {0};
    int active_fingers = 0;
    int triggered = 0;

    printf("Interceptor running on %s\n", dev_path);

    while (read(fd, &ev, sizeof(ev)) > 0) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_SLOT) {
                slot = ev.value;
                if (slot > 15) slot = 15;
            } else if (ev.code == ABS_MT_TRACKING_ID) {
                if (ev.value != -1) {
                    tracking_id[slot] = ev.value;
                    active_fingers++;
                } else {
                    tracking_id[slot] = -1;
                    active_fingers--;
                    if (active_fingers == 0) triggered = 0;
                }
            } else if (ev.code == ABS_MT_POSITION_Y) {
                if (y_start[slot] == 0) y_start[slot] = ev.value;
                y_curr[slot] = ev.value;

                // Detect 3-finger swipe
                if (active_fingers >= 3 && !triggered) {
                    int swipes = 0;
                    for (int i=0; i<16; i++) {
                        if (tracking_id[i] != -1 && (y_curr[i] - y_start[i]) > THRESHOLD) {
                            swipes++;
                        }
                    }
                    if (swipes >= 3) {
                        triggered = 1;
                        system(SCREENSHOT_CMD " &");
                    }
                }
            }
        }

        // Pass event through to virtual device unless it's the 3rd+ finger during a swipe
        // For absolute 100% no-scroll, we would buffer events, but that's complex.
        // Even this simple pass-through with grab is much better.
        if (!triggered || active_fingers < 3) {
            write(uifd, &ev, sizeof(ev));
        }
    }

    ioctl(uifd, UI_DEV_DESTROY);
    close(uifd);
    ioctl(fd, EVIOCGRAB, 0);
    close(fd);
    return 0;
}
