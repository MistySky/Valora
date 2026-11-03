// Functional native regressions using production code and fake API callbacks.
#define VALORA_LOCK_SPACE_TESTING 1
#import "../../Sources/NativeBridge/NativeBridge.m"
static NSMutableSet<NSNumber *> *members;
static int moves, removes, mode;
static CFArrayRef fakeCopy(int32_t c,uint32_t mask,CFArrayRef windows) {
    if(mode==3 || (mode==4 && moves>0))return NULL;
    return CFBridgingRetain(members.allObjects);
}
static int32_t fakeMove(int32_t c,int32_t target,CFArrayRef windows,int32_t flags) {
    NSCAssert((flags==7),@"migration flags");moves++;
    if(mode==1)return 0; // Unsupported call silently succeeds without moving.
    [members removeAllObjects];[members addObject:@(target)];return mode==2 ? 1 : 0;
}
static void fakeAdd(int32_t c,CFArrayRef windows,CFArrayRef spaces) {
    [members addObjectsFromArray:(__bridge NSArray *)spaces];
}
static void fakeRemove(int32_t c,CFArrayRef windows,CFArrayRef spaces) {
    removes++;[members minusSet:[NSSet setWithArray:(__bridge NSArray *)spaces]];
}
static void fakeHide(int32_t c,CFArrayRef spaces) {}
static void fakeDestroy(int32_t c,uint64_t space) {}
static ARLockPresentationSpace *makeSpace(int scenario) {
    members=[NSMutableSet setWithObject:@11];moves=0;removes=0;mode=scenario;
    ARLockSpaceFunctions f={0};f.copyForWindows=fakeCopy;f.addAndRemove=fakeMove;
    f.add=fakeAdd;f.remove=fakeRemove;f.hide=fakeHide;f.destroy=fakeDestroy;
    if(mode==5)f.addAndRemove=NULL;
    return [[ARLockPresentationSpace alloc] initWithTestFunctions:f];
}
int main(void) { @autoreleasepool {
    { ARLockPresentationSpace *s=makeSpace(0);
      NSCAssert(([s migrateWindowNumberToOwnedSpace:7]),@"success");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@901]]),@"exclusive target");
      [s detachWindowNumber:7];
      NSCAssert((removes==1 && members.count==0),@"migrated overlay is registered for detach");
    }
    { ARLockPresentationSpace *s=makeSpace(1);
      NSCAssert((![s migrateWindowNumberToOwnedSpace:7]),@"silent no-op rejected");
      NSCAssert(([members containsObject:@11]),@"fallback desktop retained");
    }
    { ARLockPresentationSpace *s=makeSpace(2);
      NSCAssert((![s migrateWindowNumberToOwnedSpace:7]),@"partial movement error rejected");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@11]]),@"partial movement rolled back");
    }
    { ARLockPresentationSpace *s=makeSpace(3);
      NSCAssert((![s migrateWindowNumberToOwnedSpace:7] && moves==0),@"unknown original does not migrate");
    }
    { ARLockPresentationSpace *s=makeSpace(4);
      NSCAssert((![s migrateWindowNumberToOwnedSpace:7]),@"unknown result rejected");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@11]]),@"unknown result rolled back");
    }
    { ARLockPresentationSpace *s=makeSpace(5);
      NSCAssert((![s migrateWindowNumberToOwnedSpace:7] && moves==0),@"missing symbol does not call backend");
    }
    puts("6 isolated native overlay scenarios passed; no real windows or Space calls");
} return 0; }
