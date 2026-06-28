# QQ Group Push — Troubleshooting Reference

## Error Codes & Solutions

### 100016 — invalid appid or secret

**Cause:** AppID or AppSecret rejected by QQ server.

**Fix checklist:**
1. Go to [https://q.qq.com/](https://q.qq.com/) → select the bot → 开发设置
2. Verify AppID is correct (pure digits, no spaces)
3. Click "Reset Secret" to get a fresh AppSecret — copy immediately (shown once)
4. Ensure bot status is **已上线** (Online), not **开发中** (In Development). If in development mode, submit for review and wait for approval.
5. Try sending AppID as integer in REST test — if this returns `100002` instead of `100016`, the API is reachable but credential format may vary.

### 340067 — fetch robot info failed

**Cause:** REST API call without active WebSocket session, OR bot hasn't joined the target group.

**Fix:**
- Must use WebSocket connection (not REST API) to send proactive group messages.
- Ensure the bot has been added to the target group.
- Verify group_openid is correct (re-run `qq_get_group_openid.py` if unsure).

### botpy.Client raises "takes 1 positional argument but 2 were given"

**Cause:** `Intents()` initialization with wrong argument — botpy v2 expects `Intents.all()`.

**Fix:**
```python
intents = botpy.Intents.all()  # Correct
# NOT: botpy.Intents(botpy.Intents.DEFAULT_VALUE)
```

### FileNotFoundError: botpy.log (sandbox)

**Cause:** On WorkBuddy sandbox, botpy attempts to create `botpy.log` in the current directory.

**Fix:** Pass `bot_log=False` when creating the client:
```python
client = MyClient(intents=intents, bot_log=False)
```

### ImportError: cannot import name 'GroupMessage'

**Cause:** Wrong import path — `GroupMessage` moved between botpy versions.

**Fix:**
```python
from botpy.message import GroupMessage  # Correct path for botpy >= 2.x
```

### GBK encoding error on stdout (UnicodeEncodeError)

**Cause:** Windows console uses GBK; emoji in print() or command-line arguments triggers it.

**Fix:**
- Remove all emoji from message content and print statements.
- Use ASCII-only or Chinese-only text in command-line args.
- Use `--file` mode to pass content via UTF-8 file instead of CLI arg.

### PermissionError when writing qq_group_openid.txt

**Cause:** WorkBuddy sandbox denies file write in certain directories.

**Fix:** The script prints `GROUP_OPENID=<value>` to stdout before attempting file write. Capture this value and manually save it to `qq_group_openid.txt`. Or run the script outside the sandbox.

### Message not received in group

**Cause checklist:**
1. Bot has not been added to the group → add it
2. "机器人主动在群聊内发言" not enabled → enable in group settings
3. WebSocket session not yet established → the script auto-connects; wait 2-3 seconds
4. Bot rate-limited → QQ allows max 20 messages/minute/group; wait and retry

## Verification Commands

### Test credentials directly via REST

```bash
curl -s --noproxy '*' \
  -X POST https://bots.qq.com/app/getAppAccessToken \
  -H "Content-Type: application/json" \
  -d '{"appId":"YOUR_APPID","clientSecret":"YOUR_APPSECRET"}'
```

Successful response includes `access_token` and `expires_in` fields.

### Test bot identity

```bash
curl -s --noproxy '*' \
  -X GET https://api.sgroup.qq.com/v2/users/me \
  -H "Authorization: Bearer QQBot <access_token>"
```

## Known Platform Limitations (as of June 2026)

- **C2C private chat**: Max 4 proactive messages per month per user — NOT suitable for daily push
- **Group chat**: Max 20 messages per minute per group — suitable for daily automation
- **WebSocket session**: Must be initiated by the bot; QQ server does not accept proactive REST group message API calls
- **Group at-message events**: Only `GROUP_AT_MESSAGE_CREATE` is needed for basic functionality
