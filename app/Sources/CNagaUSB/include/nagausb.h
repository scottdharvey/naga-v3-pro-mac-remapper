// Direct USB control transfers to a Razer mouse on macOS, without the HID layer.
// The 90-byte Razer reports go over endpoint 0 as HID SET_REPORT / GET_REPORT class requests.
// This path doesn't need Input Monitoring permission (idea from cepheiden/Razer-Naga-Trinity-MACOS, MIT).
#ifndef NAGAUSB_H
#define NAGAUSB_H

#include <stdint.h>

typedef struct naga_usb naga_usb_t;

typedef struct {
    uint16_t vendor_id;
    uint16_t product_id;
    uint32_t location;
    char name[128];
} naga_usb_info_t;

/// Lists USB devices with this vendor id (0 = all USB devices). Returns how many were written to `out`.
int naga_usb_list(uint16_t vendor_id, naga_usb_info_t *out, int max);

/// Opens the first device with this vendor id whose product name contains `name_substring` (NULL = any).
/// Returns 0 on success, otherwise an IOReturn error code.
int naga_usb_open(uint16_t vendor_id, const char *name_substring, naga_usb_t **out, naga_usb_info_t *info);

/// One control transfer on endpoint 0. Returns 0 on success, otherwise an IOReturn error code.
int naga_usb_control(naga_usb_t *h, uint8_t bm_request_type, uint8_t request, uint16_t value,
                     uint16_t index, uint8_t *data, uint16_t length, uint16_t *transferred);

/// 1 if the device could also be opened for exclusive access (not required for control transfers).
int naga_usb_opened_exclusive(const naga_usb_t *h);

void naga_usb_close(naga_usb_t *h);

#endif
