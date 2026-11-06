# V0101-R1 两个开发辅助入口隔离

现有会话继续。V0101主体独立LaunchPolicy10、Release拒绝5flag通过，但整体未接受；数字单位间距补充独立18通过且build12唯一运行，保留“重置卡 N 张”。见docs/verification/independent-v0101/decision.md。

IndependentDevelopmentIsolationTests两个新增纯用例4断言失败：--lock-card-preview / --expand-media单独传入debug时AppRuntimeDefaults.isQAMode false、startupMode production→standard配置和真实媒体/音频/蓝牙等源启动，随后才处理preview。不能把这称作“debug全部隔离”。

## 限定修复
- 有效开发预览/检查入口须进入隔离suite与明确非production路径，不启动真实媒体/音频/蓝牙/个人日历授权服务。保留正常生产启动及已隔离QA、真实锁屏功能不动。
- 可以选择最小支持组合：无法安全支持standalone --expand-media等辅助flag时在main/AppDelegate开始任何服务之前明确拒绝，要求带合法synthetic parent；不能静默production。--preview-long-title等同类辅助flag一并核清valid组合。
- 若某辅助flag只用于真实媒体调试而不适合隔离，则明确拒绝该未授权模式，不恢复真实探针；保留现有debug synthetic预览能力，不为此新增产品设置或播放器分支。
- Release gate仍拒绝这些flag，不从名单删除来隐藏问题。不改变正常用户设置键、不读写正常偏好/账号数据。
- 根据选定契约更新独立纯参数测试：有效模式隔离配置/非production服务路径；无效组合早拒绝。原断言若因改为早拒绝而调整须验证真实main早门控，不删除独立回归覆盖。加相关debug初始化路径守卫避免再把shared controller错误条件化导致Release崩溃。

只相关纯参数/隔离模式定向，不跑整套SettingsReductionTests（含窗口）；旧sidebar期望漏Codex用量留下一批文档/契约核对，不动实际UI。不开QA窗口/真实媒体/权限/锁解，不性能审计或全量。

一次正式候选自动build13或当前下一号，新的/private/tmp目录；签名/hash/Info/JSON，正常退出旧版→0→唯一启动，不强退/覆盖运行包/dist/Git提交。报告docs/reports/v0101-r1-development-preview-isolation.md，完成停等独立复验，不展开文档改写或完整回归。
