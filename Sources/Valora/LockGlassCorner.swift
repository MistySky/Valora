import SwiftUI

/// Corner radius from the decompiled macOS 26+ branch: `100186a7c` calls
/// `FUN_100187f28(width 345, corner 30)` on `OS >= 26`.
enum LockGlassCorner {
    static let radius: CGFloat = 30
}
