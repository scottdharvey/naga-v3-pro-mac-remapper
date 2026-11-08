// usbprobe: tests the direct-USB path (no Input Monitoring needed) to a Razer Naga V3 Pro.
// Build (from the repo root):
//   clang -O2 -Wall -o usbprobe tools/usbprobe.c app/Sources/CNagaUSB/nagausb.c \
//         -I app/Sources/CNagaUSB/include -framework IOKit -framework CoreFoundation
// Usage:
//   ./usbprobe list                      Razer USB devices
//   ./usbprobe listall                   every USB device macOS sees (diagnostics)
//   ./usbprobe scan                      which USB interface index answers Razer commands
//   ./usbprobe info      [--if N]        firmware, serial, DPI, battery
//   ./usbprobe buttons   [--if N] [profile]   raw button mappings (read-only)
//   ./usbprobe dpistages [--if N]        DPI stage lists (read-only)
//   ./usbprobe setkey <profile> <button 40-4B> <hid key> [--if N] --yes   write test, verified, prints undo
// All numbers are hex. Close the Naga Remapper app before running this (one program at a time).
#include "nagausb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define RAZER_VID 0x1532
static naga_usb_t *H;
static int IFACE = -1;
static const uint8_t TID = 0x1F;

static const char *status_name(uint8_t s) {
    switch (s) {
    case 0x00: return "new";
    case 0x01: return "busy";
    case 0x02: return "ok";
    case 0x03: return "failed";
    case 0x04: return "timeout";
    case 0x05: return "not supported";
    default: return "?";
    }
}

static void hex(const uint8_t *b, int n) {
    for (int i = 0; i < n; i++) printf("%02X%s", b[i], i + 1 < n ? " " : "");
}

// Returns 0 and fills resp (90 bytes) on success, otherwise an IOReturn code (or -1 if the mouse stayed busy).
static int transact(int iface, uint8_t cls, uint8_t cmd, uint8_t size, const uint8_t *args, int nargs, uint8_t *resp) {
    uint8_t req[90];
    memset(req, 0, sizeof req);
    req[1] = TID; req[5] = size; req[6] = cls; req[7] = cmd;
    for (int i = 0; i < nargs && i < 80; i++) req[8 + i] = args[i];
    uint8_t crc = 0;
    for (int i = 2; i < 88; i++) crc ^= req[i];
    req[88] = crc;
    int kr = naga_usb_control(H, 0x21, 0x09, 0x0300, (uint16_t)iface, req, 90, NULL);   // SET_REPORT (feature)
    if (kr) return kr;
    for (int t = 0; t < 10; t++) {
        usleep(40000);
        memset(resp, 0, 90);
        kr = naga_usb_control(H, 0xA1, 0x01, 0x0300, (uint16_t)iface, resp, 90, NULL);  // GET_REPORT (feature)
        if (kr) return kr;
        if (resp[0] != 0x01) return 0;
    }
    return -1;
}

static int pick_iface(void) {
    if (IFACE >= 0) return IFACE;
    uint8_t r[90];
    for (int i = 0; i < 4; i++)
        if (transact(i, 0x00, 0x81, 0x02, NULL, 0, r) == 0 && r[0] == 0x02) return i;
    return -1;
}

static int read_map(int iface, uint8_t p, uint8_t b, uint8_t out[10]) {
    uint8_t args[3] = {p, b, 0x00}, r[90];
    if (transact(iface, 0x02, 0x8C, 0x0A, args, 3, r) != 0 || r[0] != 0x02) return 0;
    memcpy(out, r + 8, 10);
    return 1;
}

static long parse_hex(const char *s) { return strtol(s, NULL, 16); }

