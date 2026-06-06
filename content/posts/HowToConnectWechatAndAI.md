---
title: "让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南"
date: 2026-06-06T14:30:00+08:00
draft: false
description: "从零打通 WorkBuddy AI 助手与微信本地数据库的完整过程，包含 WeChat 4.1+ 新版密钥派生方案的踩坑与解决"
summary: "记录将个人微信聊天记录接入 AI 助手的完整过程，重点解决 WeChat 4.1+ 新版加密密钥派生问题，实现 AI 读取微信聊天记录"
categories: ["AI应用"]
tags: ["微信", "AI助手", "WorkBuddy", "Python", "SQLCipher", "wx_key"]
keywords: ["微信聊天记录", "AI助手", "wechat-cli", "wx_key", "PBKDF2", "SQLCipher解密"]
series: ["AI工具链"]
---

## 背景：为什么要把微信接入 AI？

日常工作中，大量沟通在微信里完成——项目讨论、需求确认、问题排查……这些信息分散在不同聊天窗口，很难回顾和整理。

如果能让我用的 AI 助手（WorkBuddy）直接读取微信聊天记录，就可以：

- 📋 **自动整理会议讨论要点**
- 🔍 **跨聊天搜索关键信息**（不用再一条条翻记录）
- 📊 **统计沟通频率和活跃时段**
- 💾 **导出重要对话存档**

听起来很美好，但微信的聊天数据库是加密的，直接读取并不容易。本文记录了**从零打通**的全过程，包括一个关键的坑——**WeChat 4.1+ 版本的密钥派生问题**。

---

## 技术原理：微信本地数据库是怎么加密的？

微信 Windows 客户端使用 **SQLCipher** 加密本地数据库，核心加密参数：

| 参数 | 值 |
|------|-----|
| 加密算法 | AES-256-CBC |
| 页面大小 | 4096 字节 |
| Salt 位置 | 每个数据库文件前 16 字节 |
| KDF | PBKDF2-HMAC-SHA512 |
| KDF 迭代次数 | 256,000 |
| HMAC | HMAC-SHA512 |

微信的数据目录通常在 `C:\Users\<用户名>\Documents\xwechat_files\<微信ID>\db_storage\`，里面有十几个 `.db` 文件，每个都用不同的密钥加密（因为每个文件的 salt 不同）。

### 关键变化：WeChat 4.0 vs 4.1

这是整个过程中**最大的坑**，也是网上大多数教程没有提到的：

| 版本 | 内存中存储的内容 | 提取方式 |
|------|-----------------|---------|
| **4.0.x** | PBKDF2 派生后的原始加密密钥（`x'<hex>'` 格式） | 内存扫描可直接提取，拿来即用 |
| **4.1+** | 派生前的 **passphrase**（一段原始密钥材料） | 内存扫描只能提取 passphrase，还需 PBKDF2 派生才能得到实际加密密钥 |

也就是说，如果你按 4.0 时代的教程操作，在 4.1+ 上拿到的"密钥"根本解不开数据库——因为它不是最终密钥，而是密钥的原材料。

---

## 第一步：安装 wechat-cli

[wechat-cli](https://github.com/pingao123/wechat-cli) 是一个 Python 命令行工具，可以读取本地微信的加密数据库，提取聊天记录、联系人等信息。

```bash
# 方式一：从 PyPI 安装
pip install wechat-cli

