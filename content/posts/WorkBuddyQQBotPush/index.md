---
title: "WorkBuddy 自动化任务打通 QQ 消息推送：完整踩坑实录"
date: 2026-06-28T16:50:00+08:00
draft: false
description: "从企微消息权限被拒到 QQ Bot 群推送全链路打通，记录 WorkBuddy 自动化任务消息推送的完整方案，含 Python 脚本、QQ 开放平台配置、botpy WebSocket 认证及 5 个踩坑实录"
categories: ["AI应用"]
tags: ["WorkBuddy", "QQ机器人", "自动化", "消息推送", "botpy", "QQ开放平台"]
keywords: ["WorkBuddy QQ推送", "QQ机器人", "botpy", "自动化消息推送", "QQ Bot API", "WorkBuddy自动化"]
series: ["AI工具链"]
---

> ✅ **本文方案已于 2026-06-28 实际验证通过** — 两个 WorkBuddy 定时自动化任务（凌晨 2:00 工作纪要、3:00 早间新闻）均已成功通过 QQ 群推送。

## 背景：自动化任务需要"最后一公里"

前面几篇文章分别解决了 [Gitea 代码仓库](https://sikinzen.github.io/posts/howtoconnectgiteaandai/)、[禅道项目管理](https://sikinzen.github.io/posts/howtoconnectzentaoandai/)、[微信/企微数据读取](https://sikinzen.github.io/posts/howtoconnectwechatandai/) 的 AI 接入问题。但这些解决的都是**数据输入**——让 AI 能读数据、查信息。

一个真正有用自动化助手还需要**输出通道**。具体需求：

- **「悟空的早间新闻推送」**：每天凌晨 3:00 自动采集 AI 动态、天气、财经行情、ETF 监控，推送到手机
- **「温陵布衣昨日工作纪要」**：每天凌晨 2:00 整理前一天的企微消息、邮件、项目日志，推送摘要

两个任务都跑得挺好，但**消息一直只能写本地文件**——你需要主动打开电脑去看，手机端完全收不到。这和"主动通知"的目标背道而驰。

---

## 路线一：企业微信（失败）

最自然的思路是企业微信——公司全员在用，WorkBuddy 也有企微连接器（wecom connector）。

### 尝试过程

1. **企微连接器发消息**：WorkBuddy 企微连接器已绑定成功，但发消息时报错 `当前企业暂不支持授权机器人「消息」使用权限`
2. **管理员确认**：咨询企业微信管理员，回复只有「文档」授权，没有「消息」授权
3. **`wecom-cli` skill**：这个 skill 本质是解密本地 SQLite 数据库，**只读不写**，无法发送消息

### 结论

企微消息推送的前提是**企业管理员在企微后台开通「消息」权限**。如果你的企业没有开通（多数企业内部出于安全管控不开放），企微推送这条路就彻底堵死了。**无绕路方案。**

> 📎 如果你所在企业的企微已开通消息权限，WorkBuddy 企微连接器可以直接发消息，本文后续的 QQ Bot 方案不必看。

---

## 路线二：QQ 机器人（成功）

受 [OpenClaw 接入 QQ 机器人](https://www.appinn.com/openclaw-channel-qqbot/) 的思路启发——OpenClaw 可以通过 QQ Bot 定时推送消息，WorkBuddy 的自动化任务同样可以。

核心技术栈：

```
WorkBuddy 自动化任务（凌晨执行）
    → 采集数据、生成消息文本
    → 调用 Python 脚本
    → botpy SDK 连接 QQ WebSocket 认证
    → 发送群消息
    → 手机 QQ 收到推送
```

---

## 完整实施步骤

### 第一步：在 QQ 开放平台注册机器人

1. 打开 [QQ 开放平台](https://q.qq.com/)，用手机 QQ 扫码登录
2. 点击「创建机器人」，填写名称（如 `YourBot-WorkBuddy`）
3. 进入机器人详情 → **开发设置** → 获取以下两个凭据：

| 凭据 | 说明 |
|------|------|
| **AppID** | 纯数字，如 `YOUR_APPID` |
| **AppSecret** | 点击「生成」获取，只显示一次，**立即保存** |

4. 在「开发设置 → 权限配置」中开启 **「群聊消息」** 权限
5. 确认机器人状态为 **「已上线」**（开发中的机器人无法调用 API）

> ⚠️ AppSecret 只显示一次。错过了只能「重置」，旧密钥立即失效。

### 第二步：创建专用 QQ 群

1. 在手机 QQ 创建一个新群（只有你一人即可），命名如 `YourGroup-WorkBuddy`
2. 把刚注册的机器人拉进群
3. **关键配置**：群设置 → 机器人 → 打开 **「机器人主动在群聊内发言」**

> 为什么是群聊而不是私聊？QQ 官方 Bot API 对私聊有严格限制——每月只能主动发 4 条消息。群聊则无此限制（2026 年 6 月全量开放），每分钟可发 20 条。

### 第三步：安装 botpy SDK

```bash
pip install qq-botpy
```

botpy 是腾讯官方维护的 QQ Bot Python SDK，封装了 WebSocket 连接和 REST API。

### 第四步：获取群标识（group_openid）

QQ Bot API 发送群消息需要 `group_openid`，这不是群号，需要通过 WebSocket 事件获取。

创建 `qq_get_group_openid.py`（[下载](/downloads/qq_get_group_openid.py)）：

```python
#!/usr/bin/env python3
"""
获取 QQ 群的 group_openid
运行方式：把机器人加到群后，运行本脚本，然后在群里 @机器人 发一条消息
脚本会打印 group_openid 并保存到文件，然后自动退出
"""
import os
import sys

APPID = "YOUR_APPID"           # 替换为你的 AppID
SECRET = "YOUR_APPSECRET"       # 替换为你的 AppSecret
OUTPUT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qq_group_openid.txt")

import botpy
from botpy.message import GroupMessage

class GetGroupOpenidClient(botpy.Client):
    async def on_group_at_message_create(self, message: GroupMessage):
        """收到群 @消息时触发"""
        group_openid = message.group_openid
        print(f"GROUP_OPENID={group_openid}", flush=True)
        # 退出脚本
        import os as _os
        _os._exit(0)

if __name__ == "__main__":
    print("=" * 50)
    print("QQ Group openid Capture Script")
    print("=" * 50)
    print(f"AppID: {APPID}")
    print("In the QQ group, send an @message to the bot")
    print("=" * 50)

    intents = botpy.Intents.all()
    client = GetGroupOpenidClient(intents=intents, bot_log=False)
    client.run(appid=APPID, secret=SECRET)
```

**运行方式**：

```bash
python qq_get_group_openid.py
```

脚本启动后，去手机 QQ 群 **@机器人 发一条消息**。脚本会打印 `GROUP_OPENID=XXXXXXXX`，同时保存到 `qq_group_openid.txt`。

### 第五步：编写推送脚本

创建 `qq_send_group_msg.py`（[下载](/downloads/qq_send_group_msg.py)）：

```python
#!/usr/bin/env python3
"""
QQ 群消息发送脚本 - 通过 botpy WebSocket 连接发送群消息
用法：
  python qq_send_group_msg.py "消息内容"
  python qq_send_group_msg.py --file <文件路径>
"""
import sys
import os

APPID = "YOUR_APPID"           # 替换
SECRET = "YOUR_APPSECRET"       # 替换
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GROUP_OPENID_FILE = os.path.join(SCRIPT_DIR, "qq_group_openid.txt")

import botpy
from botpy.message import GroupMessage

class SendGroupMsgClient(botpy.Client):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._msg_to_send = None
        self._group_openid = None

    async def on_ready(self):
        """WebSocket connected, send message then exit"""
        if self._msg_to_send and self._group_openid:
            try:
                result = await self.api.post_group_message(
                    group_openid=self._group_openid,
                    msg_type=0,
                    content=self._msg_to_send
                )
                msg_id = result.get('id') if isinstance(result, dict) else result.id
                print(f"SEND_OK: id={msg_id}", flush=True)
            except Exception as e:
                print(f"SEND_FAIL: {e}", flush=True)
        else:
            print("READY_OK: no message to send", flush=True)
        os._exit(0)

    async def on_group_at_message_create(self, message: GroupMessage):
        print(f"GROUP_OPENID={message.group_openid}", flush=True)

def main():
    if len(sys.argv) < 2:
        print("Usage: python qq_send_group_msg.py <message>")
        print("       python qq_send_group_msg.py --file <file_path>")
        sys.exit(1)

    msg = sys.argv[1]
    if msg == "--file" and len(sys.argv) >= 3:
        filepath = sys.argv[2]
        if os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8") as f:
                msg = f.read().strip()
        else:
            print(f"ERROR: File not found: {filepath}")
            sys.exit(1)

    if not os.path.exists(GROUP_OPENID_FILE):
        print("ERROR: qq_group_openid.txt not found")
        print("Run qq_get_group_openid.py first to capture group_openid.")
        sys.exit(1)
    with open(GROUP_OPENID_FILE, "r", encoding="utf-8") as f:
        group_openid = f.read().strip()

    print(f"Target: {group_openid} | Size: {len(msg)} chars", flush=True)

    intents = botpy.Intents.all()
    client = SendGroupMsgClient(intents=intents, bot_log=False)
    client._msg_to_send = msg
    client._group_openid = group_openid

    try:
        client.run(appid=APPID, secret=SECRET)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
```

**测试发送**：

```bash
python qq_send_group_msg.py "[测试] WorkBuddy QQ推送通道测试"
```

如果手机 QQ 群收到消息，通道即打通。

### 第六步：接入 WorkBuddy 自动化任务

在 WorkBuddy 自动化任务的 prompt 中，将「推送」步骤改为调用上述脚本：

```
## 任务六：通过QQ机器人推送

调用 Python 脚本发送消息：
```
python /path/to/qq_send_group_msg.py "<消息内容>"
```

如果推送失败，将内容写入备用文件：
/path/to/fallback_news.txt
```

**注意事项**：

1. 消息内容中不要使用 emoji（Windows GBK 控制台编码兼容问题）
2. 消息内容中的双引号需要转义
3. 建议在自动化 prompt 中指定 `cwds` 为脚本所在目录

---

## 五个踩坑实录

以下是实际过程中遇到的五个坑，排序按耗时从多到少。

### 坑一：AppSecret 复制错误

**现象**：`botpy` 连接报错 `100016 invalid appid or secret`

**排查过程**：
1. 检查 AppID 格式（字符串/数字都试过）
2. 检查 AppSecret 是否有隐藏字符（空格、换行）
3. 直接 curl API 测试

**根因**：QQ 开放平台的 AppSecret **生成和展示不在同一个页面**。第一次从错误位置复制的旧密钥已失效。

**教训**：获取 AppSecret 后立刻用 `curl` 验证：
```bash
curl -s -X POST https://bots.qq.com/app/getAppAccessToken \
  -H "Content-Type: application/json" \
  -d '{"appId":"YOUR_APPID","clientSecret":"YOUR_APPSECRET"}'
```
返回 `access_token` 即为有效。

### 坑二：botpy SDK API 变化

**现象**：`ImportError: cannot import name 'GroupMessage' from 'botpy.types.message'`

**根因**：botpy SDK 大版本更新后，类的位置变了：
- ❌ 旧版：`from botpy.types.message import GroupMessage`
- ✅ 新版：`from botpy.message import GroupMessage`

同样，`Intents` 的构造方式也变了：
- ❌ 旧版：`botpy.Intents(botpy.Intents.DEFAULT_VALUE)`
- ✅ 新版：`botpy.Intents.all()`

**教训**：遇到 SDK 文档不匹配时，直接读安装的包源码：
```bash
pip show qq-botpy | grep Location   # 找到安装路径
grep -r "class GroupMessage" <安装路径>/botpy/   # 找到类的真实位置
```

### 坑三：Windows 沙箱拦截文件写入

**现象**：脚本内部写文件时报 `PermissionError`

**根因**：WorkBuddy 沙箱模式下，某些路径的写操作被拦截。

**解决方案**：改为先打印到 stdout，再手动创建文件写入：
```python
print(f"GROUP_OPENID={group_openid}", flush=True)  # stdout 总能捕获
```

### 坑四：GBK 控制台编码导致 emoji 崩溃

**现象**：脚本打印 emoji 时崩溃 `UnicodeEncodeError`

**根因**：WorkBuddy 自动化任务运行环境使用 GBK 编码控制台，emoji 字符无法 encode。

**解决方案**：
1. 脚本中全部使用纯英文/ASCII 字符输出
2. 消息内容中去掉 emoji，用纯文本符号代替
3. 设置 `PYTHONIOENCODING=utf-8` 环境变量（如环境支持）

### 坑五：消息发送后脚本没有退出

**现象**：自动化任务执行后一直挂起不结束

**根因**：botpy Client 的 `on_ready` 回调发送消息后没有主动退出进程，WebSocket 连接保持导致脚本不退出。

**解决方案**：发送完成后调用 `os._exit(0)` 强制退出：
```python
async def on_ready(self):
    result = await self.api.post_group_message(...)
    print(f"SEND_OK: id={result.id}", flush=True)
    os._exit(0)  # 必须强制退出
```

---

## 方案对比

| 维度 | 企微推送 | QQ Bot 群推送 |
|------|---------|-------------|
| 前提条件 | 企业管理员开通「消息」权限 | 注册 QQ 开放平台机器人 |
| 开通难度 | 高（多数企业不开放） | 低（个人即可操作） |
| 发送限制 | 无 | 20 条/分钟 |
| 私聊推送 | 支持 | 每月仅 4 条 |
| 技术栈 | WorkBuddy 内置连接器 | botpy + 自定义脚本 |
| 手机端 | 企微 App | QQ App |

---

## 附录：企微推送失败全记录

企业微信推送尝试了以下三条路径，全部失败：

### 尝试一：WorkBuddy 企微连接器

WorkBuddy 内置的企微连接器（wecom connector）在绑定企业微信后，文档读写正常，但发送消息时报错：

```
当前企业暂不支持授权机器人「消息」使用权限
```

### 尝试二：企业微信管理后台

咨询企业微信管理员后确认：该企业的企微授权范围仅为「文档」，不包含「消息」。这是企业层面（而非用户层面）的权限管控，管理员本人也无法单独开通。

### 尝试三：wecom-cli skill

`wecom-cli` 的工作原理是解密本地企微客户端的 SQLite 数据库文件来**读取**聊天记录和联系人。它不具备发送消息的能力（没有调用企微消息 API）。

### 结论

企微消息推送的三要素：**企业授权 + 管理员配置 + 消息 API 权限**。缺一不可。如果你的企业没有开通「消息」权限，**不要在这条路上浪费时间**，直接走 QQ Bot 方案。

---

## 是否值得封装为 Skill？

**可以，而且建议。** 将 QQ Bot 推送流程封装为 WorkBuddy Skill 有以下好处：

1. **一键安装**：其他人只需安装 skill，无需手动下载脚本
2. **统一配置**：凭据和路径集中管理在 SKILL.md 中
3. **自动化任务引用更简洁**：只需 `@skill:qq-bot-push --msg "内容"`

Skill 结构建议：

```
qq-bot-push/
  SKILL.md           # 技能定义 + 配置说明
  scripts/
    qq_send_group_msg.py    # 发送脚本（已脱敏占位）
    qq_get_group_openid.py  # 获取 group_openid 脚本
```

后续我会把这一整套流程封装为一个 Skill，届时单独发布。

---

## 需要替换的脱敏数据

> ⚠️ **占位符替换说明** — 以下占位符需替换为你的真实值，真实值请自行妥善保存（建议存本地加密备忘录或密码管理器）。

| 占位符 | 说明 | 获取方式 |
|--------|------|----------|
| `YOUR_APPID` | QQ 开放平台 AppID（纯数字） | QQ 开放平台 → 机器人详情 → 开发设置 |
| `YOUR_APPSECRET` | QQ 开放平台 AppSecret | QQ 开放平台 → 开发设置 → 点击「生成」获取（只显示一次） |
| `YOUR_GROUP_OPENID` | 目标 QQ 群的 openid | 运行 `qq_get_group_openid.py` 后从 stdout 获取 |
| `YourBot-WorkBuddy` | 你在 QQ 开放平台注册的机器人名称 | 自定义 |
| `YourGroup-WorkBuddy` | 你自建的 QQ 群名称 | 自定义 |

---

## 附件下载

以下脚本文件可直接下载使用（已脱敏，替换占位符即可）：

| 文件 | 下载 | 说明 |
|------|------|------|
| `qq_get_group_openid.py` | [下载](/downloads/qq_get_group_openid.py) | 获取 QQ 群 group_openid（WebSocket 事件监听） |
| `qq_send_group_msg.py` | [下载](/downloads/qq_send_group_msg.py) | 发送 QQ 群消息（WebSocket 连接+发送+退出） |

> 附件中所有 `YOUR_APPID`、`YOUR_APPSECRET` 均为占位符，使用前需替换为真实值。完整 Skill 封装见后续文章 [WorkBuddy Skill 封装实战](/posts/workbuddyskillencapsulation/)。

---

## 总结

打通 WorkBuddy 自动化任务的消息推送，核心结论：

1. **企微用不了就别纠结**——没有消息权限就是没有，绕不过
2. **QQ Bot 群推送是目前最可行的替代方案**——个人即可注册，零成本
3. **botpy 的 WebSocket 模式比纯 REST API 更可靠**——QQ 平台要求先建 WebSocket 连接再发消息
4. **踩过的坑都是好的**——SDK API 变化、沙箱限制、编码问题，各花 5-10 分钟排查

---
