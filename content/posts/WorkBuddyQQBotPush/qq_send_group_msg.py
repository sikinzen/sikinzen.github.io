#!/usr/bin/env python3
"""
QQ 群消息发送脚本（脱敏版本）
通过 botpy WebSocket 连接发送群消息
用法：
  python qq_send_group_msg.py "消息内容"
  python qq_send_group_msg.py --file <文件路径>

使用前：
  1. 替换 YOUR_APPID、YOUR_APPSECRET 为真实凭据
  2. 先运行 qq_get_group_openid.py 获取 group_openid
  3. 确保 qq_group_openid.txt 与脚本在同一目录
"""
import sys
import os

# ========== 此处替换为你的真实凭据 ==========
APPID = "YOUR_APPID"           # QQ 开放平台 AppID
SECRET = "YOUR_APPSECRET"       # QQ 开放平台 AppSecret
# ===========================================

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
        print("Expected at:", GROUP_OPENID_FILE)
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
