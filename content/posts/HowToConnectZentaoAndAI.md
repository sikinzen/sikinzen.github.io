---
title: "让 AI 管理你的项目：禅道接入 AI 的两种方案"
date: 2026-06-08T21:10:00+08:00
draft: false
description: "从零打通 AI 助手与禅道项目管理系统的完整过程。涵盖两种方案：① ZenTaoMcp MCP Server（App 认证，只读）；② zentao-cli Web 登录（完整读写）。含实测诊断、踩坑记录与方案优劣对比"
summary: "记录将禅道项目管理系统接入 AI 助手的两种方案：方案一使用 ZenTaoMcp MCP Server（App 认证，读取正常但写入静默失败）；方案二使用 zentao-cli Web 登录（Session 认证，完整读写能力）。含完整踩坑记录与优劣对比"
categories: ["AI应用"]
tags: ["禅道", "ZenTao", "AI助手", "MCP", "项目管理"]
keywords: ["禅道AI", "ZenTaoMcp", "MCP Server", "项目管理AI", "禅道API", "zentao-cli"]
series: ["AI工具链"]
---

## 背景：为什么要把禅道接入 AI？

前两篇写了[个人微信](https://sikinzen.github.io/posts/howtoconnectwechatandai/)和[企业微信](https://sikinzen.github.io/posts/howtoconnectwecomandai/)接入 AI 的方案，解决的是**沟通数据**的 AI 化问题。但在日常工作中，还有一个信息密度极高的系统——**禅道**。

项目进度、Bug 追踪、需求管理、任务分配……这些结构化的项目管理数据如果能让 AI 直接读取和操作，就可以：

- 🐛 **快速查看和处理 Bug**（"帮我看看今天新提的 S1 Bug"）
- 📋 **跟踪项目进度**（"XX 项目当前完成度如何？"）
- 🔍 **全局搜索**（"搜索所有关于 XX 的需求"）
- 📝 **自动创建和分配任务**（"帮我建一个 Bug，标题 XX，指派给 XX"）⚠️ *方案一受限，见下文*
- 📊 **汇总项目数据**（"统计本月各项目的 Bug 数量"）

本文记录**两种**将禅道接入 AI 的完整方案，**不覆盖、不替代**，请根据实际需求选择：

| | 方案一 | 方案二 |
|---|--------|--------|
| **方式** | ZenTaoMcp MCP Server | zentao-cli Web 登录 |
| **认证** | App 认证（APP_CODE + APP_KEY） | Web 登录（账号密码 Session） |
| **读取** | ✅ | ✅ |
| **写入** | ❌ 静默失败 | ✅ 完整读写 |
| **部署难度** | ⭐⭐⭐（需编译 Go） | ⭐（Python 脚本，免编译） |
| **推荐场景** | 只读场景、多用户共享 | 需要写入、个人使用 |

> 🔴 **重要更新（2026-06-09）**：新增方案二（zentao-cli），解决方案一无法写入的根本问题。两种方案各有优劣，请根据场景选择。

---

## 先说结论：两种接入方案对比

| 对比项 | 方案一：ZenTaoMcp (MCP) | 方案二：zentao-cli (Web 登录) |
|--------|------------------------|-------------------------------|
| **核心思路** | 编译 Go 程序作为 MCP Server，通过 MCP 协议连接 | Python 脚本模拟 Web 登录，直接调用禅道表单接口 |
| **认证方式** | App 认证（APP_CODE + APP_KEY） | Web 登录（账号密码 → Session Cookie） |
| **读取能力** | ✅ 542 个工具，53 个模块全覆盖 | ✅ 项目/任务/Bug/迭代等常用模块 |
| **写入能力** | ❌ App 认证下静默失败 | ✅ 完整读写（Session 有用户身份） |
| **创建子任务** | ❌ 缺 parent 参数 + 路径 Bug | ✅ 两步法可创建（详见后文） |
| **工具数量** | 542 | ~10（按需扩展） |
| **部署难度** | ⭐⭐⭐（需 Go 环境 + 编译 + MCP 配置） | ⭐（Python 脚本，免编译） |
| **数据隔离** | 多人共用一个 App | 每人用自己的账号，天然隔离 |
| **凭据安全** | APP_KEY 长期不变 | 密码仅首次登录，后续用 Session |
| **稳定性** | ⭐⭐⭐（MCP 进程，自动重连） | ⭐⭐（Session 过期需重新登录） |
| **可扩展性** | ⭐⭐⭐（542 工具全覆盖） | ⭐⭐（需手写 Python 扩展） |
| **适用场景** | 纯读取、多人共享 | 需写入、个人使用 |

### 如何选择？

- **只需要读取禅道数据** → 选方案一（MCP），功能全面、稳定性好
- **需要创建/修改任务** → 必须选方案二（CLI），方案一写入静默失败
- **两者都要** → **方案一 + 方案二并行**，读取走 MCP（542 工具覆盖广），写入走 CLI（Session 有用户身份）

### 方案一内部的 MCP Server 选型

方案一（MCP 方式）内部还有几种实现可选：

| 对比项 | ZenTaoMcp (Go) | zentao-mcp-server (Node.js) | 自建 MCP Server |
|--------|----------------|------------------------------|-----------------|
| 语言 | Go | Node.js / TypeScript | 自选 |
| 工具数 | **542** | ~30 | 自定义 |
| 资源数 | 46 | 0 | 自定义 |
| 功能覆盖 | **53 个模块全覆盖** | 基础 CRUD | 按需 |
| 认证方式 | Token / App / Account | Account | 自定义 |
| 维护状态 | 活跃 | 较少更新 | 自维护 |
| 编译方式 | `go build` 生成单文件 | npm install | 自定义 |

**选择 ZenTaoMcp 的理由**：功能最全（542 工具覆盖 53 模块）、部署简单（Go 单文件）、认证灵活、活跃维护。

---

## 技术原理：两种方案的底层机制

### 方案一：禅道 REST API + MCP 协议

禅道从 18.0 版本开始提供标准的 REST API，支持 JSON 格式的请求和响应。核心认证方式有三种：

| 认证方式 | 说明 | 适用场景 | 实测状态 |
|----------|------|----------|----------|
| **Token** | 用户名密码登录获取 Token | 通用，最简单 | ⚠️ 未验证 |
| **App** | 管理员创建应用，获取 APP_CODE + APP_KEY | 服务端集成 | ✅ 读取正常 / ❌ 写入静默失败 |
| **Account** | 直接使用账号密码 | 临时调试 | ⚠️ 未验证 |

方案一采用 **App 认证**，因为：
- 不暴露用户密码
- 可细粒度控制权限
- Token 不会过期（APP_CODE + APP_KEY 长期有效）
- 适合 AI 助手持续调用

> ⚠️ **实测发现**：App 认证只能读取数据，创建/修改等写操作返回成功但数据未持久化。详见后文「实测诊断」章节。

MCP（Model Context Protocol）是连接 AI 助手与外部工具的标准协议。方案一的工作流程：

```
AI 助手 ↔ MCP Client ↔ MCP Server (stdio/SSE) ↔ 禅道 REST API
```

WorkBuddy 内置了 MCP Client，只需配置 MCP Server 的启动命令，就能自动发现和调用所有工具。

### 方案二：Web 表单接口 + Session 认证

方案二完全绕过了禅道的 REST API，转而**模拟浏览器操作**：

```
AI 助手 → Python 脚本 (zentao.py) → 禅道 Web 表单接口 → Session Cookie 认证
```

**核心原理**：

1. 用账号密码模拟浏览器登录禅道，获取 `zentaosid` Session Cookie
2. Session Cookie 关联了**用户身份**，与 App 认证的"应用身份"截然不同
3. 直接调用禅道的 Web 表单接口（如 `/task-create-{projectID}.json`），与浏览器中手动操作完全一致
4. 因为有用户身份，所有写操作（创建、编辑、关闭）都能正常执行

**为什么 Web 表单接口比 REST API 更可靠？**

| 维度 | REST API (`/api.php/v1/...`) | Web 表单接口 (`/task-create-*.json`) |
|------|------------------------------|--------------------------------------|
| 认证 | App Token 或 Session | Session Cookie |
| 写入 | App 认证下静默失败 | Session 下正常工作 |
| 文档 | 官方文档 | 无公开文档，需抓包逆向 |
| 稳定性 | 跟随版本更新 | 与 Web UI 同步，较稳定 |
| 覆盖 | 仅 v1 版本的模块 | 与 Web 界面功能完全对等 |

**代价**：Web 表单接口没有公开文档，参数名需通过浏览器开发者工具抓包获得。且存在一些反直觉的行为（如 ZenTao 12.5.2 的 `parent` 参数在创建时被忽略），需要逐一实测验证。

---

## 第一步：安装 Go 语言环境

ZenTaoMcp 是 Go 语言编写的，需要先安装 Go 来编译。

```bash
# 从阿里云镜像下载（国内速度更快）
# 访问 https://mirrors.aliyun.com/golang/ 选择对应版本
# 我用的是 go1.23.9.windows-amd64.zip

# 解压到指定目录
Expand-Archive -Path go1.23.9.windows-amd64.zip -DestinationPath D:\Software\AI\go\

# 验证安装
D:\Software\AI\go\go\bin\go.exe version
# 输出：go version go1.23.9 windows/amd64
```

> 💡 **为什么不下载预编译版本？** ZenTaoMcp 的 GitHub Releases 没有提供 Windows 预编译版本，需要自行从源码编译。Go 的编译速度很快，整个编译过程只需 1-2 分钟。

---

## 第二步：克隆并编译 ZenTaoMcp

```bash
cd D:\Software\AI

# 克隆源码
git clone https://github.com/bivex/ZenTaoMcp.git
cd ZenTaoMcp

# 设置 Go 代理（国内加速）
set GOPROXY=https://goproxy.cn,direct

# 编译
D:\Software\AI\go\go\bin\go.exe build -o zentao-mcp.exe ./src/
```

**编译输出：**

```
生成文件：D:\Software\AI\ZenTaoMcp\zentao-mcp.exe
文件大小：约 16MB
依赖版本：mark3labs/mcp-go v0.44.0-beta.1
```

编译完成后，就得到一个独立的 `zentao-mcp.exe`，不需要 Go 运行时，也不需要 Node.js，拷贝到任何 Windows 机器都能用。

---

## 第三步：验证 MCP Server

在配置到 WorkBuddy 之前，先验证 MCP Server 是否正常工作：

```bash
# 直接运行，查看启动信息
D:\Software\AI\ZenTaoMcp\zentao-mcp.exe --help

# 带环境变量运行（测试模式）
set ZENTAO_BASE_URL=http://你的禅道地址/api.php
set ZENTAO_APP_CODE=你的AppCode
set ZENTAO_APP_KEY=你的AppKey
set ZENTAO_AUTH_METHOD=app
set ZENTAO_ALLOW_INSECURE_HTTP=true

D:\Software\AI\ZenTaoMcp\zentao-mcp.exe
```

MCP Server 正常启动后，会通过 stdin/stdout 与 MCP Client 通信，不会输出任何内容到控制台（这是正常的）。

> ⚠️ **关键修正**：`ZENTAO_BASE_URL` **必须包含 `/api.php` 后缀**。如果只配置到根路径（如 `http://禅道地址:88`），MCP Server 构建的 URL 会缺少 `/api.php`，导致所有请求被重定向到登录页面。正确示例：`http://你的禅道地址:88/api.php`

---

## 第四步：配置禅道 App 认证

在禅道管理后台创建应用，获取 APP_CODE 和 APP_KEY：

1. 登录禅道管理后台
2. 进入 **后台 → 二次开发 → 应用**
3. 点击 **添加应用**
4. 填写应用名称（如 `AI-Assistant`）
5. 设置权限范围（建议按需开放，不要全部授权）
6. 保存后获得 **APP_CODE** 和 **APP_KEY**

> ⚠️ **安全提示**：APP_KEY 是敏感信息，不要硬编码在代码中或提交到版本库。通过环境变量传递是更安全的做法。

---

## 第五步：配置 WorkBuddy MCP 连接

在 WorkBuddy 的 MCP 配置文件中添加禅道服务器。

### 配置文件位置

```
C:\Users\<你的用户名>\.workbuddy\mcp.json
```

> 💡 **注意**：配置文件名是 `mcp.json`（不是 `.mcp.json`），位于 `~/.workbuddy/` 目录下。

### 配置内容

```json
{
  "mcpServers": {
    "zentao": {
      "command": "D:\\Software\\AI\\ZenTaoMcp\\zentao-mcp.exe",
      "env": {
        "ZENTAO_BASE_URL": "http://你的禅道地址:88/api.php",
        "ZENTAO_APP_CODE": "你的AppCode",
        "ZENTAO_APP_KEY": "你的AppKey",
        "ZENTAO_AUTH_METHOD": "app",
        "ZENTAO_ALLOW_INSECURE_HTTP": "true"
      }
    }
  }
}
```

### 环境变量说明

| 变量 | 说明 | 示例 | 注意事项 |
|------|------|------|----------|
| `ZENTAO_BASE_URL` | 禅道 API 地址 | `http://192.168.x.x:88/api.php` | **必须带 `/api.php` 后缀** |
| `ZENTAO_APP_CODE` | App 认证 Code | `MyApp` | — |
| `ZENTAO_APP_KEY` | App 认证 Key | `a1b2c3d4e5f6...` | 脱敏处理，勿提交版本库 |
| `ZENTAO_AUTH_METHOD` | 认证方式 | `app` | 仅 App 认证已实测 |
| `ZENTAO_ALLOW_INSECURE_HTTP` | 允许 HTTP（非 HTTPS） | `true` | 内网禅道通常为 HTTP |

> ⚠️ **路径转义**：Windows 路径中的反斜杠 `\` 在 JSON 中需要转义为 `\\`。建议用 Python `json.dump()` 写入配置文件，避免手动转义出错。

---

## 第六步：信任 MCP 服务器

配置完成后，MCP Server 不会自动激活，需要手动信任：

1. 打开 WorkBuddy 客户端
2. 进入**连接器管理**页面
3. 在顶部**自定义连接器**入口找到 `zentao`
4. 点击**信任**按钮激活
5. **重启 WorkBuddy 会话**使 MCP 生效

信任完成后，WorkBuddy 就能发现并调用禅道的 542 个工具了。

---

## 第七步：创建禅道 Skill

为了让 AI 助手更好地理解禅道的功能和使用方式，我创建了一个 Skill 文件。

### Skill 定义

在 `~/.workbuddy/skills/zentao/SKILL.md` 中定义，包含：

- **架构说明**：WorkBuddy → MCP → zentao-mcp.exe → 禅道 REST API
- **53 个功能模块**的分类说明
- **常用场景示例**：查看 Bug、项目进度、需求详情、创建任务等
- **环境变量**：完整的配置说明
- **故障排查**：连接超时、认证失败等常见问题
- **已知限制**：App 认证只读、MCP Server Bug 等（重要）

### 支持的功能模块（53 个）

核心模块一览：

| 类别 | 模块 | 说明 |
|------|------|------|
| **项目管理** | products / projects / executions / programs | 产品、项目、迭代、项目集 |
| **需求管理** | stories / epics | 需求/Story、史诗需求 |
| **任务管理** | tasks | 任务创建、分配、跟踪 |
| **Bug 管理** | bugs | Bug 列表、创建、解决、关闭 |
| **测试管理** | testcases / testtasks / testsuite / testreport | 用例、任务、套件、报告 |
| **发布管理** | plans / releases / builds | 发布计划、版本、构建 |
| **协作** | todos / docs / feedbacks / tickets | 待办、文档、反馈、工单 |
| **其他** | users / search / kanban / ai / bi / admin | 用户、搜索、看板、AI、看板、管理 |

### 使用方式

配置好 Skill 后，直接在 AI 助手对话中说：

```
帮我查看禅道上指派给我的 Bug          ✅ 已验证可用
帮我看看 XX 项目的进度                ✅ 已验证可用
帮我在禅道搜索 XX 关键词              ✅ 已验证可用
帮我在禅道创建一个 Bug：标题 XX        ❌ App 认证下写入静默失败
```

AI 助手会自动调用对应的 MCP 工具，查询并整理结果。

---

## 实测诊断：App 认证的真实能力边界

> 本章节基于 2026-06-08 晚间的完整实测，所有结论均经实际 API 调用验证。

### 一、App 认证：读取正常，写入静默失败

这是最关键的发现。我尝试了多种方式在禅道中创建子任务，所有写操作均返回成功响应，但数据未实际持久化：

| 测试方式 | 请求路径 | 响应 | 实际结果 |
|----------|----------|------|----------|
| MCP Server `create_task` 工具 | POST `/executions/{id}/tasks` | 空响应 200 | ❌ 未创建（另有路径转换 Bug） |
| App 认证 + 表单 POST | `api.php?m=task&f=create` | `{"result":"success","message":"保存成功"}` | ❌ 未创建 |
| App 认证 + JSON POST | `api.php?m=task&f=create` | 空响应 / Token 过期 | ❌ 未创建 |
| App 认证获取 Session 后提交 | `api.php?m=task&f=create` | 302 重定向到 `/my/` | ❌ 未创建 |
| REST API v1 | `api.php/v1/tasks` | `缺少code参数` / `Token已失效` | ❌ 未创建 |

**根因分析**：App 认证生成的 Session **未关联任何用户账户**。禅道的写操作需要用户身份上下文，App 认证只提供了"应用"身份，而非"用户"身份。因此：

- ✅ 读取操作正常 — 查看任务、Bug、需求、项目等
- ❌ 写入操作静默失败 — 返回成功但数据未持久化

> ⚠️ **"静默失败"是最危险的** — 如果不验证实际数据，很容易误以为操作成功。建议每次写操作后，立即用读操作确认数据是否真正存在。

### 二、ZENTAO_BASE_URL 必须包含 /api.php 后缀

这是一个很容易忽略的配置细节。MCP Server 的 `buildURL()` 方法会将 `ZENTAO_BASE_URL` 与查询参数直接拼接：

| ZENTAO_BASE_URL 配置 | 构建的 URL | 结果 |
|----------------------|-----------|------|
| `http://禅道地址:88` | `http://禅道地址:88?m=task&f=view&...` | ❌ 重定向到登录页 |
| `http://禅道地址:88/api.php` | `http://禅道地址:88/api.php?m=task&f=view&...` | ✅ 正常返回数据 |

不带 `/api.php` 时，请求命中禅道 Web 根路径，被重定向到登录页面。带 `/api.php` 后，走的是禅道的 API 入口，App 认证正常生效。

**修正后的正确配置：**
```json
"ZENTAO_BASE_URL": "http://你的禅道地址:88/api.php"
```

### 三、MCP Server 路径转换 Bug

ZenTaoMcp 的 `convertRESTPath()` 方法存在一个路径转换缺陷，影响任务创建等操作：

**Bug 表现：**

| REST 路径 | 期望转换 | 实际转换 | 结果 |
|-----------|---------|---------|------|
| POST `/executions/1692/tasks` | `?m=task&f=create&execution=1692` | `?m=execution&f=create` | ❌ 错误的模块和函数 |

**Bug 原因：** 当 POST 请求的路径为 `/executions/{id}/tasks` 时，`convertRESTPath()` 将 `executions` 映射为 module `execution`，但没有识别 `tasks` 作为子资源（subResource）。正确的行为应该是将 `tasks` 映射为 module `task`，并将 `execution` 作为参数传递。

**影响范围：** 所有涉及"父资源/ID/子资源"模式的创建操作可能受影响，不仅限于 tasks。

**状态：** 已确认但未修复 — 需修改 `src/client/client.go` 中的 `convertRESTPath()` 逻辑并重新编译。

### 四、create_task 工具缺少 parent 参数

即使修复了上述路径转换 Bug，`create_task` 工具仍无法创建**子任务**，因为工具定义中缺少 `parent` 参数：

```go
// 当前 create_task 工具定义（简化）
createTaskTool := mcp.NewTool("create_task",
    mcp.WithNumber("execution", mcp.Required()),
    mcp.WithString("name", mcp.Required()),
    mcp.WithString("type", mcp.Required(), mcp.Enum(...)),
    mcp.WithArray("assignedTo", mcp.Required()),
    mcp.WithString("estStarted", mcp.Required()),
    mcp.WithString("deadline", mcp.Required()),
    // ❌ 缺少 parent 参数 — 无法指定父任务 ID
)
```

**状态：** 已确认但未修复 — 需在 `src/tools/tasks.go` 中添加 `parent` 参数并重新编译。

### 五、网络代理干扰

如果本机运行了代理工具（如 Clash），Bash/curl 默认会走代理，导致内网禅道地址不可达：

```bash
# ❌ 默认走代理，内网地址不可达
curl http://禅道地址:88/api.php?m=task&f=view&taskID=1

# ✅ 显式绕过代理
curl --noproxy '*' http://禅道地址:88/api.php?m=task&f=view&taskID=1
```

MCP Server 作为 WorkBuddy 子进程运行，**不继承 Shell 的代理环境变量**，因此不受此影响。

### 六、首次信任 MCP 后 spawn ENAMETOOLONG 报错

在 WorkBuddy 中**首次信任 zentao MCP Server 后**，任何对话提问都会报如下错误：

```
MCP error -32603: spawn ENAMETOOLONG
```

**现象**：
- 信任 MCP 后立即使用 → 所有对话报错（不仅仅是调用禅道工具时）
- 关闭该 MCP 连接后重开 → 一切正常
- 后续重启会话也不再复现

**原因分析**：这是 **Windows 命令行长度限制**问题。WorkBuddy 在首次 spawn MCP Server 时，通过命令行参数传递 MCP 协议握手信息（包括工具列表、能力声明等）。ZenTaoMcp 注册了 542 个工具，序列化后的握手数据体量较大，导致命令行总长度超出 Windows 的 `MAX_PATH` / 命令行长度限制（约 32,767 字符），从而触发 `ENAMETOOLONG`。

**这不是 ZenTaoMcp 的 Bug** — 而是 MCP 工具数量过多时，Windows 平台上 stdio 传输的命令行长度瓶颈。工具数量较少的 MCP Server 不会触发此问题。

**解决方法**：

| 方法 | 操作 | 推荐度 |
|------|------|--------|
| 关闭重开 MCP | 在连接器管理中关闭 zentao，再重新开启 | ⭐⭐⭐ 首选 |
| 缩短 exe 路径 | 将 `zentao-mcp.exe` 移到更短路径（如 `D:\zt\zentao-mcp.exe`） | ⭐⭐ 辅助 |
| 等待客户端修复 | WorkBuddy 后续版本可能改用环境变量或临时文件传递握手数据 | ⭐ 长期方案 |

> 💡 **经验**：首次信任任何工具数量较多的 MCP Server 后，如果出现全对话报错，先尝试关闭重开该 MCP 连接，大概率是此问题。

### 实测结论汇总

| 能力 | App 认证状态 | 备注 |
|------|-------------|------|
| 查看任务详情 | ✅ 已验证 | `get_task` 返回完整数据含子任务 |
| 查看 Bug 列表 | ✅ 已验证 | — |
| 查看项目/迭代 | ✅ 已验证 | — |
| 全局搜索 | ✅ 已验证 | — |
| 查看统计数据 | ✅ 已验证 | — |
| 创建任务/子任务 | ❌ 静默失败 | 返回成功但数据未持久化 |
| 创建 Bug | ❌ 静默失败 | 同上 |
| 修改/关闭 Bug | ❌ 静默失败 | 同上 |
| 创建需求 | ❌ 静默失败 | 同上 |
| 任何写操作 | ❌ 静默失败 | App 认证 Session 无用户身份 |

---

## 写入能力的解决方案

方案一（MCP + App 认证）的写入静默失败是根本性限制。以下方案从"已验证"到"未验证"排列：

| 方案 | 原理 | 优点 | 缺点 | 验证状态 |
|------|------|------|------|----------|
| **E. zentao-cli Web 登录** | Python 脚本模拟浏览器登录，获取 Session | 完整读写，无需管理员操作 | 需暴露账号密码；需维护 Python 脚本 | ✅ **已验证可用** |
| **A. 提供用户凭据** | MCP Server 切换为 Session/Account 认证 | 完整读写能力 | 需暴露账号密码；需修复 MCP Server Bug | ⚠️ 部分验证 |
| **B. 管理员调整 App 权限** | 禅道后台为 App 授予写权限 | 不暴露用户凭据 | 不确定禅道是否支持此粒度 | ⚠️ 未验证 |
| **C. 修复 MCP Server + Session 认证** | 修复路径转换 Bug，添加 parent 参数，配合 Session 认证 | 技术层面完整 | 仍需用户凭据；需 Go 开发能力 | ⚠️ 待修复 |
| **D. 手动操作** | AI 读取 + 人工写入 | 最安全，零风险 | 无法自动化 | ✅ 可行 |

> 💡 **建议路径**：优先使用方案 E（zentao-cli），已经完整验证读写能力。如需 542 工具的全覆盖读取，可方案一（MCP）+ 方案二（CLI）并行。

---

## 完整架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        AI 助手                               │
│                    (WorkBuddy / 其他)                        │
└────────────┬──────────────────────────┬─────────────────────┘
             │                          │
    方案一：MCP 协议             方案二：Python CLI
             │                          │
             ▼                          ▼
┌────────────────────────┐  ┌─────────────────────────────────┐
│  zentao-mcp.exe (Go)   │  │  zentao.py (Python 脚本)        │
│  542 tools / 53 模块    │  │  Web 登录 + Session Cookie      │
│  App 认证（只读）        │  │  完整读写                        │
└────────────┬───────────┘  └────────────┬────────────────────┘
             │                           │
             │  REST API                 │  Web 表单接口
             │  App Token                │  Session Cookie
             ▼                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    禅道项目管理系统                           │
│              (http://禅道地址:88)                             │
│  ┌────────┬────────┬────────┬────────┐                      │
│  │ 产品   │ 项目   │ Bug    │ 需求   │                      │
│  ├────────┼────────┼────────┼────────┤                      │
│  │ 任务   │ 用例   │ 发布   │ 文档   │                      │
│  └────────┴────────┴────────┴────────┘                      │
│                                                             │
│  方案一(MCP)：✅ 读取正常 / ❌ 写入静默失败                    │
│  方案二(CLI)：✅ 读取正常 / ✅ 写入正常                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 三套系统对比：微信 / 企微 / 禅道

接入三个系统后，整体对比：

| 对比项 | 个人微信 | 企业微信 | 禅道（MCP + CLI） |
|--------|----------|----------|-------------------|
| 数据类型 | 非结构化聊天记录 | 非结构化聊天记录 + 组织架构 | **结构化项目数据** |
| 接入方式 | 本地数据库解密 | 本地数据库解密 | **REST API + Web 表单接口** |
| 加密难度 | ⭐⭐⭐⭐ (SQLCipher 4) | ⭐⭐ (wxSQLite3) | **⭐ (无加密，API 鉴权)** |
| 工具链 | wechat-cli + wx_key | wechat-decrypt | **ZenTaoMcp + zentao-cli** |
| AI 可操作性 | 只读 | 只读 | **MCP 只读 / CLI 完整读写** |
| 数据时效性 | 需重新解密 | 需重新解密 | **实时（API 调用）** |
| 网络要求 | 本地 | 本地 | **需要网络连通** |

**核心区别**：微信和企微是"破解本地数据库"，禅道是"调用官方 API / 模拟浏览器操作"。禅道接入更规范、更稳定。MCP 方式功能全面但只读；CLI 方式通过 Web 登录获取完整读写能力，弥补了 MCP 的根本缺陷。两者并行使用是最佳实践。

---

## 踩坑记录

| # | 问题 | 根本原因 | 解决方法 | 验证状态 |
|---|------|---------|---------|----------|
| 1 | GitHub Releases 没有 Windows 预编译版 | 作者只发布了 Linux/macOS 版本 | 自行从源码编译 `go build` | ✅ 已验证 |
| 2 | Go 下载慢（国内网络） | Go 官方 CDN 在国内速度慢 | 使用阿里云镜像 + `GOPROXY=https://goproxy.cn` | ✅ 已验证 |
| 3 | MCP 配置 JSON 路径转义错误 | Bash heredoc 会吞掉反斜杠 | 用 Python `json.dump()` 写入配置文件 | ✅ 已验证 |
| 4 | 禅道 API 连接超时 | 禅道在内网，AI 沙箱环境不在同一网络 | 需在公司网络或 VPN 环境使用 | ✅ 已验证 |
| 5 | `ZENTAO_ALLOW_INSECURE_HTTP` 未设置 | 禅道使用 HTTP 而非 HTTPS | 设置环境变量为 `true` | ✅ 已验证 |
| 6 | MCP Server 配置后未生效 | 需要手动信任并重启会话 | 在连接器管理中信任 zentao 服务器 | ✅ 已验证 |
| 7 | **读取操作返回登录页 HTML** | `ZENTAO_BASE_URL` 缺少 `/api.php` 后缀 | 配置为 `http://禅道地址:88/api.php` | ✅ 已验证 |
| 8 | **写操作返回"保存成功"但未生效** | App 认证 Session 无用户身份，写操作静默失败 | 切换为 Session/Account 认证，或手动操作 | ❌ 当前无法解决 |
| 9 | **MCP Server 创建任务发到错误 URL** | `convertRESTPath()` 对 `/executions/{id}/tasks` 转换错误 | 需修改 Go 源码 `client.go` 并重新编译 | ⚠️ 待修复 |
| 10 | **无法创建子任务** | `create_task` 工具缺少 `parent` 参数 | 需修改 Go 源码 `tasks.go` 并重新编译 | ⚠️ 待修复 |
| 11 | **内网 curl 失败但浏览器正常** | 本机代理工具拦截内网请求 | curl 加 `--noproxy '*'` | ✅ 已验证 |
| 12 | **MCP 配置文件路径错误** | Skill 文档中写的是 `.mcp.json`，实际应为 `mcp.json` | 修正文档为 `mcp.json` | ✅ 已验证 |
| 13 | **首次信任 MCP 后 spawn ENAMETOOLONG** | 542 个工具的握手数据超出 Windows 命令行长度限制 | 关闭重开 MCP 连接即可恢复 | ✅ 已验证 |
| 14 | **zentao-cli Session 过期后操作失败** | Session Cookie 有时效，过期后所有操作返回 401 | 重新执行 `login` 命令即可 | ✅ 已验证 |
| 15 | **创建子任务必须两步法** | ZenTao 12.5.2 的 `parent` 参数在创建时被忽略 | 先创建普通任务，再编辑设置 parent | ✅ 已验证 |
| 16 | **assignedTo vs assignedTo[] 混淆** | 创建接口用 `assignedTo[]`（带括号），编辑接口用 `assignedTo`（无括号） | 严格区分两个接口的字段名 | ✅ 已验证 |
| 17 | **POST 返回空 body** | 缺少 CSRF token (kuid) 导致 PHP 级错误 | 从创建/编辑页面 HTML 中提取 `uid` 隐藏字段 | ✅ 已验证 |
| 18 | **调试过程创建大量测试任务** | 每次试错直接调用 API，未先做 mock 测试 | 关闭测试任务清理；建议先在沙箱验证逻辑 | ✅ 已验证 |
| 19 | **关闭任务接口返回非标准 JSON** | `task-close` 接口可能返回 302 重定向或空响应 | 不依赖 JSON 解析，检查 HTTP 状态码 | ✅ 已验证 |

### 重点展开：问题 #8 —— App 认证写入静默失败

这是**最隐蔽、最危险**的问题。禅道的 App 认证 API 对写操作返回的响应与成功时完全一致：

```json
// App 认证创建任务 — 返回"成功"但数据未持久化
{"result":"success","message":"保存成功"}
```

如果不做二次验证（读取确认数据是否存在），很容易误以为操作成功。**建议所有通过 AI 执行的写操作，都必须在操作后立即用读操作验证数据是否真正写入。**

**底层原因**：禅道 App 认证的工作机制是：
1. 用 `APP_CODE` + `APP_KEY` + 时间戳 生成 Token
2. Token 用于 API 鉴权（相当于"应用身份"）
3. 写操作需要"用户身份"上下文，App 认证只提供"应用身份"
4. 禅道不返回权限错误，而是静默忽略写操作

**可能的解决方向**：
- 切换为 Account 认证（直接传用户名密码）
- 切换为 Session 认证（先登录获取 Session ID）
- 在禅道后台为 App 开放写权限（需确认是否支持）
- 手动操作，AI 仅做读取辅助

### 重点展开：问题 #7 —— ZENTAO_BASE_URL 的 /api.php 后缀

这是一个配置级别的坑。MCP Server 的 URL 拼接逻辑为：

```
最终URL = ZENTAO_BASE_URL + "?" + 查询参数
```

| 配置 | 拼接结果 | 效果 |
|------|---------|------|
| `http://禅道地址:88` | `http://禅道地址:88?m=task&f=view` | ❌ 命中 Web 根路径，重定向到登录页 |
| `http://禅道地址:88/api.php` | `http://禅道地址:88/api.php?m=task&f=view` | ✅ 命中 API 入口，App 认证生效 |

**这不是 MCP Server 的 Bug** — 禅道的 API 确实以 `/api.php` 为入口，只是文档中没有明确说明这个配置要求。

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **App 认证只读** — App 认证模式下，所有写操作（创建/修改/删除）静默失败。不要依赖 API 返回的"成功"消息，必须二次验证 ❌ 当前已确认
2. **写入静默失败** — 这是最危险的：API 返回成功但数据未持久化，容易造成误判
3. **数据安全** — 禅道数据包含项目进度、Bug 详情、需求文档等，属于企业内部信息
4. **操作审计** — 通过 AI 执行的写操作（如果后续切换为 Session 认证）应可追溯
5. **网络暴露** — 如果将禅道 API 暴露到公网，务必配置 HTTPS + IP 白名单
6. **凭据安全** — APP_KEY 不要硬编码、不要提交到版本库，通过环境变量传递
7. **版本兼容** — ZenTaoMcp 基于禅道 18.0+ 的 API，低版本禅道可能不完全兼容
8. **MCP Server Bug** — 路径转换缺陷和 `parent` 参数缺失是已知问题，需源码修复

**建议：**

- 初期使用 App 认证的**只读模式**，确认数据读取稳定可靠
- 如需写入，优先确认禅道管理员能否为 App 开放写权限
- 定期检查禅道后台的**应用调用日志**
- APP_KEY 定期**轮换**
- 发布博客或文章时，**不要暴露真实的 API 地址、APP_CODE、APP_KEY**
- 所有 AI 执行的写操作，**必须做二次读取验证**

---

## 总结

### 方案一：ZenTaoMcp MCP Server

| 环节 | 工具 | 难度 | 实测状态 | 备注 |
|------|------|------|----------|------|
| 安装 Go | 官方/镜像下载 | ⭐ | ✅ | 国内用阿里云镜像加速 |
| 编译 ZenTaoMcp | go build | ⭐ | ✅ | 单文件输出，约 16MB |
| 配置禅道 App 认证 | 禅道后台 | ⭐ | ✅ | 记录 APP_CODE 和 APP_KEY |
| 配置 WorkBuddy MCP | mcp.json | ⭐⭐ | ✅ | 注意 `/api.php` 后缀和路径转义 |
| 信任 MCP 服务器 | WorkBuddy UI | ⭐ | ✅ | 首次信任后关闭重开，避免 ENAMETOOLONG |
| 创建 Skill | SKILL.md | ⭐⭐ | ✅ | 一次配置，长期使用 |
| 读取操作 | App 认证 | ⭐⭐ | ✅ | 正常工作 |
| 写入操作 | App 认证 | — | ❌ | 静默失败，需 Session 认证 |
| 创建子任务 | MCP Server | — | ❌ | 缺少 parent 参数 + 路径转换 Bug |
| 网络连通 | VPN / 内网 | ⭐⭐⭐ | ✅ | 最常见的障碍，注意代理干扰 |

### 方案二：zentao-cli Web 登录

| 环节 | 工具 | 难度 | 实测状态 | 备注 |
|------|------|------|----------|------|
| 部署脚本 | zentao.py | ⭐ | ✅ | Python 脚本，免编译 |
| 登录 | account + password | ⭐ | ✅ | Session Cookie 认证 |
| 读取操作 | Web 接口 | ⭐⭐ | ✅ | 项目/任务/Bug/迭代 |
| 写入操作 | Web 表单接口 | ⭐⭐ | ✅ | 创建/编辑/关闭任务 |
| 创建子任务 | 两步法 | ⭐⭐⭐ | ✅ | ZenTao 12.5.2 Bug，需先创建再编辑 |
| 关闭任务 | task-close 接口 | ⭐⭐ | ✅ | 注意非标准 JSON 响应 |
| Session 管理 | 自动 | ⭐ | ✅ | 过期后重新 login |
| 网络连通 | requests 库 | ⭐ | ✅ | 不受系统代理影响 |

### 最佳实践：方案一 + 方案二并行

```
读取 → 方案一（MCP，542 工具，覆盖广）
写入 → 方案二（CLI，Session 认证，完整读写）
```

**核心收获**：禅道接入 AI 的本质是"标准化 API 对接"，不像微信/企微需要破解本地数据库。方案一（MCP）提供了 542 个工具的单文件部署方案，一次编译覆盖禅道全部 53 个功能模块，但 **App 认证只能读取，写入静默失败**。方案二（zentao-cli）通过 Web 登录获取 Session，解决了写入问题，且部署更简单（Python 脚本免编译），但功能覆盖面不如 MCP 全面。两者并行是当前最优解——读取走 MCP 的广覆盖，写入走 CLI 的完整权限。

---

## 方案二详解：zentao-cli Web 登录方式

> 以下内容基于 2026-06-09 晚间的完整实测，所有结论均经实际 API 调用验证。

### 方案二的诞生背景

方案一（MCP + App 认证）的写入静默失败是**根本性限制**——App 认证的 Session 不关联任何用户账户，禅道的写操作需要用户身份上下文。与其等待 MCP Server 修复 + 切换认证方式，不如直接模拟浏览器的行为：**用账号密码登录 → 获取 Session Cookie → 调用 Web 表单接口**。

这就是方案二的思路——绕过 REST API，走与浏览器完全一致的操作路径。

### 安装与部署

方案二的核心是一个 Python 脚本 `zentao.py`，部署步骤极其简单：

**1. 确保 Python 环境可用**

```bash
# 验证 Python 3 已安装
python3 --version
# 输出：Python 3.x.x
```

**2. 安装依赖**

```bash
pip install requests
```

> 💡 `zentao.py` 仅依赖 `requests`，无其他第三方库。

**3. 部署脚本到 Skill 目录**

```
~/.workbuddy/skills/zentao-cli/
├── SKILL.md        # Skill 定义（AI 助手使用说明）
└── zentao.py       # Python 脚本（核心逻辑）
```

无需编译，无需 Go 环境，无需 MCP 配置。

### 首次使用：登录

```bash
python3 ~/.workbuddy/skills/zentao-cli/zentao.py \
  --account 你的账号 --password 你的密码 login
```

登录成功后：
- Session Cookie 自动缓存到 `~/.workbuddy/zentao_cli_config.json`
- 后续调用只需 `--account 你的账号`，脚本自动读取缓存

### 常用操作

```bash
# 查看个人信息
python3 zentao.py --account 你的账号 whoami

# 查看我的任务
python3 zentao.py --account 你的账号 tasks

# 查看我的 Bug
python3 zentao.py --account 你的账号 bugs

# 查看项目列表
python3 zentao.py --account 你的账号 projects

# 搜索项目
python3 zentao.py --account 你的账号 projects -k 关键词

# 查看项目详情
python3 zentao.py --account 你的账号 view 项目ID
```

### 关键能力：创建子任务（两步法）

方案二最大的价值在于**写入能力**。但创建子任务有一个 ZenTao 12.5.2 的已知 Bug，需要分两步完成：

**为什么不能一步创建？**

在禅道 12.5.2 中，`task-create` 接口的 `parent` 参数会被静默忽略——即使 POST body 中包含 `parent=38328`，创建出的任务 `parent` 仍为 `0`（普通任务）。

**两步法操作：**

```python
import requests, json, re

ZENTAO_URL = 'http://你的禅道地址:88'
session = requests.Session()

# === 先登录获取 Session ===
resp = session.get(f'{ZENTAO_URL}/api-getSessionID.json')
inner = json.loads(resp.json().get('data', '{}'))
sid = inner.get('sessionID', '')
session.get(f'{ZENTAO_URL}/user-login.json?account=你的账号&password=你的密码&zentaosid={sid}')

# === Step 1: 创建普通任务（不带 parent）===
# 从创建页面获取 CSRF token (kuid)
resp = session.get(f'{ZENTAO_URL}/task-create-{projectID}.html')
kuid = re.search(r'name="uid"\s+value="([^"]+)"', resp.text).group(1)

r = session.post(f'{ZENTAO_URL}/task-create-{projectID}.json?onlybody=yes', data={
    'uid': kuid,
    'project': str(projectID),
    'type': 'devel',
    'name': '任务名称',
    'desc': '任务描述',
    'assignedTo[]': '用户名',  # 注意：创建用 assignedTo[]（带括号）
    'estStarted': '2026-06-09',
    'deadline': '2026-06-16',
    'estimate': '4',
    'pri': '3',
    'status': 'wait',
    'module': '0',
})
# 创建成功后，从项目任务列表中找到新任务的 ID

# === Step 2: 编辑设置 parent ===
# 从编辑页面获取新的 kuid
resp = session.get(f'{ZENTAO_URL}/task-edit-{newTaskID}.html')
kuid = re.search(r'name="uid"\s+value="([^"]+)"', resp.text).group(1)

r = session.post(f'{ZENTAO_URL}/task-edit-{newTaskID}.json?onlybody=yes', data={
    'uid': kuid,
    'parent': str(parentTaskID),  # 关键：设置父任务
    'name': '任务名称',
    'type': 'devel',
    'desc': '任务描述',
    'assignedTo': '用户名',  # 注意：编辑用 assignedTo（无括号）
    'estStarted': '2026-06-09',
    'deadline': '2026-06-16',
    'estimate': '4',
    'pri': '3',
    'status': 'wait',
    'module': '0',
    'comment': '',
})
```

**实测验证**：以上两步法已成功在 task-38328 下创建子任务 #39109 "TestZentao"，指派给 llizhong。

### 关键注意事项

| 陷阱 | 说明 | 影响 |
|------|------|------|
| **parent 在创建时被忽略** | `task-create` 接口的 `parent` 参数静默丢弃 | 必须用两步法 |
| **assignedTo vs assignedTo[]** | 创建接口用 `assignedTo[]`，编辑接口用 `assignedTo` | 字段名不一致，混用会失败 |
| **CSRF token (kuid)** | 必须从创建/编辑页面 HTML 中提取 `uid` 隐藏字段 | 缺少则 PHP 报错，返回空 body |
| **Session 过期** | Cookie 有时效，过期后所有操作返回 401 | 重新 login 即可 |
| **关闭任务非标准响应** | `task-close` 接口可能返回 302 重定向 | 不依赖 JSON 解析，检查状态码 |

### 已验证能力汇总（2026-06-09）

| 能力 | 状态 | 备注 |
|------|------|------|
| Web 登录 | ✅ | Session Cookie 认证，role: sw |
| 项目列表 | ✅ | 1599 个项目可读 |
| 我的任务 | ✅ | — |
| 我的 Bug | ✅ | — |
| 创建普通任务 | ✅ | 一步完成 |
| 创建子任务 | ✅ | 两步法（ZenTao 12.5.2 Bug） |
| 编辑任务 | ✅ | 修改名称、指派人、父任务等 |
| 关闭任务 | ✅ | task-close 接口，注意非标准响应 |
| 搜索项目 | ✅ | 关键词搜索 |
| 查看项目详情 | ✅ | — |

### 方案二与方案一的详细对比

| 维度 | 方案一：ZenTaoMcp (MCP) | 方案二：zentao-cli (Web 登录) |
|------|------------------------|-------------------------------|
| **部署** | 需 Go 环境 + 编译 + MCP 配置 + 信任 | Python 脚本，pip install requests 即可 |
| **认证** | APP_CODE + APP_KEY（管理员创建） | 账号密码（个人即可） |
| **读取** | ✅ 542 工具，53 模块全覆盖 | ✅ 常用模块（项目/任务/Bug/迭代） |
| **写入** | ❌ App 认证静默失败 | ✅ 完整读写（Session 有用户身份） |
| **创建子任务** | ❌ 缺 parent 参数 + 路径 Bug | ✅ 两步法可用 |
| **数据隔离** | 多人共用一个 App | 每人用自己的账号，天然隔离 |
| **凭据管理** | APP_KEY 长期不变，集中管理 | 密码仅首次登录，后续用 Session |
| **功能覆盖** | ⭐⭐⭐⭐⭐（542 工具） | ⭐⭐⭐（常用功能，需手写扩展） |
| **稳定性** | ⭐⭐⭐（MCP 进程，自动重连） | ⭐⭐（Session 过期需重新登录） |
| **代理兼容** | MCP 不继承 Shell 代理 | requests 不走系统代理，内网直通 |
| **调试难度** | ⭐⭐⭐（需看 MCP 日志 + Go 源码） | ⭐⭐（Python 脚本，可逐步调试） |
| **适用场景** | 只读、多人共享、全模块覆盖 | 写入、个人使用、快速部署 |

**推荐策略**：方案一 + 方案二并行。日常查询走方案一（MCP 覆盖广、稳定），需要写入时走方案二（CLI 完整读写）。两者互补，不冲突。

---

---

## 系列文章（AI 工具链）

本博客「AI 工具链」系列，教你把各类研发工具接入 AI 助手（悟空）：

- [让 AI 管理你的代码仓库：Gitea MCP Server 接入指南](https://sikinzen.github.io/posts/howtoconnectgiteaandai/)
- [让 AI 帮你管代码评审：Gerrit 接入指南](https://sikinzen.github.io/posts/howtoconnectgerritandai/)
- [让 AI 管理你的项目：禅道接入指南](https://sikinzen.github.io/posts/howtoconnectzentaoandai/)
- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](https://sikinzen.github.io/posts/howtoconnectwechatandai/)
- [让 AI 读懂你的企业微信：wechat-decrypt 接入指南](https://sikinzen.github.io/posts/howtoconnectwecomandai/)
- [在 WorkBuddy 中通过 REST API 操作 Jenkins：原理与实战](https://sikinzen.github.io/posts/howtoconnectjenkinsandai/)
- [在 Jenkins 上搭建基于 Docker 的编译流水线：手把手教程](https://sikinzen.github.io/posts/howtobuildjenkinscompilejob/)
