# V0035-R2：AirPods 3 实际重连仍无提示，定位整条链路并限定修复

用户最新明确授权交给当前 pi；这是修复任务，不只写报告。保留本目录与绑定会话，不新建 pi，不改模型/历史。先读 AGENTS.md 最新覆盖、CONTINUATION-PLAN 和下列独立证据。

## 最新真实结果（覆盖此前通过推测）

- 用户已在 reconnect-candidate 启动后尝试授权、断开重连，反馈 Valora 仍不出现耳机提示；同条件原版 Alcove 能出现。不要再次解释为“只是启动时已有连接”。当前权限是否确实在新签名候选就绪，应以完整链路证据核实，不能把用户反馈自动等同已采到权限状态。
- 用户纠正：原版 Alcove 提示时，macOS 自带弹窗也会出现。系统弹窗同时出现是正常现象，本轮不抑制、不接管、不研究拦截系统通知。
- 当前用户运行 `/private/tmp/valora-v0035-reconnect-candidate/Valora.app`；不要退出、替换、覆盖此包或 dist，不另开生产实例。Codex 会在你正式交付并独立验收后协调一次新候选实测。
- AirPods3 已有真实 left67/right77/single0→display67 的证据；电量聚合不要回退。该样本不是本次重连事件日志。

## 必须先理解已做修复，不能丢成果

- `docs/verification/independent-v0035-live/decision.md`：真实 Bluetooth coordinatorQueue 调用 @MainActor selector 造成两次 SIGTRAP。Codex 已改 `ConnectivitySystemEvents.bluetoothConnected` 为 nonisolated，复制 String/registration identity，Task MainActor 验证旧注册；保留后台原生入口回归，不能改回 actor-isolated selector 或关闭并发检查。
- `docs/verification/independent-v0035-reconnect/decision.md` 和 before/after.log：两项独立 fake 在修复前失败（连接早于首次baseline被吞；型号晚到时known提前消费fresh）。Codex 已按稳定 ID 保存明确连接意图10秒，识别后仅消费一次，off/stop清空、过期丢弃，21定向通过。但用户实际仍失败，不能把这两处当唯一根因或再声称已完成。
- 生产修改在 ConnectivityController/ConnectivitySystemEvents/ConnectivitySource，测试 IndependentDeviceMediaReviewTests。当前工作区有 Codex 未提交改动，按现状增量修复，禁止 reset/覆盖。
- 三方审计 `docs/research/v0035-original-revival-valora.md` 顶部更新；来源 `/Users/wangqing/code/alcove-revival-archive` 只读，原版与复刻证据分清。

## 本轮定位与实现

沿真实路径逐段核查，找可验证的断点，禁止继续凭推测堆补丁：
1. 新签名候选授权后 settings 总开关/authorizationGate/启动订阅是否真正就绪，是否仍无意停在off或不注册。
2. IOBluetooth 注册成功/失败及回调线程、selector签名、registration identity校验是否误拒真实回调；SDK header明确第一个参数是notification对象，核真实接口契约，不盲去掉迟到保护。
3. 断开/重连的系统事件是否被漏订阅；现有仅connect/CoreAudio监听是否能保证目标耳机时序。对照原版/复刻能找到的真实证据，不把3秒poll说成原版已证明实现，不靠提高轮询频率补洞。
4. one-in-flight、revision、pendingRefresh、取消、原生源返回是否一直等待或丢掉最终有效设备；型号/电量晚到、默认输出变化都需区分；仅切换输出不能冒充新连接。
5. controller 设置 connectionToast 后，WindowCoordinator 活动屏/visibility、展开态、歌词/音乐优先级、UI门控是否把真实toast吞掉。模型有值不等于界面可见；不能为修耳机破坏用户现有多屏/展开交互。

若缺真实事件证据，允许准备**默认禁用、明确临时验收开关**的有界匿名诊断，记录上述阶段计数/成功失败/时间，不记录MAC、设备名、其他配对清单/个人媒体内容；最多一个短会话/有硬上限，结束停止，不反复写盘/无限日志/新增常驻定时器。不用外部unsigned helper绕TCC、不注入运行进程、不扫描设备。诊断由Codex协调用户新候选后再采，本轮先交可审查候选与确实成立的修复；没有采到实际回调就明确待实机，不能编造native日志。

## 验证和边界

只跑修改模块/相邻接口/原失败的定向无界面测试，不每轮全量、不运行任何 --verify-*、弹窗/菜单开关循环、批量截图、性能/内存压力测试。补能证明新根因的回归（修前失败、修后通过），保留既有真实0/未知电量、首次已有设备不弹、明确新连接可越过baseline、晚型号、过期事件、stop/off、旧回调、single占位等语义。必要一次 release构建签名，候选放 `/private/tmp/valora-v0035-r2-real-reconnect-candidate`。

不控制真实播放/切歌/seek/音量、连接断开配对或系统输出；不写权限/TCC/登录项/系统设置；授权和耳机操作由用户完成。无真实用户日历/账号读取，不恢复下载/Codex/定时器，不进入锁屏；保持Alcove外观、Calmon日历监控、已接受歌词和品牌。归档只读、不Git提交推送、不安装发布。

## 交付

报告 `docs/reports/v0035-r2-real-reconnect-toast.md`，说明用户失败事实、真实已知/未知、可复现断点和修复前后证据、涉及文件/测试选择、候选及签名、若需诊断如何一次短操作取得结果。不只凭fake通过宣布实际重连修好。完成后停等Codex独立验收，不自动下一批。
