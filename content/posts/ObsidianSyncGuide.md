---
title: "Obsidian 双机同步：Git Sync + GitHub 私有仓库全攻略"
date: 2026-06-22T23:08:00+08:00
draft: false
description: "手把手教你用 GitHub 私有仓库 + Git Sync 插件实现两台 Windows 电脑间 Obsidian 笔记自动双向同步，覆盖 SSH 密钥配置、OAuth 认证、防火墙代理踩坑、文件锁定问题等实战细节"
summary: "两台 Windows 电脑间 Obsidian 笔记自动同步的完整方案：GitHub 私有仓库 + Git Sync 插件，附带 HTTPS/SSH 切换和文件锁定等 3 个踩坑实录"
categories: ["知识管理"]
tags: ["Obsidian", "GitHub", "Git Sync", "笔记同步", "SSH", "OAuth"]
keywords: ["Obsidian同步", "Obsidian双机同步", "Git Sync插件", "GitHub私有仓库", "Obsidian多设备"]
series: ["知识管理"]
---

> 一台笔记本（移动办公） + 一台台式机（固定公司），怎么让两台电脑上的 Obsidian 笔记自动保持同步？这篇文章记录了用 GitHub 私有仓库 + Git Sync 插件实现的完整方案，包括配置步骤和 3 个踩坑实录。

## 一、场景与需求

| 设备 | 场景 | 需求 |
|------|------|------|
| 台式机 | 公司固定使用 | 主力编辑，自动 push，每次打开自动 pull |
| 笔记本 | 在家/公司/出差 | 随时读写，自动同步 |

核心要求：
- **全自动**：不需要手动 `git push/pull`
- **双向同步**：任何一边的修改都能同步到另一边
- **安全**：笔记内容不经过第三方服务器

最终选型：**GitHub 私有仓库 + Git Sync 插件**。

---

## 二、为什么选 Git Sync 插件？

Obsidian 社区插件市场有好几个 Git 同步插件：

| 插件 | 原理 | 评价 |
|------|------|------|
| **Git Sync**（Livan Kumar） | GitHub OAuth 授权，自动 commit + push + pull | 推荐，配置最简单 |
| Obsidian Git | 调用系统 git 命令 | 功能强大但需手动配置 |
| GitHub Sync (Multi-Platform) | GitHub API | 大文件限制 |

选择 **Git Sync** 的理由：
1. 用 GitHub OAuth，不需要手动创建 Token
2. 自动创建私有仓库，零配置上手
3. Auto-sync 开关一键开启

---

## 三、安全分析：OAuth 真的安全吗？

你可能会担心：插件不需要我提供 Token 就能访问我的 GitHub 仓库，数据安全吗？

### 3.1 认证方式对比

| 方式 | 实现 | 安全等级 |
|------|------|---------|
| Git Sync OAuth | 浏览器跳转 GitHub 授权，Token 存本地 | ⭐⭐⭐⭐ |
| 手动 PAT | 自己生成 Personal Access Token | ⭐⭐⭐⭐ |
| 明文密码 | 不推荐 | ❌ |

两者的安全级别相当。OAuth 的优势是 GitHub 官方授权流程，权限范围明确（仅 `repo`），随时可以在 GitHub → Settings → Authorized OAuth Apps 中一键撤销。

### 3.2 数据路径

```
Obsidian ←→ GitHub API ←→ GitHub 仓库
```

**数据不经过任何第三方服务器**。插件作者也看不到你的笔记。Token 只存本地插件目录。

> **结论**：Git Sync OAuth 方式足够安全，不需要手动 PAT。

---

## 四、完整配置步骤

### 第 1 步：台式机（主力机）初始化

**安装插件：**

1. Obsidian → 设置 → 第三方插件 → 关闭受限模式
2. 浏览 → 搜索 `Git Sync`（注意选作者 **Livan Kumar** 的）
3. 安装并启用

**连接 GitHub：**

1. 设置 → Git Sync → 点 **Connect to GitHub**
2. 浏览器自动打开 → 登录 GitHub → 授权
3. 授权成功自动跳回 Obsidian
4. 插件自动创建私有仓库（命名规则：`obsidian-<vault名称>`）

**开启自动同步：**

1. 设置 → Git Sync → 打开 **Auto-sync** 开关
2. 下方设置防抖间隔（默认 3000ms，即修改停止 3 秒后自动提交）

此时台式机上的任何修改，停笔 3 秒后自动 push 到 GitHub。

---

### 第 2 步：笔记本配置

不要在笔记本上创建空 Vault。正确的做法是**先克隆远程仓库，再用 Obsidian 打开**。

**① 克隆仓库到本地：**

```bash
# 确认 GitHub 仓库名（在台式机 Git Sync 设置里看 Repository 字段）
git clone git@github.com:sikinzen/obsidian-mybrain.git D:\Work\AI\MyBrain
```

我用的是 SSH 克隆（需要提前配置 SSH key）。如果还没有，执行：

