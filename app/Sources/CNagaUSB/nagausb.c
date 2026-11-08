#include "nagausb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>
#include <string.h>

struct naga_usb {
    IOUSBDeviceInterface182 **dev;
    int opened;
};

// Enumerates every USB device. Vendor filtering happens in the callers: putting "idVendor" in the
// matching dictionary silently matched nothing on macOS 26 even with the Naga plugged in.
static io_iterator_t find_devices(void) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) return 0;
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) return 0;  // consumes match
    return it;
}

static void read_info(io_service_t s, naga_usb_info_t *info) {
    memset(info, 0, sizeof *info);
    CFTypeRef p = IORegistryEntryCreateCFProperty(s, CFSTR("idVendor"), kCFAllocatorDefault, 0);
    if (p) {
        int v = 0;
        if (CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)p, kCFNumberIntType, &v);
        info->vendor_id = (uint16_t)v;
        CFRelease(p);
    }
    p = IORegistryEntryCreateCFProperty(s, CFSTR("idProduct"), kCFAllocatorDefault, 0);
    if (p) {
        int v = 0;
        if (CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)p, kCFNumberIntType, &v);
        info->product_id = (uint16_t)v;
        CFRelease(p);
    }
    p = IORegistryEntryCreateCFProperty(s, CFSTR("locationID"), kCFAllocatorDefault, 0);
    if (p) {
        int64_t v = 0;
        if (CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)p, kCFNumberSInt64Type, &v);
        info->location = (uint32_t)v;
        CFRelease(p);
    }
    p = IORegistryEntryCreateCFProperty(s, CFSTR("USB Product Name"), kCFAllocatorDefault, 0);
    if (!p) p = IORegistryEntryCreateCFProperty(s, CFSTR("kUSBProductString"), kCFAllocatorDefault, 0);
    if (p) {
        if (CFGetTypeID(p) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)p, info->name, sizeof info->name, kCFStringEncodingUTF8);
        CFRelease(p);
    }
}

int naga_usb_list(uint16_t vendor_id, naga_usb_info_t *out, int max) {
    io_iterator_t it = find_devices();
    if (!it) return 0;
    int n = 0;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        if (n < max) {
            read_info(s, &out[n]);
            if (!vendor_id || out[n].vendor_id == vendor_id) n++;
        }
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return n;
}

int naga_usb_open(uint16_t vendor_id, const char *name_substring, naga_usb_t **out, naga_usb_info_t *info) {
    *out = NULL;
    io_iterator_t it = find_devices();
    if (!it) return kIOReturnNotFound;
    int result = kIOReturnNotFound;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        naga_usb_info_t inf;
        read_info(s, &inf);
        if (vendor_id && inf.vendor_id != vendor_id) { IOObjectRelease(s); continue; }
        if (name_substring && !strstr(inf.name, name_substring)) { IOObjectRelease(s); continue; }

        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        kern_return_t kr = IOCreatePlugInInterfaceForService(s, kIOUSBDeviceUserClientTypeID,
                                                             kIOCFPlugInInterfaceID, &plugin, &score);
        IOObjectRelease(s);
        if (kr != KERN_SUCCESS || !plugin) { result = kr ? kr : kIOReturnError; continue; }

        IOUSBDeviceInterface182 **dev = NULL;
        HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182), (LPVOID *)&dev);
        IODestroyPlugInInterface(plugin);
        if (hr || !dev) { result = kIOReturnError; continue; }

        naga_usb_t *h = calloc(1, sizeof *h);
        if (!h) { (*dev)->Release(dev); result = kIOReturnNoMemory; break; }
        h->dev = dev;
        // Usually fails because the HID driver owns the device; control transfers on endpoint 0 work anyway.
        h->opened = ((*dev)->USBDeviceOpen(dev) == kIOReturnSuccess);
        if (info) *info = inf;
        *out = h;
        result = 0;
        break;
    }
    IOObjectRelease(it);
    return result;
}

int naga_usb_control(naga_usb_t *h, uint8_t bm_request_type, uint8_t request, uint16_t value,
                     uint16_t index, uint8_t *data, uint16_t length, uint16_t *transferred) {
    IOUSBDevRequestTO r;
    memset(&r, 0, sizeof r);
    r.bmRequestType = bm_request_type;
    r.bRequest = request;
    r.wValue = value;
    r.wIndex = index;
    r.wLength = length;
    r.pData = data;
    r.noDataTimeout = 1000;
    r.completionTimeout = 1000;
    IOReturn kr = (*h->dev)->DeviceRequestTO(h->dev, &r);
    if (transferred) *transferred = (uint16_t)r.wLenDone;
    return kr;
}

int naga_usb_opened_exclusive(const naga_usb_t *h) { return h->opened; }

void naga_usb_close(naga_usb_t *h) {
    if (!h) return;
    if (h->opened) (*h->dev)->USBDeviceClose(h->dev);
    (*h->dev)->Release(h->dev);
    free(h);
}
