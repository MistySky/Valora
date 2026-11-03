#import <dlfcn.h>
#import <AppKit/AppKit.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import "NativeBridge.h"
#import <CoreAudio/CoreAudio.h>
#import <IOBluetooth/IOBluetooth.h>
#import <objc/message.h>
#import <math.h>

static AudioDeviceID outputDevice(void) {
    AudioDeviceID device=0;UInt32 size=sizeof(device);
    AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&size,&device)!=noErr)return 0;
    return device;
}
static NSString *audioString(AudioDeviceID device,AudioObjectPropertySelector selector) {
    if(!device)return @"";CFStringRef value=NULL;UInt32 size=sizeof(value);
    AudioObjectPropertyAddress a={selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    if(AudioObjectGetPropertyData(device,&a,0,NULL,&size,&value)!=noErr || !value)return @"";
    return CFBridgingRelease(value);
}
static BOOL audioGet(AudioDeviceID device, AudioObjectPropertySelector selector,
                     AudioObjectPropertyElement element, void *value, UInt32 size) {
    AudioObjectPropertyAddress a={selector,kAudioDevicePropertyScopeOutput,element};
    return device && AudioObjectGetPropertyData(device,&a,0,NULL,&size,value)==noErr;
}
static BOOL audioWritable(AudioDeviceID device, AudioObjectPropertySelector selector, AudioObjectPropertyElement element) {
    AudioObjectPropertyAddress a={selector,kAudioDevicePropertyScopeOutput,element}; Boolean writable=false;
    return device && AudioObjectIsPropertySettable(device,&a,&writable)==noErr && writable;
}
static BOOL audioSet(AudioDeviceID device, AudioObjectPropertySelector selector,
                     AudioObjectPropertyElement element, const void *value, UInt32 size) {
    AudioObjectPropertyAddress a={selector,kAudioDevicePropertyScopeOutput,element};
    return device && AudioObjectSetPropertyData(device,&a,0,NULL,size,value)==noErr;
}
static NSArray<NSNumber *> *volumeChannels(AudioDeviceID device) {
    Float32 value=0;
    if(audioGet(device,kAudioDevicePropertyVolumeScalar,0,&value,sizeof(value)) &&
       audioWritable(device,kAudioDevicePropertyVolumeScalar,0)) return @[@0];
    AudioObjectPropertyAddress a={kAudioDevicePropertyStreamConfiguration,kAudioDevicePropertyScopeOutput,0};
    UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(device,&a,0,NULL,&size)!=noErr || !size)return @[];
    AudioBufferList *list=malloc(size); UInt32 channels=0;
    if(AudioObjectGetPropertyData(device,&a,0,NULL,&size,list)==noErr)
        for(UInt32 i=0;i<list->mNumberBuffers;i++)channels+=list->mBuffers[i].mNumberChannels;
    free(list);
    NSMutableArray *result=[NSMutableArray array];
    for(UInt32 channel=1;channel<=channels;channel++) {
        if(!audioGet(device,kAudioDevicePropertyVolumeScalar,channel,&value,sizeof(value)) ||
           !audioWritable(device,kAudioDevicePropertyVolumeScalar,channel))return @[];
        [result addObject:@(channel)];
    }
    return result;
}
NSDictionary *ARAudioOutputSnapshot(void) {
    AudioDeviceID device=outputDevice(); if(!device)return @{};
    NSArray<NSNumber *> *channels=volumeChannels(device); Float32 volume=0;
    for(NSNumber *channel in channels) { Float32 v=0; audioGet(device,kAudioDevicePropertyVolumeScalar,channel.unsignedIntValue,&v,sizeof(v)); volume=fmaxf(volume,v); }
    UInt32 muted=0; BOOL canMute=audioGet(device,kAudioDevicePropertyMute,0,&muted,sizeof(muted)) && audioWritable(device,kAudioDevicePropertyMute,0);
    UInt32 transport=0; UInt32 size=sizeof(transport);
    AudioObjectPropertyAddress a={kAudioDevicePropertyTransportType,kAudioObjectPropertyScopeGlobal,0};
    AudioObjectGetPropertyData(device,&a,0,NULL,&size,&transport);
    NSString *kind=transport==kAudioDeviceTransportTypeBuiltIn ? @"builtIn" :
        (transport==kAudioDeviceTransportTypeBluetooth || transport==kAudioDeviceTransportTypeBluetoothLE ? @"bluetooth" : @"external");
    // The built-in device may be using its headphone jack.
    UInt32 source=0; NSString *port=@"";
    if(audioGet(device,kAudioDevicePropertyDataSource,0,&source,sizeof(source))) {
        CFStringRef name=NULL; AudioValueTranslation translation={&source,sizeof(source),&name,sizeof(name)};
        if(audioGet(device,kAudioDevicePropertyDataSourceNameForIDCFString,0,&translation,sizeof(translation)) && name)port=CFBridgingRelease(name);
    }
    return @{@"uid":audioString(device,kAudioDevicePropertyDeviceUID), @"name":audioString(device,kAudioObjectPropertyName),
             @"modelUID":audioString(device,kAudioDevicePropertyModelUID), @"kind":kind, @"port":port,
             @"volume":@(volume), @"muted":@(muted!=0), @"canMute":@(canMute), @"canSetVolume":@(channels.count>0)};
}
BOOL ARSetOutputVolume(NSString *expectedUID,double volume) {
    AudioDeviceID device=outputDevice();
    if(!isfinite(volume) || !expectedUID.length || ![audioString(device,kAudioDevicePropertyDeviceUID) isEqual:expectedUID])return NO;
    NSArray<NSNumber *> *channels=volumeChannels(device); if(!channels.count)return NO;
    NSMutableArray<NSNumber *> *values=[NSMutableArray array]; Float32 maximum=0;
    for(NSNumber *channel in channels) { Float32 v=0; if(!audioGet(device,kAudioDevicePropertyVolumeScalar,channel.unsignedIntValue,&v,sizeof(v)))return NO; [values addObject:@(v)];maximum=fmaxf(maximum,v); }
    Float32 target=fmax(0,fmin(1,volume)); BOOL ok=YES;
    for(NSUInteger i=0;i<channels.count;i++) {
        Float32 v=maximum>0 ? target*values[i].floatValue/maximum : target;
        ok=audioSet(device,kAudioDevicePropertyVolumeScalar,channels[i].unsignedIntValue,&v,sizeof(v)) && ok;
    }
    return ok;
}
BOOL ARSetOutputMuted(NSString *expectedUID,BOOL muted) {
    AudioDeviceID device=outputDevice();
    if(!expectedUID.length || ![audioString(device,kAudioDevicePropertyDeviceUID) isEqual:expectedUID] || !audioWritable(device,kAudioDevicePropertyMute,0))return NO;
    UInt32 value=muted ? 1:0; return audioSet(device,kAudioDevicePropertyMute,0,&value,sizeof(value));
}


