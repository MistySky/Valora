# V0028-R1：请求生命周期/新鲜缓存节流/严格解析限定返修

Codex独立45项相关回归和release构建/签名通过，但新增IndependentCodexUsageTests三项全失败，见docs/verification/independent-v0028/decision.md及boundary-failures.log。UI三项列表/5H-WEEK入口方向保留，不重做UI、不扩功能，下载继续等待。

1 stop/start真实在途<=1：当前stop清task/isRefreshing而旧请求仍未结束，重启会启动第二份。保留实际在途锁/所有权直至旧工作真正结束，generation旧结果不提交，restart合并最新请求，不永远禁用重启。传输defer server.stop异步返回与2秒kill grace也应纳入实际子进程生命周期，不能只管Swift Task而旧app-server仍活。暂停/隐藏恢复/sleep-wake/退出均要正确清理，补受控非合作provider与fake子进程退出验证，不靠sleep猜取消。
2 refreshOnOpen冷却/缓存：后台180秒不等于开窗限频；当前30次开关30次请求，快照新鲜时应直接展示，不重复进程/网络。按本模块最小新鲜度（如30–60秒）与已确认180秒刷新、错误退避合并，快速重复点击最多共享在途/新鲜快照。失败时打开不能绕过冷却无限重试，过期后仍可有界刷新；用可注入时钟验证，不能为测试把网络/刷新全部禁用。已接受测试中旧“每次open都有request delta”应改为产品正确节流断言，保留新增独立case的目的，不弱化单在途断言。
3 严格解析：rateLimitsByLimitId错误字符串/数组等已存在畸形类型应协议失败或明确缺失，不能fallback旧rateLimits冒充有效，null按实际nullable协议语义处理；空map依然权威，其他桶不混入。integer边界避免Double(Int.max)舍入上界转换trap，保留0/1真数字与Bool区别，重置卡count/credit明细缺失不假零、真实数量仍权威。credit id重复等影响ForEach身份时做有界稳定处理，不伪造数量/时间。
4 传输最小可验证：当前只有allowlist集合测试，新增本地临时fake可执行子进程（不得实际Codex账号查询）捕获真实三命令序列，验证正常协议、超时、输出超限、取消/stop和终止子进程、旧响应；hard deadline要在持续有通知/行输出时仍生效，不只等待无数据时超时。输出/日志不含账号/令牌/原始真实RPC。不得为测试调用thread/turn/account/read或消费重置卡。已发生一次live字段读足够，本R1不重复live。

记录所有最小内部改动及证据，不改变Calmon/Alcove UI/设置/歌词/音乐/设备/品牌、历史资源/许可；候选仅/private/tmp/valora-v0028-r1-candidate，禁止覆盖dist或退出用户Valora，不Git/真实权限/媒体/个人数据/浏览器安装。原失败3项与必要新增回归、构建签名、原生注入QA/开关请求数和子进程有界；报告docs/reports/v0028-r1.md，停止Codex独立验收，再串行下载。
