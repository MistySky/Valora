import SwiftUI
import AppKit

struct SettingsIcon: View {
    let page: SettingsPage
    var muted = false
    var size: CGFloat = 22
    var body: some View {
        Group {
            if page == .calendar {
                // Directly recovered from the archived SettingsIcon calendar
                // branch: colored header, paper surface and date "12".
                VStack(spacing: 0) {
                    Rectangle().fill(muted ? Color.gray : page.color)
                        .frame(height: size * 0.27)
                    Text("12")
                        .font(.system(size: size * 0.48, weight: .medium))
                        .foregroundStyle(muted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.background(Color(nsColor: .controlBackgroundColor))
            } else {
                Image(systemName: page.symbol).font(.system(size: size * 0.60, weight: .semibold))
                    .foregroundStyle(.white).frame(width: size, height: size)
                    .background(LinearGradient(colors: [(muted ? .gray : page.color).opacity(0.65), muted ? .gray : page.color], startPoint: .top, endPoint: .bottom))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.29))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29).stroke(.black.opacity(0.06), lineWidth: 0.5)).accessibilityHidden(true)
    }
}
struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(SettingsPalette.cardBackground(scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.11), lineWidth: 1))
            .shadow(color: .black.opacity(0.045), radius: 1, y: 1)
    }
}
struct SettingsRule: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
}
struct SettingsSwitch: ToggleStyle {
    let label: String
    @Environment(\.controlActiveState) private var active
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn && active != .inactive ? Color.accentColor : Color.primary.opacity(configuration.isOn ? 0.16 : 0.075))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(.white).frame(width: 26, height: 16)
                        .shadow(color: .black.opacity(0.14), radius: 2, y: 1).padding(2)
                }.frame(width: 44, height: 20)
        }.buttonStyle(.plain).accessibilityLabel(SettingsText.localized(label)).accessibilityValue(configuration.isOn ? "开启" : "关闭")
            .animation(.easeOut(duration: 0.14), value: configuration.isOn)
    }
}
struct SettingsToggleRow: View {
    let title: String
    @Binding var value: Bool
    var symbol: String? = nil
    var badge: SettingsPage? = nil
    var blocked = false
    var info: String? = nil
    var sound = false
    var onAccessory: (() -> Void)? = nil
    @State private var showInfo = false
    @Environment(\.controlActiveState) private var active
    var body: some View {
        HStack(spacing: 8) {
            if let badge { SettingsIcon(page: badge, size: 20) }
            else if let symbol { Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(value && active != .inactive ? Color.accentColor : Color.secondary).frame(width: 18) }
            Text(SettingsText.localized(title)).fixedSize(horizontal: true, vertical: false)
            if sound { Button { onAccessory?() } label: { Image(systemName: "play.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("预览：\(SettingsText.localized(title))") }
            if let info {
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("查看说明").popover(isPresented: $showInfo) { Text(SettingsText.localized(info)).font(.system(size: 12)).padding(14).frame(width: 250) }
            }
            Spacer(minLength: 2)
            if blocked {
                // The hand is a status marker only. The switch below is the
                // single interaction that can begin an authorization intent.
                Image(systemName: "hand.raised.slash.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("需要授权")
                    .accessibilityHint("点击开关尝试开启并处理授权")
            }
            Toggle(SettingsText.localized(title), isOn: $value).labelsHidden().accessibilityLabel(SettingsText.localized(title)).toggleStyle(SettingsSwitch(label: title))
        }.font(.system(size: 13.5)).padding(.horizontal, 12).frame(height: 41)
    }
}
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "s"
    var decimals: Int = 0
    var ticks: Int = 11
    @State private var editing = false
    @State private var editingText = ""
    @Environment(\.controlActiveState) private var active
    // A saved value can predate a corrected reference range.
    private var boundedValue: Double { value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : range.lowerBound }
    private var formatted: String { String(format: "%.*f", decimals, boundedValue) }
    private func set(_ x: CGFloat, width: CGFloat) {
        let raw = range.lowerBound + Double(min(1, max(0, x / max(1, width)))) * (range.upperBound - range.lowerBound)
        value = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
    }
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(SettingsText.localized(title)); Spacer()
                HStack(spacing: 2) {
                    if editing {
                        SettingsNumberEditor(text: $editingText, label: SettingsText.localized(title), onEdit: { text in
                            let separator = Locale.current.decimalSeparator ?? "."
                            guard let number = Double(text.replacingOccurrences(of: separator, with: ".")), number.isFinite else { return nil }
                            let clamped = min(range.upperBound, max(range.lowerBound, number))
                            value = clamped
                            return clamped == number ? nil : NSNumber(value: clamped).stringValue
                        }, onFinish: { editing = false })
                        .frame(width: max(12, (editingText as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)]).width + 2), height: 20)
                    } else {
                        Button { editingText = NSNumber(value: boundedValue).stringValue; editing = true } label: {
                            Text(formatted).font(.system(size: 13.5, design: .monospaced))
                        }.buttonStyle(.plain).accessibilityLabel("\(SettingsText.localized(title))：\(formatted)")
                    }
                    Text(SettingsText.localized(unit)).font(.system(size: 13.5, design: .monospaced))
                }.padding(.horizontal, 8).fixedSize().frame(height: 24)
                    .background(Color.primary.opacity(0.025), in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.09), lineWidth: 1))
            }
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 20)
                let fraction = (boundedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10)).frame(height: 6)
                    Capsule().fill(active == .inactive ? Color.primary.opacity(0.13) : Color.accentColor).frame(width: max(6, 10 + width * fraction), height: 6)
                    Capsule().fill(.white).frame(width: 20, height: 16).shadow(color: .black.opacity(0.12), radius: 3, y: 1).offset(x: width * fraction)
                    if ticks > 1 {
                        HStack { ForEach(0..<ticks, id: \.self) { index in Circle().fill(Color.secondary.opacity(0.45)).frame(width: 2, height: 2); if index < ticks - 1 { Spacer(minLength: 0) } } }.padding(.horizontal, 10).offset(y: 7)
                    }
                }.frame(height: 24).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { set($0.location.x - 10, width: width) })
            }.frame(height: 24)
            .accessibilityElement().accessibilityLabel(SettingsText.localized(title)).accessibilityValue("\(formatted) \(SettingsText.localized(unit))")
            .accessibilityAdjustableAction { direction in value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step))) }
        }.font(.system(size: 13.5)).padding(.horizontal, 12).padding(.top, 4).frame(height: 77)
            .onChange(of: value) { _, _ in
                // Dragging the slider while its inline editor is still open
                // must update the number too, without resetting valid typing.
                guard editing else { return }
                let separator = Locale.current.decimalSeparator ?? "."
                let entered = Double(editingText.replacingOccurrences(of: separator, with: "."))
                if entered != boundedValue { editingText = NSNumber(value: boundedValue).stringValue }
            }
    }
}
struct SettingsChoice: Identifiable {
    let title: String
    let symbol: String
    var style: String = "symbol"
    var value: String
    /// A choice kept for layout parity whose backend is not part of this slice.
    /// It renders disabled and explains the exact missing system capability.
    var unavailable = false
    var unavailableReason: String? = nil
    var id: String { title }

