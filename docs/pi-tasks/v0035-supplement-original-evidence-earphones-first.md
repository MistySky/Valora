# V0035补充：必须对照复刻实机/反编译证据，耳机优先，锁屏后置

用户指出不能只看当前新代码而忽略复刻及原版反编译；随后明确下一步锁屏，但“这版先把耳机做起来”。保留R1成果，禁止自动进入锁屏开发，先设备正确性与实机验证收尾。当前R1已交付，Codex独立复验会同时运行定向fake测试，因此本补充先只读审计+文档，不并行改生产源码/测试/构建；若发现需要修复，列具体偏差待Codex收齐复验后安排限定返修，不擅改刚交付R1。

Codex已找到直接证据：
1 /Users/wangqing/code/alcove-revival-archive/docs/alcove-1.7.9-detail-audit/evidence/fixed-0.6.35/airpods3-real-notes.txt：历史真实AirPods3左右IOBluetooth 100/99，Single=0不适用；当时已确认single0进min造成红环，修复后与original-airpods3-arrival.png同设备稳定帧对照。读取笔记时不复制其中用户MAC地址，报告用型号与电量即可。
2 /Users/wangqing/code/alcove-revival-archive/Sources/AlcoveRevival/Models.swift AudioDevice.battery用>0过滤；Controllers.swift BluetoothController解析valid1...100。这是历史复刻修复策略，并不证明真0不可能，不能无脑全过滤0；Valora改成允许0又三字段min确实丢了已知single占位修复。R1/主体应保留左右优先、不适用single不压左右，未知/真实0语义逐项区分。
3 /Users/wangqing/code/alcove-revival-archive/reverse-engineering/connection-appearance/核对结果.txt，1002b5cf4.c /1001f4c48.c /1002ba4a8.c /10031fbe8.asm /1002b45f8.c：原版batteryLevel可选，缺失时空白；非百分比文字/非对勾；电影32/28pt，环14/12pt，线2.5/2；型号mapping/模型电影与symbol分支分别证据。只读实际函数核对对应逻辑，不只引用汇总。
4 音乐原Controllers.swift command和SystemMediaSource.swift：send2最终在后台根据最新system snapshot解析为显式pause1/play0；Valora的SystemMediaSource当前保留相同映射，不误判成真toggle。对照本次即时playing状态变更不得破坏真实timeline/歌词；已有R1旧callback三case继续复验。不为“流畅”另创动画/修改点击语义。
5 原版系统AirPods通知屏蔽：目前复刻/上述反编译未找到，不等于证明原版没有；只报告哪些函数覆盖了哪些路径、哪些仍未知，不把全仓库关键词无结果当严格否定证据，不写系统设置/杀通知进程。

交付一份三方对照docs/research/v0035-original-revival-valora.md：原版反编译地址与能证明范围→成熟复刻/真实记录→当前Valora/R1对应函数，逐项迁移缺失、保留改进与未知。不得重新泛称“先前未实测”：历史AirPods3实际上实测过。低电/Pro3等历史限制则保持限制。只读源目录，不修改归档/历史证据，不落MAC/用户名称。

实机后续方案也列入：如何在用户已经授权的Valora候选内只采当前活动音频设备电量（最多3样本10秒，类型/左右/Single/合成结果/型号，无MAC/用户名称/其他配对列表），不操作真实播放/输出/耳机连接，不外部probe触发新TCC，不向当前运行app注入。此补充只给方案，先别增加诊断代码或启动新实例，等Codex安排后在一份可检查候选上一次验证。

不全量/压力/反复菜单闪窗/系统权限修改/旧功能恢复，不Git，不覆盖运行包/dist，定时器关闭。完成报告后停，锁屏只列下一步待设备通过，不自动派或实现。
