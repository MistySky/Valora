# V0037-R1 基础监控剩余容量内容纠正

日期：2026-10-30
状态：内容纠正完成，等待 Codex 独立验收；**候选未启动，当前运行版未替换**。
候选：`/private/tmp/valora-v0037-r1-summary-candidate/Valora.app`
候选二进制 SHA-256：`98baaebf2bccc02e418a09d84daf3bbd8ab7542da8c17b2325ad025a8f8e4630`

## 1. 本次修改

`Sources/Valora/CalendarMonitorSharedView.swift` 的 `MonitorSummaryCard` 从单行 chip/OS/总量/uptime 改为用户最新要求的单行信息：

```text
内存 <memory.total> <memory.unusedCapacity>   磁盘 <disk.total> <disk.available>   已运行 <uptime>
```

单行使用 11pt Calmon caption、等宽容量文本、单行缩放；不使用芯片/OS、多行或旧复杂监控。

- 完整移除芯片和 macOS 版本展示。
- 内存保留总量，并显示 `Snapshot.memory.unusedCapacity`（既有无 free 口径）。
- 磁盘保留总量，并显示 `Snapshot.disk.available`；不合并 APFS 卷、不硬编码示例容量。
- uptime 继续使用 `Snapshot.uptime`。
- 内存/磁盘标签与总量/剩余在同一行显示；使用现有单位格式和单行缩放，避免 400pt 内挤成过小字体。
- 缺失值显示 `--`；真实 0 仍按 `0` 有效显示，不伪造成 `--` 或示例值。
- 保留单层共享 popover、400pt 日历/368pt 网格、两入口路由、开关生命周期和 Calmon 材质；没有恢复进程采集/搜索/圆环。

## 2. 简化后台保持

- V0037 的生产 `SystemMonitor()` 仍不注入应用 reader；仅历史 audit 可使用 fake reader。
- `MonitoringView.swift` 旧圆环/应用列表/搜索生产视图继续删除，不恢复。
- 本轮未改音乐、锁屏、设备、日历核心或菜单栏图标。

## 3. 验证

命令：

```text
swift test --filter 'CalendarMonitorSharedTests'
```

结果：**4 项通过，0 失败**：

- `CalendarMonitorSharedTests` 4：两开关四组合、共享路由 close/switch/open、缺失值 `--`、生产 monitor 无应用 reader。
- 本轮只跑相关共享面板/格式 4 项，未重跑无关 SystemMonitor 全组；生产无应用 reader 的 V0037 实现未变。

未运行全量、真实 `NSStatusItem`/`NSPanel`/`NSPopover`、真实日程权限、截图/点击/循环/性能测试。

日志/清单：

- `docs/verification/v0037-r1/targeted-tests.log`
- `docs/verification/v0037-r1/source-manifest.json`
- `docs/verification/v0037-r1/test-inventory.json`
- `docs/verification/v0037-r1/build-verification.json`
- `docs/verification/v0037-r1/resource-check.json`
- `docs/verification/v0037-r1/codesign-display.txt`

## 4. 构建与待验

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0037-r1-summary-candidate` Release；arm64、macOS 27、ad-hoc hardened runtime。
- `codesign --verify --deep --strict` 通过。
- 候选未启动；用户当前 V0037 运行版和 `dist` 未替换。
- 真实菜单栏共享面板的 400pt 单行间距、明暗主题、开关即时更新仍待用户实机视觉验收。
