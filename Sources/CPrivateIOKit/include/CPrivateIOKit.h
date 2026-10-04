#ifndef CPRIVATEIOKIT_H
#define CPRIVATEIOKIT_H

#include <stdint.h>
#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>

CF_ASSUME_NONNULL_BEGIN

#pragma mark - AppleSMC user client

// These structs mirror the kernel's SMC parameter block byte for byte.
// Swift cannot guarantee C padding rules, so they are declared here.

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must match the kernel layout");

/// `mach_task_self()` is a macro over a mutable global, which Swift 6 rejects.
static inline mach_port_t CPKTaskSelf(void) { return mach_task_self(); }

#pragma mark - IOHIDEventSystem (private)

// Apple Silicon exposes additional temperature sensors (SSD, battery gauge, SoC die)
// through the HID event system. These symbols are exported by IOKit but not declared
// in the SDK. They are renamed with asm labels so they never collide with IOKit's
// public declarations of the same names.

typedef CFTypeRef CPKHIDEventSystemClientRef;
typedef CFTypeRef CPKHIDServiceClientRef;
typedef CFTypeRef CPKHIDEventRef;

CF_RETURNS_RETAINED CPKHIDEventSystemClientRef _Nullable
CPKHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) __asm("_IOHIDEventSystemClientCreate");

int CPKHIDEventSystemClientSetMatching(CPKHIDEventSystemClientRef client, CFDictionaryRef matching)
    __asm("_IOHIDEventSystemClientSetMatching");

CF_RETURNS_RETAINED CFArrayRef _Nullable
CPKHIDEventSystemClientCopyServices(CPKHIDEventSystemClientRef client) __asm("_IOHIDEventSystemClientCopyServices");

CF_RETURNS_RETAINED CPKHIDEventRef _Nullable
CPKHIDServiceClientCopyEvent(CPKHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp)
    __asm("_IOHIDServiceClientCopyEvent");

CF_RETURNS_RETAINED CFTypeRef _Nullable
CPKHIDServiceClientCopyProperty(CPKHIDServiceClientRef service, CFStringRef key) __asm("_IOHIDServiceClientCopyProperty");

double CPKHIDEventGetFloatValue(CPKHIDEventRef event, int32_t field) __asm("_IOHIDEventGetFloatValue");

/// kIOHIDEventTypeTemperature
static const int64_t CPKHIDEventTypeTemperature = 15;

CF_ASSUME_NONNULL_END

#endif /* CPRIVATEIOKIT_H */
