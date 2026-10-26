# V0023：修复既有授权初始状态与旧开启偏好吞意图

Codex实际验收V0022最终.app时，设备页AX同时有“需要授权”标志与设备连接Toggle on。未点开关，当前无pending。V0022 UI/资源子集已接受且真实九页点击通过，不回退。此任务仅修原授权正确性，不加新功能/权限/授权中心。

证据docs/verification/independent-v0022/decision.md与persisted-permission-failure.log；新增Tests/ValoraTests/IndependentPersistedPermissionTests.swift两项均失败，禁止删除/弱化：
1 未授权、已存enabled=true、pending=false，开关不应冒称已启用。
2 此时用户尝试开启应正常开始授权意图，不能被旧value=true提前guard吞掉。

当前原因：SettingsView .onChange仅在状态后续变化时清值，不处理首次已有未授权状态；PermissionToggleRouting getter value||pending，setter开启时guard !value。既有存储意图和当前权限/当前pending未区分。

最小修：初始化/首次显示真实状态一致；未授权的旧开启偏好不得显示有效开启，未请求时不得自动触发授权；点击开关才请求，成功完成当前意图才on，取消/拒绝off，不要求先关再开。已授权已开启必须保留。pending显示和取消行为不变，同一pending不能重复请求；旧callback不能完成新意图；外部授权变化且无开启意图不能无条件重启功能。初始纠正只可改本软件自己的配置，不改系统TCC/权限/登录项；选合适最小入口，避免Binding getter产生写副作用。

共用路由还用于日历/登录，复核它们初始旧on及pending流程；不要因蓝牙修复破坏登录批准/注册取消、日历旧callback、切换页重建等边界。Controller授权gate继续拦截未授权后台查询/通知，不能仅隐藏手或强开假授权。

UI图标/分组顺序/名称/13pt顶距/权限手形不可点击均保持，AI页CodexUsage仍占位；不恢复外来品牌/许可证，不接音乐来源优先。

先跑两项独立失败回归，再跑现有AppPermissions/IndependentPermissionFlow/IndependentCalendarPermission/设置以及必要蓝牙生命周期测试和构建签名；新增必要的首次挂载/外部grant无意图回归，不海量镜像测试。用隔离注入状态真实SettingsView核旧on+未授权初始off、pending/cancel/authorized-on，区分注入与系统实测。禁止为验收点真实授权开关/改TCC。

报告docs/reports/v0023.md，证据docs/verification/v0023/。完成停止Codex独立复核，不Git提交推送/安装发布/真实媒体设备系统写/修改归档/模型历史。
