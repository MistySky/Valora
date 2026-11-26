// Exercise the production reader without querying paired devices or CoreAudio.
#import <CoreAudio/CoreAudio.h>
#import <IOBluetooth/IOBluetooth.h>

@interface FixtureDevice : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *addressString;
@property(nonatomic) BOOL isConnected;
+ (NSArray *)pairedDevices;
@end

static NSArray *paired;
@implementation FixtureDevice
+ (NSArray *)pairedDevices { return paired; }
@end

static int listReads;
static NSString *fallbackModel;
static OSStatus readSize(AudioObjectID object, const AudioObjectPropertyAddress *a,
                         UInt32 q, const void *qualifier, UInt32 *size) {
    if (a->mSelector != kAudioHardwarePropertyDevices) return kAudioHardwareUnknownPropertyError;
    listReads++;
    *size = 2 * sizeof(AudioDeviceID);
    return noErr;
}

static OSStatus readData(AudioObjectID object, const AudioObjectPropertyAddress *a,
                         UInt32 q, const void *qualifier, UInt32 *size, void *data) {
    switch (a->mSelector) {
        case kAudioHardwarePropertyDevices: {
            AudioDeviceID ids[] = {21, 22};
            memcpy(data, ids, sizeof(ids));
            return noErr;
        }
        case kAudioHardwarePropertyDefaultOutputDevice:
            *(AudioDeviceID *)data = 20;
            return noErr;
        case kAudioDevicePropertyDeviceUID:
            *(CFStringRef *)data = CFRetain(object == 20 ? CFSTR("out-aa") :
                                            object == 21 ? CFSTR("out-bb") : CFSTR("out-cc"));
            return noErr;
        case kAudioDevicePropertyModelUID:
            *(CFStringRef *)data = CFBridgingRetain(object == 20 ? @"active" : fallbackModel);
            return noErr;
        case kAudioObjectPropertyName:
            *(CFStringRef *)data = CFRetain(CFSTR("Active output"));
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

#define IOBluetoothDevice FixtureDevice
#define AudioObjectGetPropertyDataSize readSize
#define AudioObjectGetPropertyData readData
#import "../../Sources/NativeBridge/NativeBridge.m"

static FixtureDevice *device(NSString *address, NSString *name) {
    FixtureDevice *device = [FixtureDevice new];
    device.isConnected = YES;
    device.addressString = address;
    device.name = name;
    return device;
}

static int check(NSArray *devices, NSArray *expectedIDs, NSArray *expectedModels, int expectedReads) {
    paired = devices;
    listReads = 0;
    NSArray *rows = ARConnectedAudioDevices();
    BOOL ok = [[rows valueForKey:@"id"] isEqual:expectedIDs]
           && [[rows valueForKey:@"modelUID"] isEqual:expectedModels]
           && listReads == expectedReads;
    printf("rows=%lu model list queries=%d expected=%d %s\n",
           (unsigned long)rows.count, listReads, expectedReads, ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}

int main(void) { @autoreleasepool {
    FixtureDevice *active = device(@"A-A", @"AirPods");
    FixtureDevice *other = device(@"B:B", @"AirPods 2");
    FixtureDevice *third = device(@"C C", @"AirPods 3");
    FixtureDevice *disconnected = device(@"BB", @"AirPods");
    disconnected.isConnected = NO;
    fallbackModel = @"model1";
    int failures = check(@[], @[], @[], 0);
    failures += check(@[disconnected, device(@"DD", @"Speaker")], @[], @[], 0);
    failures += check(@[active], @[@"aa"], @[@"active"], 0);
    failures += check(@[other, third], @[@"bb", @"cc"], @[@"model1", @"model1"], 1);
    fallbackModel = @"model2";
    failures += check(@[other, active], @[@"bb", @"aa"], @[@"model2", @"active"], 1);
    failures += check(@[device(@"FF", @"AirPods")], @[@"ff"], @[@""], 1);
    return failures ? 1 : 0;
} }
