import Foundation

// Translate presentation only. Preference keys and stored selection values stay
// unchanged so existing English selections continue to work after this update.
enum SettingsText {
    static func localized(_ value: String) -> String { chinese[value] ?? value }
    static let chinese: [String: String] = [
        "General": "通用", "Notifications": "通知", "Live Activities": "实时活动",
        "Battery": "电池", "Connectivity": "设备连接", "Focus": "专注模式",
        "Display": "显示", "Sound": "声音", "Now Playing": "正在播放",
        "Calendar": "日历", "Lock Screen": "锁定屏幕",
        "License": "许可证", "About": "关于", "Version": "版本", "Soon": "即将推出",
        "Launch at login": "登录时启动", "Hide in fullscreen": "全屏时隐藏",
        "Hide in mission control": "调度中心打开时隐藏", "Hide while gaming": "游戏时隐藏",
        "Hide from screen capture": "在屏幕录制中隐藏", "Force simulated notch": "强制模拟刘海",
        "Display on": "显示于", "Main display": "主显示器", "All displays": "全部显示器", "Built-in display": "内建显示器", "Automatic": "自动",
        "Idle Activity": "默认活动", "Most Recent": "最近使用的活动",
        "None": "无", "Playing": "播放", "Duo": "双栏",
        "Behaviour": "行为", "Contrast outline": "对比描边", "Progressive blur": "渐进模糊",
        "Expand on hover": "悬停时展开", "Hover delay": "悬停延迟",
        "Tuning": "微调", "Notch width": "刘海宽度", "Notch height": "刘海高度",
        "Duration": "显示时长", "Notify on low power mode": "低电量模式变更时通知",
        "Warn on low battery": "低电量提醒", "Low battery threshold": "低电量阈值",
        "Play sound on low battery": "低电量时播放提示音", "Hide label": "隐藏标签",
        "Hide percentage": "隐藏百分比", "3D models": "三维模型", "Symbols": "符号",
        "Play sound on sleep focus": "睡眠专注时播放提示音", "Focus status unavailable": "专注状态暂不可用",
        "Replace waveform during focus": "专注时替换波形", "Allowed Notifications": "允许的通知",
        "Idle duration": "空闲时长",
        "Monochrome": "单色", "Colored": "彩色", "Gradient": "渐变",
        "Use live waveform": "使用实时波形", "Show lyrics": "显示歌词", "Disable compact waveform": "停用紧凑波形",
        "Disable artwork flip": "停用封面翻转", "Hide while source app is active": "来源应用在前台时隐藏",
        "Hide media title extras": "隐藏标题附加信息",
        "Automatic  ∙ System": "自动 · 系统", "Music app": "音乐应用", "System": "系统",
        "Music": "苹果音乐", "Extension": "扩展", "Quick Peek": "快速预览",
        "When media changes": "媒体变化时显示", "Peek duration": "预览时长",
        "Keep awake": "保持唤醒", "Show on screen saver": "屏幕保护时显示",
        "Play sound on lock": "锁定时播放提示音", "Play sound on unlock": "解锁时播放提示音",
        "Widgets": "小组件", "Appear on your Lock Screen": "显示在锁定屏幕上", "Glass": "玻璃", "Clear": "透明",
        "Show volume control": "显示音量控制", "Offset tuning": "位置偏移", "Weather": "天气",
        "Show percentage": "显示百分比", "Show symbol": "显示图标", "Show device": "显示设备",
        "White": "白色", "Accent": "强调色", "Decibel": "分贝", "Glow": "发光",
        "Smooth": "平滑", "Fast": "快速", "Instant": "即时",
        "Check Updates...": "检查更新…", "Automatically check for updates": "自动检查更新",
        "Early bird updates": "接收预览版更新", "Development": "开发版",
        "Share feedback regarding bugs, suggested features, or provide other valuable input.": "欢迎反馈使用中遇到的问题，提出功能建议或分享其他意见。",
        "Local build · UI reconstruction": "本地构建 · 界面复刻",
        "Send Feedback...": "发送反馈…", "Join Discord...": "加入 Discord 社区…",
        "Expand the current activity when the pointer rests on the notch.": "将指针停留在刘海上时，展开当前活动。",
        "Cycle between available live activities.": "在可用的实时活动之间循环切换。",
        "Dismiss the current activity.": "关闭当前活动。",
        "s": "秒", "m": "分", "px": "像素", "%": "%"
    ]
}
