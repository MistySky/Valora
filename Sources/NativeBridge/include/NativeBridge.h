#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// Narrow native surface kept for the music vertical slice.
/// Everything else from the archived bridge (battery, Bluetooth device list,
/// QQ Accessibility, lock presentation Space, direct MediaRemote probes) is
/// intentionally not migrated because those product features are out of scope.

/// Used only to choose the built-in laptop/desktop output symbol.
BOOL ARComputerIsPortable(void);

/// Current default CoreAudio output: uid/name/modelUID/kind/port/volume/mute.
NSDictionary *ARAudioOutputSnapshot(void);

/// Read-only connected Bluetooth audio snapshot. The synchronous IOBluetooth
/// query must run off the main thread; callers bound in-flight queries.
NSArray<NSDictionary *> *ARConnectedAudioDevices(void);
NSString *ARDefaultAudioOutputName(void);

/// Writes are only issued from explicit user gestures in the expanded player.
BOOL ARSetOutputVolume(NSString *expectedUID, double volume);
BOOL ARSetOutputMuted(NSString *expectedUID, BOOL muted);

NS_ASSUME_NONNULL_END
