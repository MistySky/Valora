# V0099 无效后台工作限定收尾

现有会话继续。V0098/R2独立接受17焦点测试、build6签名hash单实例；不再修改已接受焦点生命周期。用户授权全部当前问题分批修完→完整功能全局回归→修完回归缺陷后CPU/内存/后台唤醒及动画流畅度专项；本批只是功能修复，不跑压力/性能。

## A 音乐关闭停止0.25s调度
MediaController.start无条件创建Timer；nowPlayingEnabled sink只invalidate媒体源+clear+refresh，关后Timer仍4Hz空转。
- 把调度与controller活跃状态、nowPlayingEnabled一致：初始关闭不创建；开启恢复单一调度并立即接源；关闭立即取消调度/停止源/清理按原行为，不残留timer。反复开关/start不能叠timer；stop后开关变化不能重新启动。
- 保留开启时0.25s真实播放锚与每秒重连节奏，不改暂停/seek/歌词/锁屏需求或调度频率，不为省资源恢复猜时间。拒绝旧callback沿现有epoch/generation保护。
- 用小型调度注入/spy验证启动关、开、关、再开、stop后偏好变化、重复start无叠加；不要依赖真实播放器或墙钟长等待，不开启真实媒体probe。

## B 移除无效游戏检测专用链路
Models.hideWhileGaming private(set) false且不读取旧存档；RevivalSettingsReloadTests输入true后第48行断言false已证明忽略旧值，不能再声称旧值生效。
- ScreenStateMonitor每轮gameApplication读取前台应用/Bundle/category仅为固定false条件服务，移除该专用检测及isGaming消费/订阅。只删除证实专用无引用残留，不恢复设置/不新增检测。
- GameMatcher及专用测试如确认只有这条链路使用可同批移除；别删全屏/MissionControl检测和其它NSWorkspace观察（音乐来源等仍有用）。不写/迁移/擦除用户旧偏好；保持旧hideWhileGaming=true仍不影响显示的既定行为，必要兼容常量可保留但不保持无效工作。
- 专用无用测试不能因“既有测试”而维护已删除产品功能，但保留验证旧偏好忽略/全屏调度中心行为的有效断言。

## 边界与交付
Swift6/macOS27；Objective-C/Perl保留；现有UI/Alcove动画/玻璃/布局/选屏/R3外接位置/歌词/耳机/Codex日历均不改。只相关无窗口功能回归，不全量/真实锁解媒体/设备权限/闪窗CPU内存循环。
一次Release新/private/tmp候选，构建号自动7或真实下一号；signature/hash/Info/verification一致。正常退出旧版→确认0→启动唯一新包；不强退/不覆盖运行包或dist、不安装发布/改归档/Git提交推送。工具无法正常退出就留候选由Codex接续。
报告docs/reports/v0099-disabled-music-schedule-game-removal.md说明真实改动、旧源位置、测试与边界。完成停等独立验收，不提前做无用View/外观/验证目标/文档整理。
