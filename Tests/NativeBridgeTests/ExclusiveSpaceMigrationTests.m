// Functional native regressions for the owned-Space-only lock mount.
// Compiles the production NativeBridge.m and drives it only through injected
// fake callbacks: no NSApp, no NSWindow and no real Space call happens here.
#define VALORA_LOCK_SPACE_TESTING 1
#import "../../Sources/NativeBridge/NativeBridge.m"

static NSMutableSet<NSNumber *> *members;
static int adds, removes, mode;

static CFArrayRef fakeCopy(int32_t c, uint32_t mask, CFArrayRef windows) {
    if (mode == 5) return NULL;                 // post-migration query unknown
    return CFBridgingRetain(members.allObjects);
}
static void fakeAdd(int32_t c, CFArrayRef windows, CFArrayRef spaces) {
    adds++;
    if (mode == 2 && adds == 1) return;         // first add silently ignored
    [members addObjectsFromArray:(__bridge NSArray *)spaces];
}
static void fakeRemove(int32_t c, CFArrayRef windows, CFArrayRef spaces) {
    removes++;
    [members minusSet:[NSSet setWithArray:(__bridge NSArray *)spaces]];
}
static void fakeHide(int32_t c, CFArrayRef spaces) {}
static void fakeDestroy(int32_t c, uint64_t space) {}

static ARLockPresentationSpace *makeSpace(int scenario, NSSet<NSNumber *> *start) {
    members = [NSMutableSet setWithSet:start];
    adds = 0; removes = 0; mode = scenario;
    ARLockSpaceFunctions f = {0};
    f.copyForWindows = fakeCopy;
    f.add = fakeAdd;
    f.remove = fakeRemove;
    f.hide = fakeHide;
    f.destroy = fakeDestroy;
    if (mode == 1) f.add = NULL;                // missing symbol
    return [[ARLockPresentationSpace alloc] initWithTestFunctions:f];
}

static BOOL okOf(NSDictionary *result) {
    return [(result[@"ok"] ?: @NO) boolValue];
}

int main(void) { @autoreleasepool {
    // 1. A freshly ordered window has no Space membership; that is legal and
    //    must still end up owned by exactly the private Space.
    { ARLockPresentationSpace *s = makeSpace(0, [NSSet set]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(okOf(r), @"empty membership migrates");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@901]]), @"owned space only");
      NSCAssert(([r[@"before"] isKindOfClass:[NSArray class]] && [r[@"before"] count] == 0),
                @"empty membership reported as a real, empty array");
      [s detachWindowNumber:7];
      NSCAssert((members.count == 0), @"nothing to restore for an empty capture");
    }

    // 2. The ordinary desktop membership is dropped for the lock and restored
    //    on detach, so the panel never keeps riding the user-session surface.
    { ARLockPresentationSpace *s = makeSpace(0, [NSSet setWithObject:@11]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(okOf(r), @"desktop member migrates exclusively");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@901]]), @"desktop membership removed");
      NSCAssert(([r[@"before"] containsObject:@11]), @"capture reported");
      [s detachWindowNumber:7];
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@11]]), @"desktop membership restored");
    }

    // 3. An add that the WindowServer silently ignores must be reported and
    //    rolled back instead of pretending the surface is isolated.
    { ARLockPresentationSpace *s = makeSpace(2, [NSSet setWithObject:@11]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(!okOf(r), @"silent no-op rejected");
      NSCAssert(([r[@"reason"] isEqualToString:@"not-exclusive"]), @"reason names the branch");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@11]]), @"rollback keeps desktop membership");
    }

    // 4. A successful-looking call whose post-query says otherwise is rolled
    //    back the same way.
    { ARLockPresentationSpace *s = makeSpace(5, [NSSet setWithObject:@11]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(!okOf(r), @"unknown post-query rejected");
      NSCAssert(([r[@"reason"] isEqualToString:@"post-query-unknown"]), @"unknown branch named");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@11]]), @"rollback after unknown query");
    }

    // 5. Missing private symbols fail closed without touching the backend.
    { ARLockPresentationSpace *s = makeSpace(1, [NSSet setWithObject:@11]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(!okOf(r), @"missing symbols fail");
      NSCAssert(([r[@"reason"] isEqualToString:@"missing-symbols"]), @"missing symbol branch");
      NSCAssert((adds == 0 && removes == 0), @"no backend call without symbols");
    }

    // 6. A window already owned only by the private Space stays a success and
    //    keeps its captured membership empty-but-real for detach.
    { ARLockPresentationSpace *s = makeSpace(0, [NSSet setWithObject:@901]);
      NSDictionary *r = [s migrateWindowNumberExclusively:7];
      NSCAssert(okOf(r), @"already exclusive stays ok");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@901]]), @"kept owned space");
      [s detachWindowNumber:7];
      NSCAssert((members.count == 0), @"exclusive-only capture restores nothing");
    }

    puts("6 exclusive owned-Space scenarios passed (fake callbacks only)");
} return 0; }
