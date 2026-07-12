---
title: "Obsidian 三设备同步实战：Windows 双机 Git + Android Syncthing"
date: 2026-07-12T20:43:00+08:00
draft: false
description: "记录用 Obsidian Git（Vinzent 插件，Windows 双机）+ Syncthing（Android）实现 Obsidian 三设备同步的完整方案，重点讲解双机插件从易冲突的 Git Sync 更换为 Vinzent Git 的演变、Syncthing 文件夹共享的双向接受流程，并复盘『半小时零同步』的典型误判。"
summary: "Obsidian 三设备（Windows 双机 + Android）同步实战：Git 管双机（Vinzent Git 插件），Syncthing 管手机，含共享接受关键步骤与踩坑复盘。"
categories: ["知识管理"]
tags: ["Obsidian", "Syncthing", "Git", "笔记同步", "Android", "多设备"]
keywords: ["Obsidian三设备同步", "Obsidian Android同步", "Syncthing教程", "Vinzent Git插件", "笔记多端同步"]
series: ["知识管理"]
---

> 📚 本文是「Obsidian 知识管理」系列第三篇。同系列：
> - [从印象笔记到 Obsidian：一次完整的笔记迁移实战](/posts/evernotetoobsidian/)
> - [Obsidian 双机同步：Git Sync + GitHub 私有仓库全攻略](/posts/obsidiansyncguide/)

> 一台常开台式机 + 一台笔记本 + 一部 Android 手机，怎么让三端的 Obsidian 笔记始终保持一致，又尽量不产生 Git 冲突？这套方案跑了大半个月，期间踩过一个典型的「半小时零同步」坑，本文把完整配置和复盘一并记录下来。

## 一、为什么需要三设备同步

我的设备分布是这样的：

| 设备 | 角色 | 使用习惯 |
|------|------|----------|
| Windows 台式机 | 主力编辑，24h 常开 | 大量写作、整理 |
| Windows 笔记本 | 移动办公 | 随时读写 |
| Android 手机 | 随身携带 | 以查阅为主，偶尔新增 / 修改 |

核心诉求有两条：

1. **三端一致**：任何一端的修改，其他两端最终都能看到。
2. **尽量少冲突**：尤其是避免多方 Git 冲突导致整库无法同步。

第二条决定了架构分层的思路——**让手机绕开 Git**，只做文件级同步。

---

## 二、整体架构

```
┌──────────────┐   Vinzent Git (SSH)   ┌────────────────┐
│ Windows 笔记本 │ ───────────────────▶ │   GitHub 仓库   │
└──────────────┘ ◀─────────────────── └────────────────┘
                        ▲                      │
                        │ Vinzent Git (SSH)    │
                        │                      │
                  ┌─────┴──────┐               │
                  │ Windows 台式机 │ ◀───────────┘
                  │ (24h 常开)   │
                  └─────┬──────┘
                        │ Syncthing (P2P 直连，不走 Git)
                        ▼
                  ┌──────────────┐
                  │ Android 手机  │
                  └──────────────┘
```

要点：

- **双 Windows 机器**走 **Vinzent 的 Git 插件**，通过 SSH 连接 GitHub 私有仓库，自动 commit / push / pull。
- **Android 手机**不安装任何 Git 工具，改用 `Syncthing` 与台式机做 P2P 文件同步。
- **台式机是锚点**：既跑 Git 插件，又跑 Syncthing，把手机的文件变化桥接进 Git 工作流。

为什么手机不碰 Git：手机（尤其境内无 Google Play 环境）装 Termux + Git + SSH 既麻烦又容易和 Windows 产生三方冲突；而 Syncthing 只做文件读写，从根上消除了手机端的 Git 冲突风险。

---

## 三、Windows 双机：从 Git Sync 切换到 Vinzent 的 Git 插件

两台 Windows 机器的 Git 同步是整套方案的基础，但中间踩过插件选型的坑，单独说一下。

