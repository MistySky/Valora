# V0039-R1 独立验收：代码/隔离回归接受，可交用户单次实机

2026-11-01。37项Swift定向全部通过：25真实锁fake、9模拟fake、3采样策略；原重复建窗、完整overlay日志预算两个失败回归均通过。未全量/真实窗口/Space/锁通知/声音或UI循环压力。

独立补原生测试而非只依赖Swift FakeSpace：Tests/NativeBridgeTests/IsolatedOverlaySpaceTests.m直接包含生产native文件，用VALORA_LOCK_SPACE_TESTING专用初始化注入fake函数表，生产不编译此入口。6场景通过：成功仅目标Space并detach确实调用remove；返回success但未移动被拒绝且desktop仍在；部分移动error回滚；未知原归属不迁移；迁移后query未知回滚；缺符号不调用。它不证明真实macOS私有API行为，真实fallback和隔离仍待用户。

源码确认：失败attempt/frame门控阻止媒体刷新重复创建，换screen/wake/lock/stop边界重置；native成功登记_windows使detach不再no-op，失败还原原成员；独立notch hosting零safeArea/sizingOptions[]；每真实阶段及reposition记录overlay边界/Quartz/role，释放前真实visible；每phase各lane减少后120总上限可保留解锁和最终交棒。保留原地open→neutral实际completion→withAnimation恢复最新音乐、已正常preview。

候选/private/tmp/valora-v0039-r1-isolated-lock-candidate/Valora.app binary01d69669b7b97f1398c50a185d79079a45830c450dd4a1c6b3802ef91dd21984与报告一致，codesign strict/deep独立通过。Info.plist诊断LSEnvironment指向/private/tmp/valora-v0039-r1-lock-handoff.jsonl。生产清单全部匹配；NativeBridge仅Codex新增fake-only条件初始化器，去除该条件块SHA与交付清单完全一致，生产编译不受影响。

额外独立Release重编译两次均在启动前因自动审批服务超时而未运行（不是编译失败/不是unsafe结论）；不继续重试。现有候选由pi构建、Codex核验签名/哈希与生产源码，不冒称完成本轮独立Release构建。源码和原生fake测试已实际编译运行。

总体代码/隔离验证接受，可供下一次用户手动真实锁屏。实际系统下浮是否消失、窗口迁移是否触发fallback、open→neutral→音乐是否流畅、物理双屏/底部Glass仍未实机，不能称完整体验验收通过。本轮未启动/退出/替换当前capture-v2或任何用户软件，dist/权限偏好/归档不动，无Git/自动化/新派工。
