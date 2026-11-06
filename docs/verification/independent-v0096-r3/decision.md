# V0096-R3 独立验收

日期：2026-11-05。结论：本轮外接屏位置修复接受；用户已反馈这版实看可以。

## 独立核验

- 读取 OpenCode 正式交付、报告、生产布局与协调器接线；externalReserveFraction 为 0.21，生产 place() 仍传 reserveFullExpansion: !(target?.isBuiltIn ?? false)，没有退回漏参数版。
- 1080pt 外接屏相对原点：顶部 466.8pt、歌词态底部 258.8pt、完全展开底部 226.8pt。相对 R2 下移 97.2pt，相对最初漏接线版上移 44pt。
- 独立运行 LockCardLayoutTests、LockMusicCoordinatorTests、MusicDisplayPolicyTests 定向测试，命令退出 0，通过。协调器通过注入显示器和 fake 窗口验证实际 setFrameOrigin 接线：外接 minY300/H1080 → panel.minY526.8；内置 H1117 →190.57。它不是物理锁屏实测；视觉判断采用本轮用户反馈。
- codesign --verify --strict --deep 通过；git diff --check 通过。
- 当前仅一个 Valora 进程：PID81948，路径 /private/tmp/valora-v0096-r3-reference-fraction-candidate/Valora.app/Contents/MacOS/Valora。
- 当前二进制 SHA256 e04d497ca173133937587f54581b03915113296aa9a9508b140f31a1724b7785，与交付一致，无需再次重启。

## 非阻断记录

报告“最初正常歌词底边216.8”应为214.8（422.8−208）；测试失败提示仍残留0.30文字，实际断言为526.8且生产为0.21。部分注释将产品参考线称为绝不遮挡头像，表述过强；21%不是系统头像边界，不保证所有屏幕均安全。上述文案留后续收尾统一修正，不影响本轮数值与用户已确认效果。

未全量测试、未闪窗循环或性能审计、未操作真实锁屏/媒体/权限；未改生产代码、未Git提交推送。其他未测试分辨率不扩大宣称实机通过。
