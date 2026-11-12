# V0112 点击阻挡独立验收（2026-11-12）

## 结论

本地 build63 接受。用户实测确认：鼠标进入刘海后移开，设置顶部通用/音乐与原来点不了的其他软件区域都恢复正常。当前只替换运行候选；未覆盖 Applications，未提交、推送或更新 GitHub Release。公开 v1.0.4 仍是 build62。

## 故障与历史核对

- build62 的设置窗口顶部落在高层级刘海 624×320 透明 canvas 下；实鼠坐标点击日历成功，顶部通用失败；AXPress 可以切页。用户确认退出 Valora 后其他软件点击恢复。
- 11月9日 3b4dc91 为鼠标CPU优化移除常驻 global/local mouseMoved 监听，改为小 sensor + tracking area。输入所有权交接后，退出漏报可能留下 pointerInside=true 与 canvas.ignoresMouseEvents=false。
- 发布提交 2cbb604 未改 WindowCoordinator.swift 或 SettingsWindow.swift，并非提交时回退/删除了本文件的新修复。安装程序 SHA256 与发布记录一致：8e12114a0d831f32303ca6fb624fb8c17f9a596911b50011a158026f5fadaa36。

## 变更与边界

生产仅 WindowCoordinator.swift：有悬停所有权时安装 local/global move fallback，复用120Hz合并调度；离开后恢复穿透并移除监听；隐藏/锁屏清理输入所有权。local monitor 返回原事件。保留窗口属性写入去重，不新增常驻 Timer。动画、歌词 renderer、Models 外轮廓、设置导航代码无本轮改动。

## 验证

- Pi 定向指针/交互/多屏测试通过，详见其报告；独立新增实际外接屏几何下“canvas内、轮廓外”的输入释放和重复进入检查，与既有属性去重用例合计2项通过。日志：/private/tmp/valora-v0112-independent-tests.log。
- Release 显式 VALORA_LYRICS_EXPERIMENT=1，正式打包一次为1.0.4 build63。构建日志：/private/tmp/valora-v0112-build.log。
- codesign --verify --strict --deep 通过，与已安装版本 designated requirement 相同。
- 确认0实例后启动唯一候选，核验PID10861与候选路径匹配。
- CUA打开候选设置成功，但随后坐标操作被工具报“用户改变应用状态”中断，不将这几次自动点击冒称通过。最终真实鼠标进入/离开与设置/其他软件区域的结果由用户明确回复“都恢复正常”。

候选：/private/tmp/valora-v0112-click-through-candidate-20261112/Valora.app

binary SHA256：a418c5067ac60f13d461e511f631914da37b4e7e02fa0e720679d395759a1c89

未覆盖锁屏、全屏/Mission Control全部组合；未做鼠标CPU长期复测，不据此声称所有输入边缘场景已消失。