    init(title: String, symbol: String, style: String = "symbol",
         value: String? = nil,
         unavailable: Bool = false, unavailableReason: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.value = value ?? title
        self.unavailable = unavailable
        self.unavailableReason = unavailableReason
    }
}

struct SettingsChoices: View {
    let choices: [SettingsChoice]
    @Binding var selected: String
    var tileHeight: CGFloat = 38
    @Environment(\.controlActiveState) private var active
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(choices) { choice in
                Button { selected = choice.value } label: {
                    VStack(spacing: 8) {
                        tile(choice).frame(maxWidth: .infinity).frame(height: tileHeight)
                            .background(tileBackground(choice), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                            .overlay { if choice.value == selected { RoundedRectangle(cornerRadius: 14).stroke(active == .inactive ? Color.gray.opacity(0.5) : .accentColor, lineWidth: 3).padding(-4) } }
                        Text(SettingsText.localized(choice.title)).font(.system(size: 13.5, weight: selected == choice.value ? .semibold : .regular)).foregroundStyle(selected == choice.value ? .primary : .secondary).lineLimit(1).frame(height: 16)
                    }.frame(maxWidth: .infinity).opacity(choice.unavailable ? 0.42 : 1)
                }.buttonStyle(.plain).disabled(choice.unavailable)
                    .help(choice.unavailable ? (choice.unavailableReason ?? "当前系统媒体接口不提供该能力") : "")
                    .accessibilityLabel(SettingsText.localized(choice.title))
                    .accessibilityAddTraits(choice.value == selected ? [.isSelected] : [])
                    .accessibilityHint(choice.unavailable ? (choice.unavailableReason ?? "当前系统媒体接口不提供该能力") : "")
            }
        }.padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 11)
    }
    private func tileBackground(_ choice: SettingsChoice) -> Color {
        if choice.style == "progress" { return .black }
        if choice.style == "source" {
            if choice.title == "Music" { return .pink.opacity(0.10) }
            if choice.title == "Spotify" { return .mint.opacity(0.12) }
        }
        if choice.style == "idle" && choice.value == selected { return .pink.opacity(0.10) }
        if choice.value == selected && active != .inactive { return Color.accentColor.opacity(0.07) }
        return .primary.opacity(0.035)
    }
    @ViewBuilder private func tile(_ choice: SettingsChoice) -> some View {
        if choice.style == "source" {
            if choice.title == "Spotify" {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.24))
                    Circle().fill(Color(red: 0.12, green: 0.78, blue: 0.58)).padding(3)
                    Path { path in
                        for index in 0..<3 {
                            let y = CGFloat(9 + index * 4)
                            path.move(to: CGPoint(x: 7 + CGFloat(index), y: y))
                            path.addQuadCurve(to: CGPoint(x: 20 - CGFloat(index), y: y + 1.5), control: CGPoint(x: 14, y: y - 3))
                        }
                    }.stroke(Color(white: 0.2), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }.frame(width: 26, height: 26).accessibilityHidden(true)
            } else {
                Image(systemName: choice.symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(choice.title == "Music" ? Color.pink : Color.gray, in: RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
            }
        } else if choice.style == "airpods" {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.black)
                Image(systemName: choice.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(choice.value == selected ? 1 : 0.75))
            }.padding(.horizontal, 14).padding(.vertical, 10)
        } else if choice.style == "progress" {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Rectangle().fill(LinearGradient(colors: choice.title == "Monochrome" ? [.gray,.gray] : choice.title == "Colored" ? [.mint,.mint] : [.mint,.orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * 0.65)
                }
            }.clipShape(Capsule()).frame(height: 6).padding(.horizontal, 16)
        } else if choice.style == "glass" {
            RoundedRectangle(cornerRadius: 15).fill(.gray.opacity(choice.title == "Glass" ? 0.6 : 0.2)).overlay(RoundedRectangle(cornerRadius: 15).stroke(choice.title == "Glass" ? .white.opacity(0.3) : .black.opacity(0.6), lineWidth: 1)).padding(.horizontal, 13).padding(.vertical, 10).background(Color(white: 0.26), in: RoundedRectangle(cornerRadius: 11))
        } else if choice.style == "idle" && choice.title != "None" {
            HStack(spacing: -5) {
                if choice.title != "Calendar" { SettingsIcon(page: .nowPlaying, muted: choice.title != selected) }
                if choice.title != "Playing" {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 22, height: 22)
                        .background(LinearGradient(colors: [(choice.title == selected ? Color(red: 0.98, green: 0.22, blue: 0.40) : Color.gray).opacity(0.65),
                                                            choice.title == selected ? Color(red: 0.98, green: 0.22, blue: 0.40) : Color.gray],
                                                   startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 6.4))
                }
            }
        } else {
            Image(systemName: choice.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(choice.title == selected && active != .inactive ? Color.accentColor : Color.secondary)
        }
    }
}

