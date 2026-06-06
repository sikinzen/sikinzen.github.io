---
title: "让 AI 管理你的项目：禅道 ZenTaoMcp 接入指南"
date: 2026-06-06T17:30:00+08:00
draft: false
description: "从零打通 AI 助手与禅道项目管理系统的完整过程，基于 ZenTaoMcp MCP Server，542 个工具覆盖全部 53 个功能模块"
summary: "记录将禅道项目管理系统接入 AI 助手的完整过程，使用 Go 编写的 ZenTaoMcp 作为 MCP Server，实现 AI 直接操作禅道的 Bug、需求、任务等核心功能"
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
- 📝 **自动创建和分配任务**（"帮我建一个 Bug，标题 XX，指派给 XX"）
- 📊 **汇总项目数据**（"统计本月各项目的 Bug 数量"）

好消息是：禅道提供了完整的 REST API，而且社区已经有了成熟的 MCP Server 实现——**ZenTaoMcp**，一次编译即可覆盖全部 542 个工具。

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

| 认证方式 | 说明 | 适用场景 |
|----------|------|----------|
| **Token** | 用户名密码登录获取 Token | 通用，最简单 |
| **App** | 管理员创建应用，获取 APP_CODE + APP_KEY | **服务端集成（推荐）** |
| **Account** | 直接使用账号密码 | 临时调试 |

我们选择 **App 认证**，因为：
- 不暴露用户密码
- 可细粒度控制权限
- Token 不会过期（APP_CODE + APP_KEY 长期有效）
- 适合 AI 助手持续调用

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
set ZENTAO_BASE_URL=http://你的禅道地址
set ZENTAO_APP_CODE=你的AppCode
set ZENTAO_APP_KEY=你的AppKey
set ZENTAO_AUTH_METHOD=app
set ZENTAO_ALLOW_INSECURE_HTTP=true

D:\Software\AI\ZenTaoMcp\zentao-mcp.exe
```

MCP Server 正常启动后，会通过 stdin/stdout 与 MCP Client 通信，不会输出任何内容到控制台（这是正常的）。

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
C:\Users\<你的用户名>\.workbuddy\.mcp.json
```

### 配置内容

```json
{
  "mcpServers": {
    "zentao": {
      "command": "D:\\Software\\AI\\ZenTaoMcp\\zentao-mcp.exe",
      "env": {
        "ZENTAO_BASE_URL": "http://你的禅道地址",
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

| 变量 | 说明 | 示例 |
|------|------|------|
| `ZENTAO_BASE_URL` | 禅道访问地址 | `http://192.168.x.x:88` |
| `ZENTAO_APP_CODE` | App 认证 Code | `MyApp` |
| `ZENTAO_APP_KEY` | App 认证 Key | `a1b2c3d4e5f6...` |
| `ZENTAO_AUTH_METHOD` | 认证方式 | `app` |
| `ZENTAO_ALLOW_INSECURE_HTTP` | 允许 HTTP（非 HTTPS） | `true` |

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
帮我查看禅道上指派给我的 Bug
帮我看看 XX 项目的进度
帮我在禅道搜索 XX 关键词
帮我在禅道创建一个 Bug：标题 XX，严重程度 S1
```

AI 助手会自动调用对应的 MCP 工具，查询并整理结果。

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
│         (http://你的禅道地址:88)                  │
│  ┌────────┬────────┬────────┬────────┐          │
│  │ 产品   │ 项目   │ Bug    │ 需求   │          │
│  ├────────┼────────┼────────┼────────┤          │
│  │ 任务   │ 用例   │ 发布   │ 文档   │          │
│  └────────┴────────┴────────┴────────┘          │
└─────────────────────────────────────────────────┘
```

---

## 三套方案对比：微信 / 企微 / 禅道

接入三个系统后，整体对比：

| 对比项 | 个人微信 | 企业微信 | 禅道 |
|--------|----------|----------|------|
| 数据类型 | 非结构化聊天记录 | 非结构化聊天记录 + 组织架构 | **结构化项目数据** |
| 接入方式 | 本地数据库解密 | 本地数据库解密 | **REST API（官方支持）** |
| 加密难度 | ⭐⭐⭐⭐ (SQLCipher 4) | ⭐⭐ (wxSQLite3) | **⭐ (无加密，API 鉴权)** |
| 工具链 | wechat-cli + wx_key | wechat-decrypt | **ZenTaoMcp** |
| AI 可操作性 | 只读 | 只读 | **读写（创建/修改/删除）** |
| 数据时效性 | 需重新解密 | 需重新解密 | **实时（API 调用）** |
| 网络要求 | 本地 | 本地 | **需要网络连通** |

