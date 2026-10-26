import SwiftUI

/// Calmon-style native calendar/monitor material and rhythm; no ring cards,
/// no nested popover, and no reset action. This view only reads the provider
/// snapshot and formats local times.
struct CodexUsageContentView: View {
    let provider: CodexUsageProvider

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Codex 用量")
                    .font(UIStyle.Fonts.panelTitle)
                    .accessibilityAddTraits(.isHeader)
                switch provider.snapshot.status {
                case .loading:
                    Text("正在读取额度…")
                        .font(UIStyle.Fonts.body)
                        .foregroundStyle(.secondary)
                case .ready:
                    if provider.isRefreshing {
                        Text("正在后台更新…")
                            .font(UIStyle.Fonts.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = provider.snapshot.refreshErrorMessage {
                        Text("更新失败：\(error)")
                            .font(UIStyle.Fonts.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if let observed = provider.snapshot.observedAt {
                            Text("上次成功 \(observed.formatted(date: .abbreviated, time: .shortened))")
                                .font(UIStyle.Fonts.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if provider.snapshot.fiveHour == nil && provider.snapshot.week == nil {
                        Text("额度数据未提供")
                            .font(UIStyle.Fonts.body)
                            .foregroundStyle(.secondary)
                    } else {
                        windowRow(title: "5小时剩余", window: provider.snapshot.fiveHour)
                        Divider()
                        windowRow(title: "周剩余", window: provider.snapshot.week)
                    }
                    Divider()
                    resetCredits
                default:
                    Text(provider.snapshot.message ?? provider.snapshot.status.displayMessage ?? "额度暂不可用")
                        .font(UIStyle.Fonts.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(UIStyle.Metrics.contentMargin)
            .frame(width: UIStyle.Metrics.menuBarPopoverWidth, alignment: .leading)
    }

    private func windowRow(title: String, window: CodexQuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(UIStyle.Fonts.groupTitle)
                Spacer(minLength: 8)
                Text(percentText(window?.remainingPercent))
                    .font(UIStyle.Fonts.body)
                    .monospacedDigit()
            }
            Text(resetText(window?.resetsAt))
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，剩余 \(percentText(window?.remainingPercent))，\(resetText(window?.resetsAt))")
    }

    @ViewBuilder private var resetCredits: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("重置卡")
                    .font(UIStyle.Fonts.groupTitle)
                Spacer(minLength: 8)
                Text(resetCountText)
                    .font(UIStyle.Fonts.body)
                    .monospacedDigit()
            }
            if let count = provider.snapshot.resetAvailableCount {
                if count > 0 {
                    Text("到期时间 · 本地时区")
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                    let visibleCredits = Array(provider.snapshot.resetCredits.prefix(count))
                    ForEach(Array(visibleCredits.enumerated()), id: \.element.id) { index, credit in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("重置 \(index + 1)")
                                .font(UIStyle.Fonts.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(expiryText(credit.expiresAt))
                                .font(UIStyle.Fonts.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("重置 \(index + 1)，\(expiryText(credit.expiresAt))")
                    }
                    let missing = count - visibleCredits.count
                    if missing > 0 {
                        Text("\(missing) 张重置卡到期时间未提供")
                            .font(UIStyle.Fonts.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("暂无可用重置卡")
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("可用次数暂不可用")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resetCountText: String {
        guard let count = provider.snapshot.resetAvailableCount else { return "暂不可用" }
        return "\(count) 次可用"
    }

    private func percentText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "未提供" }
        return "\(Int(value.rounded()))%"
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "重置时间未提供" }
        return "重置 \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func expiryText(_ date: Date?) -> String {
        guard let date else { return "有效期未提供" }
        return date.formatted(date: .numeric, time: .shortened)
    }
}


/// Standalone Codex popover wrapper used by callers that still present it alone.
struct CodexUsagePopoverView: View {
    let provider: CodexUsageProvider
    var maxHeight: CGFloat = 600

    var body: some View {
        ScrollView(.vertical) {
            CodexUsageContentView(provider: provider)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        .frame(maxHeight: maxHeight)
    }
}
