---
title: "WorkBuddy Skill 封装实战：以 QQ 群推送为例，将踩坑经验沉淀为可复用技能"
date: 2026-06-28T17:20:00+08:00
draft: false
description: "从散落脚本到标准化 Skill 的完整封装流程。以 qq-group-push 为例，讲解 init_skill.py 初始化、SKILL.md 编写、scripts/references 组织，以及如何让其他人或 AI 通过加载 Skill 即插即用"
categories: ["AI应用"]
tags: ["WorkBuddy", "Skill", "自动化", "知识沉淀", "QQ机器人", "botpy"]
keywords: ["WorkBuddy Skill封装", "QQ机器人技能", "botpy推送", "自动化技能模板", "WorkBuddy技能开发"]
series: ["AI工具链"]
---

> 前文 [WorkBuddy 自动化任务打通 QQ 消息推送](https://sikinzen.github.io/posts/workbuddyqqbotpush/) 详细记录了从企微失败到 QQ Bot 群推送打通的完整踩坑过程。本文在此基础上，讲解如何把这个折腾了两小时的方案**封装成一个标准 WorkBuddy Skill**，让后续任何人（或 AI）加载后即插即用。

## 为什么需要封装成 Skill

打通 QQ 推送后我们手里有的东西：

| 资产 | 形态 | 问题 |
|------|------|------|
| `qq_get_group_openid.py` | Python 脚本 | 散落文件，凭据写死在代码里 |
| `qq_send_group_msg.py` | Python 脚本 | 同上，用法靠人记 |
| 踩坑经验 | 大脑记忆 | 下次重装系统全忘光 |
| 集成到自动化任务 | Prompt 中写死路径 | 换个环境就要改 |

这些资产的共同问题：**不可复制、不可分发、不可维护**。

Skill 解决的就是这个——把代码、文档、踩坑经验打成一个包，放在 `~/.workbuddy/skills/` 目录下，WorkBuddy 的 AI 在合适的时机自动加载它。对人和 AI 都友好。

---

## Skill 的文件结构

一个标准 Skill 的目录结构如下：

```
~/.workbuddy/skills/<skill-name>/
├── SKILL.md              # 核心文件：AI 的行为指南 + 使用文档
├── scripts/              # 可执行脚本（Python、Shell 等）
│   ├── qq_get_group_openid.py
│   └── qq_send_group_msg.py
├── references/           # 参考资料（故障排查表、API 文档等）
│   └── troubleshooting.md
└── assets/               # 静态资源（模板文件、配置示例等）
    └── (按需使用)
```

**最关键的只有一个文件：`SKILL.md`**。它是 AI 加载 Skill 后读取的第一份文档，决定 AI 如何理解和使用这个 Skill。其余目录按需存在。

---

## 实战：将 qq-group-push 封装为 Skill

以下按实际操作顺序记录，可以直接复现。

### Step 1：初始化 Skill 目录

WorkBuddy 内置的 `skill-creator` 提供了 `init_skill.py` 脚本，自动生成标准骨架：

```bash
# 使用 WorkBuddy 的 managed Python（路径可能不同，用你自己的 Python）
python "C:/Users/<user>/AppData/Local/Programs/WorkBuddy/resources/app.asar.unpacked/resources/builtin-skills/skill-creator/scripts/init_skill.py" \
  qq-group-push \
  --path "C:/Users/<user>/.workbuddy/skills/"
```

执行后生成：

```
.workbuddy/skills/qq-group-push/
├── SKILL.md              # 模板文件，待填充
├── scripts/
│   └── example.py        # 示例脚本（可删除）
├── references/
│   └── api_reference.md  # 示例参考（可删除）
└── assets/
    └── example_asset.txt # 示例资源（可删除）
```

把自动生成的示例文件删掉：

```bash
rm scripts/example.py references/api_reference.md assets/example_asset.txt
```

### Step 2：将脚本复制进 `scripts/`

直接把两个已脱敏的 Python 脚本放进去（[qq_get_group_openid.py](/downloads/qq_get_group_openid.py) / [qq_send_group_msg.py](/downloads/qq_send_group_msg.py)）：

```bash
cp qq_get_group_openid.py ~/.workbuddy/skills/qq-group-push/scripts/
cp qq_send_group_msg.py  ~/.workbuddy/skills/qq-group-push/scripts/
```

> **脱敏要求**：复制前确认脚本中的 `APPID`、`SECRET` 等已替换为占位符（如 `YOUR_APPID`），不要带真实凭据。

### Step 3：编写故障排查参考 `references/troubleshooting.md`

这部分是整个封装过程中**投入产出比最高的环节**。之前踩过的 7 个坑（错误码 100016/340067、Intents 参数变化、botpy 导入路径、GBK 编码、沙箱文件写入、botpy.log 权限等），全部整理成一张按错误症状索引的排查表。

核心格式：**错误信息/错误码 → 根因分析 → 修复步骤**。例如：

```markdown
### 100016 — invalid appid or secret

**Cause:** AppID or AppSecret rejected by QQ server.

**Fix checklist:**
1. Go to QQ Open Platform → select bot → 开发设置
2. Verify AppID (pure digits, no spaces)
3. Click "Reset Secret" to get a fresh AppSecret (shown only once)
4. Ensure bot status is **已上线**, not **开发中**
```

> 完整排查表见附件 [qq-group-push-troubleshooting.md](/downloads/qq-group-push-troubleshooting.md)。

### Step 4：编写核心文件 `SKILL.md`

这是最需要花心思的部分。`SKILL.md` 由两部分组成：**YAML Front Matter**（给 WorkBuddy 系统读）和**Markdown 正文**（给 AI 和人读）。

#### 4.1 Front Matter 字段说明

```yaml
---
name: qq-group-push                    # Skill 标识名（kebab-case）
description: >                         # 触发条件 + 功能概述
  This skill enables WorkBuddy automation tasks to push messages to QQ groups
  via the official QQ Bot API. Use when the user wants to send QQ group
  messages from WorkBuddy automations. Triggers: QQ group push, QQ bot message,
  QQ 群推送, QQ 机器人发消息.
agent_created: true                    # 标记为 AI 创建，允许 SkillManage 修改
---
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | Skill 标识名，用 `kebab-case`（小写 + 连字符）。用户不说也可能触发，所以取名要表达用途 |
| `description` | 是 | **最重要**。WorkBuddy 根据此字段判断何时激活 Skill。必须包含：(1) 功能描述 (2) 触发关键词（中英文都要） |
| `agent_created` | 否 | 设为 `true` 后允许通过 `SkillManage` 更新/修改这个 Skill。AI 创建的 Skill 必须加此标记 |

> `description` 编写技巧：想象一个从未见过这个 Skill 的 AI，它只会看这段描述来决定"我要不要加载这个 Skill"。所以关键词越全越好，中英文都要覆盖。

#### 4.2 正文结构

正文推荐以下五段式结构（这是反复踩坑后沉淀的最佳实践）：

```markdown
# <Skill名称> — <一句话定位>

## Overview                          ← 一句话讲清楚这个 Skill 是干嘛的
## Prerequisites (one-time setup)    ← 一次性环境准备，明确列出所有前置依赖
## Step-by-Step Workflow             ← 核心：按操作顺序分步骤，每步包含命令和预期结果
## Important Technical Notes         ← 关键踩坑点：强制 WebSocket、GBK emoji、沙箱问题
## Scripts                           ← 每个脚本的入参、出参、依赖文件说明
## Integration Patterns              ← 三种典型的自动化任务集成方式
```

参考实际 [SKILL.md](/downloads/qq-group-push-SKILL.md) 的完整内容（已作为附件），特别注意以下几点：

1. **Prerequisites 要穷尽**：如果用户没装 `qq-botpy`，Skill 加载后 AI 会尝试 `pip install`，但前提是你在 SKILL.md 里写明了这个依赖
2. **Workflow 用祈使句**：每条操作指令直接可执行，不要加"你可以"、"建议你"这类前缀
3. **Technical Notes 即踩坑清单**：所有踩过的坑都写成"约束 + 解决方案"格式，AI 在遇到问题时会自动查这部分
4. **Integration Patterns 覆盖典型场景**：直接调脚本、文件模式、失败回退——三种就够了

#### 4.3 一段好的 SKILL.md 正文长什么样

以下截取自 `qq-group-push` 的 Step-by-Step Workflow 部分，展示"操作指令化"的正确写法：

```markdown
### Step 1: Capture group_openid

1. Edit `scripts/qq_get_group_openid.py`: replace `YOUR_APPID` and `YOUR_APPSECRET`
   with real credentials.
2. Run the script (background it - it listens for WebSocket events):

   ```bash
   python scripts/qq_get_group_openid.py
   ```

3. In the QQ group, send an @bot message (any content, e.g. "获取openid").
4. The script prints `GROUP_OPENID=<value>` to stdout, saves it to
   `qq_group_openid.txt`, and exits.
```

注意特征：
- **编号步骤** = 操作顺序不可乱的信号
- **代码块紧跟说明** = AI 可以直接 `bash` 执行
- **输入/输出明确声明** = 方便 AI 判断是否成功

### Step 5：清理与验证

```bash
# 删除空目录
rmdir assets/

# 确认最终结构
find ~/.workbuddy/skills/qq-group-push -type f
```

预期输出：

```
.workbuddy/skills/qq-group-push/SKILL.md
.workbuddy/skills/qq-group-push/scripts/qq_get_group_openid.py
.workbuddy/skills/qq-group-push/scripts/qq_send_group_msg.py
.workbuddy/skills/qq-group-push/references/troubleshooting.md
```

此时 Skill 已完成封装。WorkBuddy 下次识别到"QQ 推送"、"QQ 群发消息"等关键词时，会自动加载此 Skill。

---

## 将 Skill 集成到自动化任务

封装完成后，自动化任务的 prompt 中只需一行引用：

```
调用 QQ 群推送脚本发送消息：
python D:\Work\AI\AiMemory\Claw\qq_send_group_msg.py "消息内容"
```

因为 Skill 已经提供了完整的 `troubleshooting.md`，AI 在执行失败时会自动查阅错误码、对比根因、尝试修复（例如检测到 `100016` 错误时会提示检查 AppSecret 是否正确）。

而用户侧要做的，只是在第一次使用时：
1. 安装 `qq-botpy`
2. 注册 QQ Bot 获取凭据
3. 创建一个 QQ 群
4. 运行 `qq_get_group_openid.py` 获取群标识

即可在 10 分钟内完成从零到推送。

---

## 封装过程中踩到的坑

| 踩坑 | 根因 | 解决 |
|------|------|------|
| `init_skill.py` 创建后示例文件未清理 | 模板包含 `example.py` 等无意义的占位文件 | 立即 `rm` 掉，只保留三个核心文件 |
| SKILL.md 第一版 description 写得太简略 | WorkBuddy 靠 `description` 决定是否加载 Skill，关键词不全会导致"触发不了" | 中英文关键词全覆盖，用"Triggers:" 后缀明确列出 |
| `references/` 写成流水账而非排查表 | AI 读参考资料时是按错误码索引的，不是按叙事顺序 | 改为"症状→根因→修复"的三段式表格结构 |
| 忘记在 SKILL.md 里写 Prerequisites | AI 加载 Skill 后不知道要 `pip install qq-botpy`，执行脚本直接报 ImportError | 把 pip 安装命令写在 Prerequisites 的第一条 |
| Front Matter 漏了 `agent_created: true` | SkillManage 无法修改非 agent_created 的 Skill，后续改进会被拦截 | init 后立即补上该字段 |

---

## Skill 封装的标准流程（总结）

把以上实战抽象为一套可复用的 SOP：

```
1. init_skill.py        → 生成骨架目录
2. 清理示例文件          → 删 example.py / api_reference.md / example_asset.txt
3. 搬入脚本              → cp 到 scripts/
4. 编写 troubleshooting  → 按"症状→根因→修复"格式列出所有踩坑
5. 编写 SKILL.md         → 按五段式填充：Overview / Prerequisites / Workflow / Notes / Patterns
6. 补 agent_created      → Front Matter 加 agent_created: true
7. 验证触发              → 在 WorkBuddy 中用关键词测试是否自动加载 Skill
```

**花时间最多的是 Step 5 的 `description` 字段和 Step 4 的 troubleshooting**——这两个才是 Skill 的核心价值，代码只是载体。

---

## 附件下载

以下文件可直接下载使用（已脱敏，替换占位符即可）：

| 文件 | 下载 | 说明 |
|------|------|------|
| `SKILL.md` | [下载](/downloads/qq-group-push-SKILL.md) | QQ 群推送 Skill 的完整主文档（可直接放入 `~/.workbuddy/skills/`） |
| `qq_get_group_openid.py` | [下载](/downloads/qq_get_group_openid.py) | 获取 QQ 群 group_openid（WebSocket 事件监听） |
| `qq_send_group_msg.py` | [下载](/downloads/qq_send_group_msg.py) | 发送 QQ 群消息（WebSocket 连接 + 发送 + 退出） |
| `troubleshooting.md` | [下载](/downloads/qq-group-push-troubleshooting.md) | 7 个常见错误的排查速查表 |

> 附件中所有 `YOUR_APPID`、`YOUR_APPSECRET`、`YOUR_GROUP_OPENID` 均为占位符，使用前需替换为真实值。

---

## 相关资源

- [WorkBuddy 自动化任务打通 QQ 消息推送：完整踩坑实录](https://sikinzen.github.io/posts/workbuddyqqbotpush/) — 前篇：打通 QQ 推送的技术细节
- [QQ 开放平台 Bot API 文档](https://bot.q.qq.com/wiki/develop/api-v2/) — 官方 API 接口
- [botpy Python SDK](https://github.com/tencent-connect/botpy) — 腾讯官方 Python SDK
- [WorkBuddy Skill Creator](https://www.codebuddy.cn/docs/workbuddy/Overview) — Skill 创建官方指南
