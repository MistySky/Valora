# V0038-R1 原地开锁→收起→音乐展开

用户实测V0038模拟加锁“没问题”，最新明确解锁：基于当前加锁图标做开锁图标动画，然后收起，再展开正在播放。保留已被用户认可的加锁动作，不重做形状/位置，不转向真实锁屏Space修改。

限定核对并修复模拟关闭：locked→unlocking必须同一左翼glyph/同一视图身份/相同展开宽度原地开锁，不能先隐藏锁、收起后再出现open图标，不另画符号飞入；开锁动画完成后才进入restoring收回基础刘海；收起实际完成后才按普通music activity动画展开最新音乐，无音乐停基础刘海。不要以同宽locked/playing直接内容替换跳过收起，也不要瞬间跳到恢复后的宽度。

源码已见LockPreviewController恢复completion直接active=false、indicator=hidden、presentationActive=false，无withAnimation；相比真实LockMusicCoordinator恢复音乐有withAnimation，需修这个确定的恢复展开缺口。glyph仍已有lock.top/bottom旋转（若系统无符号则fallback），核对保持实例、过渡身份和开锁先后顺序，不能无证据声称fallback是原版1:1。0.8现有停留可保留但不能把计时等同实际动画通过；几何收起必须真实completion再恢复音乐。

只改当前模拟预览必要实现与对应测试，保留真实session优先/快速反转generation/总开关off/stop取消、不Space/声音/新窗口/真实媒体控制；音乐正常路径、日历监控及原设置不动。定向fake覆盖unlock阶段宽度不变、neutral确实出现、收起completion前音乐不恢复、完成后最新music恢复/无音乐neutral、旧完成不能反转。不能写只断言枚举值却不检查实际geometry的测试；无需UI循环、真实锁屏、全量或压力测试。

候选/private/tmp/valora-v0038-r1-unlock-candidate，一次必要构建签名；禁止覆盖/退出/重启当前已运行V0038（f6d039...）或dist，不改偏好权限归档、不Git、定时器关。报告docs/reports/v0038-r1-unlock-in-place-then-music.md交付停止待验收，不自动换版或新任务。
