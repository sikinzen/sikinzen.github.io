---
title: "让 AI 读懂你的企业微信：wechat-decrypt 接入指南"
date: 2026-06-06T16:10:00+08:00
draft: false
description: "从零打通 WorkBuddy AI 助手与企业微信本地数据库的完整过程，对比个人微信方案，企微其实更简单"
summary: "记录将企业微信聊天记录接入 AI 助手的完整过程，对比个人微信的接入方案，展示企微 wxSQLite3 加密与一键解密的实操步骤"
categories: ["AI应用"]
tags: ["企业微信", "WeCom", "AI助手", "WorkBuddy", "Python", "wxSQLite3", "wechat-decrypt"]
keywords: ["企业微信聊天记录", "AI助手", "wechat-decrypt", "wxSQLite3解密", "企微数据库"]
series: ["AI工具链"]
---

## 背景：为什么要让 AI 读企业微信？

上一篇写了[个人微信接入 AI 的指南](./HowToConnectWechatAndAI.md)，解决的是社交沟通数据的 AI 化问题。但对于日常办公来说，**企业微信才是主战场**——项目协调、需求确认、问题排查、跨部门沟通……大量关键信息沉淀在企微的聊天记录里。

如果能让我用的 AI 助手（WorkBuddy）直接读取企微聊天记录，就可以：

- 📋 **自动整理每日工作事项**（不用自己翻聊天逐条总结）
- 🔍 **跨群搜索项目关键信息**（项目讨论散落在 N 个群里）
- 👥 **查询组织架构和联系人**（"帮我看看 XX 部门有谁"）
- 📊 **统计沟通频率和活跃时段**（谁最活跃？哪些群最忙？）

好消息是：**企业微信比个人微信更容易打通**。为什么？往下看。

---

## 先说结论：企微 vs 个人微信

| 对比项 | 个人微信 | 企业微信 |
|--------|----------|----------|
| 加密方式 | SQLCipher 4 (AES-256-CBC + HMAC-SHA512) | wxSQLite3 (AES-128-CBC) |
| 密钥长度 | 32 字节（256 bit） | 16 字节（128 bit） |
| 密钥数量 | 每个数据库文件独立密钥（需 PBKDF2 派生） | **一个总密钥解密所有库** |
| 密钥提取难度 | 高（4.1+ 需 DLL 注入 + PBKDF2 派生） | **低**（直接内存结构体扫描） |
| 解密验证 | 有 HMAC 校验（双重验证） | 无 HMAC（单层加密） |
| 社区评价 | — | 看雪论坛："企业微信是所有同类产品里解密最简单的" |
| 配置难度 | ⭐⭐⭐⭐ | ⭐⭐ |

简单来说：**个人微信 4.1+ 需要三步（DLL 注入 → 提取 passphrase → PBKDF2 派生），企微只需要一步（内存扫描）**。

---

## 技术原理：企微本地数据库是怎么加密的？

### 加密算法

企业微信使用 **wxSQLite3**（SQLite 的 AES 加密扩展），比个人微信的 SQLCipher 简单得多：

```
加密算法：AES-128-CBC（每页独立派生 key/IV）
Key 派生：page_index + "sAlT" → AES key
IV 派生：page_index → IV
密钥长度：16 字节（128 bit）
HMAC 校验：无（比 SQLCipher 少一层验证）
```

### 密钥存储

- 有一个**全局总密钥**，存在 WXWork 进程的内存中
- 每个数据库文件在打开时，由总密钥 + page_index 派生出每页的加密 key 和 IV
- **总密钥可以直接从进程内存中扫描提取**——不需要像个人微信 4.1+ 那样做 PBKDF2 派生

### 数据目录

```
C:\Users\<用户名>\Documents\WXWork\<账号ID>\Data\
├── message.db        # 聊天消息（核心，85.8MB）
├── session.db        # 会话列表（2.6MB）
├── user.db           # 联系人/同事信息（1.9MB）
├── message_lookup.db # 消息索引（11.7MB）
├── file.db           # 文件传输记录（12.3MB）
├── company.db        # 企业信息（0.2MB）
├── calendar_r7.db    # 日程信息（1.1MB）
├── crm.db            # CRM 数据（0.4MB）
└── ...
```

---

## 第一步：下载 wechat-decrypt

