// Compile the actual bridge against fake CoreAudio entry points. No hardware
// reads/writes, NSApp or windows. The production ABI/test hooks stay unchanged.
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import <math.h>
static OSStatus fakeGet(AudioObjectID, const AudioObjectPropertyAddress *, UInt32, const void *, UInt32 *, void *);
static OSStatus fakeSize(AudioObjectID, const AudioObjectPropertyAddress *, UInt32, const void *, UInt32 *);
static OSStatus fakeWritable(AudioObjectID, const AudioObjectPropertyAddress *, Boolean *);
static OSStatus fakeSet(AudioObjectID, const AudioObjectPropertyAddress *, UInt32, const void *, UInt32, const void *);
#define AudioObjectGetPropertyData fakeGet
#define AudioObjectGetPropertyDataSize fakeSize
#define AudioObjectIsPropertySettable fakeWritable
#define AudioObjectSetPropertyData fakeSet
#import "../../Sources/NativeBridge/NativeBridge.m"

static AudioDeviceID fixtureDevice;
static UInt32 channelCount;
static BOOL readable[8], writable[8];
static Float32 levels[8], written[8];
static int reads[8], writeCount, failures;
static void reset(void) {
    fixtureDevice = 42; channelCount = 2; writeCount = 0;
    memset(readable, 0, sizeof(readable)); memset(writable, 0, sizeof(writable));
    memset(levels, 0, sizeof(levels)); memset(reads, 0, sizeof(reads));
    memset(written, 0, sizeof(written));
    readable[1] = readable[2] = writable[1] = writable[2] = YES;
    levels[1] = 0.2; levels[2] = 0.6;
}
static OSStatus fakeGet(AudioObjectID object, const AudioObjectPropertyAddress *a,
                        UInt32 q, const void *qualifier, UInt32 *size, void *data) {
    if (a->mSelector == kAudioHardwarePropertyDefaultOutputDevice) {
        *(AudioDeviceID *)data = fixtureDevice; return noErr;
    }
    if (a->mSelector == kAudioDevicePropertyVolumeScalar) {
        UInt32 c = a->mElement;
        if (c >= 8) return kAudioHardwareUnknownPropertyError;
        reads[c]++;
        if (!readable[c]) return kAudioHardwareUnknownPropertyError;
        *(Float32 *)data = levels[c]; return noErr;
    }
    if (a->mSelector == kAudioDevicePropertyStreamConfiguration) {
        AudioBufferList *list = data; list->mNumberBuffers = 1;
        list->mBuffers[0] = (AudioBuffer){channelCount, 0, NULL}; return noErr;
    }
    if (a->mSelector == kAudioDevicePropertyDeviceUID || a->mSelector == kAudioObjectPropertyName ||
        a->mSelector == kAudioDevicePropertyModelUID) {
        *(CFStringRef *)data = CFRetain(CFSTR("fixture")); return noErr;
    }
    if (a->mSelector == kAudioDevicePropertyMute) { *(UInt32 *)data = 0; return noErr; }
    if (a->mSelector == kAudioDevicePropertyTransportType) {
        *(UInt32 *)data = kAudioDeviceTransportTypeBuiltIn; return noErr;
    }
    return kAudioHardwareUnknownPropertyError;
}
static OSStatus fakeSize(AudioObjectID o, const AudioObjectPropertyAddress *a,
                         UInt32 q, const void *qualifier, UInt32 *size) {
    if (a->mSelector != kAudioDevicePropertyStreamConfiguration) return kAudioHardwareUnknownPropertyError;
    *size = sizeof(AudioBufferList); return noErr;
}
static OSStatus fakeWritable(AudioObjectID o, const AudioObjectPropertyAddress *a, Boolean *result) {
    *result = a->mSelector == kAudioDevicePropertyMute || (a->mElement < 8 && writable[a->mElement]);
    return noErr;
}
static OSStatus fakeSet(AudioObjectID o, const AudioObjectPropertyAddress *a,
                        UInt32 q, const void *qualifier, UInt32 size, const void *value) {
    writeCount++;
    if (a->mSelector == kAudioDevicePropertyVolumeScalar && a->mElement < 8)
        written[a->mElement] = *(const Float32 *)value;
    return noErr;
}
#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } } while (0)
static BOOL closeTo(double a, double b) { return fabs(a-b) < 0.00001; }

int main(void) { @autoreleasepool {
    // Master volume: capability detection and value collection share one read.
    reset(); readable[0] = writable[0] = YES; levels[0] = 0.75;
    NSDictionary *d = ARAudioOutputSnapshot();
    CHECK(closeTo([d[@"volume"] doubleValue], 0.75), "master volume preserved");
    CHECK([d[@"canSetVolume"] boolValue] && reads[0] == 1 && reads[1] == 0, "master read once");

    reset(); d = ARAudioOutputSnapshot();
    CHECK(closeTo([d[@"volume"] doubleValue], 0.6), "stereo peak preserved");
    CHECK(reads[0] == 1 && reads[1] == 1 && reads[2] == 1, "each stereo channel read once");

    // A readable but unwritable master must not contaminate the channel peak.
    reset(); readable[0] = YES; levels[0] = 0.95; d = ARAudioOutputSnapshot();
    CHECK(closeTo([d[@"volume"] doubleValue], 0.6) && [d[@"canSetVolume"] boolValue], "master fallback preserved");

    reset(); writable[2] = NO; d = ARAudioOutputSnapshot();
    CHECK(![d[@"canSetVolume"] boolValue] && closeTo([d[@"volume"] doubleValue], 0), "partial unwritable channels fail closed");
    reset(); readable[2] = NO; d = ARAudioOutputSnapshot();
    CHECK(![d[@"canSetVolume"] boolValue] && closeTo([d[@"volume"] doubleValue], 0), "partial unreadable channels fail closed");

    reset(); channelCount = 0; d = ARAudioOutputSnapshot();
    CHECK(![d[@"canSetVolume"] boolValue] && closeTo([d[@"volume"] doubleValue], 0), "zero channels preserved");
    reset(); fixtureDevice = 0;
    CHECK(ARAudioOutputSnapshot().count == 0, "no device remains empty");

    reset(); readable[0] = writable[0] = YES; levels[0] = NAN; d = ARAudioOutputSnapshot();
    CHECK(closeTo([d[@"volume"] doubleValue], 0), "nonfinite master retains fmax behavior");

    // A new polling round / output device never reuses a cached prior value.
    reset(); (void)ARAudioOutputSnapshot(); fixtureDevice = 43; levels[2] = 0.9;
    d = ARAudioOutputSnapshot();
    CHECK(closeTo([d[@"volume"] doubleValue], 0.9) && reads[2] == 2, "new snapshot reads fresh values");

    // Gesture write path must retain its separate validation and balance reads.
    reset(); levels[1] = 0.25; levels[2] = 0.5;
    CHECK(ARSetOutputVolume(@"fixture", 0.4), "volume command still succeeds");
    CHECK(writeCount == 2 && closeTo(written[1], 0.2) && closeTo(written[2], 0.4), "stereo balance retained");
    CHECK(reads[1] == 2 && reads[2] == 2, "write path validation unchanged");
    reset(); CHECK(!ARSetOutputVolume(@"wrong-device", 0.4) && writeCount == 0, "wrong device cannot be written");
    CHECK(!ARSetOutputVolume(@"fixture", NAN) && writeCount == 0, "invalid command cannot be written");
    printf("Audio snapshot regression: 12 scenarios, %d failures\n", failures);
    return failures ? 1 : 0;
} }
