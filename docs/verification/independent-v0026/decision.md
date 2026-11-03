# V0025-R1/V0026 独立验收：暂不接受

原有日历/统一条/授权相关39项回归通过；新增IndependentCalendarLifecycleTests五项全部失败（六个断言失败）。不是以pi的246全量测试报告宣布通过。没有重复构建有明确阻断项的候选或换用户包。

## 已复现问题

1. stop之后refreshEvents仍调用fake provider；guard分支在未started时反而load，任务停止不真正生效。
2. 快速切日对不响应Task取消的provider同时产生2个未完成读取，违反最多单个在途/合并最新。真实EventKit队列串行也可能积压被取消但仍会执行的旧工作。
3. 跟随今天从2021-02-28到03-01，可见月份仍2月，网格无本月今天选中格。
4. gate通过后、调度任务执行前被撤销，仍调用provider。provider调用前缺少最终gate/有效代际检查；最终commit检查不能代替不应发生的读取。
5. 原生日期按钮首次跨日后仍显示旧日：calendar.$menuBarText sink读取willSet前的旧属性，实际按钮从3月1日未更新为3月2日。

## 代码核查还须同轮收尾

- Popover show/hide没有驱动日历读生命周期；init/rebuild、任意设置变化即读，隐藏时仍查询。需日期条轻量跨日观察与可见面板事件查询生命周期分开。
- NSWorkspace.didWake的block observer token错误从NotificationCenter.default移除，removeObserver(self)不能移除token；queued回调也无started检查。stop后不能复活。
- 时区通知仍使用初始化的固定Calendar.current值，没有更新日历时区。
- root视图宽360+padding20，popover.contentSize硬编码300，实际popover须核裁切与高度更新，不用完整NSHosting截图代替实际容器。
- 已看pi浅色图：今天农历副行白字处在红色高亮以外，浅底不清晰。UI整体为灰实底/实线边，尚未完成用户希望的原生材质观感。

## 实际输入与运行包边界

只启动/private/tmp/valora-v0026-candidate的preview（fake数据），CUA定位该候选超时、app inventory未列出它，无法执行真实三区左右键/日格鼠标验收；未把performClick或截图算实机成功。已结束本次自有preview会话。用户dist仍19ba9a0f...未覆盖、未退出用户原进程；未发媒体命令、未查询个人日程或点权限。

限定V0026-R1修以上功能/生命周期及真实容器可读性，再完整独立验收；UI透明材质方向另给建议，不借此重做设置/刘海。