/// Keep the system's configured scrollbar behavior, with the same transparent
/// track as the reference settings window rather than the default white backing.
struct SettingsScrollBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
            @MainActor func clear(_ root: NSView) {
                if let scroll = root as? NSScrollView {
                    scroll.drawsBackground = false; scroll.contentView.drawsBackground = false
                    if scroll.hasVerticalScroller && !(scroll.verticalScroller is SettingsScroller) {
                        let scroller = SettingsScroller()
                        scroller.controlSize = .regular
                        scroll.verticalScroller = scroller
                    }
                }
                for child in root.subviews { clear(child) }
            }
            if let root = view.window?.contentView { clear(root) }
            }
        }
    }
}

struct SettingsNativeMenu: View {
    @Binding var value: String
    let options: [String]
    final class Action: NSObject {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
        @objc func invoke() { body() }
    }
    var body: some View {
        Button {
            let menu = NSMenu()
            var actions: [Action] = []
            for option in options {
                let action = Action { value = option }; actions.append(action)
                let item = NSMenuItem(title: SettingsText.localized(option), action: #selector(Action.invoke), keyEquivalent: "")
                item.target = action; item.state = option == value ? .on : .off; menu.addItem(item)
            }
            _ = withExtendedLifetime(actions) { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
        } label: {
            HStack(spacing: 10) {
                Text(SettingsText.localized(value)).foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 17, height: 20).background(Color.primary.opacity(0.025), in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.09), lineWidth: 1))
            }
        }.buttonStyle(.plain).fixedSize().accessibilityLabel(SettingsText.localized("Display on")).accessibilityValue(SettingsText.localized(value))
    }
}

private final class SettingsScroller: NSScroller {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard knobProportion < 1 else { return }
        let part = rect(for: .knob)
        let knob = NSRect(x: 1, y: part.minY, width: max(0, bounds.width - 4), height: part.height)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.4) : NSColor(calibratedWhite: 0.5, alpha: 1)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 6, yRadius: 6).fill()
    }
}
