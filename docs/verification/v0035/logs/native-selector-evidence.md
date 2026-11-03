Read-only runtime selector check (no device list, no pairing, no TCC call):

`batteryPercentLeft/Right/Single/Case/Combined` and `colorID` all report
Objective-C return encoding `C` (unsigned char). The previous native bridge
called them with an `unsigned int` function pointer, which is not the declared
ABI. The bridge now checks `method_copyReturnType` for exactly `C` and reads an
`unsigned char`; unsupported/missing return types yield `-1`.

This check did not read current device values. The running user candidate was
not injected, replaced, or restarted.
