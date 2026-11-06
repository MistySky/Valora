# 歌词获取/匹配方案对照（V0012 补充）

本批只采用已经由当前公开样例验证的 QQ 链路；未引入 Go、未引入新依赖、未读取本地账户/曲库。

| 方案 | 定位歌曲 | 歌词端点/格式 | 匹配/回退 | 许可与采用 |
|---|---|---|---|---|
| LyricsKit (ddddxxx) | `client_search_cp` + songmid | `fcg_query_lyric_new`，LRC；旧代码兼容 JSONP/base64 | 搜索 term、LRC 解析 | MPL-2.0；只作协议/组织参考，未复制 |
| Lyrimuse (Yudaotor) | `client_search_cp`/smartbox + 客户端数字 ID；本地 SQLite 仅辅助 | `GetPlayLyricInfo`/`lyric_download.fcg`；QRC 3DES+zlib | 候选评分、版本/歌手/专辑/时长；QRC 优先 | GPL-3.0；未复制、未链接、未运行 Go/本地库 |
| 当前 Valora | 公开 `client_search_cp?new_json=1`，取 mid + 数字 ID | 真实 QRC 优先（`lyric_download`），失败退回 LRC | 标题/版本签名、请求歌手子集、专辑、时长；歧义拒绝 | Swift 6/URLSession；QRC DES 适配来自 MIT QQMusicDecoder |
| 网易云/酷狗/LRCLIB | 未接入 | 未在本批验证 | 不采用 | 无新依赖/账户；不能凭源码宣称可用 |

## 本批结论

- QQ 搜索、LRC 和 QRC 公开样例均已实测；QRC 真实解密得到 studio 63 行/602 words、live 36 行/391 words。
- 多歌手系统元数据（`胡夏`）与 QQ 合唱署名（`胡夏 / 郁可唯`）采用“请求歌手集合是候选歌手集合子集”的保守规则；标题版本、专辑、时长仍先过滤，男声版不会被 `contains` 或取第一首误配。
- 仍保持 3 秒总预算、失败不缓存、成功有界缓存、请求取消/去重；跨源回退未因“可能有帮助”而盲接。
