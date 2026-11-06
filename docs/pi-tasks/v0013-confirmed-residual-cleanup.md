# V0013：歌词验收后的限定代码清理

本任务只有收到文件邮箱派工后才执行；写出任务文件不代表前一批已接受。先读AGENTS.md、docs/CONTINUATION-PLAN.md、docs/verification/independent-v0012-r3/decision.md。本轮范围歌词收尾→清理→流畅度，不进入设备。

用户要求清理代码，保持已接受的功能/外观不变，不为了减行数重构成熟底座。只删确定无引用的专用残留并纠正过时注释；先核rg/调用链证据，列清单，再做最小修改。已发现候选（仍须你核验）：

- Sources/Valora/Models.swift中的lyricFallbackText属性，旧失败显示歌名策略已取消，当前rg仅定义；如确认无引用可删。
- Sources/Valora/WindowCoordinator.swift约453行未使用的局部generation，编译警告；勿删除实际hover generation保护或改变时序。
- LyricsService注释仍称line-lyric且无QRC解密，纠正为当前真实路径及MIT来源，勿删除许可。
- 只清本批可证明无用的变量、私有残留/重复逻辑；没有足够证据就保留并解释。不要为了凑工作量删除测试、QA命令或重写架构。

不要删基线、用户资源、应用/菜单栏旧候选资源、历史任务/验收证据、QRC fixture、第三方许可/来源或其他项目文件。不清整目录/磁盘缓存，不把gitignore产物当用户授权删除。无Git提交推送，不安装发布，不改来源归档，不操作真实媒体/系统设置/设备。保留Brand/Outline-v7及原设置UI。

交付docs/reports/v0013.md，逐项给删除/修改位置、无引用证据及保留项理由；swift test、构建签名，若无行为变化不重复网络探针。测试已有意义回归，不写只验证删除行数的测试。完成后停止，等Codex独立验收；流畅度将另批派工。