# 方式二：从源码安装（我用的方式，因为需要适配 WorkBuddy 环境）
git clone https://github.com/pingao123/wechat-cli.git
cd wechat-cli
pip install -e .
```

> ⚠️ **环境隔离提示**：如果你用的是 WorkBuddy 等 AI 助手，它可能有自己的 Python 环境。务必确认 `wechat-cli` 安装到了正确的 Python 环境中，否则后续调用会找不到命令。

安装后验证：

```bash
wechat-cli --version
# 输出：wechat-cli, version 0.2.4
```

---

## 第二步：尝试初始化（遇到第一个坑）

按照文档，运行 `wechat-cli init` 应该能自动从微信进程内存中提取加密密钥：

```bash
wechat-cli init
```

**结果：0/18 salts matched** —— 18 个数据库文件，一个都没解开。

### 排查过程

1. **确认微信版本**：我的微信是 **4.1.10.29**（Windows），而 wechat-cli 的内存扫描方式是为 4.0.x 设计的
2. **尝试 wechat-decrypt**：这是 wechat-cli 的上游项目，同样使用内存扫描——同样失败
3. **确认不是环境问题**：刚开始以为是 WorkBuddy 重装导致的，但反复排查后发现，是微信版本升级后密钥提取方式变了

### 根因

WeChat 4.1+ 不再在进程内存中缓存派生后的原始加密密钥，只存储派生前的 passphrase。传统的内存扫描方式找到的值无法直接用于 SQLCipher 解密。

---

## 第三步：使用 wx_key 提取 passphrase

[wx_key](https://github.com/ycccccccy/wx_key) 是一个专门针对 WeChat 4.1+ 的密钥提取工具，使用 **DLL 注入**方式而非内存扫描。

### 下载与运行

从 [GitHub Releases](https://github.com/ycccccccy/wx_key/releases) 下载最新版（我用的 v2.1.8），解压后运行 `wx_key.exe`。

> ⚠️ **DLL 注入安全性**：wx_key 通过 DLL 注入方式读取微信进程内存。实际测试中，注入后微信功能正常，不会导致崩溃或异常。但仍建议仅在个人学习研究目的下使用。

### 操作步骤

1. 确保**微信客户端正在运行并已登录**
2. 打开 `wx_key.exe`，它会自动检测微信进程
3. 点击**获取密钥**按钮
4. 工具会显示一串十六进制字符串——这就是 **passphrase**（不是最终的加密密钥！）

示例输出：

```
83f480fab7324b6881df635621ce4c996bf5e06154db4f92866e99859597582a
```

> ⚠️ **关键认知**：这串 hex 不是加密密钥本身，而是密钥的"原材料"。每个数据库文件有自己的 salt，需要用 PBKDF2 算法结合 salt 才能派生出真正的加密密钥。

---

## 第四步：PBKDF2 密钥派生（核心步骤）

这是整篇文章**最关键的部分**——把 passphrase 转换为每个数据库的实际加密密钥。

### 派生原理

```
加密密钥 = PBKDF2-HMAC-SHA512(passphrase, salt, iterations=256000, dklen=32)
```

其中：
- `passphrase`：wx_key 提取的十六进制字符串，转为 bytes
- `salt`：每个 `.db` 文件的前 16 字节
- `iterations`：256000 次（微信的固定参数）
- `dklen`：32 字节（AES-256 需要）

### 完整派生脚本

```python
import hashlib
import os
import json

# ====== 配置区 ======
# 微信数据库目录（根据你的实际路径修改）
db_dir = r'C:\Users\<用户名>\Documents\xwechat_files\<微信ID>\db_storage'
# wx_key 提取的 passphrase（替换为你的实际值）
passphrase_hex = '<从 wx_key 获取>'
# ====== 配置区结束 ======

passphrase = bytes.fromhex(passphrase_hex)

result = {}
for root, dirs, files in os.walk(db_dir):
    for name in files:
        # 跳过 WAL 和 SHM 文件
        if not name.endswith('.db') or name.endswith(('-wal', '-shm')):
            continue

        path = os.path.join(root, name)
        size = os.path.getsize(path)

        # 跳过空文件
        if size < 4096:
            continue

        # 读取第一页（4096字节），前16字节是 salt
        with open(path, 'rb') as f:
            page1 = f.read(4096)

        salt = page1[:16]

        # PBKDF2-HMAC-SHA512 派生密钥
        enc_key = hashlib.pbkdf2_hmac(
            'sha512',
            passphrase,
            salt,
            256000,
            dklen=32
        )

        rel = os.path.relpath(path, db_dir)
        result[rel] = {
            "enc_key": enc_key.hex(),
            "salt": salt.hex(),
            "size_mb": round(size / 1024 / 1024, 1)
        }

# 写入 wechat-cli 的配置目录
output_dir = os.path.expanduser('~/.wechat-cli')
os.makedirs(output_dir, exist_ok=True)

with open(os.path.join(output_dir, 'all_keys.json'), 'w') as f:
    json.dump(result, f, indent=2)

