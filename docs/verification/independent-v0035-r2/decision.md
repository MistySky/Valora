# V0035-R2 独立复核

## 结论
源码与相关逻辑回归子集可接受，真实授权完成/耳机重连到达仍待新候选实机，不宣称用户漏报已修复完成。

## 修复与证据
- AppDelegate 的用户开关 bluetoothRequest 已由 IOBluetooth read probe 改为 BluetoothAuthorizationRequester。只有用户明确尝试开启才创建 CBCentralManager；queue.main，禁止扫描/连接，授权状态离开notDetermined后异步回MainActor刷新既有pending intent。
- 这补齐了请求与权限gate使用同一CoreBluetooth状态的路径；此前偏好off只是观测，不是完整TCC或native事件证据，不能认定唯一根因。
- 保留此前非隔离native selector、注册身份校验、左右优先电量合成、10秒明确连接intent、旧结果/生命周期保护。
- 独立定向执行48项通过（含原设备/媒体/权限/持久化回归；以独立日志为准）。没有操作真实媒体/蓝牙/权限、没有UI循环或压力测试。现有测试不直接调用新CBCentralManager授权适配器，真实系统弹窗及回调链路需实测，不能以旧fake注入覆盖此缺口。
- 八份交付源快照哈希及当前源码逐字节一致；候选二进制SHA256匹配425421f92a9d8655295502c56585cc573b494dd12e7eb5c3697afb75877bba88。独立codesign deep/strict通过，蓝牙usage description存在，临时电量采样flag关闭。
- 候选 `/private/tmp/valora-v0035-r2-real-reconnect-candidate/Valora.app` 尚未由Codex启动，当前用户运行版不退出不覆盖。release构建记录采用已交付日志和哈希/签名复核，本次未重复release构建。

## 下一步
在用户授权换版后，由用户点击设备开关并完成系统授权，首先核实开关确实保持on，再由用户实测重连。若仍失败须取得有界匿名阶段诊断，不能重复让用户无证据重连。系统原生AirPods弹窗正常保留。锁屏开发继续等待耳机收尾，定时器保持关闭。