```bash
ssh-keygen -t ed25519 -C "你的GitHub邮箱"
cat ~/.ssh/id_ed25519.pub
# 将输出内容添加到 GitHub → Settings → SSH and GPG keys
```

**② Obsidian 打开文件夹：**

打开 Obsidian → 打开其他仓库 → 打开文件夹作为仓库 → 选择 `D:\Work\AI\MyBrain`

**③ 安装 Git Sync 插件并授权：**

跟台式机步骤完全一样：安装 → Connect to GitHub → OAuth 授权 → 插件自动识别已有仓库 → 打开 Auto-sync。

此时两台设备都连接到了同一个 GitHub 私有仓库。

---

### 第 3 步：验证同步

1. 在台式机上修改任意文件，等待 3 秒
2. 去笔记本上刷新 Obsidian（或等插件自动 pull）
3. 确认修改已同步
4. 反过来：笔记本修改 → 台式机验证

双向同步确认成功后，日常使用中不需要任何手动操作。

---

## 五、踩坑一：HTTPS 被公司防火墙封堵

### 现象

台式机上执行 `git pull` 报错：

```
fatal: unable to access 'https://github.com/...':
Failed to connect to github.com port 443
```

### 原因

Git Sync 插件用 HTTPS + OAuth Token 克隆仓库，但公司防火墙拦截了 443 端口对 GitHub 的出站连接。

### 解决：把 remote 从 HTTPS 改为 SSH

```bash
cd D:\Work\AI\MyBrain
git remote set-url origin git@github.com:sikinzen/obsidian-mybrain.git
```

SSH 走 22 端口，只要你已配置好 SSH key，不受防火墙影响。

验证：

```bash
git remote -v
# origin  git@github.com:sikinzen/obsidian-mybrain.git (fetch)
# origin  git@github.com:sikinzen/obsidian-mybrain.git (push)
```

> **经验教训**：公司网络环境下，GitHub HTTPS 很可能不通。用 SSH 替代是最简单的解法。提前配好 SSH key 能省很多折腾。

---

## 六、踩坑二：文件锁定——插件和 git 命令互相抢占

### 现象

手动执行 `git pull` 时报错：

```
Unlink of file '.git/objects/pack/...idx' failed.
Should I try again?
```

即使关了 Auto-sync 也解决不了。

### 原因

Git Sync 插件在 Obsidian 内部维护了一个 Git 进程，后台持续监控文件变化。即使关掉 Auto-sync，**进程本身仍在运行**，锁住了 `.git` 目录下的 pack 文件。

手动 `git pull` 需要写入这些文件，但被插件进程占用，导致失败。

### 解决方案：完全退出 Obsidian 后操作

1. **关闭 Obsidian**（不是最小化，是完全退出）
2. 确认任务管理器中没有 `Obsidian.exe` 进程
3. 再执行 `git pull`
4. 手动同步完成后重新打开 Obsidian

或者 — **更彻底的方法** — 如果你确实是全新开始：

```bash
# 备份当前目录
move D:\Work\AI\MyBrain D:\Work\AI\MyBrain_backup
# 重新克隆
git clone git@github.com:sikinzen/obsidian-mybrain.git D:\Work\AI\MyBrain
```

> **经验教训**：Git Sync 插件管理 Git 操作时，避免在 Obsidian 运行期间手动执行 git 命令。两者会争抢 `.git` 锁。日常使用无需手动 git 操作——插件的 Auto-sync 已经够用。

---

## 七、踩坑三：重复仓库问题

### 现象

多次添加 Git Sync 插件后，GitHub 上出现了多个名字相似的仓库：

```
obsidian-mybrain
obsidian-obsidian-mybrain
MyBrain
```

### 原因

每次清除配置再重新添加插件，插件都会"智能"地创建新仓库，但命名规则导致叠加。

### 解决

1. 在 GitHub 上删除所有多余仓库（Settings → Danger Zone → Delete this repository）
2. 只保留一个
3. 某台设备上重新配置 Git Sync 指向唯一的仓库

---

## 八、日常使用建议

| 场景 | 操作 |
|------|------|
| 日常编辑 | 不需要任何操作，3 秒自动同步 |
| 新电脑加入 | git clone → 打开 Vault → 安装 Git Sync → OAuth 授权 |
| 冲突处理 | 极少发生（两台不同时编辑同一文件） |
| 检查同步状态 | Git Sync 面板显示最后同步时间 |

---

## 九、总结

**核心方案**：GitHub 私有仓库 + Git Sync 插件（OAuth 认证）

**关键教训**：
1. **SSH 优于 HTTPS**：公司防火墙环境下优先配置 SSH key
2. **别手动 git 操作**：插件和手动 git 会锁冲突，日常用插件就够了
3. **重复仓库要清理**：多次重配插件会产生多个仓库，手动删除多余的

这个方案的代价：30 分钟初始配置。收益：之后所有笔记自动同步，零维护。
