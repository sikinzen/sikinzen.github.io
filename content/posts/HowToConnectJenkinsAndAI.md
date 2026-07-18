---
title: "在 WorkBuddy 中通过 REST API 操作 Jenkins：原理与实战"
date: 2026-07-18T14:50:00+08:00
draft: false
description: "从零讲清 AI 助手是如何通过 Jenkins 自带的 REST API（而非连接器或官方 CLI）来读取配置、修改任务、管理节点、触发构建的，含真实踩坑与脱敏对照"
summary: "记录用 WorkBuddy 操作 Jenkins 的完整原理：没有内置连接器，改用 Jenkins REST API + curl 直接调用，覆盖配置读写、节点管理、触发构建、脚本控制台，以及中文配置推送 500、CSRF 等注意事项"
categories: ["AI应用"]
tags: ["Jenkins", "REST API", "WorkBuddy", "持续集成", "curl", "自动化运维"]
keywords: ["Jenkins REST API", "Jenkins AI", "curl Jenkins", "Jenkins 自动化", "WorkBuddy Jenkins"]
series: ["AI工具链"]
---

> ✅ **本文基于真实的内网 Jenkins 运维场景整理**，所有涉及的内网 IP、账号、端口、路径均已脱敏。文末附「脱敏对照表 + 小白如何获取真实值」，照着替换即可复用。

## 一、背景：为什么让 AI 帮你管 Jenkins？

Jenkins 是企业里最常见的持续集成（CI）工具——负责把"拉代码 → 编译 → 出包 → 上传"这一整套活儿自动化。但它的 Web 界面操作繁琐：改个流水线要进好几层菜单，换台编译机得在节点配置里翻半天。

如果你有一个像 WorkBuddy（悟空）这样的 AI 助手，最理想的状态是只说一句话："帮我改一下 XX 构建任务，编译机换成 223，编完传到 46"——不用自己点界面。

本文就讲清楚三件事：**AI 到底通过什么"接口"操作 Jenkins？原理是什么？能让你干哪些事？**

---

## 二、核心原理：用的不是"连接器"，也不是"官方 CLI"，而是 REST API

这是很多人（包括最初的我）会搞混的地方。先给结论：

> **WorkBuddy 目前没有内置的 Jenkins 连接器（Connector / MCP）。我操作 Jenkins，用的是 Jenkins 自带的 REST API，通过 AI 的 Bash 工具直接发 `curl` 命令完成。**

### 2.1 Jenkins 的三种"被操控"方式

| 方式 | 是什么 | 需要装什么 | 适合谁 |
|------|--------|-----------|--------|
| **REST API**（本文用的） | Jenkins 把每个资源（任务、节点、构建）都暴露成一个 URL，配置是一份 XML 文档，可用 HTTP 增删改查 | **什么都不用装**，只要能访问 Jenkins 的 HTTP 端口 | 任何能发 HTTP 请求的工具 / AI |
| **Jenkins CLI** | 官方提供的 `jenkins-cli.jar`，用 Java 跑命令行 | 需下载 jar 包，且 Jenkins 要开对应端口或走 SSH | 写批量 shell 脚本的运维 |
| **连接器 / MCP** | WorkBuddy 这类 AI 平台的"即插即用"集成 | 平台提供对应连接器 | 最省心，但目前 Jenkins 还没有这东西 |

### 2.2 什么是"REST API"？用大白话讲

把 Jenkins 想成一家"网上银行"：

- 每个**任务（Job）**就像你的一个**账户**，有专属网址，例如 `http://jenkins.example.com:8080/job/你的任务名/`
- 这个账户的**设置（配置）**是一份 **XML 文件**，打开 `.../config.xml` 就能看到它的全部内容
- 你想**改设置**：把新 XML 用 HTTP `POST` 发回去
- 你想**触发构建**：访问 `.../build` 这个网址（POST 一下）
- 这一切只需要"能上网 + 有账号密码"，**不需要在 Jenkins 上装任何插件**

