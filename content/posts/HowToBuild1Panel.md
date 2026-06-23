---
title: "1Panel 面板搭建与使用指南"
date: 2026-06-14T10:30:00+08:00
draft: false
description: "从零开始搭建 1Panel Linux 面板，涵盖安装步骤、命令行工具 1pctl 用法、常用应用栈及学习资源，适合替代宝塔面板进行现代化服务器运维。"
categories: ["工具教程"]
tags: ["1Panel", "Linux", "Docker", "运维", "面板", "服务器"]
keywords: ["1Panel", "1Panel安装", "Linux面板", "Docker运维", "宝塔替代", "1pctl"]
series: ["网络与运维"]
---

## 一、1Panel 是什么？

1Panel 是一个现代化的开源 Linux 服务器运维管理面板，由飞致云（FIT2CLOUD）公司出品，强调轻量化和高安全性。

与宝塔面板的核心差异主要体现在：

| 对比维度 | 1Panel | 宝塔面板 |
|---|---|---|
| 底层架构 | 强调容器化（Docker/Kubernetes）部署应用（Nginx、MySQL 等全在容器中运行），隔离性好 | 当前支持虚拟化和直接安装在宿主机上，部分应用须安装为 RPM 包，传统 LNMP 对宿主机侵入更大 |
| 安全权限 | 默认禁止 SSH 直接 root 登录，Web 端与操作系统权限严格分离，安全性更高 | 安全设置依赖用户手动配置，但 Web 端权限较高且操作更直接 |
| 运维模式 | 所有运维操作（端口放行、日志查看等）均在 Web 界面完成 | 除 Web 界面外还可通过 `bt` 命令进行各种快捷操作 |
| 开源收费 | 开源免费程度高，付费主要集中在同步和增值服务 | 免费版功能足够，但企业级功能（防火墙/集群管理/负载均衡等）需付费 |

**总结**：如果你追求现代化运维、习惯 Docker 生态、看重开箱即用的安全隔离，推荐 1Panel；如果你需要快速搭建传统网站、习惯直接操作文件系统，宝塔目前生态更成熟。

---

## 二、如何安装 1Panel

### 1. 环境准备

```bash
sudo apt update
sudo apt upgrade
sudo apt install wget curl lsof
```

v1 版本安装（较老，仅供旧版参考）：

```bash
curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && sudo bash quick_start.sh
```

卸载命令：

```bash
sudo 1pctl uninstall
```

推荐使用 v2 版本安装：

```bash
sudo bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
```

### 2. 安装完成后

安装成功后会输出面板访问信息（**以下为示例，请以实际输出为准**）：

- 外部地址：`http://<your-server-ip>:<port>/<entrance-code>`
- 内部地址：`http://<your-lan-ip>:<port>/<entrance-code>`
- 面板用户：`<your-username>`
- 面板密码：`<your-password>`

**官网**：https://1panel.cn  
**项目文档**：https://1panel.cn/docs  
**仓库地址**：https://github.com/1Panel-dev/1Panel  
**官方论坛**：https://bbs.fit2cloud.com/c/1p/7  

> 🔐 如果使用云服务器，需要在安全组中开放对应端口（安装向导会有提示）。

---

## 三、1pctl 命令行工具

SSH 登录 1Panel 服务器后，执行 `1pctl user-info` 可获取安全入口（entrance）。

安装成功后，使用 `1pctl` 命令进行管理维护：

```text
Commands:
  status [core|agent]         查看 1Panel 服务状态
  start [core|agent|all]      启动 1Panel 服务
  stop [core|agent|all]       停止 1Panel 服务
  restart [core|agent|all]    重启 1Panel 服务
  uninstall                   卸载 1Panel 服务
  user-info                   获取 1Panel 用户信息
  listen-ip                   切换 1Panel 监听 IP
  version                     查看 1Panel 版本信息
  update                      更新 1Panel 系统信息
  reset                       重置 1Panel 系统信息
  restore                     恢复 1Panel 服务
```

