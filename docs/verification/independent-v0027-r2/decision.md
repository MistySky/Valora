# V0027-R2 独立验收：自动及固定展示内存范围接受

独立37项定向回归通过，含审计有效性5项、原两失败及授权撤销/stop、日历单在途/日期/监控等。原R1独立267项基线保留；此次不冒称独立重跑272全量。独立release构建/临时打包/签名通过，binary 2af49b8e0036a68b5c079a4b2937653adc922d36948d6c8a9e1c8c6019a9fa22。用户dist仍19ba9a0f...，未覆盖或退出当前应用。

代码复核：ContinuousVisibilityTracker按实际visible判定completed/interrupted/inconclusive，中断不会被后续隐藏内存误标长开成功。生产MenuBarModuleController默认仍.transient，QA参数/固定窗口仅显式诊断启动模式，原Calmon布局/样式与Valora其他功能未动。检查了提交transient原始记录：app失活约2.388秒、window resignKey同步，约2.929秒popover关闭；证据只说明焦点移出/关闭顺序，不能独立断言所有原因或实机体验通过。

独立执行R2正式候选的--audit-calendar-fixed-window：188.7秒总时长、37/37全程visible并未遮挡、可见跨度187.4秒、status completed/productionTransient false。预热30秒后footprint29.423→29.438MiB、斜率+0.0015MiB/min，RSS75.375→75.422MiB、斜率+0.0123MiB/min；本窗口未观察持续阶梯增长。日程始终1start/1completion/2fake events。原始JSON保留。该固定NSWindow同一生产view/model基线不替代生产transient交互/长期真实图标缓存/真实个人日程验证。

决定：本轮迁入/返修自动与固定展示内存范围接受；原R1监控实际popover37/37稳定/60轮开关对象释放证据保留。生产transient 180秒/真实鼠标左右键/物理双屏/真实EventKit权限依旧列待实机，不重复催同一检查，不以固定窗口冒充。可独立推进用户已确认V0028 Codex用量，不再无限补跑日历焦点实验。用户已授权每15分钟接续与后续下载串行计划，详见CONTINUATION-PLAN最新章节。