**核心区别**：微信和企微是"破解本地数据库"，禅道是"调用官方 API"。这意味着禅道接入更规范、更稳定、功能更强（可读写），但需要网络连通。

---

## 踩坑记录

| # | 问题 | 根本原因 | 解决方法 |
|---|------|---------|---------|
| 1 | GitHub Releases 没有 Windows 预编译版 | 作者只发布了 Linux/macOS 版本 | 自行从源码编译 `go build` |
| 2 | Go 下载慢（国内网络） | Go 官方 CDN 在国内速度慢 | 使用阿里云镜像 + `GOPROXY=https://goproxy.cn` |
| 3 | MCP 配置 JSON 路径转义错误 | Bash heredoc 会吞掉反斜杠 | 用 Python `json.dump()` 写入配置文件 |
| 4 | 禅道 API 连接超时 | 禅道在内网，AI 沙箱环境不在同一网络 | 需在公司网络或 VPN 环境使用 |
| 5 | `ZENTAO_ALLOW_INSECURE_HTTP` 未设置 | 禅道使用 HTTP 而非 HTTPS | 设置环境变量为 `true` |
| 6 | MCP Server 配置后未生效 | 需要手动信任并重启会话 | 在连接器管理中信任 zentao 服务器 |

### 重点展开：问题 #4 —— 内网访问

这是部署中**最常见的障碍**。禅道通常部署在公司内网，而 AI 助手（尤其是云端版本）无法直接访问内网地址。

**解决方案优先级：**

1. **最佳方案**：AI 助手在本地运行（如 WorkBuddy 桌面版），天然可访问内网
2. **次选方案**：通过 VPN 将 AI 运行环境接入内网
3. **备选方案**：将禅道 API 通过反向代理暴露到公网（需做好安全加固）

本文的配置方案基于 WorkBuddy 桌面版（本地运行），所以只要电脑能访问禅道，AI 就能访问。

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **API 权限控制** — App 认证的权限范围需要谨慎设置，避免授予不必要的写权限
2. **数据安全** — 禅道数据包含项目进度、Bug 详情、需求文档等，属于企业内部信息
3. **操作审计** — 通过 AI 执行的写操作（创建/修改/删除）应可追溯
4. **网络暴露** — 如果将禅道 API 暴露到公网，务必配置 HTTPS + IP 白名单
5. **凭据安全** — APP_KEY 不要硬编码、不要提交到版本库，通过环境变量传递
6. **版本兼容** — ZenTaoMcp 基于禅道 18.0+ 的 API，低版本禅道可能不完全兼容

**建议：**

- 初期建议**只开放读权限**给 AI 助手，确认稳定后再逐步开放写权限
- 定期检查禅道后台的**应用调用日志**
- APP_KEY 定期**轮换**
- 发布博客或文章时，**不要暴露真实的 API 地址、APP_CODE、APP_KEY**

---

## 总结

| 环节 | 工具 | 难度 | 备注 |
|------|------|------|------|
| 安装 Go | 官方/镜像下载 | ⭐ | 国内用阿里云镜像加速 |
| 编译 ZenTaoMcp | go build | ⭐ | 单文件输出，约 16MB |
| 配置禅道 App 认证 | 禅道后台 | ⭐ | 记录 APP_CODE 和 APP_KEY |
| 配置 WorkBuddy MCP | .mcp.json | ⭐⭐ | 注意 Windows 路径转义 |
| 信任 MCP 服务器 | WorkBuddy UI | ⭐ | 配置后必须手动信任 |
| 创建 Skill | SKILL.md | ⭐⭐ | 一次配置，长期使用 |
| 网络连通 | VPN / 内网 | ⭐⭐⭐ | **最常见的障碍** |

**核心收获：** 禅道接入 AI 的本质是"标准化 API 对接"，不像微信/企微需要破解本地数据库。Go 编译的 ZenTaoMcp 提供了 542 个工具的单文件部署方案，一次编译即可覆盖禅道全部 53 个功能模块。最大的挑战不在技术，而在**网络连通性**——确保 AI 助手能访问到内网的禅道服务。

---

## 系列文章

- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](https://sikinzen.github.io/posts/howtoconnectwechatandai/) — 个人微信接入方案
- [让 AI 读懂你的企业微信：wechat-decrypt 接入指南](https://sikinzen.github.io/posts/howtoconnectwecomandai/) — 企业微信接入方案
- 本文 — 禅道项目管理系统接入方案

---

*本文由 AI 助手辅助整理，所有踩坑经验均为真实记录。发布前已对敏感信息做脱敏处理，实际使用中请务必注意数据安全。*