---

## 四、1Panel 学习资源

### 1. 官方资源

1Panel 的官方文档和社区生态已经比较完善，直接看官方是最高效的方式。

- **官方文档**：最全的安装、权限、应用商店使用及常见问题解答。地址：https://1panel.cn/docs/
  - 推荐配套视频：B站搜索"飞致云开源大屏"或"1Panel 视频合集"
- **官方论坛**：适合解决实战中的具体问题。论坛同时发布官方公告、版本更新日志和社区活动。地址：https://bbs.1panel.cn/
- **GitHub 仓库**：关注项目动态（源码、Issues、PR），查看 Releases 版本记录和 Roadmap，适合寻找高阶用法或提交反馈。地址：https://github.com/1Panel-dev/1Panel

### 2. 学习建议

1. 先通读官方文档的"安装"和"快速上手"章节
2. 在本地或测试 VPS 上实际部署一个 1Panel
3. 遇到问题优先搜索官方论坛
4. 关注 GitHub Release 了解最新功能变化

---

## 五、1Panel 常用应用

可以查看 1Panel 的应用商店文档：https://1panel.cn/docs/v2/user_manual/appstore/openresty/ ，其中大部分应用都有详细说明和安装指南。

### 1. 应用商店

一键安装的开源应用合集。通过面板即可安装 WordPress（建站）、Halo（博客）、Waline（评论系统）等，无需手动配置数据库和运行环境，实现一键部署。

### 2. OpenResty

作为**反向代理**与 Web 服务器，是安装后搭建网站应用（如 WordPress）的前置条件。功能强大且灵活，可用于管理网站、SSL 证书和负载均衡。

### 3. MySQL / MariaDB

运行**数据库**。几乎所有动态网站和复杂应用都必须安装。1Panel 提供便捷的远程访问控制和备份恢复功能。

### 4. Redis

高性能**内存数据库**。用于加速网站访问速度、缓存和会话存储，是 WordPress、Typecho 等程序实现加速的关键组件。

### 5. Alist

统一管理网盘的挂载工具。支持挂载百度网盘、OneDrive 等多种存储，映射到服务器目录，通过 WebDAV 协议向其他应用（如 Infuse）提供访问，也可直接生成分享链接。

### 6. Cloudflared（Argo Tunnel）

安全穿透隧道。如果你没有公网 IP 也不想暴露端口，可以借助 Cloudflare 的隧道能力安全地将服务暴露到公网，并享受 CDN 和 DDoS 防护。

### 7. Portainer

容器管理工具。虽然 1Panel 自带 Docker 管理能力，Portainer 提供了更专业的容器编排与监控界面，适合需要频繁查看容器日志、监控资源占用的深度 Docker 用户。

---

## 六、使用 1Panel 搭建 OpenClaw

### 安装 OpenClaw

参考 1Panel 官方文档安装 OpenClaw：OpenClaw - 1Panel 文档（https://1panel.cn/docs/）。

安装后在访问 WebUI 时可能遇到如下提示：

```text
origin not allowed (open the Control UI from the gateway host 
or allow it in gateway.controlUi.allowedOrigins)
```

此时需要在配置中添加以下内容：

```json
"gateway": {
    "auth": {
      "mode": "token",
      "token": "<your-gateway-token>"
    },
    "bind": "lan",
    "controlUi": {
      "allowedOrigins": [
        "http://127.0.0.1:18789",
        "http://<your-lan-ip>:18789"
      ],
      "dangerouslyDisableDeviceAuth": true
    },
    "mode": "local",
    "port": 18789,
    "trustedProxies": [
      "127.0.0.1/32"
    ]
}
```

配置完成后，打开 OpenClaw 页面可直接看到一个对话测试窗口。如果 AI 能正常回复，说明 OpenClaw 已部署成功。
