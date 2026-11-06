# 设备实测：尚未接受

用户授权真实耳机连接测试，耳机由用户手动连接，型号AirPods 3。
- 候选 /private/tmp/valora-independent-v0034-candidate/Valora.app 已运行。
- GUI确认授权完成：设备页hand提示已消失、开关on。
- 一次只读CoreAudio当前默认输出查询确认Bluetooth=true、ModelUID=2013 4c，匹配AirPods3；未记录个人设备名称/地址，未切输出或播放/音量操作。
- 用户一次断开重连反馈无刘海提示，实机通知功能未通过。
- 源码当前3秒轮询，首次扫描仅记baseline，只有观察到ID从无到有才showConnection；因此快速重连可能被采样漏掉，这是待验证假设，不能当确诊。
- 已请用户一次断开至少5秒后重连，待结果。不反复自动连接设备，不进行循环弹窗/压力测试，不伪造提示。
