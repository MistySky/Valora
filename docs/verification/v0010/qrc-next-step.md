# QRC 逐字后续小任务

本次实测通过公开 `lyric_download.fcg` 获得了 `<result>0</result>` 和 HEX 形态的 `<content>`，但没有取得可读时间字段：

- 响应未包含明文逐字时间；
- `content` 为加密 HEX 载荷（本批只记录字符数和“看起来像 HEX”，未保存内容）；
- 统一报告字段：`decoded=false`、`decryption=not_implemented`；
- 没有用逐行 LRC 平均切字冒充逐字，也没有把 QRC 声明为已支持。

建议下一小任务只做 QRC 解密/格式验证：

1. 在不引入 GPL 代码的前提下独立实现或验证 3DES+zlib 解密；
2. 用同一公开样例核对解密后的 `[lineStart,lineDuration]word(start,duration)` 字段；
3. 增加离线 QRC fixture 与失败路径（错误 HEX、错误填充、解压失败、无逐字）；
4. 仍未接 UI，未接正常播放时间轴；完成并独立复核后再规划歌词呈现。
