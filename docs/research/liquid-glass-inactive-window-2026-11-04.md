# 为什么非活动窗口的 Liquid Glass 会变灰（2026-11-04 检索）

## 1. Apple 开发者论坛（2026-03）
标题：*Can two NSPanel windows both display active/focused appearance simultaneously on macOS 26?*

提问者描述与本项目完全一致：两个 NSPanel 同时显示新材质，**只有 key window 是 active 的 Liquid Glass，非 key 面板永远是 inactive/foggy**；即使使用
`NSWindowStyleMaskNonactivatingPanel`、`canBecomeKeyWindow = false`、`orderFrontRegardless()`、`addChildWindow(_:ordered:)` 也一样。
Apple DTS 只回复"能否提供一个最小工程"，**没有给出解决方式**（1 条回复）。

结论：非 key 窗口拿不到 active 玻璃，目前是系统合成层的行为，不是我们的写法问题。

## 2. Apple 文档：NSVisualEffectView.State.active
> "The backdrop should always appear active."

即：**NSVisualEffectView（经典 vibrancy）可以用公开 API 强制保持 active 外观**，与窗口是否 key 无关。
`state = .followsWindowActiveState` 才是默认的"跟随窗口激活状态"。

## 3. 第三方资料
`onmyway133/blog` #1025（2026-04）："Setting `state` to `.active` keeps the effect live even when the window loses focus."（同样是 NSVisualEffectView）。
`macos-liquid-glass` crate 文档：`NSGlassEffectView` **没有** opacity/state 控制，只有 style / cornerRadius / tintColor / effectIsInteractive；材料会跟随窗口 active 状态。

## 4. 与 Alcove 反编译的对应
`reverse-engineering/lock-appearance-0.6.5/100131c1c.c` 的工厂里：
- 走 `NSVisualEffectView` 时，**显式 `setState_(uVar13)`，且 slot5==1 时强制为 1（.active）**；
- 走 `NSGlassEffectView` 时只设置私有 `variant` 和 `cornerRadius`，**没有**任何 active 强制。

也就是说：Alcove 锁屏上稳定呈现的，是**强制 active 的 NSVisualEffectView 材质**，不是 require-key 的 Liquid Glass。
这解释了为什么它的锁屏卡（实拍）是"透出壁纸的模糊玻璃"，而不是带折射的 Liquid Glass。

## 5. 对 Valora 的结论
- 想在锁屏稳定拿到"玻璃感"：只能用 `NSVisualEffectView` + `state = .active`（公开 API，Alcove 同款）；
- 想要带折射的 Liquid Glass：只能在 key window 上，锁屏被登录界面接管后必然降级（实测两张照片相隔 5 秒）。