static int connectivityScalar(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return -1;
    Method method = class_getInstanceMethod([object class], selector);
    if (!method) return -1;
    char *returnType = method_copyReturnType(method);
    if (!returnType) return -1;
    BOOL isUnsignedChar = returnType[0] == 'C' && returnType[1] == '\0';
    free(returnType);
    if (!isUnsignedChar) return -1;
    unsigned char value = ((unsigned char (*)(id, SEL))objc_msgSend)(object, selector);
    return value <= 100 ? (int)value : -1;
}
static NSString *normalAddress(NSString *s) {
    return [[s.lowercaseString componentsSeparatedByCharactersInSet:
             [NSCharacterSet characterSetWithCharactersInString:@"-: "]] componentsJoinedByString:@""];
}
NSString *ARDefaultAudioOutputName(void) {
    return audioString(outputDevice(), kAudioObjectPropertyName);
}
NSArray<NSDictionary *> *ARConnectedAudioDevices(void) {
    AudioDeviceID output = outputDevice();
    NSString *uid = normalAddress(audioString(output, kAudioDevicePropertyDeviceUID));
    NSString *modelUID = audioString(output, kAudioDevicePropertyModelUID);
    NSString *outputName = audioString(output, kAudioObjectPropertyName);
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *audioModels = [NSMutableArray array];
    AudioObjectPropertyAddress listAddress = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, 0};
    UInt32 listSize = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &listAddress, 0, NULL, &listSize) == noErr && listSize > 0) {
        AudioDeviceID *ids = calloc(1, listSize);
        if (ids && AudioObjectGetPropertyData(kAudioObjectSystemObject, &listAddress, 0, NULL, &listSize, ids) == noErr) {
            for (UInt32 i = 0; i < listSize / sizeof(AudioDeviceID); i++) {
                [audioModels addObject:@{@"uid": normalAddress(audioString(ids[i], kAudioDevicePropertyDeviceUID)),
                                         @"model": audioString(ids[i], kAudioDevicePropertyModelUID)}];
            }
        }
        free(ids);
    }
    for (IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) {
        if (!device.isConnected) continue;
        int left = connectivityScalar(device, @"batteryPercentLeft");
        int right = connectivityScalar(device, @"batteryPercentRight");
        int single = connectivityScalar(device, @"batteryPercentSingle");
        NSString *name = device.name ?: @"Bluetooth device";
        NSString *address = device.addressString ?: @"";
        BOOL active = address.length && [uid containsString:normalAddress(address)];
        NSString *deviceModel = active ? modelUID : @"";
        if (!deviceModel.length && address.length) {
            for (NSDictionary *entry in audioModels) {
                if ([entry[@"uid"] containsString:normalAddress(address)]) {
                    deviceModel = entry[@"model"];
                    break;
                }
            }
        }
        BOOL namedAirPods = [name.lowercaseString containsString:@"airpods"];
        BOOL hasBattery = (left >= 0 && left <= 100) || (right >= 0 && right <= 100)
            || (single >= 0 && single <= 100);
        if (!namedAirPods && !active && !hasBattery) continue;
        [result addObject:@{
            @"id": normalAddress(address), @"name": active && outputName.length ? outputName : name,
            @"left": @(left), @"right": @(right), @"single": @(single), @"active": @(active),
            @"airpods": @(namedAirPods), @"modelUID": deviceModel,
            @"colorID": @(connectivityScalar(device, @"colorID"))
        }];
    }
    return result;
}