[wechat-decrypt](https://github.com/ylytdeng/wechat-decrypt) 是一个同时支持个人微信 4.x 和企业微信 5.x 的解密工具，功能比 wechat-cli 更全面。

```bash
cd D:\Software\AI
git clone https://github.com/ylytdeng/wechat-decrypt.git
cd wechat-decrypt
```

### 安装 Python 依赖

```bash
# 如果你用 WorkBuddy，需要安装到它自己的 Python 环境
C:\ProgramData\WorkBuddy\chromium-env\6npn1c\.workbuddy\binaries\python\versions\3.13.12\python.exe -m pip install pycryptodomex>=3.19 zstandard>=0.22 mcp>=1.0 pillow>=10.2 flask>=3.0 tqdm
```

> ⚠️ **坑**：项目自带的 `requirements.txt` 在 Git 克隆时可能因为编码问题损坏（中文注释导致 UTF-8 解码失败）。如果遇到 `MetadataGenerationFailed` 错误，手动重写 `requirements.txt` 或直接用上面的命令安装即可。

验证依赖安装：

```bash
python -c "import Cryptodome; import zstandard; import mcp; import PIL; import flask; import tqdm; print('All dependencies OK')"
```

---

## 第二步：配置数据目录

我的企微有 4 个数据目录（同一个企微账号的不同上下文）：

```
C:\Users\施金前\Documents\WXWork\
├── 1688855742617177\  ← 主账号（19 个数据库，17 个加密）
├── 1688855585443204\  ← 子上下文（15 个数据库，14 个加密）
├── 1688856108727960\  ← 子上下文
└── 1688856235822640\  ← 子上下文
```

创建配置文件 `config.json`，指定主账号的数据目录：

```json
{
  "wxwork_db_dir": "C:\\Users\\施金前\\Documents\\WXWork\\1688855742617177\\Data"
}
```

> 💡 **如何判断哪个是主账号？** 统计每个 `Data` 目录下的 `.db` 文件数量和加密数量，最多的那个通常是主账号。可以用这个脚本快速检查：

```python
import os

docs = r'C:\Users\<用户名>\Documents\WXWork'
for name in os.listdir(docs):
    data_dir = os.path.join(docs, name, 'Data')
    if not os.path.isdir(data_dir):
        continue
    encrypted = 0
    plain = 0
    total = 0
    for fname in os.listdir(data_dir):
        if not fname.endswith('.db'):
            continue
        fpath = os.path.join(data_dir, fname)
        if os.path.getsize(fpath) < 4096:
            continue
        total += 1
        with open(fpath, 'rb') as f:
            header = f.read(16)
        if header == b'SQLite format 3\x00':
            plain += 1
        else:
            encrypted += 1
    if total > 0:
        print(f'{name}: total={total}, encrypted={encrypted}, plain={plain}')
```

---

## 第三步：提取企微密钥（一步搞定！）

### 前提条件

1. 企业微信客户端**正在运行并已登录**
2. 命令行以**管理员权限**运行

### 运行密钥提取

```bash
cd D:\Software\AI\wechat-decrypt
python find_wxwork_keys.py
```

**输出：**

```
Found WXWork process: PID=16700
Scanning memory for cipher keys...
Found 1 key, verifying against 17 encrypted databases...
✓ Key verification: 15/15 salts matched (15/17 databases are encrypted)
Keys saved to wxwork_keys.json
```

**15/15 全部匹配！** 一个 16 字节的 raw key 解密了所有 17 个数据库。

跟个人微信对比一下：
- 个人微信 4.1+：需要 wx_key DLL 注入 → 提取 passphrase → PBKDF2 派生 → 18 个密钥
- 企微 5.x：**一个命令，一个密钥，搞定一切**

### 为什么这么简单？

`find_wxwork_keys.py` 的实现原理：

1. 通过 `tasklist` 找到 `WXWork.exe` 进程
2. 使用 Windows API `ReadProcessMemory` 扫描进程内存
3. 在内存中搜索 wxSQLite3 的 cipher 对象结构体
4. 从结构体中提取 16 字节的 raw key
5. 用这个 key 对每个数据库的第一个 salt 做 AES 解密验证

因为企微是 **32-bit 进程**（指针大小 4 字节），且 wxSQLite3 的 cipher 结构体特征明显，所以扫描成功率极高。

---

## 第四步：解密数据库

```bash
python decrypt_wxwork_db.py
```

**输出：**

```
Decrypting 17 encrypted databases...
  ✓ message.db (85.8MB)
  ✓ session.db (2.6MB)
  ✓ user.db (1.9MB)
  ✓ message_lookup.db (11.7MB)
  ✓ file.db (12.3MB)
  ... (more)
  ✓ calendar_r7.db (1.1MB)
  ✓ crm.db (0.4MB)

Copied 2 plain databases (no encryption).

Result: 17 decrypted, 2 copied, 0 failed.
Output directory: wxwork_decrypted/
```

**17 个加密库全部解密，2 个明文库直接复制，0 失败。** 🎉

解密后的数据库是标准 SQLite 格式，可以用任何 SQLite 工具打开。

---

## 第五步：验证数据与导出消息

### 列出所有会话

```bash
python export_wxwork_messages.py --list
```

**输出（部分）：**

```
R:22518021787036791801    1824   2026-06-06 15:05  群聊  WX08 T610平台【B1&谨讯】沟通群
MAIL                      28587  2026-06-06 15:04  应用  企业邮箱
R:22518021787036791942     622   2026-06-06 13:42  群聊  NYX-EWP售后不开机问题分析
S:1688855742617177_1688858071614068   36  2026-06-05 17:30  单聊  王明
...
--- 605 conversations with messages ---
```

**605 个企微会话**全部可读！

会话 ID 格式说明：
- `R:<数字>` — 群聊
- `S:<数字>_<数字>` — 单聊
- `O:<数字>` — 应用/公众号
- `MAIL` — 企业邮箱

### 导出聊天记录

```bash
# 导出为 JSON
python export_wxwork_messages.py --conversation "S:1688855742617177_1688858071614068" --formats json

# 导出为 HTML（可以在浏览器里看）
python export_wxwork_messages.py --conversation "R:22518021787036791801" --formats html

# 同时导出多种格式
python export_wxwork_messages.py --conversation "MAIL" --formats json,csv,html
```

### 直接 SQL 查询（高级用法）

解密后的数据库是标准 SQLite，可以直接查询：

```python
import sqlite3

conn = sqlite3.connect(r'D:\Software\AI\wechat-decrypt\wxwork_decrypted\message.db')
cur = conn.cursor()

# 查询今天的所有消息
cur.execute('''
    SELECT conversation_id, sender_id, content_type,
           datetime(send_time, 'unixepoch', 'localtime') as time
    FROM message_table
    WHERE date(send_time, 'unixepoch', 'localtime') = '2026-06-06'
    ORDER BY send_time DESC
''')

for row in cur.fetchall():
    print(f'[{row[3]}] conv={row[0]}, sender={row[1]}, type={row[2]}')

conn.close()
```

---

## 第六步：配置为 WorkBuddy Skill

为了让 AI 助手更方便地调用，我把企微的查询流程配置成了 WorkBuddy Skill。

### Skill 定义

在 `~/.workbuddy/skills/wecom-cli/SKILL.md` 中定义，包含：

- **初始化流程**：密钥提取 + 数据库解密的完整命令
- **可用命令**：列出会话、导出消息、SQL 查询、Web UI 监听
- **数据库说明**：每个 .db 文件的用途和大小
- **消息类型对照表**：content_type 与消息类型的映射
- **使用场景示例**：4 个常见场景的命令模板
- **故障排除**：3 个常见问题的解决方案

### 使用方式

配置好 Skill 后，直接在 WorkBuddy 对话中说：

```
@skill:wecom-cli 列出我企微最近 10 个会话
@skill:wecom-cli 帮我导出「WX08 T610平台」群的聊天记录
@skill:wecom-cli 查看与王明的单聊最近 20 条消息
@skill:wecom-cli 整理今天企微都有哪些事情
```

AI 助手会自动调用解密后的数据库，查询并整理结果。

---

## 实战：AI 整理今日企微事项

配置好之后，我试了一下让 AI 整理今天企微的所有工作事项：

```
@skill:wecom-cli 帮我整理下企微今天都有哪些事情？
```

AI 自动查询了 16 个会话、53 条消息，整理出了：

| 优先级 | 事项 | 来源群 |
|--------|------|--------|
| 🔴 紧急 | PAYJOY 版本今日合入发布版本 | WX08 T610平台群 |
| 🟡 重要 | 微信小程序长期订阅审核方案 | 菊风RTC2&寰乐群 |
| 🟡 重要 | 2848 老化/稳定性测试输出 | 创启@WW讨论群 |
| 🟢 一般 | Cloud5&Nyx-Lite 版本邮件释放 | D3|谨讯群 |
| 🟢 一般 | SE-JM268 FPC 寄送 | 蜂巢毛绒demo群 |
| 🟢 一般 | NYX-EWP 尼尔利亚主板内存确认 | 售后不开机群 |

甚至还能查询组织架构：

```
@skill:wecom-cli 软件中心下施金前直接管理的主要是哪些人？
```

AI 从 `user.db` 中查询了部门-人员关联，整理出了完整的组织架构：

```
厦门软件中心（施金前 - 软件总监）
├── 新业务部（庄舜冯 - 产品经理）10人
├── 智能机部（吴一心 - 智能机主管）9人
├── 影像部（陈群贤 - 影像部主管）1人
└── 驱动部（金强 - 驱动主管）5人
```

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
│              wecom-cli Skill                     │
│  ┌───────────────────────────────────────────┐  │
│  │  命令：--list / --conversation / SQL     │  │
│  └───────────────────────────────────────────┘  │
└──────────────┬──────────────────────────────────┘
               │  读取解密数据库
               ▼
┌─────────────────────────────────────────────────┐
│          wxwork_decrypted/ (SQLite 明文)         │
│  message.db / session.db / user.db / ...        │
└──────────────┬──────────────────────────────────┘
               │  解密来源
               ▼
┌─────────────────────────────────────────────────┐
│          wxwork_keys.json (16 字节 raw key)      │
│        (一个密钥解密所有 17 个数据库)            │
└──────────────┬──────────────────────────────────┘
               │  密钥来源（密钥失效时需重新提取）
               ▼
┌─────────────────────────────────────────────────┐
│        find_wxwork_keys.py (内存扫描)            │
│     扫描 WXWork 进程中的 cipher 结构体           │
└──────────────┬──────────────────────────────────┘
               │  读取企微进程内存
               ▼
┌─────────────────────────────────────────────────┐
│           WXWork 5.x 进程内存                    │
│      (32-bit, cipher 对象特征明显)               │
└─────────────────────────────────────────────────┘
               │  加密存储
               ▼
┌─────────────────────────────────────────────────┐
│     企微本地数据库 (wxSQLite3 加密)              │
│   message.db / session.db / user.db / ...       │
│   (AES-128-CBC, 无 HMAC, 一个总密钥)            │
└─────────────────────────────────────────────────┘
```

---

## 踩坑记录

| # | 问题 | 根本原因 | 解决方法 |
|---|------|---------|---------|
| 1 | `requirements.txt` 安装报错 `MetadataGenerationFailed` | 文件含中文注释，Git 克隆时编码损坏 | 手动重写 `requirements.txt` 或直接 `pip install` 指定包 |
| 2 | `find_wxwork_keys.py` 自动检测不到数据目录 | 脚本默认搜索路径与我实际路径不匹配 | 创建 `config.json` 手动指定 `wxwork_db_dir` |
| 3 | 消息内容显示为 `<binary>` | `content` 字段是 protobuf 编码的二进制数据 | 需要做 UTF-8 解码 + 正则提取可读文本 |
| 4 | 联系人 ID 无法映射到姓名 | `user_id` 是数字，需要从 `colleague` 表关联查询 | 查 `user_table` 和 `colleague` 表的 `real_name` 字段 |
| 5 | 有 4 个 WXWork 数据目录 | 同一企微账号有多个上下文 | 统计 `.db` 文件数最多的那个是主账号 |

### 重点展开：问题 #3 —— 企微消息的二进制编码

企微的消息 `content` 字段不像个人微信那样直接存纯文本，而是用了类似 protobuf 的二进制编码。直接 `str()` 会得到 `<binary>`。

**解决思路：**

```python
import re

def extract_text(data):
    """从企微二进制消息中提取可读文本"""
    if data is None:
        return ''
    if isinstance(data, str):
        return data.strip()
    if isinstance(data, bytes):
        # 尝试整体 UTF-8 解码
        try:
            s = data.decode('utf-8')
            # 提取连续的中文/ASCII/标点片段
            parts = re.findall(
                r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef'
                r'a-zA-Z0-9.,;:!?()\u2014\u2018-\u201d、。，；：！？'
                r'（）【】《》""\'\-]+', s)
            result = ' '.join(parts).strip()
            if result:
                return result
        except:
            pass
        # 逐字节 UTF-8 解码
        result = []
        i = 0
        while i < len(data):
            if data[i] < 0x20:
                i += 1
                continue
            if data[i] < 0x80:
                result.append(chr(data[i]))
                i += 1
            elif data[i] < 0xE0:
                try:
                    result.append(data[i:i+2].decode('utf-8'))
                    i += 2
                except:
                    i += 1
            elif data[i] < 0xF0:
                try:
                    result.append(data[i:i+3].decode('utf-8'))
                    i += 3
                except:
                    i += 1
            else:
                i += 1
        return ''.join(result).strip()
    return str(data)
```

---

## 对比：两套方案的完整流程

### 个人微信（WeChat 4.1+）

```
1. 安装 wechat-cli
2. wechat-cli init → 失败 (0/18 salts)
3. 下载 wx_key (DLL 注入工具)
4. 运行 wx_key.exe → 提取 passphrase
5. PBKDF2 派生 → 为每个数据库独立派生密钥
6. 生成 all_keys.json (18 个密钥)
7. wechat-cli 正常使用
```

**关键障碍：** WeChat 4.1+ 不再缓存派生后的密钥，passphrase 需要经过 PBKDF2-HMAC-SHA512（256000 次迭代）才能得到实际加密密钥。

### 企业微信（WeCom 5.x）

```
1. 安装 wechat-decrypt
2. 配置 config.json (数据目录)
3. find_wxwork_keys.py → 一步提取密钥
4. decrypt_wxwork_db.py → 一键解密
5. 直接查询或导出
```

**核心优势：** 一个 16 字节的 raw key 就能解密所有数据库，无需额外的密钥派生步骤。

---

## 注意事项与风险提示

⚠️ **使用前请充分了解以下风险：**

1. **违反服务条款** — 读取企微本地数据库可能违反企业微信服务条款
2. **企业风险** — 企业有权对使用第三方工具的账号进行限制
3. **版本兼容** — 企微更新后工具可能失效，需要等待社区适配
4. **密钥时效** — 密钥在企微重启后可能改变，需重新提取
5. **数据敏感** — 企微数据可能包含商业机密和客户信息，务必谨慎处理

**建议：**

- 仅在**个人学习研究**目的下使用
- 不要在**处理重要商业机密**的账号上使用
- 解密后的数据库**妥善保管**，不要上传到公共平台
- 了解并接受可能的后果

---

## 总结

| 环节 | 工具 | 难度 | 备注 |
|------|------|------|------|
| 安装 wechat-decrypt | git + pip | ⭐ | 注意 requirements.txt 编码问题 |
| 配置数据目录 | config.json | ⭐ | 主账号通常是 .db 文件最多的那个 |
| 提取密钥 | find_wxwork_keys.py | ⭐ | 一步完成，无需 PBKDF2 |
| 解密数据库 | decrypt_wxwork_db.py | ⭐ | 一键解密，0 失败率 |
| 导出消息 | export_wxwork_messages.py | ⭐⭐ | 支持 JSON/CSV/HTML |
| 配置 WorkBuddy Skill | SKILL.md | ⭐⭐ | 一次配置，长期使用 |
| 日常使用 | 对话式查询 | ⭐ | 密钥失效时需重新提取 |

**核心收获：** 企业微信的 wxSQLite3 加密体系比个人微信的 SQLCipher 4 简单得多——没有 PBKDF2 派生，没有 HMAC 校验，一个内存扫描提取的 raw key 就能解密所有数据库。如果你同时需要打通个人微信和企微，建议**先从企微开始**，成功后再处理个人微信的密钥派生问题。

---

## 系列文章

- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](./HowToConnectWechatAndAI.md) — 个人微信接入方案
- 本文 — 企业微信接入方案

---

*本文由 AI 助手（WorkBuddy）辅助整理，所有踩坑经验均为真实记录。*
