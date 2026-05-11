#!/usr/bin/env python3
"""
Wazuh -> Telegram custom integration.
Push to LXC 122: pct push 122 ./custom-telegram.sh /var/ossec/integrations/custom-telegram
Perms : chmod 750 + chown root:wazuh

Wazuh manager calls: /var/ossec/integrations/custom-telegram <alert.json> <api_key> <hook_url> [options]
In our ossec.conf <integration> block: api_key=<chat_id>, hook_url=<bot_token>

Refactored from bash to Python to avoid jq+bash quoting/empty-array fragility
that produced "Groups: 110" cosmetic bug. Standard library only - no jq dep.
"""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: custom-telegram <alert.json> <chat_id> <bot_token>")

    alert_path = sys.argv[1]
    chat_id = sys.argv[2]
    bot_token = sys.argv[3]

    try:
        alert = json.loads(Path(alert_path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        log(f"failed to parse alert {alert_path}: {e}")
        sys.exit(1)

    rule = alert.get("rule", {})
    agent = alert.get("agent", {})
    level = rule.get("level", 0)
    desc = rule.get("description", "")
    rule_id = rule.get("id", "?")
    groups = rule.get("groups", [])
    if not isinstance(groups, list):
        groups = [str(groups)]
    groups_str = ",".join(groups) if groups else "-"

    agent_name = agent.get("name", "?")
    agent_ip = agent.get("ip", "local")
    timestamp = alert.get("timestamp", "")
    location = alert.get("location", "")
    full_log = (alert.get("full_log", "") or "")[:600]

    if 12 <= level <= 15:
        icon = "🚨"
    elif 10 <= level <= 11:
        icon = "⚠️"
    else:
        icon = "ℹ️"

    parts = [
        f"<b>{icon} Wazuh L{level} - {esc(agent_name)}</b>",
        f"<i>{esc(desc)}</i>",
        "",
        f"<b>Agent:</b> {esc(agent_name)} ({esc(agent_ip)})",
        f"<b>Rule:</b> {esc(rule_id)}",
        f"<b>Groups:</b> <code>{esc(groups_str)}</code>",
        f"<b>When:</b> {esc(timestamp)}",
    ]
    if location and location != "null":
        parts.append(f"<b>Source:</b> <code>{esc(location)}</code>")
    if full_log and full_log != "null":
        parts.append(f"<b>Log:</b>\n<pre>{esc(full_log)}</pre>")

    msg = "\n".join(parts)
    send_telegram(bot_token, chat_id, msg)


def esc(s):
    """Minimal HTML escape for Telegram parse_mode=HTML."""
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def send_telegram(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": "true",
    }).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            log(resp.read().decode())
    except urllib.error.HTTPError as e:
        log(f"HTTPError {e.code}: {e.read().decode()}")
    except Exception as e:
        log(f"send error: {e}")


def log(msg):
    try:
        with open("/var/ossec/logs/integrations.log", "a") as f:
            f.write(msg.rstrip() + "\n")
    except OSError:
        pass


if __name__ == "__main__":
    main()
