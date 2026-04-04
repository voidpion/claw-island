# Claw Island — Architecture Notes

## Hook → Status → Color 映射

### 设计原则

Session 状态只在有意义的语义边界切换，不因实现细节产生无意义的中间状态。

### 完整映射表

| Hook 事件 | → 状态 | 颜色 | 含义 |
|-----------|--------|------|------|
| `session_start` | `.idle` | 灰白 | 刚连接，等待输入 |
| `user_prompt_submit` | `.running("thinking")` | 蓝 | 收到消息，正在思考 |
| `pre_tool_use` | `.running(toolName)` | 蓝 | 调用具体工具 |
| `post_tool_use` | 不变（保持 running） | 蓝 | 工具返回，等下一步 |
| `pre_compact` | `.compacting` | 黄 | 压缩上下文 |
| `permission_request` | `.waitingApproval` | 橙 | 等待用户授权 |
| `notification` | `.notifying` | 紫 | Claude 主动通知 |
| `stop` | `.completed` | 绿 | 本轮回答完成 |
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

## UI 组件词汇表

### 整体结构

```
┌──────────────────── NotchPill（背景形状）────────────────────┐
│  NotchPillShape: 顶边全宽直角，底部两侧内圆角（半径 br）        │
│  topBleed: 窗口向上超出屏幕 6pt，实现无缝衔接                  │
│                                                              │
│  ┌─ compactBar（折叠态，始终可见）────────────────────────┐   │
│  │ 左翼              │ 中间缺口（硬件刘海） │ 右翼          │   │
│  │ AgentIcon + dots  │   （无内容）         │ session 计数  │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ expandedPanel（展开态）──────────────────────────────┐   │
│  │ divider（0.5pt 横线）                                  │   │
│  │ ┌─ SessionRowView ──────────────────────────────────┐ │   │
│  │ │ SessionAvatar │ title         │ modelBadge        │ │   │
│  │ │ （状态图标）   │ lastUserPrompt│ elapsedTimeBadge  │ │   │
│  │ │               │ subtitle      │                   │ │   │
│  │ ├─ ApprovalView（仅 waitingApproval 时出现）────────┤ │   │
│  │ │ tool_name + tool_input + [Allow] [Deny] [Ignore]  │ │   │
│  │ └───────────────────────────────────────────────────┘ │   │
│  └───────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 组件名称对照

| 名称 | 文件 | 说明 |
|------|------|------|
| **NotchPill** | NotchContentView | 背景视图，渐变填充 + 边框描边 |
| **NotchPillShape** | NotchContentView | Shape：顶边全宽直角，底部 convex 圆角（半径 br） |
| **compactBar** | NotchContentView | 折叠态横条，三段布局：左翼/中间缺口/右翼 |
| **AgentIcon** | NotchContentView | 左翼最左侧图标（waveform / 盾牌），有 approval 时脉冲橙色光晕 |
| **StatusDot** | NotchContentView | 左翼小圆点（6pt），每个 session 一个，running 时脉冲 |
| **expandedPanel** | NotchContentView | 展开面板：divider + ScrollView + SessionRowView 列表 |
| **SessionRowView** | SessionRowView | 展开态单行：头像 + 三行文字 + 右侧 badge |
| **SessionAvatar** | SessionRowView | 28×28 圆角方块，状态色边框 + 状态图标 + 脉冲光晕 |
| **ApprovalView** | ApprovalView | inline 审批面板：工具名 + 输入预览 + Allow/Deny/Ignore 按钮 |

### Session Row 文案显示规则

SessionRowView 在展开态下显示以下内容：

**第一行 — 标题** (`session.title`)
- 优先级：`customTitle` > 目录名 > shortId
- `customTitle`：首次 `user_prompt_submit` 时取前 40 字符，冻结不更新
- 目录名：从 `transcriptPath` 提取最后一层目录名
- shortId：session ID 前 8 位（兜底）

**第二行 — 最后用户输入** (`session.lastUserPrompt`)
- 仅当 `lastUserPrompt != nil` 时显示
- 格式：`You: xxx`（灰色，10.5pt）
- 来源：`user_prompt_submit` 时取前 60 字符

**第三行 — 状态副标题** (`session.subtitle`)

| 状态 | 显示 | 颜色 |
|------|------|------|
| idle | 仅 subagent > 0 时显示 `↳ N subagent(s)` | 灰白 |
| running(tool) | 工具描述如 `Bash: git status`；有 subagent 追加 `↳ N` | 蓝 |
| waitingApproval | `Awaiting approval…` | 橙 |
| notifying(msg) | 通知原文 | 紫 |
| compacting | `Compacting context…` | 黄 |
| completed | `Done · 3m` | 绿 |
| failed | `Failed` | 红 |

**右侧徽章**

| 徽章 | 来源 | 说明 |
|------|------|------|
| modelBadge | `session_start` 的 `model` 字段 | Claude Code 不总是发送此字段，可能缺失 |
| elapsedTimeBadge | `session.startTime` 到现在的时长 | 格式：`<1m` / `3m` / `1h`，始终显示 |

### NotchPillShape 顶角设计备忘

当前：顶角为直角（90°），与屏幕上边缘齐平，内容由 `clipShape(NotchPillShape)` 约束在可见区域内。

**曾用方案 — concave 顶角（已移除）**

顶角使用 quadratic bezier 向内凹弧，半径与底角相同（`br`）。路径逻辑：

```
左顶角：起点 (x, y) → 终点 (x+br, y+br)，控制点 (x+br, y)
右顶角：起点 (x+w, y) → 终点 (x+w-br, y+br)，控制点 (x+w-br, y)
```

控制点在形状外侧，曲线向内弯，产生"挖角"效果。设计意图是让 pill 像从屏幕边缘自然生长出来，与硬件 notch 边缘呼应。**代价**：凹弧区域是透明的，桌面内容会从顶角漏出。因此暂时改为直角，待找到合适的遮罩或合成方案后可重新引入。

### 两种状态

| | 折叠态（collapsed） | 展开态（expanded） |
|---|---|---|
| 宽度 | 2×notchWidth | 520pt |
| 形状 br | 12 | 20 |
| 内容 | compactBar only | compactBar + expandedPanel |
| 触发 | 默认 / 鼠标离开 | 鼠标悬停 / approval 请求 |
