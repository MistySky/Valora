# V0036-R7 独立验收（2026-10-30）

## 通过的范围
- 独立运行NotchDiagnosticPolicyTests|LockMusicCoordinatorTests：29通过（6policy/坐标+23fake coordinator）。无真实窗口/Space/锁通知/声音/媒体或权限操作，无UI循环/压力/全量。
- source-manifest中9份生产/测试文件hash均与当前匹配。
- 代码确有isFlipped选择host局部顶部，并使用NSView/NSWindow转换；默认关闭实际NotchShape overlay GeometryReader；native windowSpaceIDs调用只读成员查询，查询失败unknown；锁阶段保留96/总120限额。
- 生产锁屏呈现仍沿旧add/remove；没有伪称位置根因已修复。外部源码差异及其未证实边界已记录。

## 局限
- shape probe只记录SwiftUI global逻辑rect，不是最终合成像素，不能排除WindowServer-only变换；没有display/window标识，不适合同时多屏定位，单屏可结合window记录参考。
- probe在onAppear/rect change记录，阶段变但rect不变时不单独记录；不得把无记录当作阶段未呈现。policy连续key去重不是按事件类别长期去重，仍有硬限额；诊断应仅有界单次使用。
- logicalScreenPoint helper未在生产使用，其fake不能当NSView真实转换测试；独立源码已确认真实调用使用host.convert/window.convertPoint。
- 临时R7候选现已不存在，无法本轮重验签名。现存Release binary SHA4e9f821f...与历史R7 d2844a...不同，不能冒充该候选；此前签名成功仅是历史记录，不套当前包。本轮未重新Release打包/启动/替换用户软件。

## 判定
诊断源码与fake回归子集接受；原锁屏下浮仍未修复/未通过视觉验收。下一步用户协助取证前需按当前源码重新构建独立临时诊断候选、核验来源和签名，协调只保留一个应用，用户自行锁解一次；不自动操作或继续猜位置。本轮未新增派工/自动化。