// An internal battery identifies a portable Mac even with its display closed.
// External UPS devices must not classify a desktop as a laptop.
BOOL ARComputerIsPortable(void) {
    static BOOL portable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFTypeRef info = IOPSCopyPowerSourcesInfo();
        if (!info) return;
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        if (sources) {
            for (CFIndex i = 0; i < CFArrayGetCount(sources); ++i) {
                CFDictionaryRef description = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
                CFTypeRef type = description ? CFDictionaryGetValue(description, CFSTR(kIOPSTypeKey)) : NULL;
                if (type && CFEqual(type, CFSTR(kIOPSInternalBatteryType))) { portable = YES; break; }
            }
            CFRelease(sources);
        }
        CFRelease(info);
    });
    return portable;
}


// Process-owned presentation Space recovered from Alcove 1.7.9. Only this
// process's own windows are attached; no other process/space is modified.
typedef int32_t ARLockSpaceConnection;
typedef uint64_t ARLockSpaceID;
typedef struct {
    ARLockSpaceConnection (*connection)(void);
    ARLockSpaceID (*create)(ARLockSpaceConnection,int,CFDictionaryRef);
    void (*destroy)(ARLockSpaceConnection,ARLockSpaceID);
    void (*setLevel)(ARLockSpaceConnection,ARLockSpaceID,int);
    int (*getLevel)(ARLockSpaceConnection,ARLockSpaceID);
    void (*show)(ARLockSpaceConnection,CFArrayRef);
    void (*hide)(ARLockSpaceConnection,CFArrayRef);
    void (*add)(ARLockSpaceConnection,CFArrayRef,CFArrayRef);
    void (*remove)(ARLockSpaceConnection,CFArrayRef,CFArrayRef);
    CFArrayRef (*copyForWindows)(ARLockSpaceConnection,uint32_t,CFArrayRef);
    int32_t (*moveToSpace)(int32_t,int32_t,CFArrayRef,int32_t);
} ARLockSpaceFunctions;
static ARLockSpaceFunctions ARLoadLockSpaceFunctions(void) {
    static ARLockSpaceFunctions f; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY|RTLD_LOCAL);
        if(!h)return;
        f.connection=dlsym(h,"CGSMainConnectionID");
        f.create=dlsym(h,"CGSSpaceCreate");
        f.destroy=dlsym(h,"CGSSpaceDestroy");
        f.setLevel=dlsym(h,"CGSSpaceSetAbsoluteLevel");
        f.getLevel=dlsym(h,"CGSSpaceGetAbsoluteLevel");
        f.show=dlsym(h,"CGSShowSpaces");
        f.hide=dlsym(h,"CGSHideSpaces");
        f.add=dlsym(h,"CGSAddWindowsToSpaces");
        f.remove=dlsym(h,"CGSRemoveWindowsFromSpaces");
        f.copyForWindows=dlsym(h,"CGSCopySpacesForWindows");
        f.moveToSpace=dlsym(h,"SLSSpaceAddWindowsAndRemoveFromSpaces");
    });
    return f;
}
@interface ARLockPresentationSpace ()
- (BOOL)attachOwnedWindowNumber:(NSInteger)number;
@end
@implementation ARLockPresentationSpace {
    ARLockSpaceFunctions _f; ARLockSpaceConnection _c; ARLockSpaceID _s;
    NSMutableSet<NSNumber *> *_windows;
    NSMutableDictionary<NSNumber *,NSArray<NSNumber *> *> *_originalSpaces;
    NSMutableSet<NSNumber *> *_verifiedWindows;
}
+ (nullable ARLockPresentationSpace *)createPresentationSpace {
    ARLockPresentationSpace *space=[[self alloc] init];
    return space;
}
- (instancetype)init {
    self=[super init]; if(!self)return nil;
    NSAssert([NSThread isMainThread],@"Space lifecycle must run on main thread");
    _f=ARLoadLockSpaceFunctions();
    if(!_f.connection||!_f.create||!_f.destroy||!_f.setLevel||!_f.getLevel||!_f.show||!_f.hide||!_f.add||!_f.remove||!_f.copyForWindows||!_f.moveToSpace)return nil;
    _c=_f.connection(); _windows=[NSMutableSet set]; _originalSpaces=[NSMutableDictionary dictionary]; _verifiedWindows=[NSMutableSet set];
    _s=_f.create(_c,1,NULL); if(!_s)return nil;
    if(_s>INT32_MAX){_f.destroy(_c,_s);_s=0;return nil;}
    _f.setLevel(_c,_s,400);
    if(_f.getLevel(_c,_s)!=400){_f.destroy(_c,_s);_s=0;return nil;}
    _f.show(_c,(__bridge CFArrayRef)@[@(_s)]);
    return self;
}
// Migrate only this process's window, rather than letting its desktop and
// login-space presentations coexist during the system transition. Preserve the
// exact previous membership for unlock/stop; never send it to a guessed desktop.
- (BOOL)attachWindowNumber:(NSInteger)number {
    NSAssert([NSThread isMainThread],@"Window membership must run on main thread");
    if(!_s||number<=0)return NO;
    NSWindow *owned=[NSApp.windows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSWindow *w,NSDictionary *b){return w.windowNumber==number;}]].firstObject;
    if(!owned)return NO;
    return [self attachOwnedWindowNumber:number];
}
- (BOOL)attachOwnedWindowNumber:(NSInteger)number {
    NSNumber *identifier=@(number);
    if([_verifiedWindows containsObject:identifier]) {
        NSArray *current=[self windowSpaceIDs:number];
        return current.count==1 && [current containsObject:@(_s)];
    }
    if([_windows containsObject:identifier]) {
        [self detachWindowNumber:number];
        if([_windows containsObject:identifier])return NO;
    }
    NSArray<NSNumber *> *original=[self windowSpaceIDs:number];
    // A newly created hidden lock card may have an empty, valid membership.
    // Only an unknown query is unsafe to restore.
    if(!original || [original containsObject:@(_s)])return NO;
    _originalSpaces[identifier]=original;
    [_windows addObject:identifier];
    int32_t error=_f.moveToSpace(_c,(int32_t)_s,(__bridge CFArrayRef)@[identifier],7);
    NSArray<NSNumber *> *actual=[self windowSpaceIDs:number];
    if(error!=0 || !actual || actual.count!=1 || ![actual containsObject:@(_s)]) {
        [self detachWindowNumber:number];
        return NO;
    }
    [_verifiedWindows addObject:identifier];
    return YES;
}
- (void)detachWindowNumber:(NSInteger)number {
    NSAssert([NSThread isMainThread],@"Window membership must run on main thread");
    NSNumber *identifier=@(number);
    if(!_s||![_windows containsObject:identifier])return;
    NSArray<NSNumber *> *original=_originalSpaces[identifier];
    // Restore the captured spaces before removing the login membership. Keep
    // ownership on an unverified restore so a later detach/stop can retry it.
    if(!original)return;
    if(original.count)_f.add(_c,(__bridge CFArrayRef)@[identifier],(__bridge CFArrayRef)original);
    NSArray<NSNumber *> *actual=[self windowSpaceIDs:number];
    if(!actual || ![[NSSet setWithArray:original] isSubsetOfSet:[NSSet setWithArray:actual]])return;
    _f.remove(_c,(__bridge CFArrayRef)@[identifier],(__bridge CFArrayRef)@[@(_s)]);
    actual=[self windowSpaceIDs:number];
    if(!actual || [actual containsObject:@(_s)])return;
    [_windows removeObject:identifier];
    [_originalSpaces removeObjectForKey:identifier];
    [_verifiedWindows removeObject:identifier];
}
- (NSArray<NSNumber *> *)windowSpaceIDs:(NSInteger)number {
    if(!_f.copyForWindows || number<=0)return nil;
    CFArrayRef spaces=_f.copyForWindows(_c,0xF,(__bridge CFArrayRef)@[@(number)]);
    if(!spaces)return nil;
    NSArray<NSNumber *> *result=[(__bridge NSArray *)spaces copy];
    CFRelease(spaces);
    return result;
}
- (NSDictionary *)diagnostic {
    BOOL verified=NO;
    if(_s&&_windows.count&&_f.copyForWindows) {
        CFArrayRef spaces=_f.copyForWindows(_c,0xF,(__bridge CFArrayRef)_windows.allObjects);
        if(spaces){verified=[(__bridge NSArray *)spaces containsObject:@(_s)];CFRelease(spaces);}
    }
    return @{@"created":@(_s!=0),@"absoluteLevel":@(_s?_f.getLevel(_c,_s):0),
             @"ownedWindowCount":@(_windows.count),@"membershipVerified":@(verified)};
}
#if VALORA_LOCK_SPACE_TESTING
// Compiled only by the standalone fake native regression harness, never the app.
- (instancetype)initWithTestFunctions:(ARLockSpaceFunctions)functions {
    self=[super init]; if(!self)return nil;
    _f=functions; _c=1; _s=901;
    _windows=[NSMutableSet set]; _originalSpaces=[NSMutableDictionary dictionary];
    _verifiedWindows=[NSMutableSet set];
    return self;
}
#endif
- (void)dealloc {
    if(!_s)return;
    for(NSNumber *number in [_windows.allObjects copy]) [self detachWindowNumber:number.integerValue];
    _f.hide(_c,(__bridge CFArrayRef)@[@(_s)]);
    _f.destroy(_c,_s);
}
@end
