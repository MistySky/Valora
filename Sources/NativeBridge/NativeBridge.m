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
    return ((unsigned int(*)(id,SEL))objc_msgSend)(object, selector);
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
            @"id": address, @"name": active && outputName.length ? outputName : name,
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
