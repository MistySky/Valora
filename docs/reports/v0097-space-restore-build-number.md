# V0097 第一批收尾：Space 幂等恢复 + 递增构建号

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
本批**只做两件事**：原生 Space 恢复幂等、构建号递增。未改游戏检测、焦点生命周期、UI/动画/玻璃/歌词/音量/锁屏选屏/外接位置。未 Git 提交/推送、未改归档。

## A. Space 恢复幂等（NativeBridge）

### 缺陷（已复现）
`migrateWindowNumberExclusively` 末尾无条件 `_originals[identifier]=captured`。同一窗口第二次独占迁移时，入口 `captured` 只剩 owned Space，覆盖首次的桌面归属，`detach` 之后桌面归属丢失。
复现（原回归，修复前）：`first=1 second=1 restoredDesktop=0`，退出码 1。

### 修复
1. **只保留第一次成功捕获**：`if(_originals[identifier]==nil) _originals[identifier]=captured;` —— 空数组 `@[]` 是合法值，不会被误判为“不存在”（判空用 `==nil`，不是 `count`）；
2. **失败回滚恢复“本次进入前状态”**：回滚时先移除本次加入的 owned，再把 `captured` **完整**（含 owned，若进入时已是独占）加回；不再沿用“排除 owned”的写法，避免重复迁移失败后被清成空归属；
3. 未知查询（`copyForWindows` 返回 NULL）仍退回首次快照做回滚，并在结果里标注 `query=unknown`；
4. 未改锁屏动画、Space 等级、展示机制，未恢复旧失败路径；不直接 `return success` 绕过归属校验。

### 原生验证（只用生产 fake 回调，无真实 NSWindow/Space）
| 用例 | 结果 |
|---|---|
| `ExclusiveSpaceMigrationTests`（既有 6 场景） | 6 通过 |
| 原失败回归 `RepeatedExclusiveMountRegression.m` | **通过**：`first=1 second=1 restoredDesktop=1`，退出 0 |
| 新增 `RepeatedExclusiveMountTests.m`（5 场景） | 5 通过 |

新增 5 场景覆盖任务要求：
1. 重复成功后 detach 恢复原桌面归属；
2. 初始空成员重复迁移后仍恢复空（且 `before` 是真实空数组）；
3. 首次失败（add 被忽略）→ 回滚保持桌面 → 重试成功 → detach 恢复桌面；
4. 重复迁移失败（post-query unknown）→ 回滚到进入时状态（仍独占）→ detach 仍恢复**首次**快照；
5. detach 结束后新周期重新捕获并再次正确恢复。

编译命令（本机 SDK，仅临时产物）：
```
clang -fobjc-arc -isysroot $(xcrun --show-sdk-path --sdk macosx) -I Sources/NativeBridge/include \
  -framework AppKit -framework CoreGraphics -framework IOBluetooth -framework IOKit \
  -framework CoreAudio -framework AVKit -o /tmp/<bin> Tests/NativeBridgeTests/<file>.m
```

## B. 递增构建号

- 新增 `scripts/build_number.py`：单一状态文件 `~/Library/Application Support/Valora/build-number.json`（本项目自己的记录，不扫描其他 App/账号）；`fcntl.flock` 跨进程互斥 + 临时文件 `os.replace` 原子写；写失败不推进、不报成功（允许跳号，不允许重号）。
- `scripts/package.py`：`--build` 默认改为 `None` → **自动分配**；显式 `--build` 仍可用但会打印“覆盖计数器、不推进”的警告。`build.sh` 只调用 `package.py` 一次，因此**一次交付只加 1**；debug/test 编译不调用，复制/重压已有产物不调用。
- 版本展示统一读 Bundle：新增 `AppVersion`（`CFBundleShortVersionString` + `CFBundleVersion`），关于页显示 `0.2.0 (2)`，菜单版本文案同源，去掉了原来 About 页硬编码的 `"0.2.0"` 回退值。
- 计数初始化：此前已知上一号为 1，本批把状态置为 `last=1`，本次正式候选分配到 **2**。

隔离脚本验证（临时目录，不反复 Release 编译）：
```
python3 scripts/test_build_number.py
→ build-number checks passed（连续 +1、peek 一致、8 线程并发无重复、
   写入失败不报成功、单次交付恰好 +1）
```

## C. 构建与单实例替换

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0097-space-restore-candidate/Valora.app` |
| CFBundleShortVersionString | `0.2.0` |
| **CFBundleVersion** | **2**（`build-verification.json` 同为 2） |
| binary SHA-256 | `b72d615cfeb2b68f3128322a5d7d7c6b288215ad5039ca3a968cb03b7ca74387` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| dist | 未动 |

替换：`pkill -f "MacOS/Valora"` → 复查 0 实例 → `open -n` 候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0097-space-restore-candidate/Valora.app/Contents/MacOS/Valora`（PID 93857）。

Swift 定向回归（无窗口）：`LockMusicCoordinatorTests 32` + `LockCardLayoutTests 13` + `LockLyricsTrackChangeTests 8` = **53 项通过**；未跑全量、未闪窗/性能。

## D. 本批未做（按任务约定）

- 游戏旧值：`RevivalSettingsReloadTests` 断言 false 的行为未动；无效游戏检测链路未删；
- 焦点生命周期、0.25s 调度、无用 View/外观字段、验证代码编译边界、文档整理：均留给后续批次；
- `LockMusicState` 中 `reserveFullExpansion` 相关注释里仍有“can never cover the avatar”这类绝对表述，本批不改（数值未动），留待文案统一修正。
