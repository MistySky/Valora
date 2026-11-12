# V0112：1.0.4 设置顶部点击失效 / 刘海悬停不退出（紧急最小修复）

用户新装1.0.4 build62，设置上方页签一直点不动，刘海像一直悬停。仅本任务，不继续内存优化。保持原 Pi 会话与模型。

## Codex 已复现的真实证据
- 唯一运行 /Applications/Valora.app build62 PID3819。
- 两屏：内置(0,0,1728,1117)，外接(1728,37,1920,1080)，目标外接U2701B。
- CGWindowList 顶层：刘海303 frame（CG左上坐标）x2376,y0,w624,h320，层2147483629；sensor304 x2618,y0,w140,h30；设置314 x2378,y122,w620,h687，层0。
- CUA app screenshot1240x1374（2x）：直接坐标点击[120,620]的日历成功从音乐切换；点击[120,145]的通用不切换。AXPress切音乐可成功，说明设置导航本身还活着。顶部点击失效与覆盖其上的透明刘海624x320绘制窗口重合。
- 用户截图刘海持续悬停，鼠标已远离。
- NSHostingView.isFlipped 实测true，不要误改tracking y方向。

## 修复边界与建议
审查WindowCoordinator的sensor/EdgeHostingView trackingArea输入所有权与pointerInside：sensor进入后打开上层大canvas输入，不能依赖被遮挡sensor的退出事件；任何悬停退出/隐藏/锁屏/重排/交互结束必须恢复click-through且清理pointerInside。检查trackingSize是否及时覆盖真实出口；不得让一旦hover后624x320透明区域持续挡住其他窗口。
建议最小的有生命周期边界的兜底（例如仅在刘海确实拥有指针时监听局部/全局mouseMoved，退出即移除，复用已有coalescing，回调local必须返回原event），但你需证明根因并优先更小正确修复。不要恢复全桌面鼠标移动的常驻昂贵处理，不新增常驻Timer。也核查圆角内外精确命中和sensor之间的交接，不能靠关闭hover/禁用刘海点击解决。

不得改任何动画、曲线、时长、缩放、透明度、歌词渲染、外轮廓、既有主动展开收起语义。设置页面导航代码目前无证据有错，不盲改；不动锁屏布局、音量、媒体控制、真实用户偏好。

定向回归至少：进入->离开恢复click-through、离开后顶部设置/普通窗口不被阻挡、重复进入可正常交互、隐藏/锁屏清理、局部event不吞。代码级fake与真实鼠标验收分开记录。保留CPU去重路径，证明远离刘海移动鼠标时不常驻昂贵回调。

先完成最小源码及定向测试，写docs/reports/v0112-settings-click-through-regression.md（根因、变更、数量、未验项），不要构建交付包、不要替换/quit用户实例、不要Git提交推送发布，不改版本。Codex独立验收后正式构建替换一次。
