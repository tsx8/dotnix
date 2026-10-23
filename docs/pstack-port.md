# pstack 移植与内化

本文记录 [pstack](https://github.com/cursor/plugins) 移植到 Pi 的约束与维护流程。移植实现在 [packages/pi-pstack](../packages/pi-pstack/)，Pi 侧的宿主说明是 [pi.md](../packages/pi-pstack/pi.md)，装配与代理清单在 [Pi 模块](../modules/agents/pi/default.nix)。

## 定位

- 上游工作流的正文、原则和 playbook 结构原样保留；移植只替换宿主概念（命令前缀、子代理字段、模型来源、路径、不可用能力），不重写流程。
- 移植分三层：构建期文本变换（`prepare.mjs`）、手写绑定（`pi.md`）、Nix 侧装配（agent profile 表、模型偏好源、包加载清单）。
- 长期方向是内化。按能力逐步从“镜像上游”走到“自有实现”，判断依据见能力台账。

## 来源与固定

- 上游快照固定在 [package.nix](../packages/pi-pstack/package.nix) 的 `rev` 与 `hash`，不是 flake 输入，因此 `just repo update` 不会移动它。文本变换持有该版本的字面量，未审阅的升级只会让构建失败，不会产生错误内容。
- 更新没有程序化入口，也不属于批量更新：它是一次用户要求的移植任务，由用户提出，agent 按[移植流程](#移植流程)完成。构建失败或顺手更新都不是升级理由；未经用户要求不改动 `rev`。
- `pi-packages` 仍是 flake 输入。它的风险是 patch 上下文失配，失败信息直接指向 hunk，不需要人工判断语义，因此保留滚动更新。

## 不变量

分两类。程序化的由脚本执行，违反即构建失败；评审类无法由结构检查表达，每次移植按条目人工核对。

### 程序化

| ID | 不变量 | 落实位置 |
| --- | --- | --- |
| P1 | 上游生成的 Claude Code 树与其源一致 | `prepare.mjs` 调用上游 `generate-pstack-harness-trees.mjs --check` |
| P2 | 上游版本等于移植声明的版本 | `prepare.mjs` 的 `SUPPORTED_UPSTREAM` |
| P3 | 每条变换的命中数等于声明值，新增或丢失锚点都失败 | 各规则表的 `expect`，默认 1 |
| P4 | 面向 agent 的文本不残留 Cursor 专有工具、字段、路径、能力 | `remaining` 清单与 `validateGuidance` |
| P5 | 子代理只使用 Pi 字段与 Nix 声明的 profile 名 | `allowedSpawnFields`、`allowedSubagentTypes`、`validateCall`、`validateFencedMapping` |
| P6 | 不出现 Cursor 模型 ID 与快变体后缀 | `validateModelValue`、`validateGuidance` |
| P7 | 不出现裸技能命令（必须有 `/skill:` 前缀） | `bareCommandPattern` |
| P8 | 生成的计划文档只引用安装路径，不引用上游仓库路径 | `plan-installed-*` 规则与 `multi-phase-plan.md` 的额外检查 |
| P9 | 计划检查器的标记与测试样例同步 | `CHECK_PLAN_RULES` |
| P10 | agent 只输出 `.body.md`，指向 agent 文档的链接随之改写 | agents 输出循环与 `agent-body-links` |
| P11 | `worktree-audit.sh` 使用 GNU 工具参数 | `SCRIPT_RULES` |
| P12 | 变换后的脚本无需安装依赖即可启动 | commander 打包与 `.poteto-mode-tools-install-key` |
| P13 | 名称与命令只有一个来源 | profile 来自 Nix 的 `agentProfiles`；命令集合来自上游 `skills/` 目录加三个捆绑技能 |

### 评审

| ID | 约束 | 判据 |
| --- | --- | --- |
| R1 | 语义等价：只换宿主，不换流程 | 改写后的步骤数、顺序与原则正文可逐句对照上游；整段重写（如 `setup-pstack`）必须逐句核对，不能只看关键词 |
| R2 | 不可落地的能力标为 BLOCKED 或上游专属，不用扁平流程模拟 | 新能力先判断 Pi 能否真实执行；不能时检查生成文本是否留下“看起来能跑”的替代步骤 |
| R3 | 新技能和新段落先判断宿主差异 | 检查新增内容是否含宿主名、命令前缀、路径、模型 ID、子代理字段；只在需要时加规则 |
| R4 | 模型偏好语义与可编辑源机制一致 | 不得指示写入 `/nix/store`，不得替换托管链接为可写文件，偏好须经仓库修改、构建和用户批准才生效 |
| R5 | 文档按读者分层 | 面向 agent 的 skill 与 playbook 零 Cursor 残留；面向人的 README 与 guide 可保留 Cursor 概念，但须标明 Pi 的边界 |
| R6 | 能力台账随使用和移植更新 | 日常使用中发现能力缺口、冗余或冲突时记一条，不必等到下次移植；移植后复盘并决定新增、废弃或内化，不把结论留在会话里 |
| R7 | 一次提交只含移植 | 不与无关输入更新、配置改动混在同一提交，便于回滚与定位 |

## 移植流程

用户提出更新后进行，按顺序完成。

1. 取上游最新提交与版本：`git ls-remote https://github.com/cursor/plugins refs/heads/main` 得到 rev，`nix eval --raw --impure --expr '(builtins.fetchTree { type = "github"; owner = "cursor"; repo = "plugins"; rev = "<rev>"; }).outPath'` 得到源码路径，`nix hash path --sri <path>` 得到 hash，读 `harness/pstack/claude-code/plugin.json` 得到版本。
2. 读上游改动：在上游仓库中查看 `old..new` 之间触及 `harness/pstack/claude-code`、`pstack`、`cursor-team-kit` 的提交，先理解变更再看规则。
3. 把新的 rev 与 hash 写入 `package.nix`，构建该包得到漂移清单：`nix build --no-link --no-update-lock-file --no-write-lock-file .#pi-pstack`。
4. 逐条分类漂移：新文本判断是否需要规则（R3）、语义变化判断改写是否仍等价（R1）、能力变化判断是否需要 BLOCKED（R2）、锚点归零则重写规则。
5. 把 `SUPPORTED_UPSTREAM` 更新为目标版本，并把结论写进能力台账（R6）。
6. 运行 `just repo fmt`、`just os build`。
7. 单独提交，提交信息写明上游版本与本次移植类型。

单独构建该包只用于快速迭代；`just os build` 仍须在交付前运行。运行时行为（技能是否好用）不由这些检查覆盖，只能靠使用中的复盘，见台账。

## 能力台账

记录每个能力组的当前形态与下一步判断，随时可增改。使用数据来自本地会话索引，仅覆盖已索引的时间范围。

状态：**适配**（已移植且在用）、**待观察**（已移植但近期未使用）、**切断**（标记为不可用）、**上游专属**（明确不移植）。

| 能力组 | 状态 | 近期证据 | 下一步判断 |
| --- | --- | --- | --- |
| `poteto-mode` 与 playbook | 适配 | 25 个会话加载，主工作流 | 与本地验证、委派做法冲突时优先改写该 playbook，冲突反复出现则转为自有实现 |
| 原则索引 `principle-*`（24 个） | 适配 | 5 个被读过，其余未用 | 保持镜像，内化优先级最低；新增原则随上游滚动 |
| `how`、`why` | 适配 | 6 / 2 个会话 | 继续镜像，观察是否需要与 Obelisk 历史检索合并 |
| `architect`、`arena` | 适配 | `architect` 7 个会话，`arena` 未直接加载 | 模型角色表已由 `setup-pstack` 接管，是内化候选 |
| `no-comments`、`deslop`、`unslop`、`technical-writing` | 适配 | 5 / 2 / 5 / 3 个会话 | 与本仓库的注释和文档边界规则高度重合，评估合并成一份本地规则 |
| `comment-sicko` 等 agent 正文 | 适配 | 委派中使用 | frontmatter 已由 Nix 拥有，正文继续跟随上游 |
| `setup-pstack` | 适配 | 1 个会话 | 已按仓库的可编辑源重写，内化程度最高；上游改动此节时优先考虑本地化整节 |
| 验证类（`create-verification-skill`、`maintain-verification-skill`、正式验证两项、`tdd`、`benchmark-checklist`） | 待观察 | 未使用 | 使用后再判断；正式验证两项与 statechart 有重叠 |
| 编排类（`swarm`、`figure-it-out`、`orchestrate`、`autopilot-*`、`shipping`、`babysit`） | 部分切断 | 未使用；定时唤醒与嵌套委派已标 BLOCKED | 需要跨会话编排时，判断是补本地能力还是继续 BLOCKED |
| 会话与记录类（`recall`、`reflect`、`show-me-your-work`、`in-your-own-words`、`bro`、`sharpen`、`teach`、`correct`、`ketchup`、`blast-radius`、`automate-me`） | 待观察 | 多数未使用；`recall` 与 Obelisk 功能重叠 | `recall` 是切断候选，其余按使用情况保留 |
| `statechart` | 待观察 | 0.15.30 新增，未使用 | 需要画状态机或给非工程读者展示行为时再评估 |
| `make-bot-ui` | 切断 | 依赖 Cursor Grok Bot routines | 保持切断，除非 Pi 侧出现等价入口 |
| 捆绑技能 `deslop`、`control-cli`、`control-ui` | 适配 | `deslop` 2 个会话，`control-ui` 1 个 | 来自 `cursor-team-kit` 快照，与 pstack 版本解耦 |

内化判断沿用三条触发条件：同一段落连续两次移植都要改写；某项能力近期零使用且移植规则数达到三条以上；与本地已有能力重叠且本地能力更可控。
