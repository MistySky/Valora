# V0012/R1—R4 歌词实现独立验收

结论：当前歌词代码及可自动验证范围接受，进入已授权限定清理；实际QQ人声对齐/真实双屏体验明确待用户实机，不宣称实机全通过。

Codex独立完成：

- swift test共168项通过（Valora63 + Core105），含非合作provider超时、立即取消保活、延迟挂载采样锚、同文本不同分段、真实逐字fraction及逐行长句滚动。
- 独立候选/private/tmp/valora-independent-v0012-r4/Valora.app构建成功，codesign --verify --deep --strict通过。
- 独立隔离歌词QA31/31、音乐UI74/74、注入多屏12/12通过。产物分别qa/、music/、multidisplay/，日志/private/tmp/valora-independent-v0012-r4-{test,build,qa,music,multidisplay}.log。
- 实际SwiftUI快照人工检查短句居中、展开歌词/音量相对位置、普通胶囊圆角与封面安全区，以及无words长LRC前后帧内容确实移动。逐行长句保持灰色，无假逐字填色；QRC按源word fraction跟随。
- QQ公开晴天studio/live真实QRC解码先前已独立网络复核成功，63行/602 words、36行/391 words，本轮未重复网络探针或控制真实播放器。

保留的已确认约束：紧凑/展开短句整体居中、上下换句、封面主色逐字且独立进度样式、统一实际采样锚、3秒失败隐藏/拒绝迟到、有界缓存、展开歌词置底音量在上，无实体刘海214pt/345pt宽、歌词与模拟开关解耦、活动屏动态。历史返修记录保留。

剩余验证：用户实际QQ人声同步试听（尤其不同歌曲版本、暂停/恢复和拖动进度），物理双屏与人眼体感；代码清理之后还有独立流畅度/资源测试。上述待验不阻止可独立推进的限定清理，也不等于删除本接续或进入设备模块。

下一批docs/pi-tasks/v0013-confirmed-residual-cleanup.md；后续V0014流畅度任务仅在清理独立接受后投递。禁止Git提交/推送、真实媒体控制或安装发布。
