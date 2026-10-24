# pi 文件派工扩展

安装日期：2026-10-23（Asia/Shanghai）。用户已在Valora完成新会话对话并要求安装派工组件。

- 目录：`/Users/wangqing/code/Valora`
- 会话：`01a1664f-f5e9-70bd-b053-21a027d5407a`
- 历史：`/Users/wangqing/.pi/agent/sessions/--Users-wangqing-code-Valora--/2026-10-23T01-11-18-762Z_01a1664f-f5e9-70bd-b053-21a027d5407a.jsonl`
- 模型：`opencode-go/deepseek-v4.1-flash`，思考级别`high`，不改动。

## 安装内容

从旧velora已用的文件派工实现复制并独立绑定上述目录/会话：

- `.pi/extensions/codex-dispatch/index.ts`：会话启动时轮询，关闭或reload时清理计时器。
- `.pi/extensions/codex-dispatch/mailbox.mjs`：核对会话、cwd、docs内任务路径、内容SHA256；空闲时经`pi.sendUserMessage`投递，先记认领防止重复执行。
- `scripts/pi-dispatch/mailbox.test.mjs`：投递与拒绝场景回归。

不修改全局配置、trust、认证、模型或会话历史，不启动第二个pi，不操作Otty。旧邮箱和请求未复制。本次只安装组件，不自动投递或重发旧迁移任务。

## 加载与核验

请在上述已打开的Valora pi会话执行`/reload`。若pi显示项目扩展信任提示，由用户核对后处理，不修改trust绕过。

安装不等于已加载。加载后`.pi/dispatch/status.json`应持续更新时间，sessionId/cwd与上述一致，空闲时state为ready。本次安装时尚无真实加载证据。

## 后续派工

限定任务保存于本目录`docs/pi-tasks/`；空邮箱时原子写入`.pi/dispatch/request.json`，字段为id、sessionId、taskFile（docs内相对路径）、sha256。sent回执仅代表消息投递；需核对真实会话历史、产物与报告，才能判断任务完成。claimed或error先人工核对历史，不自动重投。

产品任务继续以`MIGRATION-TASK.md`、`REQUIREMENTS.md`与`AGENTS.md`为准，源码迁移来源只读，安装本派工组件不代表安装应用。
