---
title: "让 AI 参与代码审查：Gerrit MCP Server 接入指南"
date: 2026-06-06T19:10:00+08:00
draft: false
description: "从零打通 AI 助手与 Gerrit 代码审查系统的完整过程，基于 Google 官方 gerrit-mcp-server，18 个工具覆盖变更查询、审查、评论等核心功能"
summary: "记录将 Gerrit 代码审查系统接入 AI 助手的完整过程，使用 Python 编写的 gerrit-mcp-server 作为 MCP Server，实现 AI 直接查询变更、发布审查评论、管理代码评审"
categories: ["AI应用"]
tags: ["Gerrit", "代码审查", "AI助手", "MCP", "CodeReview"]
keywords: ["Gerrit AI", "gerrit-mcp-server", "MCP Server", "代码审查AI", "Gerrit API"]
series: ["AI工具链"]
---

> ⚠️ **本文尚未实际验证** — MCP Server 已完成下载和配置，但因 Gerrit 在公司内网，API 连通性需到公司内网环境验证。配置步骤和命令均基于官方文档整理，实际使用时可能需要微调。

## 背景：为什么要把 Gerrit 接入 AI？

前面几篇写了[个人微信](https://sikinzen.github.io/posts/howtoconnectwechatandai/)、[企业微信](https://sikinzen.github.io/posts/howtoconnectwecomandai/)和[禅道](./HowToConnectZentaoAndAI.md)接入 AI 的方案。本篇聚焦**代码审查**环节——Gerrit。

Gerrit 是业界广泛使用的代码审查工具，每天产生大量 Change、评论、评审记录。让 AI 接入 Gerrit 后，可以：

- 🔍 **快速查询变更**（"帮我看看今天有哪些待审查的 Change"）
- 📝 **分析代码差异**（"帮我看看 CL #12345 改了什么"）
- 💬 **发布审查评论**（"在这个文件的第 42 行加一条审查意见"）
- 👥 **推荐审查人**（"这个项目谁比较熟悉？"）
- 🔄 **管理变更状态**（"把这个 CL 标记为 WIP"）

---

## 方案选择：Gerrit MCP Server

经过调研，社区有多个 Gerrit MCP Server 实现：

| 项目 | 语言 | 工具数 | 维护者 | 特点 |
|------|------|--------|--------|------|
| **GerritCodeReview/gerrit-mcp-server** | Python | 18 | Google 官方镜像 | 功能全面，认证灵活 |
| siarhei-belavus/gerrit-mcp | Node.js | ~10 | 社区 | 轻量，专注代码审查 |
| cayirtepeomer/gerrit-code-review-mcp | Python | ~8 | 社区 | 简洁，适合基础场景 |

**选择 GerritCodeReview/gerrit-mcp-server 的理由：**

1. **Google 官方镜像** — 与 Gerrit 项目同属一个组织，API 兼容性有保障
2. **工具最全** — 18 个工具覆盖变更查询、审查、评论、状态管理
3. **认证灵活** — 支持 git_cookies、http_basic、gob_curl 三种方式
4. **双模式运行** — stdio（按需启动）和 HTTP 服务器（持久化）两种模式

---

## 技术原理：Gerrit REST API + MCP

### Gerrit REST API

Gerrit 提供了完整的 REST API（默认路径 `/a/`），支持 JSON 格式的请求和响应。核心功能包括：

```
GET  /a/changes/                    — 查询变更列表
GET  /a/changes/{change-id}         — 获取变更详情
GET  /a/changes/{id}/detail         — 获取变更详细信息
POST /a/changes/{id}/revisions/{r}/review — 发布审查
POST /a/changes/{id}/abandon        — 放弃变更
```

### 认证方式

Gerrit REST API 支持三种认证方式：

| 认证方式 | 说明 | 推荐度 |
|----------|------|--------|
| **git_cookies** | 复用 Git 的 `.gitcookies` 文件 | ⭐⭐⭐ 推荐 |
| **http_basic** | 用户名 + HTTP 密码 | ⭐⭐ 简单直接 |
| gob_curl | Google 内部专用 | — 不适用 |

> 我们选择 **http_basic** 认证，因为配置最简单，不需要额外文件。如果团队已配置 `.gitcookies`，推荐使用 git_cookies 方式。

---

## 第一步：安装前置依赖

gerrit-mcp-server 需要 Python 3.11+ 和 curl：

```bash
# 检查 Python 版本
python --version
# 需要 Python 3.11+

# 检查 curl
curl --version
# 大多数系统已预装
```

---

## 第二步：克隆并构建

```bash
cd D:\Software\AI

# 克隆仓库
git clone https://github.com/GerritCodeReview/gerrit-mcp-server.git
cd gerrit-mcp-server

# 构建项目（创建虚拟环境 + 安装依赖）
# Windows 下使用 Git Bash 或 WSL 运行构建脚本
bash build-gerrit.sh
```

构建脚本会：
1. 创建 Python 虚拟环境（`.venv/`）
2. 安装所有依赖（`mcp`, `httpx` 等）
3. 使服务器就绪

---

## 第三步：配置 Gerrit 连接

在 `gerrit_mcp_server/` 目录下创建配置文件：

```bash
# 复制示例配置
cp gerrit_mcp_server/gerrit_config.sample.json gerrit_mcp_server/gerrit_config.json
```

### 配置内容

#### 方式一：http_basic 认证（推荐入门）

```json
{
  "default_gerrit_base_url": "https://你的Gerrit地址/",
  "gerrit_hosts": [
    {
      "name": "Company Gerrit",
      "external_url": "https://你的Gerrit地址/",
      "authentication": {
        "type": "http_basic",
        "username": "你的用户名",
        "auth_token": "你的HTTP密码"
      }
    }
  ]
}
```

#### 方式二：git_cookies 认证（推荐已有 Git 配置的团队）

```json
{
  "default_gerrit_base_url": "https://你的Gerrit地址/",
  "gerrit_hosts": [
    {
      "name": "Company Gerrit",
      "external_url": "https://你的Gerrit地址/",
      "authentication": {
        "type": "git_cookies",
        "gitcookies_path": "~/.gitcookies"
      }
    }
  ]
}
```

### 获取 HTTP 密码

1. 登录 Gerrit 网页端
2. 进入 **Settings → HTTP Credentials**
3. 点击 **Generate Password**
4. 复制生成的密码，填入 `auth_token` 字段

> ⚠️ **安全提示**：HTTP 密码是敏感信息，不要提交到版本库。配置文件 `gerrit_config.json` 应加入 `.gitignore`。

---

## 第四步：配置 WorkBuddy MCP 连接

在 WorkBuddy 的 MCP 配置文件中添加 Gerrit 服务器。

### 配置文件位置

```
C:\Users\<你的用户名>\.workbuddy\.mcp.json
```

### stdio 模式配置（推荐）

gerrit-mcp-server 支持两种运行模式，stdio 模式最简单：

```json
{
  "mcpServers": {
    "gerrit": {
      "command": "python",
      "args": [
        "D:\\Software\\AI\\gerrit-mcp-server\\gerrit_mcp_server\\main.py"
      ],
      "cwd": "D:\\Software\\AI\\gerrit-mcp-server"
    }
  }
}
```

> 💡 **注意**：gerrit-mcp-server 不通过环境变量传递配置，而是读取 `gerrit_mcp_server/gerrit_config.json` 文件。`cwd` 设置为项目根目录，确保能找到配置文件。

### HTTP 模式配置（备选）

如果需要持久化运行，可以用 HTTP 模式：

```bash
# 启动服务器
bash server.sh start

# 检查状态
bash server.sh status

# 停止服务器
bash server.sh stop
```

客户端配置：
```json
{
  "mcpServers": {
    "gerrit": {
      "url": "http://localhost:8080/sse"
    }
  }
}
```

---

## 第五步：信任 MCP 服务器

配置完成后，需要手动信任：

1. 打开 WorkBuddy 客户端
2. 进入**连接器管理**页面
3. 在顶部**自定义连接器**入口找到 `gerrit`
4. 点击**信任**按钮激活
5. **重启 WorkBuddy 会话**使 MCP 生效

---

## 18 个工具详解

### 变更查询与检索（5 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `query_changes` | 按查询字符串搜索变更 | "查看所有 open 状态的 Change" |
| `query_changes_by_date_and_filters` | 按日期范围+项目+状态搜索 | "本周我提交的 Change" |
| `get_change_details` | 获取单个 Change 完整摘要 | "CL #12345 的详细信息" |
| `get_most_recent_cl` | 获取用户最近的 Change | "我最新提交的 Change" |
| `changes_submitted_together` | 查看与指定 CL 一起提交的变更 | "这个 CL 还关联了哪些提交？" |

### 提交消息与文件（3 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_commit_message` | 获取提交消息 | "CL #12345 的 commit message" |
| `list_change_files` | 列出变更涉及的所有文件 | "这个 CL 修改了哪些文件？" |
| `get_file_diff` | 获取指定文件的 diff | "看看 main.py 的具体改动" |

### 评审与评论（4 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `list_change_comments` | 查看变更的所有评论 | "CL #12345 有哪些审查意见？" |
| `post_review_comment` | 在文件特定行发布评论 | "在第 42 行加一条审查意见" |
| `suggest_reviewers` | 推荐审查人 | "这个项目推荐谁做审查？" |
| `add_reviewer` | 添加审查人/抄送人 | "把张三加为审查人" |

### 变更状态操作（5 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `set_ready_for_review` | 标记为待审查 | "CL 准备好了，提交审查" |
| `set_work_in_progress` | 标记为进行中（WIP） | "先标记 WIP，还没写完" |
| `abandon_change` | 放弃变更 | "这个 Change 不要了" |
| `revert_change` | 回退单个变更 | "回退 CL #12345" |
| `revert_submission` | 回退整个提交 | "回退整个提交（含多个 CL）" |

### 变更创建与管理（2 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `create_change` | 创建新变更 | "帮我创建一个 CL" |
| `set_topic` | 设置/删除变更主题 | "给这个 CL 设置 topic" |

### 其他（1 个）

| 工具 | 功能 | 典型用法 |
|------|------|---------|
| `get_bugs_from_cl` | 从提交消息提取 Bug ID | "这个 CL 关联了哪些 Bug？" |

---

## 完整架构图

```
┌─────────────────────────────────────────────────┐
│                  AI 助手                         │
│              (WorkBuddy / 其他)                  │
└──────────────┬──────────────────────────────────┘
               │  MCP 协议 (stdio / HTTP SSE)
               ▼
┌─────────────────────────────────────────────────┐
│       gerrit-mcp-server (Python 3.11+)          │
│  ┌───────────────────────────────────────────┐  │
│  │  18 tools                                 │  │
│  │  变更查询 / 文件差异 / 审查评论 / 状态管理  │  │
│  └───────────────────────────────────────────┘  │
│  gerrit_config.json (认证配置)                   │
└──────────────┬──────────────────────────────────┘
               │  Gerrit REST API (HTTP)
               │  http_basic / git_cookies 认证
               ▼
┌─────────────────────────────────────────────────┐
│              Gerrit 代码审查系统                   │
│         (https://你的Gerrit地址/)                 │
│  ┌────────────┬────────────┬────────────┐       │
│  │ Change     │ Review     │ Comment    │       │
│  ├────────────┼────────────┼────────────┤       │
│  │ Patch Set  │ Merge      │ Abandon    │       │
│  └────────────┴────────────┴────────────┘       │
└─────────────────────────────────────────────────┘
```

---

## 五系统接入对比

| 对比项 | 微信 | 企微 | 禅道 | **Gerrit** | Gitea |
|--------|------|------|------|-----------|-------|
| 数据类型 | 聊天记录 | 聊天+组织架构 | 项目管理 | **代码审查** | 代码仓库 |
| 接入方式 | 数据库解密 | 数据库解密 | REST API | **REST API** | REST API |
| 加密难度 | ⭐⭐⭐⭐ | ⭐⭐ | ⭐ | **⭐** | ⭐ |
| MCP 工具数 | N/A | N/A | 542 | **18** | 23 |
| 认证方式 | 内存密钥 | 内存密钥 | App Token | **HTTP 密码/git_cookies** | Access Token |
| AI 可操作性 | 只读 | 只读 | 读写 | **读写** | 读写 |
| 部署难度 | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | **⭐⭐** | ⭐ |
| 语言 | Go + Python | Python | Go | **Python** | Go |

**核心区别**：Gerrit 和 Gitea 都是"官方 API 对接"，但侧重点不同——Gerrit 聚焦**代码审查流程**（变更、评论、评审），Gitea 聚焦**代码仓库管理**（仓库、分支、文件、Issue、PR）。两者互补，配合使用可覆盖完整的代码协作流程。

---

## 踩坑预判

| # | 可能的问题 | 原因 | 预期解决方法 |
|---|-----------|------|------------|
| 1 | `build-gerrit.sh` 在 Windows 下无法运行 | 构建脚本是 Bash 脚本 | 使用 Git Bash 或 WSL 运行 |
| 2 | Python 版本不兼容 | 需要 Python 3.11+ | 安装合适版本或使用 venv |
| 3 | Gerrit 内网地址不可达 | 和禅道一样的内网访问问题 | 公司网络 / VPN |
| 4 | HTTP 密码生成失败 | 部分 Gerrit 版本不支持 HTTP 认证 | 改用 git_cookies 认证 |
| 5 | gerrit_config.json 路径问题 | MCP 启动时工作目录不正确 | 确保设置 `cwd` 为项目根目录 |
| 6 | curl 命令不可用 | Windows 默认可能没有 curl | Git Bash 自带 curl，或手动安装 |

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **代码安全** — Gerrit 中的代码属于企业核心资产，AI 读取 diff 时可能接触敏感逻辑
2. **操作权限** — `post_review_comment`、`abandon_change` 等写操作需要谨慎授权
3. **凭据安全** — HTTP 密码 / git_cookies 等于 Gerrit 的完整访问权限，切勿泄露
4. **审计合规** — 通过 AI 执行的操作应可追溯，建议初期只开放读权限
5. **内网访问** — 公司 Gerrit 通常在内网，需要确保 AI 运行环境可访问
6. **版本兼容** — gerrit-mcp-server 基于 Gerrit REST API v2/v3，低版本可能不完全兼容

**建议：**

- 初期建议**只开放读权限**（查询变更、查看 diff、列出评论）
- 写操作（发布评论、放弃变更等）**需人工确认**后再执行
- 配置文件 `gerrit_config.json` **不要提交到版本库**
- 发布博客时，**不要暴露真实的 Gerrit 地址、用户名、密码**

---

## 当前状态

| 环节 | 状态 | 备注 |
|------|------|------|
| 方案调研 | ✅ 完成 | 对比了 3 个 Gerrit MCP Server |
| 下载构建 | ⏳ 待执行 | 需在公司内网环境操作 |
| 配置 gerrit_config.json | ⏳ 待执行 | 需要 Gerrit 地址和认证信息 |
| 配置 WorkBuddy MCP | ⏳ 待执行 | 需先完成构建 |
| 信任 MCP 服务器 | ⏳ 待执行 | 需先完成配置 |
| API 连通性验证 | ⏳ 待执行 | **需要公司内网环境** |
| 创建 Skill | ⏳ 待执行 | 验证通过后创建 |

> 🔔 **提醒**：本文所有步骤均基于官方文档整理，**尚未在实际 Gerrit 环境中验证**。到公司内网后，请按照步骤逐一执行并验证。

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
