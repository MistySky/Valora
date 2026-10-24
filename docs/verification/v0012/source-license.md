# V0012 QRC 来源与许可

## QQMusicDecoder (MIT)

V0012 的 `Sources/ReferenceCore/QQMusicQRC.swift` 中 QQ 特定 DES 位运算实现是
WXRIW/QQMusicDecoder 的 Swift 6 适配：

- https://github.com/WXRIW/QQMusicDecoder
- `QQMusicDecoder/DESHelper.cs`
- `QQMusicDecoder/Decrypter.cs`
- MIT License, Copyright (c) 2023 WXRIW

MIT 许可要求保留版权和许可声明；本项目在源码注释与本文档中保留来源。未复制
Lyrimuse（GPL-3.0）源码，也未引入 Go 引擎或第三方依赖。QRC 的 zlib 解压使用系统
`zlib`，不复制第三方解压实现。

## 真实 QRC 样例

`Tests/ReferenceCoreTests/Fixtures/qq-qrc-studio.hex` 是从 V0010/V0012 公开显式样例
（周杰伦《晴天》，`lyric_download.fcg`）取得的加密 HEX 载荷，仅用于离线解码测试；
不包含明文歌词，不包含账户/cookie/本地曲库数据。网络探针只输出行数、word 数量与首个
word 的 start/duration 摘要，不输出整首歌词。

## 参考实现边界

QRC 逐字时间只有在真实解密并通过 `[lineStart,lineDuration]word(start,duration)` 结构
校验后才进入 `LyricsFetchResult.wordTimed`；没有真实 word 时间时退回逐行 LRC，
不按整句平均分字。


## MIT License text

Copyright (c) 2023 WXRIW

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
