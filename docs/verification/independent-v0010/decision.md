# V0010 独立验收（2026-10-24）

结论：公开样例成功获取与匹配路径已独立确认；完整V0010暂未接受，须限定修复错误状态分类后再接歌词UI。

## 已确认

- 独立运行scripts/run_qq_lyrics_probe.sh，studio/live两例HTTP200，保守匹配分别studio0039MnYb0qxYhV、live004Fs2FP1EvZYc；逐行LRC63/36行，末时间262.86/239.43秒。
- QRC公开响应content为HEX9808/6784字符，未解码，不能声称逐字可用。
- 独立swift test113项通过（Valora35/Core78），独立构建签名及dist签名通过。
- 探针只显式样例，未接正常启动/UI，未读当前歌曲或账户，无真实媒体写操作。

## 需修复

独立URLProtocol模拟了HTTP503但带可解析歌词的body，fetchLyrics仍classification=timed_lrc；HTTP200但retcode/code1001并带相同fixture，也仍timed_lrc。见error-response-check.swift与error-response-result.txt。代码perform没有HTTP状态门控，fetchLyrics只记录业务码而未判断，搜索也只依赖body code，报告所称失败路径不充分。

须在HTTP非2xx、业务错误或无法判定响应形态时返回明确失败，不继续把错误响应作匹配/有效歌词，不把no lyrics与request failed混淆。加入可注入响应的离线测试，正常成功路径不退回，网络烟测保持手动运行，不靠exit0证明成功。V0010-R1修复后可独立接入逐行显示，逐字QRC另外按真实时间字段验证；现有QRC合成解析含无戳尾段补lineStart/0，不可当逐字真实时间用于UI。

后续歌词UI沿用现有QuickPeek下方区域和设置控件样式，暂停/seek/快速切歌与多屏取消必须核验，不改Valora品牌图标。尚未启动歌词UI。
