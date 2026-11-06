# V0103-R1 独立验收接受

日期2026-11-06（Asia/Shanghai）。仅测试就绪竞态修正接受；功能自动回归范围已完成，真实UI/设备范围仍待验，不进入性能专项。

独立读取测试差异：readyPID拒绝空/空白/无效/非正PID，有效后才继续；waitForPID带明确有界setup deadline；fixture原子发布pid；启动失败有文件内容和task结果诊断。原取消<0.6s、2s deadline/<2.7s、旧TERM-ignore child必须退出的核心断言保留。仅测试/报告变化，未改产品实现。

独立只跑IndependentCodexTransportTests 7项通过，日志/private/tmp/valora-independent-v0103-r1-transport.log。包含新增3个确定性就绪用例和既有4个传输用例。没有重跑无改动398项。先前398安全Swift、23native与两套脚本独立通过记录仍有效；现多3个测试，不把“旧398+新7”混算成405个不同测试。

原首败日志与未确诊状态保留，不根据后续通过断言唯一根因已确定。测试原先存在的空文件就绪竞态已被确定并修正。

当前包仍/private/tmp/valora-v0101-r1-dev-isolation-candidate/Valora.app，binarycae680e5c4d51d748ccef6134025e2c2f9172f542094a18f621bb3f0634b34db与原build13匹配，strict/deep签名通过；只读ps唯一PID37215路径一致。无新构建/编号/替换，无Git提交推送。

47项会创建窗口/状态项的自动测试仍未执行，不能以一次肉眼观察完全替代其所有组合断言。实际锁屏/解锁焦点、合盖、耳机、QQ歌词/双击/封面与物理多屏的受影响部分需用户配合，之前同条件已确认的行为保留证据不盲目重测。下一步逐项单次功能观察，不批量闪窗、不擅自控制媒体/音量/锁屏/设备/授权；完成并修完功能缺陷后再资源及Alcove动画流畅度专项。