# 同时写入数据库目录配置
config = {"db_dir": db_dir}
with open(os.path.join(output_dir, 'config.json'), 'w') as f:
    json.dump(config, f, indent=2)

# 验证结果
print(f"成功派生 {len(result)} 个数据库的加密密钥")
for name, info in result.items():
    print(f"  {name}: {info['size_mb']}MB, key={info['enc_key'][:16]}...")
```

运行脚本后，`~/.wechat-cli/all_keys.json` 中会保存所有数据库的派生密钥，`~/.wechat-cli/config.json` 保存数据库路径配置。

### 验证成功

我的环境输出：

```
成功派生 18 个数据库的加密密钥
  MicroMsg.db: 39.2MB, key=a3f2e1b4c5d67890...
  MSG0.db: 156.7MB, key=b4c5d6e7f8901234...
  ...
```

18/18 全部成功！🎉

---

## 第五步：使用 wechat-cli 读取聊天记录

密钥配置好后，就可以正常使用 wechat-cli 了：

### 查看最近会话

```bash
wechat-cli sessions --format text
```

### 查看与某人的聊天记录

```bash
# 按昵称查看
wechat-cli history "黄磊" --limit 20 --format text

# 按微信 ID 查看（如果昵称不匹配，用 ID 更准确）
wechat-cli history "babyfacehl" --limit 20 --format text
```

### 按时间范围查询

```bash
wechat-cli history "babyfacehl" --start-time "2026-06-05" --end-time "2026-06-06" --format text
```

### 搜索消息

```bash
# 全局搜索
wechat-cli search "项目进度" --format text

# 在指定聊天中搜索
wechat-cli search "需求" --chat "产品组" --format text
```

### 导出聊天记录

```bash
# 导出为 Markdown
wechat-cli export "黄磊" --format markdown

# 导出为 HTML
wechat-cli export-html "黄磊"
```

---

## 第六步：配置为 WorkBuddy Skill

为了让 AI 助手更方便地调用，我把 wechat-cli 配置成了 WorkBuddy 的 Skill（技能）。

### 创建 Skill 文件

在 `~/.workbuddy/skills/wechat-cli/SKILL.md` 中定义技能，包含：
- 工具说明和命令列表
- 可执行文件路径
- WeChat 4.1+ 的特殊处理流程（wx_key + PBKDF2）
- 故障排除指南

### 关键配置

Skill 中最重要的是记录 **WeChat 4.1+ 的完整密钥提取流程**，确保 AI 助手在密钥失效时能指导用户重新操作：

1. 运行 wx_key 提取 passphrase
2. 执行 PBKDF2 派生脚本
3. 验证 all_keys.json 生成成功

---

## 完整架构图

```
┌─────────────────────────────────────────────────┐
│                  WorkBuddy AI                    │
│              (你的 AI 助手)                       │
└──────────────┬──────────────────────────────────┘
               │  调用 Skill
               ▼
┌─────────────────────────────────────────────────┐
│              wechat-cli Skill                    │
│  ┌───────────────────────────────────────────┐  │
│  │  命令：sessions / history / search / ...  │  │
│  └───────────────────────────────────────────┘  │
└──────────────┬──────────────────────────────────┘
               │  读取密钥 + 解密查询
               ▼
┌─────────────────────────────────────────────────┐
│           ~/.wechat-cli/all_keys.json            │
│        (PBKDF2 派生后的 18 个数据库密钥)         │
└──────────────┬──────────────────────────────────┘
               │  密钥来源（密钥失效时需重新操作）
               ▼
┌─────────────────────────────────────────────────┐
│              wx_key (DLL 注入)                   │
│         提取 WeChat 4.1+ passphrase             │
└──────────────┬──────────────────────────────────┘
               │  读取微信进程内存
               ▼
┌─────────────────────────────────────────────────┐
│           WeChat 4.1+ 进程内存                   │
│        (存储 passphrase 而非派生密钥)            │
└─────────────────────────────────────────────────┘
               │  passphrase + salt → PBKDF2 → enc_key
               ▼
