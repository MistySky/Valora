# V0022及侧栏顺序补充独立验收（2026-10-25）

## 结论

AI用量/内部命名/外来品牌资源与许可移除/最终分组与关于标题子集接受；实际打开最终新包并逐页点击已核。不把全部设置权限体验称为通过：额外实机发现“需要授权标志但设备开关on”，两个新增隔离回归失败，已单独限定V0023修复既有授权初始化与意图路由问题，不回退已接受UI成果。

## 本轮独立验证

- 当前SettingsReductionTests 9/9通过，独立release构建签名成功，二进制ce6d159673444197435814b47f925e298291a6a6982db65dba829151654d51e5，与dist一致。
- 项目外运行临时完整.app --verify-settings成功，检查独立AI用量渲染：系统sparkles、Codex 用量/准备中、菜单栏日历→下载监控→AI 用量→系统监控、Valora组标题下关于。13pt内容间距保持。
- 独立resource-check.json：无CodexUsage目录、chatgpt.png、两份本次导入许可证或Valora_Valora.bundle；MediaRemote/LICENSE/应用彩色图标/Outline-v7/设备和声音资源保留。签名保留日历entitlement，无系统音频捕获用途声明。
- rg确认当前运行时代码不留codexMonitor/Codex Monitor/旧品牌Mark/Bundle.module；AI壳aiUsage，内部实际SwiftUI子内容CodexUsageView，无provider或账号调用。
- 根据此前用户启动最新包的授权，CUA退出旧Valora并启动已核hash的dist，打开设置，实际点击全部九页；AX确认三个非按钮组标题、顺序、AI子内容及关于版本。最终停留AI用量页。未点真实功能开关/授权/媒体控制，未退出原Alcove。
- 构建既有actor-isolation/QRC fixture警告保留，未全局抑制并发检查。

## 新发现的授权状态缺陷

实际设备页AX同时出现“需要授权”Image和设备连接Toggle on，当前没有pending意图。源码SettingsView只监听权限变化而不处理首次挂载已有未授权状态；PermissionToggleRouting.get直接value||pending，set(true)因旧value为true提前返回。旧偏好开启不等于当前授权或当前开启意图。

新增IndependentPersistedPermissionTests两项，均失败：未授权+旧on+无pending应呈关闭；此时用户尝试开启应发授权意图，实际被旧value吞掉。测试只用本地Binding，无真实权限/系统设置/媒体操作。失败日志已保存。需最小修初始状态/路由并保持pending取消、旧回调、授权成功后才开启、已授权原on不被清、外部授权无意图不自启。