int main(int argc, char **argv) {
    // pull out --if N and --yes
    int yes = 0, n = 0;
    char *args[16];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--yes")) yes = 1;
        else if (!strcmp(argv[i], "--if") && i + 1 < argc) IFACE = (int)strtol(argv[++i], NULL, 10);
        else if (n < 16) args[n++] = argv[i];
    }
    const char *cmd = n > 0 ? args[0] : "help";

    if (!strcmp(cmd, "list")) {
        naga_usb_info_t list[16];
        int c = naga_usb_list(RAZER_VID, list, 16);
        if (c == 0) printf("No Razer USB devices found. Use the USB cable or HyperSpeed dongle (not Bluetooth).\n");
        for (int i = 0; i < c; i++)
            printf("%s  pid=0x%04X  location=0x%08X\n", list[i].name, list[i].product_id, list[i].location);
        return 0;
    }
    if (!strcmp(cmd, "listall")) {
        naga_usb_info_t list[64];
        int c = naga_usb_list(0, list, 64);
        printf("%d USB devices:\n", c);
        for (int i = 0; i < c; i++)
            printf("  vid=0x%04X pid=0x%04X  %s\n", list[i].vendor_id, list[i].product_id, list[i].name);
        return 0;
    }
    if (!strcmp(cmd, "help") || n == 0) {
        printf("usbprobe list | scan | info | buttons [profile] | dpistages | setkey <p> <btn 40-4B> <hid> --yes   [--if N]\n");
        return 0;
    }

    naga_usb_info_t info;
    int kr = naga_usb_open(RAZER_VID, "Naga V3 Pro", &H, &info);
    if (kr) {
        printf("Couldn't open a Razer Naga V3 Pro over USB (error 0x%08X).\n", (unsigned)kr);
        printf("Run './usbprobe list' to see what's connected.\n");
        return 1;
    }
    printf("Opened %s (pid 0x%04X). Exclusive open: %s (not needed).\n",
           info.name, info.product_id, naga_usb_opened_exclusive(H) ? "yes" : "no");

    uint8_t r[90];
    int rc = 0;
    if (!strcmp(cmd, "scan")) {
        for (int i = 0; i < 4; i++) {
            int k = transact(i, 0x00, 0x81, 0x02, NULL, 0, r);
            printf("  interface index %d: ", i);
            if (k == -1) printf("device stayed busy\n");
            else if (k) printf("transfer error 0x%08X\n", (unsigned)k);
            else { printf("status=%s firmware data=[", status_name(r[0])); hex(r + 8, 2); printf("]\n"); }
        }
    } else {
        int iface = pick_iface();
        if (iface < 0) { printf("No interface index answered. Run './usbprobe scan' and paste the output.\n"); naga_usb_close(H); return 1; }
        printf("Using interface index %d\n", iface);

        if (!strcmp(cmd, "info")) {
            struct { const char *name; uint8_t c, m, s; } q[] = {
                {"firmware", 0x00, 0x81, 0x02}, {"serial", 0x00, 0x82, 0x16}, {"poll rate", 0x00, 0x85, 0x01},
                {"DPI", 0x04, 0x85, 0x07}, {"battery", 0x07, 0x80, 0x02}};
            for (int i = 0; i < 5; i++) {
                int k = transact(iface, q[i].c, q[i].m, q[i].s, NULL, 0, r);
                printf("  %-10s ", q[i].name);
                if (k) { printf("transfer error 0x%08X\n", (unsigned)k); continue; }
                printf("status=%s data=[", status_name(r[0]));
                hex(r + 8, r[5] < 80 ? r[5] : 80);
                printf("]\n");
            }
        } else if (!strcmp(cmd, "buttons")) {
            uint8_t p = n > 1 ? (uint8_t)parse_hex(args[1]) : 0x01;
            const uint8_t ids[] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x09, 0x0A, 0x0B, 0x0C, 0x0E, 0x34, 0x35, 0x39,
                                   0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B,
                                   0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x6A};
            for (size_t i = 0; i < sizeof ids; i++) {
                uint8_t m[10];
                printf("  0x%02X  ", ids[i]);
                if (read_map(iface, p, ids[i], m)) { hex(m, 10); printf("\n"); }
                else printf("(no reply)\n");
            }
        } else if (!strcmp(cmd, "dpistages")) {
            for (uint8_t which = 0; which < 2; which++) {
                uint8_t a[1] = {which};
                int k = transact(iface, 0x04, 0x86, 0x26, a, 1, r);
                printf("  %s list: ", which ? "saved  " : "runtime");
                if (k) { printf("transfer error 0x%08X\n", (unsigned)k); continue; }
                printf("status=%s data=[", status_name(r[0]));
                hex(r + 8, r[5] < 80 ? r[5] : 80);
                printf("]\n");
            }
        } else if (!strcmp(cmd, "setkey")) {
            if (n < 4) { printf("usage: setkey <profile> <button 40-4B> <hid key> --yes\n"); rc = 1; goto done; }
            uint8_t p = (uint8_t)parse_hex(args[1]), b = (uint8_t)parse_hex(args[2]), key = (uint8_t)parse_hex(args[3]);
            if (b < 0x40 || b > 0x4B) { printf("Only side buttons 40-4B.\n"); rc = 1; goto done; }
            uint8_t before[10], after[10] = {0};
            if (!read_map(iface, p, b, before)) { printf("Couldn't read the current mapping; nothing written.\n"); rc = 1; goto done; }
            printf("before: "); hex(before, 10); printf("\n");
            if (before[3] != 0x02) { printf("Current mapping isn't a key; nothing written.\n"); rc = 1; goto done; }
            uint8_t w[10];
            memcpy(w, before, 10);
            w[5] = 0x00; w[6] = key;
            printf("new:    "); hex(w, 10); printf("\n");
            if (memcmp(before, w, 10) == 0) { printf("Already set; nothing written.\n"); goto done; }
            if (!yes) { printf("Re-run with --yes to write.\n"); goto done; }
            int k = transact(iface, 0x02, 0x0C, 0x0A, w, 10, r);
            if (k) { printf("transfer error 0x%08X\n", (unsigned)k); rc = 1; goto done; }
            printf("write status: %s\n", status_name(r[0]));
            usleep(100000);
            if (read_map(iface, p, b, after)) { printf("after:  "); hex(after, 10); printf("\n"); }
            printf("%s\n", memcmp(after, w, 10) == 0 ? "Verified." : "Read-back does NOT match.");
            printf("Undo: ./usbprobe setkey %02X %02X %02X --yes\n", p, b, before[6]);
        } else {
            printf("Unknown command. Run ./usbprobe help\n");
            rc = 1;
        }
    }
done:
    naga_usb_close(H);
    return rc;
}