┌─────────────────────────────────────────────────┐
│      微信本地数据库 (SQLCipher 加密)              │
│   MicroMsg.db / MSG0.db / Contact.db / ...     │
│   (每个 .db 文件前 16 字节 = salt)               │
└─────────────────────────────────────────────────┘
```

---

## 踩坑完整记录

| # | 问题 | 根本原因 | 解决方法 |
|---|------|---------|---------|
| 1 | `wechat-cli init` 返回 0/18 salts matched | WeChat 4.1+ 内存中不再缓存派生后的密钥 | 使用 wx_key DLL 注入提取 passphrase |
| 2 | wechat-decrypt 同样失败 | 同上，所有基于内存扫描的方案都不适用 4.1+ | 同上 |
| 3 | wx_key 提取的值直接验证失败 | 提取的是 passphrase，不是加密密钥 | 用 PBKDF2-HMAC-SHA512 派生实际密钥 |
| 4 | wechat-cli 安装到了系统 Python，WorkBuddy 找不到 | WorkBuddy 有自己的 Python 隔离环境 | 安装到 WorkBuddy 的 Python 路径下 |
| 5 | wx_key 从 Gitee 下载超时/损坏 | Gitee CDN 不稳定 | 改用 GitHub 镜像下载 |
| 6 | 密钥在微信重启后失效 | passphrase 是动态的，每次登录可能改变 | 重新运行 wx_key + PBKDF2 派生脚本 |

### 重点展开：问题 #3 —— passphrase ≠ 加密密钥

这是最容易搞错的一步。wx_key 输出的值看起来就像一个密钥（64 个十六进制字符 = 32 字节），但实际上它是 PBKDF2 的输入参数 passphrase。

**错误做法（❌）：**

```python
# 直接把 wx_key 输出当密钥用
key = bytes.fromhex("83f480fab732...")
# → SQLCipher 解密失败！
```

**正确做法（✅）：**

```python
import hashlib

passphrase = bytes.fromhex("83f480fab732...")
salt = db_file_first_16_bytes  # 从 .db 文件读取
enc_key = hashlib.pbkdf2_hmac('sha512', passphrase, salt, 256000, dklen=32)
# → 18/18 全部解密成功！
```

**为什么？** 因为 WeChat 4.1+ 的设计是：每个数据库文件有独立的 salt（文件头前 16 字节），运行时用 `PBKDF2(passphrase, salt, 256000)` 动态派生加密密钥。这样即使某个数据库的密钥被泄露，其他数据库仍然安全。

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **违反服务条款** — 读取微信本地数据库可能违反微信服务条款
2. **账号风险** — 微信有权对使用第三方工具的账号进行限制
3. **版本兼容** — 微信更新后工具可能失效，需要等待社区适配
4. **密钥时效** — passphrase 在微信重启或更新后可能改变，需重新提取
5. **杀毒软件** — DLL 注入可能被杀毒软件拦截，需要临时关闭或加白名单

**建议：**
- 仅在**个人学习研究**目的下使用
- 不要在**处理重要业务的账号**上使用
- 定期备份 `~/.wechat-cli/all_keys.json`，避免重复操作
- 了解并接受可能的后果

---

## 总结

| 环节 | 工具 | 难度 | 备注 |
|------|------|------|------|
| 安装 wechat-cli | pip | ⭐ | 注意 Python 环境隔离 |
| 提取 passphrase | wx_key | ⭐⭐ | DLL 注入，需要微信运行中 |
| PBKDF2 密钥派生 | Python 脚本 | ⭐⭐⭐ | **核心步骤**，4.1+ 必须 |
| 配置 WorkBuddy Skill | SKILL.md | ⭐⭐ | 一次配置，长期使用 |
| 日常使用 | wechat-cli 命令 | ⭐ | 密钥失效时需重新执行步骤 2~3 |

**核心收获：** WeChat 4.1+ 的加密体系从"直接缓存派生密钥"升级为"运行时 PBKDF2 派生"，这意味着传统的内存扫描方案不再适用。理解 passphrase → PBKDF2 → enc_key 的派生链路，是打通微信与 AI 的关键。

如果你也在尝试将微信数据接入 AI 助手，希望这篇文章能帮你少走弯路。

---

*本文由 AI 助手（WorkBuddy）辅助整理，所有踩坑经验均为真实记录。*
