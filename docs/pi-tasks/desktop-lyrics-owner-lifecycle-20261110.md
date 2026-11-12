# build56收尾：消除view-update发布状态及失效owner重开资源

音符真实连续性已改善：Codex独立23项通过，note before200，采样[200,185,129,48,39]，参考[200,182,124,62,39]，无反向；签名/hash/唯一build56进程14580已核验。但验收日志存在不能忽略的生命周期异常，内存任务仍等待。

## 实际日志与代码

日志 `/private/tmp/valora-build56-independent-20261110.log`：多个desktop keyed用例出现
`LyricsRowExperiment.swift:138 Publishing changes from within view updates is not allowed, this will cause undefined behavior.`
同时出现非失败注入的 `shared image capture failed`，比如Note连续性/SharedPreparation用例退出阶段。部分可能来自测试主动invalidate/切换root时的迟到更新，但必须保证退出不再触发截图或fallback，不能因为断言通过就当无问题。不要把这些日志统称“预期失败注入”。

NativeLyricsRowHost.wire在make/updateNSView期间调用host.begin(identity:)，其中failed/displayedLine/contentWidth/presentationID等@Published改变，构成非法同步SwiftUI状态发布。host.invalidate又把textPreparer.isAvailable=false；同identity begin直接guard返回，而迟到bridge仍可能prepare，导致关闭后反复失败/重建。

## Codex指定边界

1. 新owner初始identity/generation通过构造/未被SwiftUI观察的初始准备赋值；**NSViewRepresentable make/update/wire期间不得同步写@Published状态**。wire只绑定当前有效token/callback。
2. 身份/呈现重置放在安全的外层onAppear/onChange处理，或一个有generation保护、合并的主队列提交；若为避免首次回调被丢需要先登记identity，用非published“预留输入token”阶段，并确保发布reset先于该token的异步line callback，不得增加固定16ms延迟或破坏现有keyed动画。
3. 显式owner呈现lease/phase：invalidate后不允许迟到bridge apply/prepare重新打开截图窗口，不把“owner已退出”当图像渲染失败触发fallback；旧generation回调无效。重新显示同identity须通过合法begin/appearance重新激活、更新token，并立即对齐当前行/时钟，不能只因identity相同就永久不可用、等用户点击。
4. retired旧child不能因wire/stop后的迟到update重新成为active；共享preparer由有效owner控制开关/关闭，旧child拆卸不能关闭新child在用的preparer。保持一份旧句视觉、一个live clock、三句不同文本一份capture宿主。
5. 不通过关日志、放宽测试、切回Compact fallback、降低帧率隐藏问题。保留build56新的原版布局/音符连续性、独立锁屏legacy策略/开关/44pt位置。

## 验证与交付

补必要无窗口/有限隔离视图回归：make/update路径零非法发布警告；owner退出后迟到update不prepare、不fallback、不重新开window；同identity隐藏重显恢复，无点击；内容替换/seek/快速handoff仍正确。给测试增加显式host.failed=false/native存在等断言，防止走fallback后像素恰好等于原版而冒称native通过。清理测试必须先移除/停有效视图再invalidate，生产路径仍有自己的失效门控，不能只改测试顺序掩盖。

运行前述独立23项和自然tick用例，报告哪些image failure属于真实失败注入，其他应消除。必要检查后一次Release候选按AGENTS正常替换、唯一实例、签名hash、默认无诊断，保留build56。更新原report独立章节，不能声称用户真实体感已验。完成后停等Codex；尚未派封面内存任务。