### 3.1 为什么放弃 Git Sync 插件

最初用的是社区里的 **Git Sync** 插件（Livan Kumar，基于 GitHub OAuth，自动建仓库）。它上手快，但实战中**经常产生冲突**——本质原因是它通过 GitHub API 做提交 / 合并，在双机频繁交替编辑时，容易出现「远程已更新、本地落后」的合并失败，严重时整库卡住无法同步。

### 3.2 改用 Vinzent 的 Git 插件

后来换成 **Vinzent 的 Git 插件**（在 Obsidian 社区插件商店里以 `Git` 为关键词搜索排名最高，常被称为 Obsidian Git）。它是本地调用 git 命令，行为更接近原生 git：

- 提交 / 拉取 / 推送逻辑透明可控
- 自动同步间隔可配（commit、pull、push 分别设置）
- 冲突时就是标准 git 冲突，按文件解决，不会整库卡死

**核心步骤：**

1. **准备仓库**：在 GitHub 创建私有仓库（如 `my-vault`），本地 `git clone` 到笔记目录（如 `<你的本地笔记目录>`）。
2. **配置 SSH**：生成 `ed25519` 密钥并添加到 GitHub → Settings → SSH and GPG keys；将 remote 设为 `git@github.com:<你的GitHub用户名>/<仓库名>.git`（SSH 比 HTTPS 更不容易被公司防火墙拦截）。
3. **安装 Vinzent Git 插件**：设置 → 第三方插件 → 浏览 → 搜索 `Git` → 安装启用（认准作者 Vinzent）。
4. **开启自动同步**：设置 Auto commit interval 与 Auto pull interval（建议 5–10 分钟）。
5. **忽略工作区与同步配置**：`.gitignore` 必须包含两项：
   ```
   .obsidian/
   .stfolder/
   ```
   - `.obsidian/` 是 Obsidian 的工作区配置（打开的标签页、面板布局等），不同设备不同，不应跨设备同步。
   - `.stfolder/` 是 **Syncthing 在每个同步文件夹里自动生成的标记目录**，用于标识该目录由 Syncthing 管理。它会被 Git 误当成普通文件跟踪，导致跨设备 `.stfolder` 内容打架——所以必须忽略。

两台机器都指向同一个仓库、且都忽略上述两项后，双机同步即建立。后续新增的 Android 只是挂在台式机这一个锚点上。

> 双机 Git 同步的早期尝试（Git Sync 插件 + OAuth）可参考本博客的《[Obsidian 双机同步](/posts/obsidiansyncguide/)》一文，其中记录了该插件的配置与踩坑——也正是因为它易冲突，才催生了本文的 Vinzent Git 方案。

---

## 四、Android 端准备

### 4.1 安装 Obsidian

