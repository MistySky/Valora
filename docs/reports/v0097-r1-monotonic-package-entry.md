# V0097-R1：构建号只在打包入口分配（拒绝手动覆盖）

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
保留 V0097 已通过的 Space 幂等修复与 Swift 定向；**只**改打包入口的构建号路径。未动焦点/调度/无用代码，未跑全量。未 Git 提交。

## 一、问题

`scripts/package.py` 的 `--build` 直接取原值且不推进状态：`--build 1`/`--build 999` 都会被原样写进 `CFBundleVersion`，既能重复旧号，也能在高号之后倒退回低号。用户要求"构建一次加 1"，正常打包路径不应存在手动重用编号的入口。

## 二、最小方案

1. 新增 `scripts/package_args.py`：真实打包入口的唯一解析/分配点。
   - `parse(argv)`：**没有** `--build` 参数；一旦传入 `--build` 或 `--build=…`，直接 `argparse.error`（退出码 2），**不写任何状态**；
   - `allocate(state_dir=None)`：调用同一个原子分配器 `build_number.py`（`flock` + `os.replace`），一次调用只取一个号；
   - `resolve(argv, state_dir=None)`：解析一次、分配一次，返回 `(args, build_number)`。
2. `scripts/package.py`：删除自己的 `--build` 与内联分配逻辑，改为
   ```python
   args, build_number = package_args.resolve(sys.argv[1:])
   ```
   `build.sh` 仍只调 `package.py` 一次 → **一次交付 +1**；复制/重压已有 `.app` 不经过该入口，不加号；debug/test 不调用。
3. 分配器状态校验加固：非对象、`last` 为 bool（bool 是 int 子类，会把 `true` 当成 1）、负数、损坏 JSON 一律**拒绝**，不自动清零（清零会导致重号）。
4. 现有 `last = 2` 未重置；本次正式候选分配到 **3**。

## 三、隔离验证（只临时目录，不碰真实计数器/包/网络）

`python3 scripts/test_build_number.py` → 通过（连续 +1、peek 一致、8 线程并发不重复、写失败不伪报、单次交付恰好 +1）。

`python3 scripts/test_package_entry.py` → 通过，覆盖**真实打包入口**：

| 用例 | 断言 |
|---|---|
| 旧 `--build 1` / `--build=999` | 退出码 2、被拒绝，且**状态文件未改变** |
| 自动解析两次（预置 last=2） | 依次分配 3、4，状态与返回值一致（严格 +1） |
| 参数传递 | `--binary` 等参数正常解析 |
| 元数据一致性 | 分配值是十进制字符串，写入 Info.plist 与 build-verification 的即该值 |
| 源码检查 | `package.py` 必须调用 `package_args.resolve(...)`，且不再出现 `--build` |
| 损坏/非法状态 | `{not json`、`{"last": true}`、`[1,2]` 全部拒绝且文件**不被改写** |

## 四、Release 交付（一次）

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0097-r1-monotonic-entry-candidate/Valora.app` |
| CFBundleShortVersionString | `0.2.0` |
| **CFBundleVersion** | **3**（`build-verification.json` 同为 3，计数器 peek 也是 3） |
| binary SHA-256 | `763c38ecfda97e9df684f9ee95ae55b7e14281631c3996647c6ddc0f46e126c2` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 单实例 | 正常 `pkill` 退出旧候选 → 复查 0 → `open -n` → **仅 1 个进程**（PID 99232）；`dist` 未覆盖 |

回归（保留项未受影响）：原生 6 + 新增 5 + 原失败回归 1（`restoredDesktop=1`）、Swift `LockMusicCoordinatorTests 32` + `LockCardLayoutTests 13` + `LockLyricsTrackChangeTests 8`。

## 五、未做

焦点生命周期、0.25s 调度、无效游戏检测、无用 View/外观字段、验证代码编译边界与文档整理均未开始（留给后续批次）；`reserveFullExpansion` 注释中的绝对表述未改。
