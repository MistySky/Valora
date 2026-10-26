// Shared menu-bar panel for system monitoring and Codex remaining quota.
// Content is composed from the already accepted Calmon/Codex content views;
// one outer vertical ScrollView owns the 400pt panel.
import SwiftUI

struct MonitorCodexCombinedView: View {
    let monitor: SystemMonitor
    let codex: CodexUsageProvider?
    let maxHeight: CGFloat
    @Bindable var search: AppSearchModel
    let showMonitor: Bool
    let showCodex: Bool
    var onClose: () -> Void

    /// The initial monitor view renders a 36 pt "loading" application row
    /// before the async app list arrives; the intrinsic popover height then
    /// changes. Suppress only that provisional indicator while the first
    /// monitor/Codex snapshot is loading, then return to the system-automatic
    /// overlay scroller. Scrolling and overflow content remain available.
    private var isInitialContentLoading: Bool {
        if showMonitor, monitor.applicationState == .idle || monitor.applicationState == .loading {
            return true
        }
        if showCodex, codex?.snapshot.status == .loading {
            return true
        }
        return false
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if showMonitor {
                    MonitoringContentView(monitor: monitor, maxHeight: maxHeight,
                                          search: search, onClose: onClose)
                }
                if showMonitor && showCodex {
                    Divider()
                        .padding(.horizontal, UIStyle.Metrics.contentMargin)
                }
                if showCodex, let codex {
                    CodexUsageContentView(provider: codex)
                }
            }
            .frame(width: UIStyle.Metrics.menuBarPopoverWidth, alignment: .leading)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        .frame(maxHeight: maxHeight)
        .scrollIndicators(isInitialContentLoading ? .hidden : .automatic)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}
