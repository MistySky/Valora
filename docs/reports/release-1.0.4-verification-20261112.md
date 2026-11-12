# 1.0.4 发布准备验收

用户当次授权：停止进一步静置内存优化，提交代码到当前分支、不合入main，打包1.0.4并上传现有GitHub Releases。

## 代码与版本

- 分支 `codex/lock-screen-idle-cpu`，发布前HEAD3b4dc91，main固定6c98d2be683e035fdaab9f29dcbd795236748655；不执行合并。
- 提交本轮源码、相邻测试、任务/验收文档；旧未跟踪docs/verification日志、截图、历史快照与本机dispatch状态不进入提交。
- package_args默认营销版本更新为1.0.4，README同步发布分支、固定签名及显式歌词配置。
- 实际生产代码沿用已体验build61；不继续调整静置缓存、动画或交互。显式 `VALORA_LYRICS_EXPERIMENT=1` 保持既有native歌词渲染器。

## 集中验证

- 289项定向用例（Valora149、ReferenceCore140）。首次1项LaunchPolicy测试的4个断言失败：源码扫描器只递增开发条件、对歌词等所有endif却递减，深度为负造成误报；生产控制器确实在开发区外。
- 仅修测试扫描器：跟踪所有条件栈并标记开发区，检查配对；LaunchPolicy14项复验通过。其它275项未变且首轮通过，不伪称初次全绿。日志 `/private/tmp/valora-1.0.4-release-tests-20261112.log`、`/private/tmp/valora-1.0.4-launch-recheck-20261112.log`。
- scripts/test_package_entry.py、test_build_number.py通过；git diff --check通过。
- 未执行压力/长时间内存循环/真实媒体操作，也未将定向用例称为产品全量覆盖。

## 产物

- 一次正式Release打包：1.0.4/build62，arm64，Valora Self-Signed，strict/deep签名通过；新包满足build61的designated requirement，签名身份延续。
- 路径 `/private/tmp/valora-1.0.4-release-20261112/Valora.app`。
- binary SHA256 `8e12114a0d831f32303ca6fb624fb8c17f9a596911b50011a158026f5fadaa36`。
- DMG `Valora-1.0.4-arm64.dmg`，SHA256 `e07df3be38cdc6c3012dac44ca8ac74f0fec12fc236b0b54e0a5448510655246`；hdiutil verify通过，单次只读挂载核验版本、签名、包内binary哈希与Applications链接后正常卸载。
- SHA256SUMS同时校验DMG和build-verification.json。完整构建日志 `/private/tmp/valora-1.0.4-release-build-20261112.log`，DMG日志 `/private/tmp/valora-1.0.4-dmg-20261112.log`。

## 运行替换及验证命令纠正

旧build61/PID66987正常quit，确认0进程。一次开发入口探测误用了未登记的 `--verify-release-boundary`；现有LaunchPolicy是已知flag集合，该探测进入普通启动并被subprocess的5秒超时处理终止。已确认无残留；没有把该探测记为成功，也没有因此修改产品启动规则。

随后在零进程下使用已登记的 `--verify-music`、`--audit-resources`、`--preview-music` 分别确认Release返回2，再正常启动正式包。唯一实例PID84140，路径对应本次1.0.4候选；未覆盖Applications。实际记录 `/private/tmp/valora-1.0.4-release-20261112/local-verification.json`。

## 发布方式

按用户授权提交推送当前分支，v1.0.4标签指向该分支最终提交。GitHub Release随标签上传DMG、校验文件及构建验证JSON；保留所有旧发布和资产，不移动main。远端发布结果由执行记录及最终GitHub链接核对，不提前以本报告充当上传成功证明。
