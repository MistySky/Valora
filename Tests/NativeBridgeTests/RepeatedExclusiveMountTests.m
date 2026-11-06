// V0097 native regressions for repeated exclusive mounts.
// Compiles the production NativeBridge.m and drives it only through injected
// fake callbacks: no NSApp, no NSWindow and no real Space call happens here.
#define VALORA_LOCK_SPACE_TESTING 1
#import "../../Sources/NativeBridge/NativeBridge.m"

static NSMutableSet<NSNumber *> *members;
static int addCalls;
static BOOL ignoreNextAdd;
static int copiesUntilUnknown = -1;

static CFArrayRef fakeCopy(int32_t c, uint32_t mask, CFArrayRef windows) {
    if (copiesUntilUnknown > 0) {
        copiesUntilUnknown--;
        if (copiesUntilUnknown == 0) return NULL;   // post-migration query unknown
    }
    return CFBridgingRetain(members.allObjects);
}
static void fakeAdd(int32_t c, CFArrayRef windows, CFArrayRef spaces) {
    addCalls++;
    if (ignoreNextAdd) { ignoreNextAdd = NO; return; }   // WindowServer ignores this add
    [members addObjectsFromArray:(__bridge NSArray *)spaces];
}
static void fakeRemove(int32_t c, CFArrayRef windows, CFArrayRef spaces) {
    [members minusSet:[NSSet setWithArray:(__bridge NSArray *)spaces]];
}
static void fakeHide(int32_t c, CFArrayRef spaces) {}
static void fakeDestroy(int32_t c, uint64_t space) {}

static ARLockPresentationSpace *makeSpace(NSSet<NSNumber *> *start) {
    members = [NSMutableSet setWithSet:start];
    addCalls = 0;
    ignoreNextAdd = NO;
    copiesUntilUnknown = -1;
    ARLockSpaceFunctions f = {0};
    f.copyForWindows = fakeCopy;
    f.add = fakeAdd;
    f.remove = fakeRemove;
    f.hide = fakeHide;
    f.destroy = fakeDestroy;
    return [[ARLockPresentationSpace alloc] initWithTestFunctions:f];
}

static BOOL okOf(NSDictionary *result) {
    return [(result[@"ok"] ?: @NO) boolValue];
}

int main(void) { @autoreleasepool {
    // 1. Repeated success must still restore the original desktop membership.
    { ARLockPresentationSpace *s = makeSpace([NSSet setWithObject:@11]);
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"first mount");
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"repeat mount stays ok");
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@901]], @"owned only after repeat");
      [s detachWindowNumber:7];
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]],
                @"detach must restore the FIRST captured desktop membership");
    }

    // 2. A genuinely empty first capture stays empty through a repeat.
    { ARLockPresentationSpace *s = makeSpace([NSSet set]);
      NSDictionary *first = [s migrateWindowNumberExclusively:7];
      NSCAssert(okOf(first), @"empty capture migrates");
      NSCAssert([first[@"before"] isKindOfClass:[NSArray class]] && [first[@"before"] count] == 0,
                @"empty capture is a real array");
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"repeat on empty ok");
      [s detachWindowNumber:7];
      NSCAssert(members.count == 0, @"empty first capture restores nothing");
    }

    // 3. A failed first attempt stores nothing; a retry captures the desktop.
    { ARLockPresentationSpace *s = makeSpace([NSSet setWithObject:@11]);
      ignoreNextAdd = YES;
      NSCAssert(!okOf([s migrateWindowNumberExclusively:7]), @"ignored add fails");
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]], @"rollback keeps desktop");
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"retry succeeds");
      [s detachWindowNumber:7];
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]],
                @"retry captured the desktop for detach");
    }

    // 4. A failed repeat keeps the first snapshot and rolls back to the entry
    //    state (already exclusive), not to an empty membership.
    { ARLockPresentationSpace *s = makeSpace([NSSet setWithObject:@11]);
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"first mount");
      // The repeat's post-query is unknown, so the call must fail and roll back
      // to the entry state while keeping the first snapshot for detach.
      copiesUntilUnknown = 2;
      NSDictionary *repeat = [s migrateWindowNumberExclusively:7];
      NSCAssert(!okOf(repeat), @"repeated failure reported");
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@901]],
                @"rollback restores the entry state (still exclusive)");
      [s detachWindowNumber:7];
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]],
                @"first snapshot survives a failed repeat");
    }

    // 5. Detach ends the cycle; a later mount captures afresh.
    { ARLockPresentationSpace *s = makeSpace([NSSet setWithObject:@11]);
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"first cycle mount");
      [s detachWindowNumber:7];
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]], @"restored after first cycle");
      NSCAssert(okOf([s migrateWindowNumberExclusively:7]), @"second cycle mount");
      [s detachWindowNumber:7];
      NSCAssert([members isEqualToSet:[NSSet setWithObject:@11]],
                @"second cycle re-captured and restored the desktop");
    }

    puts("5 repeated exclusive-mount scenarios passed (fake callbacks only)");
} return 0; }
