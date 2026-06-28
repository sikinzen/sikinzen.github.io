#!/usr/bin/env python3
"""
获取 QQ 群的 group_openid（脱敏版本）
用法：替换 YOUR_APPID 和 YOUR_APPSECRET 后运行
然后在 QQ 群 @机器人 发一条消息，脚本自动捕获并退出
"""
import os
import sys

# ========== 此处替换为你的真实凭据 ==========
APPID = "YOUR_APPID"           # QQ 开放平台 AppID
SECRET = "YOUR_APPSECRET"       # QQ 开放平台 AppSecret
# ===========================================

OUTPUT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qq_group_openid.txt")

import botpy
from botpy.message import GroupMessage


class GetGroupOpenidClient(botpy.Client):
    async def on_group_at_message_create(self, message: GroupMessage):
        """收到群 @消息时触发，打印并保存 group_openid"""
        group_openid = message.group_openid
        print(f"GROUP_OPENID={group_openid}", flush=True)

        try:
            with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                f.write(group_openid)
            print(f"Saved to: {OUTPUT_FILE}", flush=True)
        except Exception as e:
            print(f"Save failed (permission?): {e}", flush=True)
            print("group_openid captured from stdout above, save manually.", flush=True)

        import os as _os
        _os._exit(0)


if __name__ == "__main__":
    print("=" * 50)
    print("QQ Group openid Capture Script")
    print("=" * 50)
    print(f"AppID: {APPID}")
    print("Steps:")
    print("  1. Ensure bot is in the target QQ group")
    print("  2. In group settings, enable 'Bot active message in group'")
    print("  3. Send an @message to the bot in the group")
    print("  4. Script captures group_openid, saves to file, and exits")
    print("=" * 50)
    print()

    intents = botpy.Intents.all()
    client = GetGroupOpenidClient(intents=intents, bot_log=False)
    client.run(appid=APPID, secret=SECRET)
