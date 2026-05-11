# Wazuh API "Some Wazuh daemons are not ready yet" - Fix

## Symptoms

- Dashboard `wazuh.home.example.com` shows : `[API connection] No API available to connect`
- Login fails with: `Error: 3002 - Request failed with status code 500`
- Direct curl on `https://localhost:55000/security/user/authenticate` returns HTTP 500 :
  ```json
  {"title": "Wazuh Internal Error", "detail": "Some Wazuh daemons are not ready yet in node \"node01\" (wazuh-modulesd->restarting, wazuh-analysisd->restarting, wazuh-execd->restarting, wazuh-db->restarting, wazuh-remoted->restarting)"}
  ```
- BUT `wazuh-control status` shows tous les daemons as "running"
- BUT `ss -tlnp | grep :55000` shows API listening normally
- BUT `ps -ef | grep wazuh-` shows tous les processes alive

## Root cause

Wazuh API checks `/var/ossec/var/run/.restart` flag file. If present, returns "daemons restarting" error for ALL requests, even auth.

This file is created when Wazuh manager triggers an internal restart (config reload, etc.) and SHOULD be cleared automatically when restart completes - but **stale flag files persist** if a manager restart is interrupted (e.g., systemctl restart killed mid-flight).

## Fix

```bash
# On LXC 122 (Wazuh manager)
rm -f /var/ossec/var/run/.restart

# Verify API responds
PWD=$(grep -E "      password" /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml | head -1 | cut -d'"' -f2)
curl -sk -u "wazuh-wui:$PWD" -X POST "https://localhost:55000/security/user/authenticate?raw=true" -w "\nHTTP %{http_code}\n"
# Expected: HTTP 200 + JWT token
```

## Prevention

- **Avoid `systemctl restart wazuh-manager` while a config change/upgrade is in flight.** Wait for previous operation to complete.
- **Don't kill manager subprocesses manually** unless you also clean up `/var/ossec/var/run/.restart`.
- **After any major Wazuh upgrade**, check this file as part of post-upgrade verification.

## Related issues

- `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml` ships with placeholder password `q3V32d.dVv1MJciJkkmXJw2NeVdwSs69` for `wazuh-wui` user. Must be replaced with actual password from `/var/ossec/wazuh-install-files/wazuh-passwords.txt` (cf [`scripts/fix-wazuh-dashboard-api-v2.py`](scripts/fix-wazuh-dashboard-api-v2.py)).
- Vulnerability scanner DB schema mismatch post-upgrade : `Couldn't find column family: 'vendor_map'` → `rm -rf /var/ossec/queue/vd && mkdir -p /var/ossec/queue/vd` then restart manager (regenerates fresh DB).