所以 AI 做的，本质上就是：**替你拼好这些 HTTP 请求，并用 `curl` 发出去**。比如"把编译机从 A 换成 B"，AI 实际干的是：拉下 `config.xml` → 改里面的 `label` → 再 `POST` 回去。你看到的是一句话，背后是几十条 HTTP 调用。

### 2.3 为什么选 REST API 而不是 CLI？

当时有几个现实约束：

1. WorkBuddy 没有 Jenkins 连接器，MCP 路线暂时走不通；
2. 不想在 Jenkins 服务器上额外装 CLI jar、开端口（增加运维负担和安全暴露面）；
3. REST API 零部署，AI 在本机用 `curl` 就能调，最快最稳。

---

## 三、前置条件（脱敏值）

要让 AI 通过 REST API 操作 Jenkins，你需要准备：

| 项目 | 示例值（脱敏） | 说明 |
|------|---------------|------|
| Jenkins 地址 | `http://jenkins.example.com:8080` | 浏览器里打开的那个地址 |
| 账号 | `jenkinsadmin` | 对目标任务有读写权限的账号 |
| 密码 / API Token | `Jenkins@2024`（示例） | 建议用 API Token，见下文 |
| 网络 | AI 机器能直连 Jenkins 的 8080 端口 | 若中间有代理（如 Clash），需让请求绕过代理 |

> ⚠️ **关于代理**：AI 所在机器常开着系统代理（如 Clash 的 `127.0.0.1:7890`）。访问内网 Jenkins 时，代理会拦截请求导致连不上。解决：在 `curl` 加 `--noproxy '*'`（表示所有地址都不走代理），或把内网网段加入代理白名单。

## 四、如何获取 Jenkins 凭据（小白实操）

**账号密码**：就是你平时登录 Jenkins Web 界面的账号密码。

**更推荐用 API Token**（不用暴露登录密码，且可随时吊销）：

1. 浏览器登录 Jenkins
2. 右上角点你的用户名 → **Settings（设置）**
3. 左侧 **API Token** → **Add new Token** → 取个名字 → 生成
4. 复制这串 token，它就是你的"密码替代品"

之后 `curl -u 用户名:令牌` 即可，和用密码一模一样。

---

## 五、AI 能替你做的核心操作（带脱敏命令）

下面所有命令中的 `<...>` 都是占位，换成你自己的真实值（见文末对照表）。

### 5.1 读取一个任务的配置

```bash
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  "http://jenkins.example.com:8080/job/<JOB_NAME>/config.xml"
```

用途：先看清楚任务现在长什么样（编译机是哪个、上传到哪），再决定怎么改。

### 5.2 修改任务配置（最关键的一步）

先把改好的配置存成 `new_config.xml`，再推送：

```bash
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  -H "Content-Type: application/xml; charset=UTF-8" \
  --data-binary @new_config.xml \
  "http://jenkins.example.com:8080/job/<JOB_NAME>/config.xml"
```

🔥 **大坑提醒**：如果配置里含中文（比如 stage 名字叫"Docker 编译"），`Content-Type` **必须**写成 `application/xml; charset=UTF-8`。只写 `application/xml` 会让 Jenkins 按老编码（ISO-8859-1）误读中文，结果返回 **HTTP 500** 推送失败。这是真实踩过的坑。

### 5.3 触发一次构建

```bash
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  -X POST "http://jenkins.example.com:8080/job/<JOB_NAME>/build"
```

如果有参数（如选分支），改成 `/buildWithParameters?branch=xxx`。

### 5.4 管理编译节点（Agent）

节点的配置也是 XML，地址在 `computer/<节点名>/` 下：

