# V0028-R1 独立验收：本批自动/原生注入范围接受

独立42项针对性测试通过（Codex parser/provider/transport与原3独立失败、菜单、原权限回归、审计有效性）；原3失败均修复。未宣称独立复跑pi报告300全量。代码核查provider真实inFlight不随stop清除，旧代际只丢结果，restart待旧工作完成才启动最新；transport等待实际子进程结束，fake child正常三RPC/持续通知硬超时/输出上限/取消终止均独立跑过。解析权威map错误类型不再fallback，nullable null区别处理、整数边界无Int转换trap。无新增真实额度探针（沿用V0028唯一2.44秒只读字段摘要，不存账户/原始RPC）。

独立release构建/临时打包/签名通过，binary f7631f4498d6ae04c0574d79cbd1210518dc67f7e124307e95be1ec70d59f261，与pi正式候选一致。用户dist仍19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f，无覆盖/退出/重启。

独立原生注入QA：Codex列表360x272，5H/WEEK两行与卡逐张到期明细，30开关request/completion delta0/0、同statusitem、preview子进程0；RSS约101.4→98.8MB/footprint65.9→44.2MB，未将短序列当长期保证。软件图标生产菜单含音乐/显示器，模块基础菜单无音乐/显示器。其他Calmon/Alcove UI未改。真实鼠标左右键/物理双屏仍未实测，注入QA不是实际账户长期运行，明确保留边界。

决定：本批自动/原生注入范围接受，按用户确认计划进入V0029依赖编译与下载数据隔离。下一步只读核查发现Convoy 007a20973923fcd69c42a3571fc299f5b8582dc6的DownloadManager.shared/private init会立即读写硬编码Application Support/Convoy/downloads.json并测临时存储，不能盲目实例化；先SPM/纯映射/隔离可行性，未证公开可配置前不跑单例、不碰用户Convoy/Downloads数据，也不静默fork/改checkout。详见下一任务。
