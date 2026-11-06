# V0097 第一批收尾：Space幂等恢复 + 构建号递增

用户已明确授权把核实的问题交给OpenCode落地，并补充“构建一次加1”。在现有Valora会话实施；当前分支codex/final-cleanup，检查点9869890已推送。不得修改模型、重置/切分支、提交推送；不并行开另一会话改代码。完成本批停止，交Codex独立验收后再进下一批。

## 当前约定与审查纠正

Swift tools6.4/language6/macOS27；保留三个生产target及现有UI/动画、glass darkAqua/variant5、歌词/音量、独立锁屏选屏、外接21%+最大展开接线、用户v11图标。归档只读。
游戏偏好当前Models只有private(set) false且无存档赋值；RevivalSettingsReloadTests输入true之后断言false（第48行），不是旧存档仍生效。后续可清无效游戏检测，本批不做。LockMusicState reserveFullExpansion注释仍有“can never cover the avatar”，不能仅凭附近反向免责声明说全文件无绝对表述；后续修正文案，数值不动。

## A 本批原生修复

NativeBridge.m migrateWindowNumberExclusively末尾无条件覆盖_originals。同一窗口首次从desktop11迁移到owned901成功，再调用入口captured只剩901，覆盖首次记录；detach丢desktop11。

- 保留第一次成功捕获的原始成员（包括合法空数组），直到detach完成，重复成功迁移不能覆盖；不要把“空数组”误作不存在。
- 当前查询/验证/回滚和original恢复职责分清：第二次迁移失败时要恢复本次进入前状态，同时保留最初退出恢复快照，不能用首次快照替代所有错误回滚。
- 不盲目直接return success绕开当前归属验证；不改锁屏动画、Space等级或展示机制，不恢复旧失败路径。
- 覆盖：重复成功后detach恢复原桌面；初始空成员重复后仍恢复空；首次失败后重试成功；重复迁移失败保留首次记录；detach后新周期重新捕获。使用现有生产native fake回调，不构造真实NSWindow或真实Space调用。
- 历史原失败回归：docs/verification/independent-opencode-lock-2026-11-03/RepeatedExclusiveMountRegression.m及native-tests.txt。应原样复验，不能只改预期掩盖缺陷。

## B 用户新增构建号规则

版本0.2.0保持，CFBundleVersion改为持久递增整数。每次正式Release候选构建分配新号（本项目build/package交付流程统一接入），例如0.2.0 (2)，下一次(3)。测试/debug编译不消耗，重复压缩/复制已构建包不加号。

- 当前脚本默认--build=1不能继续每次重置。先读现有工程记录选单一构建号来源，不扫描其他用户App/账号；从已知上一号1续接可从2开始。
- 跨进程分配防重复、原子保存；失败允许留下跳号，不重复已分配号。正常流程不允许无意用旧--build覆盖递增。
- 不要在编译任务每个target或每个测试启动时加号。明确脚本入口的“构建/打包一次”边界，直接package候选和build.sh不要双增。同一产物归档不再增。
- 关于页和版本展示从Bundle读取版本+构建号，不硬编码；Info.plist、build-verification.json、报告一致。不加设置项、不改页面布局。
- 小型隔离临时目录验证两次分配严格+1、并发不重复、写入失败不伪报成功、同一交付流程不双增；不为验证反复Release编译或启动App。

## 测试/交付

仅native注入定向功能回归+相关无窗口Swift测试和构建号脚本用例；不全量、不闪窗/内存性能循环、不真实锁屏/播放/音量/设备/权限/登录项/个人日程账号读取。不得删除既有证据或用户资源。
正常Release构建一次，打包到新的/private/tmp/valora-v0097-space-restore-candidate/（已存在则另取），严格签名、hash、版本构建号核验。完成后按用户常驻要求正常退出旧候选→确认0进程→启动唯一新包→核路径及仅1实例；不覆盖当前运行.app、dist或/Applications。若无法正常退出或锁屏阻止则说明，不并开多实例或强制终止。
报告docs/reports/v0097-space-restore-build-number.md：变更/原失败回归/测试命令与真实数量/候选hash签名/构建号来源和递增边界/运行单实例证据，完成停等验收。

## 后续串行范围（本批不实施）
1. 焦点生命周期先核必要性与恢复条件，不把未证明的“只有key才有玻璃”当事实，不在解锁时盲目抢回过期应用；不改变已接受材质。
2. 音乐关闭暂停0.25s调度、移除无效游戏检测。
3. 无引用View/样例/旧外观实验/过时测试、摘要无障碍按真实显示内容。
4. 开发验证代码编译边界与文档当前约定整理，保留历史索引/许可证/用户资源，不借机重构成熟底座。
