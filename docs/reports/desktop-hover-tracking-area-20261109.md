# 桌面悬停：Alcove 式 tracking area 原型

2026-11-09。用户要求在不动当前功能与体验的前提下，先落地一版基于 Alcove 的鼠标悬停实现。分支 `codex/alcove-tracking-area`，从 `codex/idle-cpu-optimization` 的 `580f86f` 拉出；未合并 main。

## 改动

1. 移除全屏 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` 与 local mouse monitor。
2. `EdgeHostingView` 安装 `NSTrackingArea`，只监听 `mouseEntered/mouseExited`；跟踪矩形使用当前可见 Notch 尺寸，而不是 624×320 透明画布。
3. `NotchPanel` 的 frame 从固定 624×320 改为跟随当前可见 Notch 尺寸（外加 8pt 水平/4pt 垂直小余量），保持顶部锚定；隐藏/锁屏仍 orderOut。
4. 面板可见时保持接受鼠标事件，以便 tracking area 能检测再次进入；普通桌面移动不再进入 Valora。
5. 进入/离开时调用现有 `trackMouse`，hover delay、展开/收起、拖动、媒体、锁屏逻辑不变。
6. 保留已有 CGPath 命中缓存和 120Hz 合并代码；这次原型不再依赖它们做全屏鼠标回调。

## 验证

定向无窗口/状态测试：

`IndependentPointerWindowStateTests|IndependentPointerDedupAcceptanceTests|NotchHitTestPrefilterTests|IndependentNotchPrefilterTests|MultiDisplayCoordinatorTests|IndependentInteractionTests`

结果：**32 项通过，0 失败**。旧的窗口状态翻转用例已按新 tracking-area 语义收缩为可见面板保持接受、锁屏/隐藏仍忽略、路径缓存与粗筛检查。

## 候选

- `/private/tmp/valora-hover-tracking-area-20261109/Valora.app`
- `1.0.3 (40)`
- binary SHA-256：`515d20b126c84b86cc7a4ade60003bd804423af5a43e1134d042fe874241c442`
- strict/deep 签名通过
- build39 已正常退出，当前唯一实例 PID `14715`
- build39 保留在 `/private/tmp/valora-user-test-39/Valora.app`

## 未验 / 风险

- 面板尺寸从固定 624×320 收缩到可见尺寸后，SwiftUI 展开/收起、悬停 scale、歌词宽度、多屏被动面板的实际视觉是否完全不变，必须由用户实测；单测不能证明 AppKit/SwiftUI 布局没有裁切或位移。
- 面板可见时接受整块小窗口事件；窗口外 16×8pt 余量可能挡住极小的桌面点击，需实测确认。
- 顶部菜单栏点击、右键、拖动、全屏 Space、锁屏过渡未由自动测试覆盖。
- 若悬停或视觉有回归，应回退 build39；不要继续在未验证的窗口尺寸上叠加改动。

## R1：恢复 624×320 动画画布

用户实测 build40 后确认：CPU 不再升高，但刘海动画被改动。定位为 build40 把 `NotchPanel` 从 624×320 动画画布收缩为可见尺寸，导致 SwiftUI 布局/动画几何改变。

build41 回退这一部分：

- `NotchPanel` 恢复固定 624×320 顶部锚定画布，动画/布局回到 build39 的坐标体系；
- 不再让整块 624×320 画布接收鼠标；面板默认点透；
- 新增一个**与当前可见 Notch 等尺寸**的小透明 sensor，位于面板下方，只负责进入/离开事件；
- 指针进入 sensor 后，现有 `trackMouse` 才把面板切为接收事件；离开轮廓恢复点透；
- 普通桌面移动不进入 Valora；没有额外扩大交互区域。

定向测试 **32 项通过，0 失败**。

build41 候选：

- `/private/tmp/valora-hover-tracking-area-r1-20261109/Valora.app`
- `1.0.3 (41)`
- binary SHA-256：`0bb1f3d121a22b10c1b9065af46f14e7b65c0699b9b66abb0ee1efc5f8e8ea6c`
- strict/deep 签名通过
- build40 已正常退出，当前唯一 build41 实例 PID `16311`
- build40 保留在 `/private/tmp/valora-hover-tracking-area-20261109/Valora.app`

仍待用户确认：624×320 动画是否完全恢复；小 sensor 是否挡住可见 Notch 范围之外的点击；悬停进入/离开是否与 build39 一致。
