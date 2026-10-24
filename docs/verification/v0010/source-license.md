# V0010 参考来源与许可说明

本批只实现独立 Swift 6 协议探针和纯解析/匹配逻辑，没有把参考仓库作为运行时依赖，也没有引入 Go 引擎、第三方 Swift 包或 QQ 本地曲库读取。

## LyricsKit

- 文件：`Sources/LyricsService/Provider/QQMusic.swift`
- 地址：https://github.com/ddddxxx/LyricsKit/blob/master/Sources/LyricsService/Provider/QQMusic.swift
- 许可：Mozilla Public License 2.0（MPL-2.0）
- 使用方式：只参考公开的搜索/歌词接口路径与响应字段数量级；本项目的 Swift 解析、匹配、LRC/QRC 结构实现为重新编写，没有整段复制该文件。
- 未将 LyricsKit 源码、CXShim 依赖或 LyricsCore 类型打包进 Valora。

## Lyrimuse

- 文件：`lyrimuse-engine/qq.go`、`lyrimuse-engine/qqlocal.go`、`lyrimuse-engine/qqfallback.go`（协议观察）
- 地址：
  - https://github.com/Yudaotor/lyrimuse/blob/main/lyrimuse-engine/qq.go
  - https://github.com/Yudaotor/lyrimuse/blob/main/lyrimuse-engine/qqlocal.go
- 许可：GNU General Public License v3.0（GPL-3.0）
- 使用方式：只读取接口路径、公开 QRC 载荷形态和“本地曲库只能作为辅助线索”的边界说明；**没有复制、改编或链接任何 GPL 源码**。本批没有读取 QQ 本地数据库，没有使用 `qqlocal` 路径，也没有引入 Go 实现。
- QRC 密文只记录“存在、HEX 字符、未解码”，没有搬入或调用参考实现的解密代码。QRC 解密/逐字支持是独立后续任务，不能据此宣称逐字已可用。

## 腾讯 QQ 音乐接口

- 请求由独立探针手动发起，使用显式公开样例；未登录、未处理验证码、未读取用户账户/本地曲库/凭据/cookie。
- 探针使用 ephemeral URLSession，禁用 cookie 存储；日志只记录 HTTP 状态、字段结构和时间统计，不保存整首歌词、响应 Set-Cookie 或身份信息。
- 接口属于外部服务，随时可能变更或限制；V0010 只记录本次实测，不承诺长期可用或全曲库覆盖。
