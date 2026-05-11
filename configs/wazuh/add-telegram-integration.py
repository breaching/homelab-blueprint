#!/usr/bin/env python3
"""
Idempotent add of <integration name="custom-telegram"> block to Wazuh ossec.conf.
Reads $WAZUH_TG_TOKEN and $WAZUH_TG_CHAT_ID from env (passed by ssh wrapper).
"""
import os
import sys
import shutil
import time

TOKEN = os.environ.get("WAZUH_TG_TOKEN")
CHAT = os.environ.get("WAZUH_TG_CHAT_ID")
LEVEL = os.environ.get("WAZUH_TG_LEVEL", "10")
CFG = "/var/ossec/etc/ossec.conf"

if not TOKEN or not CHAT:
    print("ERROR: WAZUH_TG_TOKEN and WAZUH_TG_CHAT_ID env vars required")
    sys.exit(1)

with open(CFG) as f:
    cfg = f.read()

if "custom-telegram" in cfg:
    print("custom-telegram integration already present, skipping")
    sys.exit(0)

block = f"""
  <integration>
    <name>custom-telegram</name>
    <hook_url>{TOKEN}</hook_url>
    <api_key>{CHAT}</api_key>
    <level>{LEVEL}</level>
    <alert_format>json</alert_format>
  </integration>
"""

# Backup first
backup = f"{CFG}.bak.{int(time.time())}"
shutil.copy(CFG, backup)
print(f"backup: {backup}")

new_cfg = cfg.replace("</ossec_config>", block + "</ossec_config>", 1)
if new_cfg == cfg:
    print("ERROR: </ossec_config> not found")
    sys.exit(1)

with open(CFG, "w") as f:
    f.write(new_cfg)
print(f"inserted custom-telegram block (level>={LEVEL})")