```bash
# 读取节点配置
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  "http://jenkins.example.com:8080/computer/<NODE_NAME>/config.xml"

# 修改节点配置（如换 Java 路径、换 IP）
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  -H "Content-Type: application/xml; charset=UTF-8" \
  --data-binary @new_node.xml \
  "http://jenkins.example.com:8080/computer/<NODE_NAME>/config.xml"
```

### 5.5 跑一段 Groovy 脚本（脚本控制台）

Jenkins 有个"脚本控制台"，能直接执行 Groovy 代码，用来做界面做不到的底层操作。例如清掉"配置未保存不能构建"的标志：

```bash
curl -s -u <JENKINS_USER>:<JENKINS_PASS> \
  --data-urlencode "script=Jenkins.instance.getItemByFullName('<JOB_NAME>').save()" \
  "http://jenkins.example.com:8080/script"
```

### 5.6 关于 CSRF / Crumb（防跨站请求）

如果 Jenkins 开了"防止跨站请求伪造"，某些操作可能要求带一个 `Jenkins-Crumb` 请求头。但**用账号密码（Basic Auth）调 REST API 时，Jenkins 通常免 crumb**。只有当用"登录 cookie + 表单"方式时才必须带。本文命令均按 Basic Auth 写法，一般无需 crumb。

---

## 六、这套方式能做什么 / 不能做什么

**能做：**

- ✅ 读取、修改任意任务的配置（编译机、步骤、上传目标等）
- ✅ 新建 / 删除 / 修改编译节点（Agent）
- ✅ 触发构建、查询构建状态与日志
- ✅ 通过脚本控制台执行 Groovy，做底层维护

**不能做 / 不擅长：**

- ❌ 像"连接器 / MCP"那样用自然语言直接对话式操作（目前是 AI 替你拼 HTTP 命令）
- ❌ 实时流式追日志（REST 是轮询式，要看实时日志还是得进 Web Console）
- ❌ 不需要你给 Jenkins 装任何东西——这是优点也是局限（功能完全取决于 Jenkins 原生 API 暴露了什么）

---

## 七、更好的演进方向

1. **Pipeline as Code（流水线即代码）**：把流水线脚本（Jenkinsfile）存进 Git 仓库，Jenkins 直接从代码库拉取执行。比手工 POST 配置更规范、可版本化、可 review。
2. **Jenkinsfile 语法校验**：本地用 `jenkins-cli` 或 Blue Ocean 校验。
3. **未来若有 Jenkins MCP 连接器**：那时就能像"连禅道、连 Gitea"一样，直接跟 AI 说人话操作 Jenkins，体验最佳。在那之前，REST API 是最稳的桥。

---

## 八、脱敏对照表 & 小白如何获取真实值

> 本文所有内网信息均为**仿真示例值**，与真实环境无关。请按下表把 `<...>` 换成你自己的值。

| 文中示例值 | 真实对应什么 | 小白怎么获取 |
|-----------|-------------|-------------|
| `jenkins.example.com:8080` | 你们公司的 Jenkins 访问地址 | 问运维，或在浏览器地址栏复制你平时登录 Jenkins 的网址 |
| `jenkinsadmin` / `Jenkins@2024` | 你的 Jenkins 登录账号 / 密码或 API Token | 账号 = 你登录 Jenkins 的用户名；密码 = 登录密码，或按第四节生成 API Token |
| `<JOB_NAME>` | 你要操作的具体任务名 | Jenkins 首页任务列表里的名字 |
| `<NODE_NAME>` | 编译节点名 | Jenkins → 管理 → 节点列表里的名字 |
| `--noproxy '*'` | 绕过系统代理 | 仅当你的 AI 机器开着代理且连不上内网 Jenkins 时才需要；否则可省略 |

**一句话总结获取路径**：Jenkins 地址和任务名在 Web 界面一眼可见；账号密码用你现有的登录凭据或生成 API Token；节点名在"节点管理"页。把这些都告诉 AI，它就能用上面的命令帮你批量改配置、触发构建。

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
