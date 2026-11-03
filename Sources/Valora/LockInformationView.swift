import SwiftUI

/// Lock-screen device summary. The original lock surface shows a single inline
/// `icon + percentage` line directly on the wallpaper: no frosted tile, no
/// device name. Keep the existing information panel geometry and only change
/// what is drawn inside it.
///
/// Size: the original photo and the Valora photo show the same physical line at
/// the same pixel size, but the Valora frame is 1.235x more zoomed (music card
/// 473 px vs 383 px for the same 345pt card). Our 13pt therefore read about a
/// quarter smaller on screen; 16pt matches the original's weight.
struct LockInformationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var coordinator: LockMusicCoordinator
    var body: some View {
        HStack(spacing: 7) {
            if let device = coordinator.informationAirPods {
                Image(systemName: device.symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(device.battery.map { "\($0)%" } ?? "电量暂不可用")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
            }
        }
        // White text has to survive a bright wallpaper without a tile behind it.
        .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
        // The panel keeps the original top anchor. The header is a thin line, so
        // it sits at the top of that slot instead of in the middle of the old
        // 94pt tile; measured against the clock the centred version read ≈60pt
        // too low.
        .frame(width: 360, height: 94, alignment: .top)
        .foregroundStyle(.white)
        .colorScheme(.dark)
    }
}
