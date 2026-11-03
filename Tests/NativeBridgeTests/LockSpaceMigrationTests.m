// Historical R8 fake regression, retained against its archived implementation.
// R8 is disabled after the user reported that the lock surface disappeared.
#define VALORA_LOCK_SPACE_TESTING 1
#import "../../docs/verification/direct-v0036-r8/NativeBridge-r8.m"
static NSMutableSet<NSNumber *> *members;
static int moveError, moveCalls, removeCalls;
static BOOL failRestore, failQuery, noOpMove;
static CFArrayRef fakeCopy(int32_t c,uint32_t mask,CFArrayRef windows) {
    if(failQuery)return NULL;
    return CFBridgingRetain(members.allObjects);
}
static int32_t fakeMove(int32_t c,int32_t target,CFArrayRef windows,int32_t mode) {
    NSCAssert((mode==7),@"migration mode");moveCalls++;
    if(noOpMove)return 0;
    [members removeAllObjects];[members addObject:@(target)];return moveError;
}
static void fakeAdd(int32_t c,CFArrayRef windows,CFArrayRef spaces) {
    if(!failRestore)[members addObjectsFromArray:(__bridge NSArray *)spaces];
}
static void fakeRemove(int32_t c,CFArrayRef windows,CFArrayRef spaces) {
    removeCalls++;[members minusSet:[NSSet setWithArray:(__bridge NSArray *)spaces]];
}
static void fakeHide(int32_t c,CFArrayRef spaces) {}
static void fakeDestroy(int32_t c,uint64_t space) {}
static ARLockPresentationSpace *makeSpace(void) {
    members=[NSMutableSet setWithArray:@[@11,@22]];
    moveError=0;moveCalls=0;removeCalls=0;failRestore=NO;failQuery=NO;noOpMove=NO;
    ARLockSpaceFunctions f={0};f.copyForWindows=fakeCopy;f.moveToSpace=fakeMove;
    f.add=fakeAdd;f.remove=fakeRemove;f.hide=fakeHide;f.destroy=fakeDestroy;
    return [[ARLockPresentationSpace alloc] initWithTestFunctions:f];
}
int main(void) { @autoreleasepool {
    { ARLockPresentationSpace *s=makeSpace();
      NSCAssert(([s attachOwnedWindowNumber:7]),@"attach succeeds");
      NSCAssert(([members isEqualToSet:[NSSet setWithObject:@901]]),@"exclusive target membership");
      NSCAssert(([s attachOwnedWindowNumber:7] && moveCalls==1),@"idempotent attach");
      [s detachWindowNumber:7];
      NSCAssert(([members isEqualToSet:[NSSet setWithArray:@[@11,@22]]]),@"restore all original spaces");
    }
    { ARLockPresentationSpace *s=makeSpace();noOpMove=YES;
      NSCAssert((![s attachOwnedWindowNumber:7]),@"silent no-op success is rejected");
      NSCAssert(([members isEqualToSet:[NSSet setWithArray:@[@11,@22]]]),@"no-op retains desktop membership");
    }
    { ARLockPresentationSpace *s=makeSpace();moveError=1;
      NSCAssert((![s attachOwnedWindowNumber:7]),@"error even after partial movement fails");
      NSCAssert(([members isEqualToSet:[NSSet setWithArray:@[@11,@22]]]),@"partial error rolls back");
    }
    { ARLockPresentationSpace *s=makeSpace();failQuery=YES;
      NSCAssert((![s attachOwnedWindowNumber:7] && moveCalls==0),@"unknown origin never migrates");failQuery=NO;
    }
    { ARLockPresentationSpace *s=makeSpace();[members removeAllObjects];
      NSCAssert(([s attachOwnedWindowNumber:7]),@"new hidden card can migrate");
      [s detachWindowNumber:7];NSCAssert((members.count==0),@"hidden card restores empty membership");
    }
    { ARLockPresentationSpace *s=makeSpace();
      NSCAssert(([s attachOwnedWindowNumber:7]),@"attach before failed restore");failRestore=YES;
      [s detachWindowNumber:7];
      NSCAssert((removeCalls==0 && [members containsObject:@901]),@"failed restore does not orphan window");
      failRestore=NO;[s detachWindowNumber:7];
      NSCAssert(([members isEqualToSet:[NSSet setWithArray:@[@11,@22]]]),@"failed restore remains retryable");
    }
    puts("6 native migration scenarios passed (fake callbacks only)");
} return 0; }
