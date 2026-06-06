---
title: "让 AI 管理你的代码仓库：Gitea MCP Server 接入指南"
date: 2026-06-06T19:15:00+08:00
draft: false
description: "从零打通 AI 助手与 Gitea 代码托管平台的完整过程，基于官方 gitea-mcp，23 个工具覆盖仓库、分支、文件、Issue、PR 等核心功能"
summary: "记录将 Gitea 代码托管平台接入 AI 助手的完整过程，使用 Go 编写的 gitea-mcp 作为 MCP Server，实现 AI 直接操作仓库、Issue、PR 等功能"
categories: ["AI应用"]
tags: ["Gitea", "代码仓库", "AI助手", "MCP", "代码管理"]
keywords: ["Gitea AI", "gitea-mcp", "MCP Server", "代码仓库AI", "Gitea API"]
series: ["AI工具链"]
---

> ⚠️ **本文尚未实际验证** — MCP Server 已完成调研和配置规划，但因 Gitea 在公司内网，API 连通性需到公司内网环境验证。配置步骤和命令均基于官方文档整理，实际使用时可能需要微调。

## 背景：为什么要把 Gitea 接入 AI？

前面几篇分别解决了[沟通数据](https://sikinzen.github.io/posts/howtoconnectwechatandai/)（微信/企微）和[项目管理](https://sikinzen.github.io/posts/howtoconnectzentaoandai/)（禅道）的 AI 化问题。本篇聚焦**代码托管**环节——Gitea。

Gitea 是轻量级自托管 Git 平台，在企业内网广泛使用。让 AI 接入 Gitea 后，可以：

- 📦 **管理仓库**（"帮我创建一个新仓库" / "Fork XX 项目"）
- 🌿 **操作分支**（"列出所有分支" / "创建 feature 分支"）
- 📝 **管理文件**（"帮我看看 XX 文件的内容" / "更新配置文件"）
- 🐛 **处理 Issue**（"查看最近的 Bug Issue" / "创建一个新 Issue"）
- 🔀 **处理 PR**（"看看有哪些待合并的 PR" / "帮我创建 PR"）
- 🔍 **全局搜索**（"搜索所有包含 XX 关键词的仓库"）

---

## 方案选择：gitea-mcp（Gitea 官方出品）

Gitea 官方维护的 MCP Server，Go 语言编写，**预编译单文件部署，下载即用**。

| 项目 | 详情 |
|------|------|
| 仓库 | `https://gitea.com/gitea/gitea-mcp` |
| 最新版 | **v1.3.0**（2026-05-14） |
| 语言 | Go |
| 工具数 | **23 个** |
| 文件大小 | ~4.1 MB（Windows x86_64） |
| 认证方式 | Personal Access Token |
| 运行模式 | stdio / SSE |
| 许可证 | MIT |
| 作者 | Lunny Xiao（Gitea 核心维护者） |

### 为什么选 gitea-mcp？

1. **官方出品** — 由 Gitea 核心维护者开发，API 兼容性有保障
2. **零构建** — 预编译二进制，下载解压即可使用，不需要 Go 环境
3. **功能全面** — 23 个工具覆盖仓库/分支/文件/Issue/PR 全流程
4. **双模式运行** — stdio（简单稳定）和 SSE（支持实时推送）两种模式

---

## 技术原理：Gitea REST API + MCP

### Gitea REST API

Gitea 兼容 GitHub API（Swagger 文档路径 `/api/swagger`），提供完整的 RESTful 接口：

```
GET    /api/v1/repos/{owner}/{repo}           — 获取仓库信息
POST   /api/v1/repos/{owner}/{repo}/issues     — 创建 Issue
GET    /api/v1/repos/{owner}/{repo}/pulls       — 列出 PR
POST   /api/v1/repos/{owner}/{repo}/branches    — 创建分支
PUT    /api/v1/repos/{owner}/{repo}/contents/{path} — 更新文件
```

### 认证方式

Gitea 使用 **Personal Access Token** 认证：

| 对比项 | 说明 |
|--------|------|
| 认证方式 | HTTP Header: `Authorization: token <your-token>` |
| 权限范围 | 创建 Token 时可选：repo / read:user / write:issue 等 |
| 有效期 | 默认长期有效，可手动撤销 |
| 安全性 | 比用户名密码更安全，可细粒度控制权限 |

---

## 第一步：下载 gitea-mcp

### 方式一：直接下载预编译版本（推荐）

从官方发布页下载对应平台的二进制文件：

```
https://gitea.com/gitea/gitea-mcp/releases
```

选择 Windows x86_64 版本，下载后解压到指定目录：

```bash
# 建议存放路径
D:\Software\AI\gitea-mcp\gitea-mcp.exe
```

> 💡 这是**最简单的方式**——不需要 Go 环境，不需要编译，下载即用。文件仅 ~4.1 MB。

### 方式二：源码编译

如果需要自定义修改或预编译版本不适用：

```bash
cd D:\Software\AI

# 克隆仓库
git clone https://gitea.com/gitea/gitea-mcp.git
cd gitea-mcp

# 设置 Go 代理（国内加速）
set GOPROXY=https://goproxy.cn,direct

# 编译
go build -o gitea-mcp.exe .

# 编译完成后复制到目标目录
copy gitea-mcp.exe D:\Software\AI\gitea-mcp\
```

---

## 第二步：获取 Gitea Access Token

在 Gitea 网页端生成 Personal Access Token：

1. 登录 Gitea
2. 进入 **Settings → Applications → Manage Access Tokens**
3. 点击 **Generate New Token**
4. 填写 Token 名称（如 `AI-Assistant`）
5. 勾选权限范围：
   - `repo` — 仓库读写权限
   - `read:user` — 读取用户信息
   - `write:issue` — Issue 写入权限（按需）
   - `write:pull_request` — PR 写入权限（按需）
6. 点击 **Generate Token**
7. **立即复制** Token（只显示一次！）

> ⚠️ **安全提示**：Access Token 等于你的 Gitea 账号权限，切勿泄露。建议初期只勾选**读权限**，确认稳定后再逐步开放写权限。

---

## 第三步：配置 WorkBuddy MCP 连接

在 WorkBuddy 的 MCP 配置文件中添加 Gitea 服务器。

### 配置文件位置

```
C:\Users\<你的用户名>\.workbuddy\.mcp.json
```

### stdio 模式配置（推荐）

```json
{
  "mcpServers": {
    "gitea": {
      "command": "D:\\Software\\AI\\gitea-mcp\\gitea-mcp.exe",
      "args": [
        "-t", "stdio",
        "--host", "https://你的Gitea地址",
        "--token", "你的Access-Token"
      ]
    }
  }
}
```

### SSE 模式配置（备选）

适合需要实时事件推送的场景：

**步骤 1 — 启动服务器：**

```bash
D:\Software\AI\gitea-mcp\gitea-mcp.exe -t sse --host https://你的Gitea地址 --token 你的Access-Token
```

**步骤 2 — 客户端配置：**

```json
{
  "mcpServers": {
    "gitea": {
      "url": "http://localhost:8080/sse"
    }
  }
}
```

### 命令行参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `-t` | 运行模式 | `stdio`（默认）或 `sse` |
| `--host` | Gitea 服务器地址 | `https://gitea.example.com` |
| `--token` | Personal Access Token | `a1b2c3d4e5f6...` |

---

## 第四步：信任 MCP 服务器

配置完成后，需要手动信任：

1. 打开 WorkBuddy 客户端
2. 进入**连接器管理**页面
3. 在顶部**自定义连接器**入口找到 `gitea`
4. 点击**信任**按钮激活
5. **重启 WorkBuddy 会话**使 MCP 生效

---

## 23 个工具详解

### 用户管理（2 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_my_user_info` | 获取已认证用户信息 | "我的 Gitea 账号信息" |
| `search_users` | 搜索用户 | "搜索用户 XX" |

### 仓库管理（3 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `create_repo` | 创建新仓库 | "帮我创建一个新仓库" |
| `fork_repo` | Fork 现有仓库 | "Fork XX 项目到我的账号" |
| `list_my_repos` | 列出我的所有仓库 | "我有哪些仓库？" |

### 分支管理（3 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `create_branch` | 创建新分支 | "从 main 创建 feature 分支" |
| `delete_branch` | 删除分支 | "删除 feature-xx 分支" |
| `list_branches` | 列出所有分支 | "XX 仓库有哪些分支？" |

### Commit 管理（1 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `list_repo_commits` | 查看提交历史 | "最近的 commit 记录" |

### 文件操作（4 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_file_content` | 获取文件内容和元数据 | "看看 config.yaml 的内容" |
| `create_file` | 创建新文件 | "创建 README.md" |
| `update_file` | 更新现有文件 | "更新配置文件" |
| `delete_file` | 删除文件 | "删除临时文件" |

### Issue 管理（4 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_issue_by_index` | 获取特定 Issue 详情 | "Issue #42 的详情" |
| `list_repo_issues` | 列出所有 Issue | "最近的 Bug Issue" |
| `create_issue` | 创建新 Issue | "创建一个 Bug 报告" |
| `create_issue_comment` | 添加 Issue 评论 | "在 Issue #42 加一条评论" |

### PR 管理（3 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_pull_request_by_index` | 获取特定 PR 详情 | "PR #10 的详情" |
| `list_repo_pull_requests` | 列出所有 PR | "待合并的 PR 有哪些？" |
| `create_pull_request` | 创建新 PR | "帮我创建 PR" |

### 搜索与组织（3 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `search_repos` | 搜索仓库 | "搜索包含 XX 的仓库" |
| `search_org_teams` | 搜索组织团队 | "XX 组织下有哪些团队？" |
| `get_gitea_mcp_server_version` | 获取服务器版本 | "gitea-mcp 版本" |

---

## 完整架构图

```
┌─────────────────────────────────────────────────┐
│                  AI 助手                         │
│              (WorkBuddy / 其他)                  │
└──────────────┬──────────────────────────────────┘
               │  MCP 协议 (stdio / SSE)
               ▼
┌─────────────────────────────────────────────────┐
│     gitea-mcp.exe (Go 单文件, ~4.1 MB)          │
│  ┌───────────────────────────────────────────┐  │
│  │  23 tools                                 │  │
│  │  仓库 / 分支 / 文件 / Issue / PR / 搜索   │  │
│  └───────────────────────────────────────────┘  │
│  --host + --token (启动参数)                     │
└──────────────┬──────────────────────────────────┘
               │  Gitea REST API (HTTP)
               │  Personal Access Token 认证
               ▼
┌─────────────────────────────────────────────────┐
│              Gitea 代码托管平台                    │
│         (https://你的Gitea地址)                   │
│  ┌────────────┬────────────┬────────────┐       │
│  │ Repos      │ Issues     │ PRs        │       │
│  ├────────────┼────────────┼────────────┤       │
│  │ Branches   │ Files      │ Commits    │       │
│  └────────────┴────────────┴────────────┘       │
└─────────────────────────────────────────────────┘
```

---

## Gitea vs Gerrit：两个代码平台 MCP 对比

Gitea 和 Gerrit 虽然都涉及代码管理，但定位完全不同，两者互补：

| 对比项 | Gitea MCP | Gerrit MCP |
|--------|-----------|------------|
| **平台定位** | 代码托管（类 GitHub） | 代码审查（Code Review） |
| **核心功能** | 仓库/分支/文件/Issue/PR | 变更查询/审查/评论/回退 |
| **工具数** | 23 | 18 |
| **语言** | Go（预编译单文件） | Python（需构建） |
| **认证方式** | Access Token | HTTP 密码 / git_cookies |
| **部署难度** | ⭐ 最低 | ⭐⭐ |
| **文件大小** | ~4.1 MB | Python 项目 |
| **AI 使用场景** | 管理仓库、创建 Issue/PR | 代码审查、发布评论 |

**典型配合场景：**

```
开发者推送代码 → Gitea 仓库收到 Push
                  ↓
              Gitea 触发 PR
                  ↓
          Gerrit 发起 Code Review
                  ↓
       AI 助手同时操作两边：
       - Gitea: 创建 Issue 记录 Bug
       - Gerrit: 查看变更 diff，发布审查意见
```

---

## 六系统接入全景对比

| 对比项 | 微信 | 企微 | 禅道 | Gerrit | **Gitea** |
|--------|------|------|------|--------|-----------|
| 数据类型 | 聊天记录 | 聊天+组织架构 | 项目管理 | 代码审查 | **代码仓库** |
| 接入方式 | 数据库解密 | 数据库解密 | REST API | REST API | **REST API** |
| MCP 工具数 | N/A | N/A | 542 | 18 | **23** |
| 部署方式 | Python 工具链 | Python 工具链 | Go 编译 | Python 构建 | **下载即用** |
| 认证方式 | 内存密钥 | 内存密钥 | App Token | HTTP 密码 | **Access Token** |
| AI 可操作性 | 只读 | 只读 | 读写 | 读写 | **读写** |
| 部署难度 | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐ | **⭐** |
| 文件体积 | 工具链 | 工具链 | 16 MB | Python 项目 | **~4.1 MB** |

**核心发现**：在所有接入方案中，Gitea 的部署难度**最低**——官方提供预编译二进制，下载解压即可使用，不需要任何编译或构建步骤。如果团队已经在使用 Gitea，这是最先推荐的 AI 接入方案。

---

## 踩坑预判

| # | 可能的问题 | 原因 | 预期解决方法 |
|---|-----------|------|------------|
| 1 | Token 权限不足 | 创建时未勾选所需权限 | 重新生成 Token，勾选对应权限 |
| 2 | Gitea 内网地址不可达 | 公司 Gitea 在内网 | 公司网络 / VPN |
| 3 | Windows 路径转义 | JSON 中 `\` 需转义为 `\\` | 用 Python `json.dump()` 写配置 |
| 4 | HTTP 协议被拒绝 | Gitea 使用 HTTP 非 HTTPS | 检查 Gitea 配置，确保允许 API 调用 |
| 5 | SSE 模式端口冲突 | 默认 8080 端口被占用 | 指定其他端口 |
| 6 | Token 过期或被撤销 | 管理员重置或手动撤销 | 重新生成 Token |

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **代码安全** — Gitea 中的代码属于企业核心资产，AI 读取文件内容时可能接触敏感逻辑和密钥
2. **操作权限** — `create_file`、`update_file`、`delete_file` 等写操作需要谨慎授权
3. **Token 安全** — Access Token 等于你的完整 Gitea 权限，泄露风险极大
4. **审计合规** — 通过 AI 执行的操作应可追溯
5. **内网访问** — 公司 Gitea 通常在内网，需要确保 AI 运行环境可访问
6. **文件误操作** — AI 执行 `delete_file` 或 `update_file` 前应确认文件内容

**建议：**

- 初期建议**只勾选读权限**（`read:repository`, `read:user`），确认稳定后再开放写权限
- Token 名称标注用途（如 `AI-Assistant-ReadOnly`），便于管理和审计
- 定期**轮换 Token**，不要长期使用同一个
- 发布博客时，**不要暴露真实的 Gitea 地址和 Token**

---

## 当前状态

| 环节 | 状态 | 备注 |
|------|------|------|
| 方案调研 | ✅ 完成 | 确认 gitea-mcp 为最佳方案 |
| 下载预编译二进制 | ⏳ 待执行 | 需在公司内网或下载后拷贝 |
| 获取 Access Token | ⏳ 待执行 | 需要 Gitea 管理员权限 |
| 配置 WorkBuddy MCP | ⏳ 待执行 | 需先完成下载和 Token |
| 信任 MCP 服务器 | ⏳ 待执行 | 需先完成配置 |
| API 连通性验证 | ⏳ 待执行 | **需要公司内网环境** |
| 创建 Skill | ⏳ 待执行 | 验证通过后创建 |

> 🔔 **提醒**：本文所有步骤均基于官方文档整理，**尚未在实际 Gitea 环境中验证**。到公司内网后，请按照步骤逐一执行并验证。

---

## 系列文章

- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](https://sikinzen.github.io/posts/howtoconnectwechatandai/) — 个人微信接入方案
- [让 AI 读懂你的企业微信：wechat-decrypt 接入指南](https://sikinzen.github.io/posts/howtoconnectwecomandai/) — 企业微信接入方案
- [让 AI 管理你的项目：禅道 ZenTaoMcp 接入指南](https://sikinzen.github.io/posts/howtoconnectzentaoandai/) — 禅道项目管理系统接入方案
- [让 AI 参与代码审查：Gerrit MCP Server 接入指南](https://sikinzen.github.io/posts/howtoconnectgerritandai/) — Gerrit 代码审查系统接入方案
- 本文 — Gitea 代码托管平台接入方案

---

*本文由 AI 助手辅助整理，所有步骤基于官方文档和调研结果。尚未在实际环境验证，发布前已对敏感信息做脱敏处理，实际使用中请务必注意代码安全和 Token 保护。*
