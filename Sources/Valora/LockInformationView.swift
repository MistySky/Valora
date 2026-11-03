import SwiftUI

/// Selected lock-screen device tile: only the existing device snapshot is
/// consumed; no Bluetooth query, battery/focus/calendar provider is created.
struct LockInformationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var coordinator: LockMusicCoordinator
    var body: some View {
        HStack(spacing: 12) {
            if let device = coordinator.informationAirPods {
                HStack(spacing: 10) {
                    Image(systemName: device.symbol).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(device.battery.map { "\($0)%" } ?? "电量暂不可用")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(14).frame(maxWidth: .infinity, minHeight: 68)
                .background(LockFrostedBackground(cornerRadius: 22))
            }
        }
        .frame(width: 360, height: 94)
        .foregroundStyle(.white)
        .colorScheme(.dark)
    }
}
