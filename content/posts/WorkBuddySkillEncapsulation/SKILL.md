---
name: qq-group-push
description: >
  This skill enables WorkBuddy automation tasks to push messages to QQ groups via the official
  QQ Bot API (botpy SDK, WebSocket). It provides two scripts: one to capture the group_openid
  via WebSocket event, and one to send group messages via WebSocket connection. The skill should
  be used when the user wants to send QQ group messages from WorkBuddy automations, or when
  integrating QQ Bot push into an existing workflow. Triggers: QQ group push, QQ bot message,
  QQ automation notification, QQ 群推送, QQ 机器人发消息.
agent_created: true
---

# QQ Group Push — WorkBuddy 自动化 QQ 群消息推送

## Overview

Use the official QQ Bot API (botpy SDK) to send messages from WorkBuddy automation tasks
to a designated QQ group, via WebSocket (mandatory — REST API alone cannot send proactive
group messages).

## Prerequisites (one-time setup)

### 1. Register QQ Bot on Open Platform

- Go to [https://q.qq.com/](https://q.qq.com/), log in with QQ.
- Create a new bot, record **AppID** and **AppSecret**.
- In bot settings, enable **群聊消息 (Group Message)** permission under 开发设置 → 权限配置.
- Under 事件订阅, enable `GROUP_AT_MESSAGE_CREATE`.

### 2. Create a dedicated QQ group

- Create a new QQ group (can have just one member).
- Invite the bot into the group.
- Group settings → 机器人 → enable **机器人主动在群聊内发言 (Bot proactive group chat)**.

### 3. Install botpy SDK

Run (using managed Python):

```
<managed_python> -m pip install qq-botpy
```

On Windows with WorkBuddy managed Python, use the isolated venv or install directly:

```
C:\Users\alex\.workbuddy\binaries\python\versions\3.13.12\python.exe -m pip install qq-botpy
```

## Step-by-Step Workflow

### Step 1: Capture group_openid

1. Edit `scripts/qq_get_group_openid.py`: replace `YOUR_APPID` and `YOUR_APPSECRET` with real credentials.
2. Run the script (background it — it listens for WebSocket events):

```bash
python scripts/qq_get_group_openid.py
```

3. In the QQ group, send an **@bot message** (any content, e.g. "获取openid").
4. The script prints `GROUP_OPENID=<value>` to stdout, saves it to `qq_group_openid.txt`, and exits.
5. If file write fails (sandbox), capture the value from stdout manually and save it.

### Step 2: Send a test message

```bash
python scripts/qq_send_group_msg.py "Test message from WorkBuddy"
```

Check the QQ group to confirm delivery.

### Step 3: Integrate into WorkBuddy automation

In the automation task prompt, add a task step like:

```
Call the QQ group push script:
python D:\Work\AI\AiMemory\Claw\qq_send_group_msg.py "message content"
```

Or use the skill's bundled scripts with full paths.

**Key constraint:** The `qq_group_openid.txt` file must exist in the same directory as
`qq_send_group_msg.py` (or modify `GROUP_OPENID_FILE` in the script).

## Important Technical Notes

### WebSocket is mandatory

QQ Bot API **requires** a WebSocket connection before the bot can send proactive group
messages. The `qq_send_group_msg.py` script automatically connects to WebSocket, sends
the message in the `on_ready` callback, then exits with `os._exit(0)`.

### No emoji in messages (Windows GBK)

On Windows, the console encoding is GBK. Messages with emojis will cause encoding errors
when passed as command-line arguments. Use plain text with ASCII/Chinese characters only.

### AppID / AppSecret must match

Error code `100016` means invalid AppID or AppSecret. Common causes:
- Copied with extra spaces or newlines
- Bot not yet activated (must be "已上线", not "开发中")
- Wrong bot selected on QQ Open Platform

### Sandbox file write

On WorkBuddy sandbox, `open(..., "w")` may raise PermissionError. The `qq_get_group_openid.py`
script handles this by printing the value to stdout first, so it can be captured manually.

### botpy import path

The `GroupMessage` class is at `botpy.message.GroupMessage` (NOT `botpy.types.message.GroupMessage`).
This is version-dependent and may change in future botpy releases.

### Python version

Use Python 3.12+ (tested with 3.13.12). botpy uses `asyncio` so Python's async support is required.

## Scripts

### `scripts/qq_get_group_openid.py`

Captures the QQ group's `group_openid` by listening for a `GROUP_AT_MESSAGE_CREATE` WebSocket
event. Edit `APPID` and `SECRET` at the top before running.

### `scripts/qq_send_group_msg.py`

Sends a message to a QQ group via WebSocket. Usage:

```bash
python scripts/qq_send_group_msg.py "Your message here"
python scripts/qq_send_group_msg.py --file /path/to/message.txt
```

Requires `qq_group_openid.txt` in the same directory. Edit `APPID` and `SECRET` at the top.

## Troubleshooting

See `references/troubleshooting.md` for detailed error codes and solutions.

## Integration Patterns

### Pattern A: Direct shell call in automation

```
python D:\scripts\qq_send_group_msg.py "message content"
```

Simplest. Script handles WebSocket connect → send → exit.

### Pattern B: Combined with file generation

```
Write message to temp file → call qq_send_group_msg.py --file <temp_file>
```

Useful when the message is long and complex (avoids shell quoting issues).

### Pattern C: Fallback on failure

```
python qq_send_group_msg.py "msg" || echo "msg" > fallback.txt
```

If QQ push fails, save content locally.
