# V0023/R1 独立验收（2026-10-25）

## 结论

既有授权初始状态与登录项写隔离修复的自动/注入视图范围接受，无需继续返修。真实系统授权、登录项批准、设备连接仍待用户实机，不以注入状态代替系统成功。当前运行的V0022进程未为本次验收自动重启；修复已在新候选打包。

## 独立检查

- 41项定向回归全通过，含IndependentPersistedPermissionTests原两失败及7项扩展；关联蓝牙/日历/登录所有权、旧callback、生命周期及设置回归通过。pi报告235全量不是本轮独立全量重跑。
- 路由getter仅pending或authorized且偏好on显示on；未授权旧on不吞新开启意图，同一pending不重复请求，取消沿原语义。
- SettingsView首次normalize只改本软件配置，无Binding getter写副作用。已授权on和有效pending保留，外部grant无意图不复活旧偏好。
- 已移除SettingsView泛型login draft onChange及所有直接LoginItem全局访问，程序性纠正/refresh不再能调用真实ServiceManagement。显式关闭路由到AppPermissions.disableLoginItem和AppDelegate注入unregister；本次拥有注册取消与已有批准注册取消区别保留，旧回调有generation保护。新回归通过：首次挂载/refresh/外部grant注入register/unregister均0，显式off注销恰好1。没有用真实系统注册/注销验证。
- 独立release构建和严格签名通过，候选/private/tmp/valora-independent-v0023-r1-candidate/Valora.app，SHA256 19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f。日历entitlement保留、无音频捕获声明、外来品牌资源/旧bundle无残留，MediaRemote/LICENSE保留。
- 从项目外运行完整.app --verify-settings，实际查看旧on未授权为off、pending为on、取消off、authorized-on无手形等注入视图；最终侧栏顺序和AI页不回退。构建既有actor-isolation/QRC fixture警告未消除，不声称零警告。

## 后续边界

V0021只读静态研究事实范围已复核，下一步需要用户确认是否允许真实只读后台音乐来源探针，具体提案docs/pi-tasks/proposed-v0024-per-client-read-probe.md；未投递、未执行，无媒体命令/新权限/账号读取方案。不可直接启动多来源实现、未定监控/下载/锁屏模块或旧任务队列。此轮已授权修复与验收完成，等待用户决定，不继续无效轮询。
