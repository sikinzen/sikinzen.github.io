---
title: "让 AI 管理你的项目：禅道 ZenTaoMcp 接入指南"
date: 2026-06-08T21:10:00+08:00
draft: false
description: "从零打通 AI 助手与禅道项目管理系统的完整过程，基于 ZenTaoMcp MCP Server，542 个工具覆盖全部 53 个功能模块。含 App 认证实测诊断与已知限制"
summary: "记录将禅道项目管理系统接入 AI 助手的完整过程，使用 Go 编写的 ZenTaoMcp 作为 MCP Server。包含 App 认证实测结果：读取正常但写入静默失败，MCP Server 路径转换 Bug 等关键发现"
categories: ["AI应用"]
tags: ["禅道", "ZenTao", "AI助手", "MCP", "项目管理"]
keywords: ["禅道AI", "ZenTaoMcp", "MCP Server", "项目管理AI", "禅道API"]
series: ["AI工具链"]
---

## 背景：为什么要把禅道接入 AI？

前两篇写了[个人微信](https://sikinzen.github.io/posts/howtoconnectwechatandai/)和[企业微信](https://sikinzen.github.io/posts/howtoconnectwecomandai/)接入 AI 的方案，解决的是**沟通数据**的 AI 化问题。但在日常工作中，还有一个信息密度极高的系统——**禅道**。

项目进度、Bug 追踪、需求管理、任务分配……这些结构化的项目管理数据如果能让 AI 直接读取和操作，就可以：

- 🐛 **快速查看和处理 Bug**（"帮我看看今天新提的 S1 Bug"）
- 📋 **跟踪项目进度**（"XX 项目当前完成度如何？"）
- 🔍 **全局搜索**（"搜索所有关于 XX 的需求"）
- 📝 **自动创建和分配任务**（"帮我建一个 Bug，标题 XX，指派给 XX"）⚠️ *实测受限，见下文*
- 📊 **汇总项目数据**（"统计本月各项目的 Bug 数量"）

好消息是：禅道提供了完整的 REST API，而且社区已经有了成熟的 MCP Server 实现——**ZenTaoMcp**，一次编译即可覆盖全部 542 个工具。

> 🔴 **重要更新（2026-06-08）**：经过完整实测，发现 App 认证模式下**写入操作静默失败**（返回"保存成功"但数据未持久化），以及 MCP Server 存在路径转换 Bug。本文已更新所有实测结论，请在部署前务必阅读「实测诊断」章节。

---

## 先说结论：三种接入方案对比

在决定技术路线之前，我调研了三种接入禅道的方案：

| 对比项 | 方案 A：ZenTaoMcp (Go) | 方案 B：zentao-mcp-server (Node.js) | 方案 C：自建 MCP Server |
|--------|------------------------|--------------------------------------|------------------------|
| 语言 | Go | Node.js / TypeScript | 自选 |
| 工具数 | **542** | ~30 | 自定义 |
| 资源数 | 46 | 0 | 自定义 |
| 功能覆盖 | **53 个模块全覆盖** | 基础 CRUD | 按需 |
| 认证方式 | Token / App / Account | Account | 自定义 |
| 维护状态 | 活跃 | 较少更新 | 自维护 |
| 编译方式 | `go build` 生成单文件 | npm install | 自定义 |
| 配置难度 | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |

**选择方案 A（ZenTaoMcp）的理由：**

1. **功能最全** — 542 个工具覆盖禅道所有 53 个模块（产品、项目、Bug、需求、任务、测试用例……），不用自己写 API 对接
2. **部署简单** — Go 编译生成单个 `.exe` 文件，无需运行时环境
3. **认证灵活** — 支持 Token、App、Account 三种认证方式
4. **活跃维护** — GitHub 上持续更新

---

## 技术原理：禅道 API + MCP 协议

### 禅道 REST API

禅道从 18.0 版本开始提供标准的 REST API，支持 JSON 格式的请求和响应。核心认证方式有三种：

| 认证方式 | 说明 | 适用场景 | 实测状态 |
|----------|------|----------|----------|
| **Token** | 用户名密码登录获取 Token | 通用，最简单 | ⚠️ 未验证 |
| **App** | 管理员创建应用，获取 APP_CODE + APP_KEY | 服务端集成 | ✅ 读取正常 / ❌ 写入静默失败 |
| **Account** | 直接使用账号密码 | 临时调试 | ⚠️ 未验证 |

我们最初选择 **App 认证**，因为：
- 不暴露用户密码
- 可细粒度控制权限
- Token 不会过期（APP_CODE + APP_KEY 长期有效）
- 适合 AI 助手持续调用

> ⚠️ **实测发现**：App 认证只能读取数据，创建/修改等写操作返回成功但数据未持久化。详见后文「实测诊断」章节。

### MCP 协议

MCP（Model Context Protocol）是连接 AI 助手与外部工具的标准协议。工作流程：

```
AI 助手 ↔ MCP Client ↔ MCP Server (stdio/SSE) ↔ 外部系统 API
```

WorkBuddy 内置了 MCP Client，只需配置 MCP Server 的启动命令，就能自动发现和调用所有工具。

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

如果需要 AI 具备禅道写入能力，有以下几条路径：

| 方案 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| **A. 提供用户凭据** | 切换为 Session/Account 认证 | 完整读写能力 | 需暴露账号密码 |
| **B. 管理员调整 App 权限** | 禅道后台为 App 授予写权限 | 不暴露用户凭据 | 不确定禅道是否支持此粒度 ⚠️ 未验证 |
| **C. 修复 MCP Server + Session 认证** | 修复路径转换 Bug，添加 parent 参数，配合 Session 认证 | 技术层面完整 | 仍需用户凭据；需 Go 开发能力 |
| **D. 手动操作** | AI 读取 + 人工写入 | 最安全，零风险 | 无法自动化 |

> 💡 **建议路径**：先确认方案 B 是否可行（咨询禅道管理员），如不可行则选方案 A 或 C。

---

## 完整架构图

```
┌─────────────────────────────────────────────────┐
│                  AI 助手                         │
│              (WorkBuddy / 其他)                  │
└──────────────┬──────────────────────────────────┘
               │  MCP 协议 (stdio)
               ▼
┌─────────────────────────────────────────────────┐
│          zentao-mcp.exe (Go 编译)                │
│  ┌───────────────────────────────────────────┐  │
│  │  542 tools / 46 resources / 2 prompts    │  │
│  │  覆盖 53 个禅道功能模块                   │  │
│  └───────────────────────────────────────────┘  │
└──────────────┬──────────────────────────────────┘
               │  禅道 REST API (HTTP)
               │  App 认证 (APP_CODE + APP_KEY)
               ▼
┌─────────────────────────────────────────────────┐
│              禅道项目管理系统                     │
│         (http://禅道地址:88/api.php)             │
│  ┌────────┬────────┬────────┬────────┐          │
│  │ 产品   │ 项目   │ Bug    │ 需求   │          │
│  ├────────┼────────┼────────┼────────┤          │
│  │ 任务   │ 用例   │ 发布   │ 文档   │          │
│  └────────┴────────┴────────┴────────┘          │
│                                                  │
│  ✅ 读取：App 认证可用                           │
│  ❌ 写入：App 认证静默失败，需 Session 认证       │
└─────────────────────────────────────────────────┘
```

---

## 三套方案对比：微信 / 企微 / 禅道

接入三个系统后，整体对比：

| 对比项 | 个人微信 | 企业微信 | 禅道（App 认证） |
|--------|----------|----------|------------------|
| 数据类型 | 非结构化聊天记录 | 非结构化聊天记录 + 组织架构 | **结构化项目数据** |
| 接入方式 | 本地数据库解密 | 本地数据库解密 | **REST API（官方支持）** |
| 加密难度 | ⭐⭐⭐⭐ (SQLCipher 4) | ⭐⭐ (wxSQLite3) | **⭐ (无加密，API 鉴权)** |
| 工具链 | wechat-cli + wx_key | wechat-decrypt | **ZenTaoMcp** |
| AI 可操作性 | 只读 | 只读 | **⚠️ App 认证仅可读；Session 认证可读写** |
| 数据时效性 | 需重新解密 | 需重新解密 | **实时（API 调用）** |
| 网络要求 | 本地 | 本地 | **需要网络连通** |

**核心区别**：微信和企微是"破解本地数据库"，禅道是"调用官方 API"。禅道接入更规范、更稳定，但 App 认证模式下实际能力被限制在**只读**范围。要实现完整的读写操作，需要切换到 Session/Account 认证。

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

**核心收获：** 禅道接入 AI 的本质是"标准化 API 对接"，不像微信/企微需要破解本地数据库。Go 编译的 ZenTaoMcp 提供了 542 个工具的单文件部署方案，一次编译即可覆盖禅道全部 53 个功能模块。但实测发现 **App 认证只能读取，写入操作静默失败**——这是一个文档中未提及的关键限制。最大的挑战不仅在**网络连通性**，更在于**认证方式的选择**——App 认证方便安全但功能受限，Session/Account 认证功能完整但需暴露用户凭据。

---

## 系列文章

- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](https://sikinzen.github.io/posts/howtoconnectwechatandai/) — 个人微信接入方案
- [让 AI 读懂你的企业微信：wechat-decrypt 接入指南](https://sikinzen.github.io/posts/howtoconnectwecomandai/) — 企业微信接入方案
- [让 AI 参与代码审查：Gerrit MCP Server 接入指南](https://sikinzen.github.io/posts/howtoconnectgerritandai/) — Gerrit 代码审查系统接入方案
- [让 AI 管理你的代码仓库：Gitea MCP Server 接入指南](https://sikinzen.github.io/posts/howtoconnectgiteaandai/) — Gitea 代码托管平台接入方案
- 本文 — 禅道项目管理系统接入方案（含 App 认证实测诊断）

---

*本文由 AI 助手辅助整理，所有踩坑经验均为真实记录。发布前已对敏感信息做脱敏处理（实际 IP、APP_CODE、APP_KEY 均已替换为占位符），实际使用中请务必注意数据安全。*
