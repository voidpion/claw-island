# Claude Code Buddies

来源：https://variety.is/posts/claude-code-buddies/

## 激活方式

在 Claude Code v2.1.89+ 中输入 `/buddy`。
Buddy 由 `userId` + 固定 `SALT` 经确定性 PRNG 生成，每个账号固定分配一只。

---

## 物种（18 种）

每种有独特 ASCII art，含 3 帧动画：

| 物种 | 动画描述 |
|------|---------|
| duck | 尾巴轻摇 |
| goose | "长脖子，充满压迫感" |
| blob | 呼吸（膨胀/收缩） |
| cat | ω 嘴，尾巴甩动 |
| dragon | 第 3 帧喷烟 |
| octopus | 触手交替，墨水泡泡 |
| owl | 第 3 帧眨眼，脚步移动 |
| penguin | 鳍交替，蹦跳 |
| turtle | 壳纹路变化 |
| snail | 眼柄摇摆，单眼 |
| ghost | 底部波动，向上漂浮 |
| axolotl | 鳃朝不同方向摆动 |
| capybara | "平静，偶尔鼻孔抖动" |
| cactus | 手臂上下移动 |
| robot | 天线闪烁，嘴形变化 |
| rabbit | 耳朵下垂，鼻子抖动 |
| mushroom | 菌盖斑点移动，孢子飘散 |
| chonk | 耳朵轻弹，尾巴摇摆 |

---

## 属性

### 眼睛（6 种）
`·` `✦` `×` `◉` `@` `°`
依次：平静、闪亮、调皮、睁大、数字感、惊讶

### 帽子（8 种）
`none` · `crown` · `tophat` · `propeller` · `halo` · `wizard` · `beanie` · `tinyduck`
> Common 级别固定无帽，其他稀有度从完整列表中随机。

### 稀有度（5 档）

| 稀有度 | 基础属性下限 | 有帽子 | 属性峰值 |
|--------|------------|--------|---------|
| common | 5 | 否 | 55–84 |
| uncommon | 15 | 是 | 65–94 |
| rare | 25 | 是 | 75–100 |
| epic | 35 | 是 | 85–100 |
| legendary | 50 | 是 | 100 |

### 五维属性（目前纯展示）
`debugging` · `patience` · `chaos` · `wisdom` · `snark`

每只 buddy 有一个峰值属性和一个短板属性，"像宝可梦 IV，但不影响对战。"

### Shiny
独立于稀有度，1% 概率触发。目前仅标记，视觉暂未实现。Shiny Legendary 概率 = 0.01%。

---

## 名字与性格

通过 LLM 根据物种、属性、稀有度和 4 个随机"灵感词"生成。稀有度越高，名字越奇特。

名字单词，最多 12 字符，"令人印象深刻，略带荒诞感"。

**API 失败时的备用名：** Crumpet、Soup、Pickle、Biscuit、Moth、Gravy

---

## 反应（Reactions）

Buddy 会偶尔对你的 session 发表评论，通过：
```
POST /api/organizations/{org_uuid}/claude_code/buddy_react
```
请求携带名字、性格、物种、稀有度和五维属性，不计入使用配额。

---

## 自定义 UUID

可通过编辑 `~/.claude.json` 指定 buddy：
```json
{
  "oauthAccount": { "accountUuid": "your-uuid-here" },
  "companion": { "name": "Gristle", "personality": "..." }
}
```
PRNG 在 32-bit 空间运算（约 42.9 亿种状态），暴力枚举 UUID 在浏览器中可行。
