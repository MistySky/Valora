# 打包使用前只读复核（2026-11-06）

基于当前工作区，非已提交HEAD。复核未改生产代码、未运行真实媒体/权限/日历/设备探针；OC的V0106测量工具仍在开发，其新文件不在此最终接受范围。

## 结论

本次抽查未发现新增使用阻断；不是无缺陷保证。功能基线build15已接受，396项安全回归及用户日历/音乐/锁屏反馈见各独立记录。性能基线及其开发入口的最终隔离仍须正式交付后另验。

## 已核

- Package.swift：Swift6语言，tools6.4，最低macOS27，三个生产target，无新生产包依赖。
- Controllers.swift：音乐关停tick，start守卫、stop清订阅/回调，真实时间锚不重写。
- NativeBridge.m：首次成功Space归属不被重复独占覆盖，失败回滚到本次入口快照；锁屏stop路径有detach。
- LockActivationOwner.swift：共享最后owner恢复policy，单次session状态判定及保守焦点恢复；不是绝对不抢焦点的玻璃方案，实际取舍保留。
- LyricsController/Cache：锁屏与普通表面共同需求判定、3秒budget、generation拒迟到、内存50首/5MiB payload与磁盘50MiB上限。
- CodexUsageProvider：关闭取消调度与任务；在途所有权保留直到返回以免重叠。180秒刷新/失败退避/重置边界；传输本身有超时和方法白名单。
- 日历个人事件整链已移除，剩余节假日query仍需授权与可见范围gate。
- 退出路径：锁屏、歌词、media、audio、bluetooth、Codex和菜单栏停止；Release开发入口早拒绝、QA实现debug-only。
- 构建号统一由正式打包入口分配，无手动覆盖；测试不消耗构建号。

## 资源观察与非阻断项

1. AudioOutputController.swift:74-87：正常启动即启动0.5秒音频输出轮询，AppDelegate.swift:487不与音乐开关联动，退出才stop。这是现有共享输出数据源，尚无资源实测证明高开销；不能以QA previewMode的early-return数据代表生产CoreAudio读取成本。性能报告需写明此测量盲区；如实测可疑，再单独提出按需求调度/系统事件方案，不先改成熟功能。
2. AudioOutputController.start没有重复启动守卫；当前生产只发现一次启动与退出停止，无已证实重复调用泄漏。记录为防御性改进候选，非已复现阻断。
3. git diff --check仍报CalmonCalendarView.swift:184 EOF多空行；提交/最终交付整理项，不影响当前包。
4. 工作区收尾代码尚未提交推送；不能将build15或后续工作当成远程已保存。

## 使用门槛

V0106独立验收无阻断（真实数据/限制清楚、无生产退化）后，可形成日常使用包：确认Release构建、版本/构建号、签名、资源与开发入口边界、唯一实例。若仅debug工具变化，不能把性能测量工具纳入Release；无需为每次测量反复分配构建号。私有MediaRemote/SkyLight/玻璃variant的系统升级风险仍在；本次不迁移它们。

47项真实窗口/状态项测试未全执行；物理多屏、实际人声/设备/长期使用仅按已有用户同条件证据，不夸大。最终包提交推送/发布不由本次只读核查自动执行。
