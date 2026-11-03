# Codex直接修复候选 R8（2026-10-30）

用户要求本聊天直接修复，不再向pi派此修复。

## 实际改动
NativeBridge.ARLockPresentationSpace由CGSAddWindowsToSpaces改为SLSSpaceAddWindowsAndRemoveFromSpaces（固定参考BoringNotch所用SkyLightWindow及DynamicNotch的ABI int32 connection/space/CFArray/int32 mode7）。仅调用方自己窗口，先验证NSApp窗口归属；不改几何、y偏移/动画时长/模拟偏好/窗口尺寸或其他功能。
迁移前复制原成员数组，未知查询不迁移，空成员允许新隐藏音乐卡；迁移后必须查询为仅目标Space且返回码成功，静默no-op不能假成功。错误时回滚；detach先恢复捕获的全部原空间，确认后移除目标，避免猜桌面ID；恢复失败保留所有权以待retry。区分verified windows与未完成回滚，后者不能被重复attach误报成功。缺符号失败关闭，不自动fallback旧add路径；目标space超int32范围拒绝并释放，level失败释放。
保留既有原版顺序/withAnimation完成链/neutral归属/音乐窗口解锁清理/设备歌词日历监控。没有修改SwiftUI锁形状或删除成熟模块。

## 验证
- 29定向fake Swift测试通过：NotchDiagnosticPolicyTests|LockMusicCoordinatorTests。
- 新增独立Objective-C harness Tests/NativeBridgeTests/LockSpaceMigrationTests.m直接包含生产native文件，测试专用编译宏仅提供注入初始化器，正常App不编译此入口。回调全部fake，不创建NSApp/NSWindow/真实Space。
- 6 native场景通过：成功独占迁移/幂等/完整恢复；返回成功但no-op拒绝；部分迁移报错回滚；未知原归属拒绝；隐藏音乐卡空归属恢复；恢复失败不移除唯一可见空间且可重试。
- 命令：xcrun clang -fobjc-arc -Wno-nullability-completeness -I Sources/NativeBridge/include Tests/NativeBridgeTests/LockSpaceMigrationTests.m -framework AppKit -framework IOKit -framework CoreAudio -framework IOBluetooth -o /private/tmp/valora-native-space-tests，然后运行该fake-only harness。
- Release完成；首次sandbox阻止dsymutil，授权工具环境重建完成。package.py单独输出临时目录，strict/deep codesign通过。
- 候选/private/tmp/valora-direct-r8-space-migration-candidate/Valora.app；binary SHA256 822a530205741de30d4826ccf60cd285594ea7b03907976673db8f29fb32f19b。

## 明确边界
这是针对外部源码空间语义差异的实际修复候选，不是已实机确证根因。尚未验证macOS27真实私有API的行为或下浮是否消失，不能把35项fake场景当真实体验通过。保留默认关闭有界诊断以支持后续实际取证。
未启动/退出/重启当前用户Valora或AlcoveRevival，未锁屏睡眠声音/媒体/设备/权限/偏好操作，dist不改、归档只读、无Git提交推送、无自动化/循环UI/压力测试。下一次启动应只保留一个对照实例，用户自行锁解。

## 用户实测拒绝与回退
2026-10-30 用户实测R8锁屏直接消失，R8整体拒绝。native迁移严格gate可能令mount=false，但具体失败分支无运行数据，不能唯一归因。已撤销生产迁移API/依赖/归属查询前置条件，恢复之前已可见的add/remove路径；保留R7默认关闭诊断及level失败释放修复。R8 native源码与fake harness留在direct-v0036-r8证据，历史harness改引用留档源码，不再冒称当前生产回归。
回退Release/签名通过，候选/private/tmp/valora-lock-visible-rollback-candidate，binary54fc0d2959b65e4f5e2744de7423af0d479877c6a3145ab952dde2ec47795ba1。用户替换授权范围内已通过CUA刘海右键退出R8（快捷键未退出，菜单退出成功），启动回退候选AX音乐歌词可见。未操作真实锁屏/媒体/设备/设置；原下浮仍未修复，不声称已实机恢复锁屏。
