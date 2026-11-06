# V0015-R4 独立验收：自动验证范围接受

## 结论

前轮三项缺陷已按最小权限接线修复，未发现本轮阻断问题。手形仍为非交互Image，开关唯一入口，保留Alcove设置布局和设备固定策略。本轮设备/权限开发自动范围接受，不将此等同真实OS授权或真实耳机实测通过。

## 独立证据

- 完整swift test：205项通过（Valora91+ReferenceCore114），原始/private/tmp/valora-independent-v0015-r4-test.log。
- 保留前三项独立回归，另补旧denied snapshot异步返回等待、取消不撤销既有requiresApproval注册两项；定向共5项通过，原始/private/tmp/valora-independent-v0015-r4-extra.log。因此本轮覆盖207个不同测试，不声称新增后重跑了完整207项。
- 独立构建/private/tmp/valora-independent-v0015-r4/Valora.app，codesign --verify --deep --strict通过。
- Codex独立隔离视图：设置生成/窗口几何通过；设备31、歌词31、音乐74、注入多屏12全部通过。JSON与截图见本目录对应子目录。
- 已目视检查Connectivity-permission和pending截图，手形位置/行高/布局保持，未新增权限页面；截图是自有SwiftUI视图的隔离渲染，不是系统权限窗口。

## 修复核对

- loginIntentGeneration隔离取消前旧注册回调；原失败回归通过。
- audioAttemptInFlight避免生产refresh刚发起异步确认时按旧denied清pending；实际回调成功一次完成，取消拒绝迟到，重复激活不并发请求。新增独立测试保留旧denied直至回调，也通过。
- 本次创建注册以loginRegistrationOwned标记，取消接loginUnregister，生产使用现有LoginItem.set(false)。初始已有requiresApproval取消不撤销，独立保护测试通过。注册/撤销生产动作是同步SMAppService调用，QA使用spy，未触发真实系统写。

## 如实待实机

真实蓝牙授权弹窗及IOBluetooth行为、系统音频授权/系统设置返回、登录项批准/撤销；真实AirPods连接/低电量/提示音/3D视频图层；物理双屏与实际QQ人声同步。fake和cacheDisplay不证明这些效果。保留既有待验记录，不重复宣称全部体验通过。

未连接设备、未实际播放/切歌/seek/音量、未修改真实权限/登录项、未安装发布、未Git提交推送，未恢复定时器。菜单栏监控/Codex/日历仍是讨论阶段，本轮未自动派工。

候选binary SHA256：1cfeee92afd92c3f42bee98e5be02df3a81a50040e2cdfe6943ea9f7aea23d2c
