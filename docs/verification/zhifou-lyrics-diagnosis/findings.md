# 知否知否无歌词：只读独立诊断（2026-10-24）

用户明确要求诊断当前歌曲，已只读MediaRemote快照，无播放/切歌/seek/音量写操作。

当前系统元数据：title=知否知否，artist=胡夏，album=知否知否应是绿肥红瘦 电视剧原声带，duration=276秒，QQ来源。

按生产相同搜索查询得到HTTP200/code0，约0.93秒。候选第一条002krvKI4Jgvq9，title=知否知否，artist=胡夏 / 郁可唯，album相同、duration276；另有001qxsQM2CmqB2，title=知否知否 (男声版)，artist=胡夏，album与duration也相同。Live/伴奏/DJ等其他版本见search-summary.json。

从已推送Git基线c4771fc取出匹配器独立编译，对真实搜索候选运行，结果noMatch(artistMismatch)，见matcher-result.txt。生产匹配要求normalized(candidate.artist)==normalized(request.artist)，因此此处是元数据署名不完整与精确比较导致拒绝，不是接口没搜到。

只读请求第一条候选歌词HTTP200/retcode0/code0/has_lyric_payload=true，约0.198秒，见lyric-summary.json。仅保存结构摘要，未输出整首歌词。不能据此证明当前播的一定为合唱版而非系统丢失版本后缀的男声版。

并入V0012修复：识别多歌手署名的分隔符/顺序，不能只做整串相等；在标题版本/专辑/时长及其他可靠身份线索支持下允许唯一可信候选，否则无匹配/ambiguous，不靠contains或取第一条硬配。加入本例、明确男声版、合唱完整署名、同专辑同长度不同版本、Live/伴奏拒绝等回归。无确证身份时宁可按3秒规则隐藏，不能显示错误版本歌词。先给出匹配策略证据，不盲目放宽所有过滤。
