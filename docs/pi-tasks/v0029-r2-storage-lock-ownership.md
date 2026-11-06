# V0029-R2 限定返修：存储锁与非所有者操作

先读AGENTS、CONTINUATION及docs/verification/independent-v0029-r1/decision.md。R1真实Range与23相关测试、构建签名通过，但新增IndependentDownloadStorageTests两项均失败，整体暂不接受。仅本批修复，不开始V0030/UI/浏览器。

- 全新persistence父目录须先建立再获取锁。锁失败不能无条件当拥有；同目录任何时刻只能一个manager拥有，不能通过测试先建目录掩盖生产首次启动问题。保留正常重启释放锁。
- lock-denied或锁创建失败实例不允许清理其他owner分段、写持久化/备份、开启新下载或其他会破坏同根资源的动作。clearOrphanedTemporaryFiles当前空列表误删owner分段已独立复现。最小实现明确不可用状态/拒绝动作，保持单owner正常功能；测无owner清理不删18字节fixture、新增/启动不产生网络或临时文件、owner继续正常。不要全局重构或更改UI。
- 必须保留两项IndependentDownloadStorageTests原有效断言。另补本地Range真实未完成下载有非零partial→暂停保存→释放manager→重建恢复同task ID与partial→继续完成字节一致；当前R1测试仅恢复已完成记录，不足。若发现生命周期retain需同范围最小修复。
- 更新Vendor源码manifest/可重建patch/校验和报告证据，保持固定007a209...。无关源/UI/下载算法不动；原兼容包明确本地SPM，非单独Convoy.app，不恢复全局shared回流。

仅自产temp/localRange测试及隔离suite/Trash替身；不操作真实Convoy/Downloads/Trash/浏览器cookie/helper，不系统权限/媒体/设备/账号写，不改归档/dist或退出当前Valora，不Git提交推送、不改pi模型历史。候选/private/tmp/valora-v0029-r2-candidate。报告docs/reports/v0029-r2.md，交付后等待Codex独立验收，通过再派菜单栏下载列表。
