# Claw Island — Architecture Notes

## Hook → Status → Color 映射

### 设计原则

Session 状态只在有意义的语义边界切换，不因实现细节产生无意义的中间状态。

### 完整映射表

| Hook 事件 | → 状态 | 颜色 | 含义 |
|-----------|--------|------|------|
| `session_start` | `.idle` | 灰白 | 刚连接，等待输入 |
| `user_prompt_submit` | `.running("thinking")` | 绿 | 收到消息，正在思考 |
| `pre_tool_use` | `.running(toolName)` | 绿 | 调用具体工具 |
| `post_tool_use` | 不变（保持 running） | 绿 | 工具返回，等下一步 |
| `pre_compact` | `.compacting` | 黄 | 压缩上下文 |
| `permission_request` | `.waitingApproval` | 橙 | 等待用户授权 |
| `notification` | `.notifying` | 紫 | Claude 主动通知 |
| `stop` | `.completed` | 蓝 | 本轮回答完成 |
| `session_end` | 5s 后移除行 | — | 进程退出 |
| `subagent_start/stop` | 不改状态，只改计数 | — | 子 agent |

### 关键决策

**`post_tool_use` 不重置为 idle**
早期版本在 `post_tool_use` 后 1.5s 回灰，目的是"让用户看清工具名"。
但工具名已显示在 row 里，1.5s 灰色只是噪音，且在 `stop` 到来前制造了无意义窗口。
现在 `post_tool_use` 什么都不做，保持 running，直到 `stop`。

**`user_prompt_submit` 进入 running("thinking")**
用户发消息后 Claude 正在思考，本质是 running 的前置阶段。
设为 idle 会导致"已完成→灰→绿"的闪烁，语义也不对。
合并进 running，整个对话周期颜色连续。

**idle 的唯一合法入口**
只有 `session_start` 会进入 `.idle`。其他情况不主动回灰。

### Stop vs SessionEnd

- `stop`：每次 Claude 回答完成都会触发，不代表会话结束，只改状态为 completed
- `session_end`：用户退出 claude 进程时触发，5s 后才移除 session 行（让"Done"可读）
