# V0012-R3 独立验收

Codex独立166项测试通过（63+103），含立即取消保活与非合作provider deadline回归；独立构建/private/tmp/valora-independent-v0012-r3/Valora.app成功，codesign --verify --deep --strict通过。日志/private/tmp/valora-independent-v0012-r3-{test,build}.log。

源码核查：采样elapsed与同一Date已由MediaController写入model，歌词视图跨挂载读取该锚；取消先于attach有pendingResult保存；测量缓存包含身份与完整分段，并有索引保护。R3三项接受。歌词隔离QA运行产物见qa/，实际人声同步和物理双屏仍未实机验证。

歌词整体还剩一项已确认旧需求缺口，不能先清理：无逐字时间的LRC长句滚动被当前实现遗漏。LyricsLineContent.readingOffset依赖current，current在words为空时nil，故offset永为0；长句只有左端可见，后半句永远被裁。R1任务明确要求无逐字时保留逐行与合理长句滚动，不造逐字时间。按docs/pi-tasks/v0012-r4-line-only-overflow.md限定补齐，不扩展设置/歌词源。

独立歌词QA已完成：28/28通过，静态注入，不等同实机试听。