- 优先在 Google Play 搜索 `Obsidian` 安装。
- 无 Google Play 的设备，可从 [Obsidian 官网](https://obsidian.md) 下载 APK 侧载（开启「未知来源」安装权限）。
- 安装后**先不急着创建 vault**，等 Syncthing 把笔记同步到手机目录后，再用 Obsidian 打开那个目录即可（见第六节）。

### 4.2 安装 Syncthing（实测于境内网络）

Syncthing 官方 Android 版已于 2024-12 停止维护，最后版本为 **1.28.1**（包名 `com.nutomic.syncthingandroid`）。APK 获取渠道与实测结果：

| 渠道 | 地址 | 实测 |
|------|------|------|
| GitHub Releases 直链 | `https://github.com/syncthing/syncthing-android/releases/download/1.28.1/app-release.apk` | ✅ 可正常下载 |
| F-Droid 页面 | `https://f-droid.org/en/packages/com.nutomic.syncthingandroid/` | ❌ 实测无法下载 |
| F-Droid 直链 | `https://f-droid.org/repo/com.nutomic.syncthingandroid_4380.apk` | ❌ 实测无法下载 |

下载后侧载安装，首次打开授予文件访问权限。

> **实测结论**：在境内网络环境下，GitHub Releases 直链可正常下载；F-Droid 的页面与直链均不可用。直接走 GitHub 直链即可，不必折腾 F-Droid。

---

## 五、Syncthing 配对与文件夹共享（核心）

这是整篇文章最关键的部分。Syncthing 的同步不是「加个设备就完事」，而是**设备配对 + 文件夹共享邀请 + 对端接受**三步，漏掉最后一步就会像我一样卡在「已连接但零字节」。

### 5.1 台式机：安装并获取设备 ID

1. 台式机从 [syncthing.net](https://syncthing.net) 下载 Windows 版，运行 `syncthing.exe`。
2. 浏览器打开管理界面 `http://127.0.0.1:8384`。
3. 右上角「操作」→「显示 ID」，复制这台机器的**设备 ID**（一长串字符）。

### 5.2 手机：添加远程设备

1. 打开手机 Syncthing → 底部「设备」→「+」→「添加设备」。
2. 粘贴台式机的设备 ID（或扫描台式机界面上的二维码）。
3. 设备名随意（如 `我的台式机`），保存。
4. 台式机端会弹出「远程设备想要连接」提示，点「添加」确认。

此时两端已互相识别、状态显示「已连接」。**但到此为止还不会同步任何文件**——因为还没有共享文件夹。

### 5.3 台式机：把文件夹共享给手机

1. 台式机 Syncthing Web UI →「文件夹」→ 选中你的笔记文件夹（如 `my-vault`）→「编辑」→「共享」。
2. 勾选刚才添加的手机设备。
3. 保存。

保存后，台式机会向手机**发送一份「文件夹共享邀请」**。

### 5.4 手机：接受共享邀请（关键步骤）

这一步是大多数人卡住的地方：

1. 打开手机 Syncthing → 右下角「设置」（齿轮）→ **Web GUI**。
2. 手机本地的 Syncthing Web GUI 会在浏览器中打开（通常是 `http://127.0.0.1:8384`）。
3. 进入后，界面顶部会出现一条通知：**「远程设备 XXX 想要共享文件夹 YYY」**。
4. 点击该通知 → **「接受」**。
5. 在弹出的对话框中选择手机上存放该 vault 的本地路径（如 `<你的手机笔记目录>`），确认。

> 部分版本的 Syncthing App 也会在「文件夹」页直接弹出共享邀请卡片，操作同理：点接受 → 选路径。

**接受之后，双向同步才真正开始。** 台式机有完整笔记、手机是空目录，Syncthing 默认 `发送和接收` 模式，会自动把台式机的内容拉取到手机。

### 5.5 忽略 `.obsidian/` 与 `.stfolder/`

在手机端该文件夹的「忽略模式」里添加：

```
.obsidian/
.stfolder/
```

- `.obsidian/`：不同设备的 Obsidian 工作区配置不同，不应跨设备同步，否则界面布局、打开的标签页会互相覆盖。
- `.stfolder/`：Syncthing 自身的标记目录，不应被同步（同步了反而会造成两端 Syncthing 互相干扰）。

Windows 端若已在 `.gitignore` 忽略这两项，此处再在 Syncthing 忽略一次，双保险。

---

## 六、Android 端 Obsidian 打开 vault

等首次同步完成（手机目录出现所有 `.md` 文件），再让 Obsidian 接管：

1. 打开手机 Obsidian → 「打开其他仓库」→「打开文件夹作为仓库」。
2. 选择 Syncthing 同步过来的目录（如 `<你的手机笔记目录>`）。
3. 笔记即刻全部显示，且后续手机上的修改会经 Syncthing 实时写回该目录。

顺序上**先同步、后打开 Obsidian** 最稳，能避免 Obsidian 在空目录里生成一套自己的 `.obsidian` 后再被 Syncthing 覆盖的尴尬。

---

## 七、踩坑实录：半小时零同步的真相

这部分值得单独写出来，因为它代表了一类非常典型的误判。

### 现象

配对完成后，台式机 Web UI 显示手机设备「已连接」，但：

- 同步进度长期 `0%`，待同步 `92.2 MiB`
- 连接类型显示「中继广域网」，速率 `1 B/s`
- 半小时后手机目录一个文件都没有

### 第一反应（错误）

看到「中继」+「1 B/s」，很自然地联想到：Syncthing 公共中继服务器在境外，境内访问被限速，所以中继不可用。于是去查 VPN、准备换 FolderSync + 坚果云等替代方案。

### 真相（正确）

**根因根本不是网络，而是文件夹共享邀请没被接受。**

只在一端「添加设备」并「共享文件夹」还不够——**对端必须在 Syncthing 里明确「接受」这份共享邀请，数据通道才会建立**。在此之前，两端虽然「已连接」，但没有任何文件夹处于共享状态，自然零字节。所谓 `1 B/s` 只是连接保活的探测流量，不是真实传输。

一旦按第五节在手机端 `设置 → Web GUI` 里接受邀请，连接类型依旧可能显示「中继」（取决于当时网络是否能直连），但**速率立刻恢复正常、进度开始增长**，几分钟内手机拿到全部笔记——全程**没有开任何 VPN**。

### 经验

- Syncthing「已连接 ≠ 已同步」。看到「已连接」先检查**两端是否都接受了彼此的文件夹共享**，而不是急着怀疑网络。
- 境内使用 Syncthing 不一定要翻墙。能否直连取决于网络环境（IPv6、NAT 类型等），即便走中继，只要共享流程完整，速度通常也可接受。
- 排查顺序建议：设备在线 → 文件夹已互相共享且对端已接受 → 忽略模式无误 → 再看连接类型与速率。

---

## 八、验证与冲突规避

| 检查项 | 预期 |
|--------|------|
| 台式机修改笔记 | 数分钟后手机 Obsidian 中出现 |
| 手机修改 / 新增笔记 | 经 Syncthing 写回目录 → 台式机 Git 插件自动提交 → 推送 GitHub → 笔记本拉取 |
| 连接状态 | 台式机 Web UI 中手机设备「已连接」、文件夹进度 100% |

冲突规避要点：

- **手机不执行 Git 操作**，从源头消除手机端 Git 冲突。
- `.obsidian/` 与 `.stfolder/` 在 Git 与 Syncthing 双重忽略。
- 尽量避免手机与 Windows 同时编辑同一篇笔记；万一冲突，Syncthing 会生成 `.sync-conflict-` 副本，不丢数据，手动合并即可。
- 台式机保持常开，确保 Git 插件自动提交 / 拉取持续运行，桥接手机与 GitHub。

---

## 九、维护清单

- [ ] 台式机 24h 常开，Syncthing 与 Obsidian 后台运行
- [ ] 台式机 Git 插件：Auto commit / Auto pull 间隔 5–10 分钟
- [ ] 每季度确认一次手机 ↔ 台式机 Syncthing 连接正常
- [ ] 关注 Syncthing Android 停更后的替代方案（FolderSync / 社区 Fork），但当前 1.28.1 仍可正常使用
- [ ] 含账户密码的笔记（如备忘录）注意不要误推到公开仓库

---

## 十、小结

三设备同步的本质是**职责分层**：

- **Git（Vinzent 插件）** 负责双 Windows 机器的版本化同步，稳、可追溯；
- **Syncthing** 负责手机与锚点台式机的文件级同步，简单、无冲突；
- **台式机**作为桥接点，把两者的变化汇流。

最容易翻车的不是网络，而是 Syncthing 的「共享邀请需对端接受」这一步——记住它，能省下我那白绕一圈的半小时。

*最后更新：2026-07-12*
