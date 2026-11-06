#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// Narrow native surface kept for the music/device/lock vertical slice.
/// Battery, Bluetooth device-list, QQ Accessibility and direct MediaRemote
/// probes remain out of scope; the owned lock presentation Space is migrated
/// separately below because the selected lock screen needs it.

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

/// Process-owned lock-screen presentation Space. Fails nil when the private
/// SkyLight symbols are unavailable; callers must fail closed.
@interface ARLockPresentationSpace : NSObject
+ (nullable instancetype)createPresentationSpace;
- (BOOL)attachWindowNumber:(NSInteger)number;
- (void)detachWindowNumber:(NSInteger)number;
- (nullable NSArray<NSNumber *> *)windowSpaceIDs:(NSInteger)number;
- (BOOL)migrateWindowNumberToOwnedSpace:(NSInteger)number;
/// Add the window to the owned Space and drop every other captured membership,
/// so the window is not part of the user-session surface the WindowServer scales
/// during the lock/unlock transition. Empty membership is legal (a freshly
/// ordered window has none). The result always reports the real captured
/// memberships and the failure branch; a failed attempt is rolled back.
- (NSDictionary<NSString *, id> *)migrateWindowNumberExclusively:(NSInteger)number;
- (uint64_t)spaceID;
- (NSDictionary *)diagnostic;
@end

/// C wrappers avoid Swift importer availability collisions on the private
/// migration selector while keeping the ObjC implementation shared.
BOOL ARLockSpaceMigrateWindow(ARLockPresentationSpace *space, NSInteger number);
NSDictionary<NSString *, id> *ARLockSpaceMigrateWindowExclusive(ARLockPresentationSpace *space, NSInteger number);
uint64_t ARLockSpaceOwnedID(ARLockPresentationSpace *space);

NS_ASSUME_NONNULL_END
