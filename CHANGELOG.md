# Changelog

Toutes les modifications notables du homelab. Format librement inspiré de [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added - Vague 2 sécu Phase L : Grafana central pane unified observability MVP
- **Vector ship AdGuard + Traefik logs to Loki** (LXC 100 + LXC 103) - sources `file` tail JSON, transforms `parse_json` extrait champs (`request_path`, `query_host`, `blocked`, etc.), labels Loki `host`/`service`/`source_type`. ACL `setfacl -m u:vector:r /opt/AdGuardHome/data/querylog.json` ajoutée pour AdGuard. Configs dans `configs/vector/vector-adguard.yaml` + `vector-traefik.yaml`.
- **Wazuh OpenSearch datasource provisioned dans Grafana** - plugin `grafana-opensearch-datasource` installé via `grafana-cli`, datasource UID `wazuh` configurée en `configs/grafana/datasources/wazuh-opensearch.yaml`, basicAuthPassword resolu via env var `WAZUH_INDEXER_ADMIN_PWD` chargée par systemd `EnvironmentFile=/etc/grafana/secrets/wazuh.env`. Setup automatisé : `runbooks/scripts/setup-grafana-wazuh-datasource.sh` (extract pwd → push env file → systemd override → restart).
- **Wazuh indexer LAN binding** - `network.host: 127.0.0.1` → `192.168.1.221` dans `/etc/wazuh-indexer/opensearch.yml` pour permettre query cross-LXC depuis Grafana. LAN-only (192.168.1.0/24), TLS self-signed + auth admin maintenus.
- **Plugin Grafana Infinity** - `yesoreyeram-infinity-datasource` installé (prêt pour PostHog + Sentry API en attente des keys).
- **Dashboard "My Day Homelab"** (`configs/grafana/dashboards/my-day-homelab.json`, uid `my-day-homelab`) - vue mobile-friendly 15 panels en 4 rows : Status (agents Wazuh actifs, alerts L≥10, hosts Loki, sessions Cowrie), Sécurité (alerts par level + top rules), Logs & DNS (ingest rate par host, AdGuard % bloqué, Traefik 4xx/5xx, top hosts errors), rows PostHog + Sentry préparés et collapsed pour activation post-keys.
- **Runbook mobile access** - `runbooks/grafana-mobile-access.md` (CF Tunnel public hostname `grafana.home.example.com`, CF Access Email OTP optionnel, app Grafana iOS/Android, bookmark home screen).

### À venir (court terme)
- VM 102 HAOS DHCP reservation à faire dans UCG manuellement
- Vercel project archive (J+3 minimum après bascule réussie le 7 mai)
- Cleanup TXT _vercel.example.com DNS record après archive Vercel
- prod-test.example.com CNAME + CF Tunnel public hostname à supprimer (legacy migration)
- PostHog + Sentry tokens à set dans Coolify env vars + redeploy
- PostHog Personal API key + Sentry Auth Token à fournir pour activer rows conversion + perf du dashboard My Day Homelab
- CF Tunnel public hostname `grafana.home.example.com` à créer côté CF Zero Trust dashboard (manual UI step)

---

## [2026-05-07] - example.com Vercel → Hetzner migration finale

### Done
- **Switch DNS example.com Vercel → Hetzner via CF Tunnel** : suppression A record `203.0.113.20` (Vercel), ajout public hostnames sur CF Zero Trust pour `example.com` apex + `www.example.com` (auto-création des CNAME flattened apex côté CF DNS).
- **Coolify FQDN app prod** updated : `http://prod-test.example.com` → `http://example.com,http://www.example.com`. Confirmation HTTP 200 end-to-end depuis le browser avec titre `the maintainer | Développeur Web Freelance · React & Next.js`.
- **2 blog posts** sur le portfolio : refresh `homelab.md` (de 14 → 16 services, ajout sections Wazuh/Cowrie/Loki/Coolify/agent groups), nouveau `mini-soc-homelab.md` (deep-dive complet sur la stack sécu observabilité avec custom rules MITRE et integration Telegram).

### Bug Coolify v4 documenté (runbook)
- Changer la FQDN d'une app Coolify v4 dans l'UI ne régénère pas le `docker-compose.yaml` côté serveur cible si on save sans avoir clear le champ d'abord. Ni Redeploy ni Force Rebuild ne forcent la régen. Le compose existant est utilisé tel quel, donc les Traefik labels conservent l'ancien Host rule = 404 sur les nouveaux domaines.
- **Workaround** : clear COMPLET du champ Domains dans l'UI, save (Coolify enregistre "vide"), re-paste la valeur souhaitée, save, redeploy. Le double-save flag le state comme dirty et force la régénération.
- **Alt workaround si bug persiste** : CF Tunnel Public Hostname avec HTTP Host Header rewrite vers l'ancienne FQDN, bypass complet sans toucher Coolify.
- Runbook complet dans `runbooks/coolify-domain-change-gotcha.md`.

### Bug Wazuh API documenté (runbook)
- Après plusieurs `systemctl restart wazuh-manager` interrompus, `/var/ossec/var/run/.restart` flag file orphelin → l'API retourne 500 sur tout (même `/security/user/authenticate`) avec message "Some Wazuh daemons are not ready yet" même quand `wazuh-control status` montre tous les daemons running.
- **Fix** : `rm -f /var/ossec/var/run/.restart`. Doc dans `runbooks/fix-wazuh-api-stuck-restarting.md`.

### Bug Wazuh dashboard placeholder password documenté
- `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml` ship par défaut avec un placeholder password `q3V32d.dVv1MJciJkkmXJw2NeVdwSs69` pour le user `wazuh-wui` (placeholder de l'exemple, jamais auto-replacé par l'installer 4.14). Conséquence : dashboard affiche "[API connection] No API available to connect" en boucle.
- **Fix** : extraire le vrai `api_password` de `/var/ossec/wazuh-install-files/wazuh-passwords.txt` (nécessite extraction préalable du `wazuh-install-files.tar`) et update wazuh.yml. Helper script committé : `runbooks/scripts/fix-wazuh-dashboard-api-v2.py` (Python stdlib only).

### Lessons learned
- **Coolify v4 cache le compose côté serveur cible**, pas dans l'UI. Le DB FQDN est metadata UI uniquement, c'est le compose.yaml généré au premier deploy qui pilote Traefik. Les changements UI n'invalident pas ce cache de compose si le save n'est pas "dirty" (UI bug).
- **CF Tunnel Public Hostnames** auto-créent les CNAME DNS au moment de l'ajout, mais ne suppriment pas les records DNS conflictuels (A record Vercel restait). À cleanup manuellement.
- **Wazuh post-install** demande une extraction explicite du tar `wazuh-install-files.tar` pour récupérer les credentials. L'installer all-in-one ne le fait pas par défaut.
- **CanaryTokens DNS en mode "DNS only"** est critique : si on laisse en proxy CF (orange), c'est CF qui résout le CNAME en cache → token fire à chaque renouvellement de cache, pas quand un attaquant query.

---

## [2026-05-06] - Quick wins block : ISM + LXC cleanup + IP static + MITRE
- Vercel project portfolio archivé après ~7 jours fallback (vers le 13 mai 2026)
- Phase 4 : backups B2 (à reprendre - `/data/coolify/` + DBs futurs clients chiffrés vers Backblaze)
- Setup PostHog ensemble pour le portfolio prod (post-migration TODO)
- Vague 1 sécu : LXC `nsm` collecteur NetFlow + Syslog (UCG → ntopng)
- Vague 1 sécu : activer NetFlow/Syslog export sur UCG vers le futur LXC nsm

---

## [2026-05-07] - Quick wins block : ISM + LXC cleanup + IP static + MITRE

### Added
- **Wazuh ISM retention policy `wazuh-retention-30d`** appliquée via OpenSearch API (`PUT /_plugins/_ism/policies/...`). Auto-applied via `ism_template` aux index `wazuh-alerts-*` + `wazuh-archives-*`. Délète indices > 30 jours → footprint disk indexer stable.
- **`runbooks/scripts/apply-wazuh-ism-policy.sh`** : helper qui extrait admin password depuis `/var/ossec/wazuh-install-files/wazuh-passwords.txt` (sur LXC, jamais en argv) et applique la policy.
- **MITRE ATT&CK mappings sur 11 custom rules Wazuh** : enrichit le dashboard MITRE de Wazuh.

  | Rule | MITRE technique |
  |------|-----------------|
  | 100100 cowrie session.connect | T1110 (Brute Force) + T1078 (Valid Accounts) |
  | 100103 cowrie command.input | T1059 (Command Interpreter) |
  | 100104 cowrie pivot direct-tcpip | T1572 (Protocol Tunneling) + T1090 (Proxy) |
  | 100105 cowrie file_download | T1105 (Ingress Tool Transfer) |
  | 100200 traefik path scan | T1595.003 (Wordlist Scanning) |
  | 100203 traefik web brute force | T1110.001 (Password Guessing) |
  | 100205 traefik 404 burst | T1595.001 (IP Block Scanning) |
  | 100400 PVE web UI brute force | T1110.003 (Password Spraying) |
  | 100500 adguard suspicious TLD | T1071.004 (DNS C2) |
  | 100501 adguard burst | T1071.004 + T1041 (Exfiltration over C2) |
  | 100502 adguard tunneling | T1572 + T1041 |

### Changed
- **LXC 101 frigate** : DHCP → **static `192.168.1.80/24`** via `pct set` + reboot. Plus de risque que le DHCP donne une autre IP au prochain renouvellement.
- **Monthly backup vmid list** : suppression de 110 (LXC détruit).

### Removed
- **LXC 110 nginxproxymanager (NPM)** détruit via `pct destroy 110 --force`. Stopped depuis migration Traefik (5 mai 2026), 0 dependances. Backups conservés sur backup-ssd (May 3) + Hitachi (May 6) - restorable si besoin via `pct restore 110 ...`.
- **8 GB libérés** sur local-lvm thinpool.

### Resolved
- **LXC `ubuntu` inconnu** (MAC `02:00:00:00:00:1a`, IP `192.168.1.86`) → identifié comme stale DHCP entry d'un ancien workload PVE supprimé (OUI `BC:24:11` = Proxmox virtio-net OUI). Hôte offline. À nettoyer manuellement dans UCG.

### Lessons learned
- **`/var/ossec/wazuh-install-files/wazuh-passwords.txt`** est le fichier canonique pour les passwords Wazuh post-install. Format `indexer_username:` + `indexer_password:` (pas `username:` standard YAML). Extract via regex, jamais cat brute.
- **`pct restart` n'existe pas** - utiliser `pct reboot` ou `pct stop` + `pct start`. Erreur courante.
- **`pct set <id> --net0 ...,ip=X/24`** met à jour la config mais runtime échoue avec "Address already assigned" si DHCP a déjà l'IP. Reboot LXC pour réappliquer proprement.
- **MITRE mapping ajouté via tag `<mitre><id>TXXXX</id></mitre>`** dans les rules - pas un attribut, un sub-element. Wazuh dashboard MITRE pull auto les techniques.

---

## [2026-05-06] - Vague 2 sécu Phase K : Docker container monitoring + Wazuh dashboards exploration

### Added
- **`configs/wazuh/group-vm-services-agent.conf`** : per-group shared config qui ajoute le `docker-listener` wodle aux agents du groupe vm-services (authentik VM 117 + coolify VM 300). Track:
  - container start/stop/die/kill
  - image pulls + creates
  - network connect/disconnect
  - volume mounts
  Wazuh built-in rules 87925-87935 (groupe `docker`) catch ces events au niveau manager → alerts dashboard.
- **`wazuh` user ajouté au groupe `docker`** sur VM 300 (coolify) + VM 117 (authentik) - pré-requis pour que docker-listener wodle puisse lire `/var/run/docker.sock`. Agent restart pour pickup.

### Wazuh dashboards : guide d'exploration UI (https://wazuh.home.example.com)

| Module | Path | Useful pour |
|--------|------|-------------|
| **Threat Hunting** | `Modules → Security events` | Vue alerts level >= X par agent/rule. Filter par `rule.level: >= 10` pour voir ce qui a triggered Telegram. |
| **Vulnerabilities** | `Modules → Vulnerabilities` | CVE découvertes via syscollector + NVD feed. Liste packages vulnérables par agent. |
| **MITRE ATT&CK** | `Modules → MITRE ATT&CK` | Mapping de tes alerts aux techniques MITRE (T1110 brute force, T1078 valid accounts, etc.). |
| **PCI DSS / GDPR / HIPAA / NIST** | `Modules → <compliance>` | Compliance dashboards auto-générés depuis groupes des rules. Visible si tu vises certif. |
| **FIM** | `Modules → File Integrity Monitoring` | Inventory des fichiers modifiés sur tous agents. Filter par agent honeypot pour voir si attaquant touche cowrie config. |
| **SCA** | `Modules → Security configuration assessment` | Score CIS Debian 13 par agent - checklist hardening. Premier scan auto au join, re-scan toutes 12h. |
| **Inventory** | `Modules → Inventory data` | Hardware/OS/processes/ports/users par agent - état exact à un instant T. |
| **Discover** | `Discover` | Recherche brute LogQL-style sur tous les events. Pour drill-down spécifique. |
| **Custom rules dashboard** | À CONSTRUIRE via UI | Filter sur `rule.id: 100100..100502` pour voir tes detections custom. |

### Lessons learned
- **Wazuh wodle docker-listener** est un sub-process Python qui parse `/var/run/docker.sock` events. Le user wazuh doit être dans le groupe docker (`usermod -aG docker wazuh`). Plus restart agent.
- **Per-group `agent.conf` push automatique via `merged.mg`** - pas besoin de touch chaque agent. Manager regénère le merged.mg quand un fichier dans `/var/ossec/etc/shared/<group>/` change, agents auto-pull dans les ~10 min.
- **Wazuh dashboards intégrés sont déjà très riches** - pour homelab, customisation UI = drag-drop dans Discover → Save view → ajouter au dashboard. Pas besoin d'écrire du JSON.
- **Vulnerability detection scan-on-start activée** - au join chaque agent inventaire ses packages, manager pulls NVD feed (60m interval), match CVE → dashboard montre vulns par agent. Excellente actionable info pour décisions update.

### Files added
- `configs/wazuh/group-vm-services-agent.conf` - agent.conf with docker-listener for vm-services group

---

## [2026-05-06] - Vague 2 sécu Phase J : Wazuh agent groups organization

### Added
- **5 Wazuh agent groups** créés via `agent_groups -a -g <name>` :

  | Group | Agents | Purpose |
  |-------|--------|---------|
  | `pve-host` | 001 (pve) | Host Proxmox lui-même - rules pveproxy/pvedaemon |
  | `lxc-services` | 002, 003, 004, 005, 006, 007, 008, 009, 010, 013 (10 LXC apps : adguard, frigate, traefik, influxdb, grafana, glance, excalidraw, servarr, nas-files, immich) | Services applicatifs standards |
  | `lxc-honeypot` | 011 (cowrie) | Honeypot LXC - FIM aggressive sur cowrie config |
  | `lxc-monitoring` | 012 (nsm-logs) | Loki + Vector (logs centralisés) |
  | `vm-services` | 014 (authentik), 015 (coolify) | VMs avec docker workloads |

  Default group vidé (0 agents). Tous les 15 agents alloués.

- **`configs/wazuh/group-lxc-honeypot-agent.conf`** : per-group shared config qui ajoute realtime FIM sur `/home/cowrie/cowrie/etc/` + `/home/cowrie/cowrie/userdb.txt` aux agents du groupe lxc-honeypot. Détecte si un attaquant ayant pivoté tente de modifier la config Cowrie pour échapper.

### Why agent groups
- **Targeted config push** : ajout d'options FIM/syscheck/localfile spécifiques par groupe sans toucher les autres LXC. Wazuh manager push automatiquement via `merged.mg` (sync ~10 min).
- **Dashboard filtering** : sur `wazuh.home.example.com`, possible de filtrer alerts par groupe → vue dédiée honeypot vs services standards.
- **Future-proof** : ajout futur de rules ciblées via `<group>vm-services</group>` etc. sans rewrite.

### Lessons learned
- **`agent_groups -a -g <name>` crée le groupe** dans `/var/ossec/etc/shared/<name>/` avec un `agent.conf` vide + `merged.mg` auto-généré.
- **`agent_groups -a -i <agent_id> -g <group> -f -q`** assigne un agent (option `-f` force = move from default to new group).
- **`systemctl reload wazuh-manager` n'est pas supporté** - utiliser `systemctl restart` (le reload time-out après 30s).
- **Agent groups ≠ rule groups** : agent groups regroupent les agents pour push de config. Les `<group>` dans les rules sont des tags d'événement (ex: "attack,web,scan"). Pas de relation directe.

### Files added
- `configs/wazuh/group-lxc-honeypot-agent.conf` - agent.conf for lxc-honeypot

---

## [2026-05-06] - Vague 2 sécu Phase I : AdGuard DNS detection (TLDs suspects + DNS tunneling)

### Added
- **ACL `setfacl -m u:wazuh:r`** sur `/opt/AdGuardHome/data/querylog.json` (file mode 600 root par défaut, ACL contourne sans modifier mode global). Pkg `acl` installé.
- **Wazuh agent localfile JSON** sur LXC 100 monitoring `/opt/AdGuardHome/data/querylog.json`.
- **3 custom rules AdGuard** (`local_rules-adguard.xml`) :

  | Rule ID | Level | Match | Tg ? |
  |---------|-------|-------|------|
  | 100500 | 9 | QH ends in `.tk\|.ml\|.ga\|.cf\|.gq\|.xyz\|.top\|.loan\|.click\|.download\|.win` | ❌ silent |
  | 100501 | **11** | freq 5+ 100500 / 60s same client IP = **C2/exfil burst** | ✅ |
  | 100502 | **10** | QH = subdomain ≥ 40 chars `[A-Za-z0-9+/=_-]` = **DNS tunneling** | ✅ |

### Validation
- Rules testées via `wazuh-logtest` avec sample JSON `{"QH":"evil-malware.tk",...}` → rule 100500 matche correctement (L9, decoded as json, IP extracted).

### Caveat (live test partiel)
- Live test (`dig +short evil.tk @192.168.1.246`) n'a pas trigger d'alert immédiat car **AdGuard bufferise les queries en mémoire (`size_memory: 1000`)** avant flush disk périodique. Les vrais events réseau seront détectés au prochain flush (typiquement < 5 min).
- En production, le délai d'alerte ~2-5 min sur DNS suspects est acceptable pour homelab.

### Lessons learned
- **`setfacl` ACL > chmod** pour exposer un file restrictif (mode 600 root) à un user spécifique sans relâcher les perms global. Survit aux opérations de l'app si append-only (AdGuard append).
- **AdGuard buffer queries en mémoire avant flush** - `size_memory: 1000` dans `AdGuardHome.yaml` contrôle ça. Pour real-time logging, faut éventuellement passer à syslog export (AdGuard supporte plusieurs sinks).
- **Rule basée sur PCRE2 sur extension TLD** est très simple et signal/noise excellent - légit traffic ~0% utilise les free TLDs (.tk/.ml/.ga/.cf/.gq) qui sont massivement abusés par C2/phishing.
- **DNS tunneling pattern** (long random subdomain ≥ 40 chars base64-like) est un proxy entropie - pas parfait, mais détecte les patterns évidents type DNScat2/Iodine/dnsmap. False positives possibles sur services normaux qui utilisent des subdomain hash long (ex: certains CDN, GCP/AWS).

### Files added
- `configs/wazuh/agent-localfile-adguard.xml`
- `configs/wazuh/local_rules-adguard.xml`

---

## [2026-05-06] - Vague 2 sécu Phase H : Coolify webhook spoofing investigation (no fix nécessaire)

### Investigated
- **Tentative de detection webhook spoofing** sur Coolify via test : `curl -X POST https://coolify.home.example.com/webhooks/source/github/events -H "X-Hub-Signature-256: sha256=DEADBEEF" ...`
- **Constat** : Coolify répond `HTTP 200` avec body `"Invalid signature."` mais **ne log RIEN** visible dans :
  - `docker logs coolify` (stdout container)
  - `/var/www/html/storage/logs/laravel.log` interne au container
- Wazuh ne peut donc pas catch ces events sans patcher Coolify (forking) ou ajouter un middleware externe - trop invasif pour le ROI.

### Decision
- **Pas de rule custom Wazuh pour Coolify webhook spoofing.** La defense en place est déjà multi-couche et robuste :
  - Cloudflare Tunnel public ingress filtré strict (`/webhooks/*` only via Bypass policy)
  - HMAC signature validation côté Coolify Laravel (rejet silencieux côté handler)
  - CF Access Email OTP + 2FA sur l'UI Coolify principale (le webhook n'est pas via UI)
- Une attaque webhook spoofing nécessiterait : récupérer le HMAC secret côté GitHub OU casser HMAC SHA-256 - both implausible.
- **À reconsidérer si** : Coolify expose les event logs webhook dans une future version, OU si on déploie un proxy intermédiaire (par ex. nginx avec acceslog enrichi).

### Lessons learned
- **Tester avant d'écrire des rules** : envoyer un fake event de la classe à détecter, voir si quelque chose est loggué quelque part. Si rien n'est loggué, pas la peine d'écrire des rules. Économise des heures.
- **Coolify Laravel utilise écrit sur stdout pour info, mais SILENT sur reject HTTP** (security through ε-obscurity). Pour audit, faudrait soit patcher la source, soit observer côté reverse proxy avec access log enrichi.
- **Architecture defense-in-depth gagne** : pas besoin de TOUT détecter en sécurité observability ; les défenses préventives bien configurées (CF Access + HMAC + tunnel restreint) couvrent là où la détection est impossible/coûteuse.

---

## [2026-05-06] - Vague 2 sécu Phase G : PVE web UI brute force detection

### Added
- **`configs/wazuh/local_rules-pve.xml`** : custom rule **100400 level 11** frequency 5+ in 60s aggregating `if_matched_sid>87201</if_matched_sid>` (sans `same_source_ip` constraint). Détecte brute force depuis n'importe quelle IP source.

### Why custom over default
- Wazuh ships **rule 87202 level 10** (frequency 8/120s + `same_source_ip />`) - built-in, mais le `same_source_ip` ne match pas toujours sur PVE car `pvedaemon` log `rhost=::ffff:X.X.X.X` (IPv4-mapped IPv6 format) et le decoder Wazuh n'extrait pas srcip de manière fiable depuis ce format.
- Notre 100400 est plus sensible (5/60s vs 8/120s) et plus permissif (any source) - meilleur signal/noise pour homelab single-host.

### Validation
- 7 attempts dense via `curl -d "username=evilN&password=wrong" https://192.168.1.90:8006/api2/json/access/ticket` → `pvedaemon` loggue `authentication failure; rhost=...` → wazuh-agent (ID 001 pve) forward via journald → manager rule 87201 fire silent (L6) → aggregate 100400 fire (L11) → integration custom-telegram → 3 Telegram delivered (message_id 69-71).

### Lessons learned
- **Wazuh décodeur `pvedaemon` existe par défaut** dans `/var/ossec/ruleset/decoders/` + `0495-proxmox-ve_rules.xml` ships rule 87201/87202. Pas besoin de décodeur custom.
- **`pveum` decoder N'existe pas** dans Wazuh stdlib - éviter `<decoded_as>pveum</decoded_as>` (manager refuse de boot avec `Invalid decoder name`).
- **`<same_source_ip />`** dépend du decoder extracting srcip field. Pour les events où le format est IPv4-mapped IPv6 (`::ffff:X.X.X.X`), l'extraction peut fail. Tester avec wazuh-logtest avant de rely dessus.
- **Aggregate rules fire MULTIPLE times** quand la fenêtre glissante continue à matcher - 7 attempts → 3 alerts 100400 (chaque fois que threshold re-atteint). Pas un bug, design.

---

## [2026-05-06] - Vague 2 sécu Phase F : SSH brute force detection (PVE host, default + custom rules)

### Validated
- **Wazuh default rule 5712 (level 10) fonctionne** pour le pattern moderne sshd "Invalid user X from Y" (= random invalid usernames = brute force réaliste). 5+ attempts en 30s → alert L10 → Telegram livré (message_id 68 lors du test). Aucune custom rule nécessaire pour ce pattern le plus courant.
- **Custom rules 100300-100304** dans `local_rules-sshd.xml` couvrent l'edge case "Connection closed by authenticating user X" (= valid system user qui échoue auth). Validé via `wazuh-logtest` (3 patterns synthetic match → L5/L10/L11 selon la rule).

### Method (debugging journey)
1. **Hypothèse fausse initiale** : "Wazuh default rules ne matchent pas modern sshd". Faux - elles matchent "Invalid user" (cas réaliste). Le test initial avec `nobody@127.0.0.1` était pathologique car `nobody` est un user système valide → sshd écrit "Connection closed by authenticating user" (pas "Invalid user").
2. **Activé `<logall>yes</logall>`** dans ossec.conf temporairement → archives.log capture les raw events reçus du wazuh-agent → confirmé que les events SONT bien forwardés.
3. **Re-test avec random invalid usernames** (fresh-1..5) → alerts.log montre rule 5710 + 5712 fire correctement. Tg livré L10.
4. **logall désactivé** ensuite (disk usage : enabled = +qq MB/jour).

### Lessons learned
- **Wazuh modern sshd detection FONCTIONNE par défaut** sur Debian 13 / Ubuntu 24 si les attempts utilisent random invalid usernames. Le mythe "Wazuh ne match pas modern sshd" vient de tests pathologiques (valid user names).
- **`<logall>yes</logall>`** dans ossec.conf est un game-changer pour debug : log TOUS les events received par manager dans `/var/ossec/logs/archives/archives.log`. À activer le temps du debug, désactiver après (forte volumétrie).
- **`wazuh-logtest` est l'outil de référence** pour tester rules vs samples logs avant deploy. Lit stdin ligne-par-ligne, output Phase 1 (pre-decoding) + Phase 2 (decoding) + Phase 3 (rules) + Alert verdict.
- **Wazuh sshd decoder regex `^sshd`** (anchored) match `sshd` ET `sshd-session` (Debian 13 split). Pas besoin de patch decoder.
- **5710 = "Attempt to login using a non-existent user"** (level 5, single event). **5712 = "brute force trying to get access. Non existent user"** (level 10, frequency 8/120s aggregate). 5712 dépend de 5710 firing first.

---

## [2026-05-06] - Vague 2 sécu Phase E : Traefik scan detection (path probing + brute force)

### Added
- **Traefik filter `statusCodes: ["200", "400-599"]`** dans `configs/traefik/traefik.yaml` (avant : `["200"]` only - 4xx invisibles, gros gap sécu). Maintenant : audit (200) + security (400-599) loggés en JSON dans `/var/log/traefik/traefik-access.log`. Headers filter garde `User-Agent` only (pour bot detection).
- **Wazuh agent LXC 103 monitor `/var/log/traefik/traefik-access.log`** (log_format json - fields `RequestPath`, `DownstreamStatus`, `ClientHost`, `request_User-Agent` etc accessibles aux rules).
- **6 rules custom Traefik** dans `local_rules.xml` :

  | Rule ID | Level | Match | Tg ? |
  |---------|-------|-------|------|
  | 100200 | **11** | RequestPath PCRE2 `\.env`/`\.git`/`admin`/`wp-login`/`phpmyadmin`/`actuator`/`HNAP1`/`boaform`/etc | ✅ |
  | 100201 | 5 | DownstreamStatus 5xx | ❌ |
  | 100202 | 6 | DownstreamStatus 401\|403 (silent base) | ❌ |
  | 100203 | **11** | freq 5+ 100202 / 60s same ClientHost = brute force | ✅ |
  | 100204 | 3 | DownstreamStatus 404 (silent base) | ❌ |
  | 100205 | **10** | freq 20+ 100204 / 60s same ClientHost = path probing | ✅ |

### Validation
- 3 path scans simulés (`/.env`, `/admin/login`, `/wp-login.php`) → 2 alerts L11 fired (`/.env` et `/wp-login.php` matchent le PCRE2 - `/admin/login` aussi mais peut-être pas dans le snapshot tail) → 2 Telegram delivered (msg_id 66, 67). Pipeline `Traefik JSON → Wazuh agent → manager → rule match → integration → Telegram` validé E2E.

### Lessons learned
- **Wazuh frequency rules nécessitent `<if_matched_sid>` ou `<if_matched_group>`** - sans ça, error `Invalid use of frequency/context options. Missing if_matched on rule '...'`. Pattern : 1 base rule (silent low level) + 1 frequency rule qui référence la base. Permet aussi de réutiliser une base pour multiple aggregations.
- **Traefik `accessLog.filters.statusCodes`** est un filtre INCLUDE (whitelist), pas une exclusion. `["200"]` = log seulement 200. Pour security on veut au moins `["200", "400-599"]`.
- **Traefik static config reload** : le `systemctl reload traefik` est cassé sur l'unit file Debian (`\$MAINPID` quoting bug), mais `systemctl restart` marche. ~3s downtime acceptable. Le file provider conf.d/ est watched live (no restart needed pour les routes).
- **Wazuh JSON decoder** parse auto les champs Traefik (CamelCase original : `RequestPath`, `DownstreamStatus`, `ClientHost`). Pas besoin de décodeur custom XML.
- **Restore + re-append** est plus safe que regex-replace sur local_rules.xml. Le fail mode (manager refuse de boot sur XML invalid) demande recovery manuelle. Convention : oldest backup = état stable de base, append blocks par-dessus.

### Files added
- `configs/wazuh/agent-localfile-traefik.xml` - block ossec.conf agent LXC 103
- `configs/wazuh/local_rules-traefik.xml` - 6 rules custom manager

### Files modified
- `configs/traefik/traefik.yaml` - filter statusCodes étendu à 400-599 + retryAttempts/minDuration/User-Agent

---

## [2026-05-06] - Vague 2 sécu Phase D2 : dedup cowrie alerting (1 Telegram par session)

### Changed
- **Lower rules cowrie 100102 (login.success) et 100103 (command.input) à level 8** dans `local_rules.xml` du manager - sous le threshold Telegram (L≥10). Conséquence : 1 SSH attempt sur honeypot = **1 seul Telegram** (cowrie.session.connect L12), au lieu de 3 précédemment. Les détails (login + command) restent dans `wazuh.home.example.com` si drill-down nécessaire.
- **Pause Grafana alert rule `cowrie-ssh-attempt`** (`isPaused: true` dans `configs/grafana/alerting/alert-rules.yaml`) - Wazuh fournit maintenant des alerts plus fines (rule_id, src_ip, agent context) que le agrégat Grafana de 5min. Réactiver si Wazuh down.

### Fixed
- **Refactor `custom-telegram` bash → Python** (`configs/wazuh/custom-telegram.sh`) - fix bug `Groups: 110/0` cosmétique. Le script bash + `set -u` + `jq` produisait un rendering inattendu du field `.rule.groups` quand appelé par Wazuh runtime (différent de tests directs avec le même JSON). Le refactor utilise stdlib Python (`json` + `urllib.request`), élimine la dep `jq`, ajoute escape HTML proprement, et log structured.

### Validation
- Test : 1 SSH attempt sur 192.168.1.158:22 → manager fire 3 rules (100100 L12, 100102 L8, 100103 L8) → integration filter level≥10 → **1 message Telegram** envoyé (rule 100100). ✅

### Known issue résiduel
- **Restart wazuh-manager casse temporairement la connexion agents** (Lost connection ~30-60s) - events cowrie pendant le gap sont buffered côté agent et flushed au reconnect. Pas de perte mais latence variable. Pattern attendu Wazuh 4.x.

### Lessons learned
- **Wazuh rule levels = filter primaire pour notification** : la stratégie homelab "1 alert par event critique" est plus simple via `<rule level="X">` que via `<integration><rule_id>` filtering ou `<options>no_log</options>`. Garder rules à L<10 = silencieuses, L≥10 = Telegram.
- **Grafana provisioning supporte `isPaused: true`** dans `alert-rules.yaml` - préserve la rule pour réactivation rapide sans la supprimer. Reload via `systemctl restart grafana-server`.
- **Editing local_rules.xml** : éviter les regex de remplacement multi-block. Préférer `restore from backup + append fresh`. Le fail mode est un XML corrompu qui empêche wazuh-manager de boot ("Element not opened. (line N)") - Wazuh ne valide pas le XML avant de tenter de parser, donc 1 erreur = service down.

---

## [2026-05-06] - Vague 2 sécu Phase D : Cowrie honeypot ↔ Wazuh integration

### Added
- **Wazuh agent LXC 120 honeypot monitor `/home/cowrie/cowrie/var/log/cowrie/cowrie.json`** (`<localfile>` block, `log_format=json` → fields décodés auto). File 0644 cowrie:cowrie, lisible par wazuh-agent.
- **6 custom rules cowrie** dans `/var/ossec/etc/rules/local_rules.xml` du manager (group `cowrie,honeypot,custom,`) :

  | Rule ID | Level | Trigger | Tg ? |
  |---------|-------|---------|------|
  | 100100 | **12** | `cowrie.session.connect` (TOUTE connexion = critique car honeypot ne devrait pas avoir de trafic légitime) | ✅ |
  | 100101 | 8 | `cowrie.login.failed` | ❌ |
  | 100102 | **10** | `cowrie.login.success` | ✅ |
  | 100103 | **11** | `cowrie.command.input` (cmd exécutée sur honeypot) | ✅ |
  | 100104 | **13** | `cowrie.direct-tcpip.request` (SSH tunnel pivot - top severity) | ✅ |
  | 100105 | 9 | `cowrie.session.file_download` (malware download attempt) | ❌ |

### Validation
- 1 SSH attempt sur `192.168.1.158:22` (NAT redirect → cowrie:2222) déclenche **3 alerts Telegram en cascade** : L12 connect + L10 login success + L11 command input. Pipeline `cowrie.json → wazuh-agent → manager → rule match → integration → Telegram` validé E2E. Latence ~10s entre SSH et notification.
- `agent_control -lc` confirme honeypot en Active.

### Known issue (cosmétique)
- Le champ `Groups` dans le message Telegram apparaît parfois mal rendu (`110` au lieu de `cowrie,honeypot,custom,attack,exec,intrusion_attempt,recon`). Le `jq -r '.rule.groups | join(",")'` fonctionne en test direct sur le même JSON, mais le file passé par Wazuh integration runtime semble avoir un format légèrement différent. À investiguer (probable refactor du script en Python pour parsing plus robuste). N'affecte que le rendering, pas la détection.

### Lessons learned
- **Wazuh JSON localfile = decoder auto-magic** : avec `<log_format>json</log_format>`, les fields cowrie (eventid, src_ip, username, password, input, dst_ip…) sont accessibles dans les rules custom via `<field name="X">VALUE</field>` SANS écrire de décodeur custom. Énorme gain de temps vs syslog/regex parsing.
- **Cowrie auto-accepte root sans password par défaut** (config Cowrie standard pour piéger plus largement) - donc chaque SSH attempt génère AU MOINS 2 alerts (connect + login.success). Si on veut un seul alert par session, déduper côté manager via `<if_sid>` ou côté Cowrie via `auth_class.UserDB`.
- **Wazuh manager appelle l'integration script avec un fichier alert temporaire** (différent de `/var/ossec/logs/alerts/alerts.json`). Pour debug, ajouter `cp $1 /tmp/last-alert.json` au début du script - lifesaver pour comprendre quels champs sont passés.
- **Variables d'env Wazuh + bash + jq** : `set -u` + `jq -r` peut retourner output silencieux si path JSON missing. Préférer `jq -r 'try (.path) // "default"'` pour fallback safe.
- **Cowrie + iptables NAT 22→2222** : externes hit cowrie:22, MAIS les commandes `pct exec 120 ssh ...` côté loopback bypassent NAT (PREROUTING ne filtre pas loopback). Pour test localhost, faut SSH depuis un autre host LAN.

### Files added
- `configs/wazuh/agent-localfile-cowrie.xml` - block à insérer dans ossec.conf de l'agent honeypot
- `configs/wazuh/local_rules-cowrie.xml` - 6 rules custom à append dans local_rules.xml du manager

---

## [2026-05-06] - Vague 2 sécu Phase C : Wazuh → Telegram alerting (level ≥ 10)

### Added
- **Custom integration `/var/ossec/integrations/custom-telegram`** (bash + jq + curl) - formate les alerts Wazuh en messages Telegram HTML (severity icon ⚠️/🚨/ℹ️ selon level, agent, rule ID, groups, location, full_log tronqué à 600 char). Exécutable par Wazuh manager comme any built-in integration.
- **`<integration>` block dans `/var/ossec/etc/ossec.conf`** (sur LXC 122 uniquement, jamais committé) :
  ```xml
  <integration>
    <name>custom-telegram</name>
    <hook_url>${BOT_TOKEN}</hook_url>
    <api_key>${CHAT_ID}</api_key>
    <level>10</level>
    <alert_format>json</alert_format>
  </integration>
  ```
  Filtre level ≥ 10 = high/critical only - pas de spam tg pour les alertes informationnelles. Le contact Telegram réutilise le bot homelab existant (token + chat_id partagés avec PVE notifications + Grafana alerting).
- **Helper `configs/wazuh/add-telegram-integration.py`** : script Python idempotent qui lit `WAZUH_TG_TOKEN` + `WAZUH_TG_CHAT_ID` depuis env vars (jamais hardcodé) et insère le block XML dans ossec.conf avec backup auto. Repétable sans risque.

### Validation
- End-to-end test avec 2 alerts JSON synthétiques (level 11, 12) → Telegram API retourne `{"ok":true, "message_id":N}` → message livré sur le bot homelab. Pipeline `Wazuh manager → integration script → Telegram API` validé.

### Method (zero-secret-in-repo workflow)
- Le token Telegram **n'apparaît dans aucun fichier commité**. Extraction runtime via :
  ```bash
  ssh root@192.168.1.90 '
    TOKEN=$(pct exec 108 -- grep "bottoken:" /etc/grafana/provisioning/alerting/telegram.yaml | awk "{print \$2}" | tr -d "\"\r\n ")
    pct exec 122 -- env WAZUH_TG_TOKEN="$TOKEN" python3 /tmp/add-tg.py
  '
  ```
  Source canonique = LXC 108 (Grafana telegram.yaml), reaccessible si rotation.

### Lessons learned
- **Custom integrations Wazuh = path-based, pas plugin**. Mettre script exécutable dans `/var/ossec/integrations/` avec nom `custom-<name>`, perms 750 root:wazuh. Wazuh appelle automatiquement avec args `<alert_file_path> <api_key> <hook_url> [options]`.
- **`alert_format json`** essentiel - sans ça Wazuh passe le format texte legacy moins parseable. Avec JSON on a `.rule.level`, `.rule.groups`, `.agent.name`, `.full_log` etc accessibles via `jq`.
- **Heredoc imbriqué dans `pct exec 122 -- bash -c "..."`** = quoting nightmare avec `[`/`]`/`"` à 3 niveaux d'escape. Pour scripts/JSON complexes, écrire fichier local + `scp` + `pct push` >> heredoc inline.
- **Telegram bot delivery confirmé via `integrations.log`** (`/var/ossec/logs/integrations.log`) - chaque POST y append le response JSON Telegram. `"ok":true` + `message_id` = livré. Si `error_code` présent = troubleshoot (token, chat_id, parse_mode escaping, message_too_long).

---

## [2026-05-06] - Vague 2 sécu Phase B : Wazuh agents partout (15 agents, 100% coverage)

### Added
- **15 Wazuh agents 4.14.5 enrolled** sur tous les hosts actifs (PVE + 12 LXC + 2 VMs), excl. HAOS VM 102 (HassOS specialisé) et NPM LXC 110 (stopped, à archiver).
  | ID | Host | Type |
  |----|------|------|
  | 001 | pve | host PVE |
  | 002 | adguard | LXC |
  | 003 | frigate | LXC |
  | 004 | traefik | LXC |
  | 005 | influxdb | LXC |
  | 006 | grafana | LXC |
  | 007 | glance | LXC |
  | 008 | excalidraw | LXC |
  | 009 | servarr | LXC |
  | 010 | nas-files | LXC |
  | 011 | honeypot | LXC |
  | 012 | nsm-logs | LXC |
  | 013 | immich | LXC |
  | 014 | authentik | VM |
  | 015 | coolify | VM |
- **Backup snapshot des 14 hosts** vers `backup-ssd` (~32 GB ajoutés, total `backup-ssd` à 39%) AVANT la modification - cohérent avec la consigne "backup-first" sur LXC existants.

### Method
- Pour les 12 LXC : loop `pct exec <id> -- bash -c "..."` sur le PVE host (snippet add apt repo Wazuh + `WAZUH_MANAGER=192.168.1.221 WAZUH_AGENT_NAME=<host> apt install wazuh-agent`).
- Pour les 2 VMs : `qm guest exec <vmid> --synchronous 1 --timeout 600 -- /bin/bash -c "..."` via qemu-guest-agent (évite SSH key juggling : VM 117 sans mes keys, VM 300 host key change post-recréation + user `ubuntu` pas `root`).
- ~10 min total post-backup.

### Fixed
- **LXC 106 immich initial deploy fail** (`gpg: command not found` + `apt update` partial fail) → root cause : initial `apt update -qq` a échoué probablement à cause d'IPv6 timeouts (les domaines Wazuh résolvent en IPv6 d'abord, et l'LXC immich n'a pas de connectivité IPv6 stable). Fix : retry avec `apt -o Acquire::ForceIPv4=true update`. Tous les agents installés ensuite forcent IPv4 systematiquement.

### Lessons learned
- **`apt update` peut échouer silencieusement sur certains LXC** quand DNS résout AAAA d'abord et que l'LXC a IPv4-only. `apt -o Acquire::ForceIPv4=true update` plus reliable. À mettre en standard dans futurs scripts.
- **`qm guest exec` propre alternative à SSH** pour automatiser des VMs depuis le PVE host - pas de gestion de SSH keys, pas de host key drift, juste qemu-guest-agent installé. Syntax `qm guest exec <vmid> --synchronous 1 --timeout 600 -- /bin/bash -c "<one-line-script>"` retourne JSON avec `out-data` field (parser via Python).
- **Wazuh agent enrollment non instantané** - le compteur agent_control peut prendre 5-15s pour montrer le nouveau agent même quand `systemctl is-active` retourne `active` côté agent. Toujours re-check enrollment après quelques secondes avant de conclure que ça a échoué.
- **Backup-first sur LXC existants confirmé utile** - le batch de backup a pris ~25 min total (5 + 20) pour 14 hosts, et même si la restauration ne s'est pas avérée nécessaire, c'est l'assurance qui permet d'agir vite et sans peur. Pattern à reproduire systématiquement avant tout `apt install` ou config change sur infrastructure shared.

---

## [2026-05-06] - Vague 2 sécu Phase A : Wazuh manager + 1er agent (PVE) + Grafana SQLite WAL fix

### Added
- **LXC 122 `wazuh`** Ubuntu 24.04, 4 vCPU / 6 GB / 30 GB **rootfs sur Hitachi (HDD)** - _volontairement pas local-lvm_ pour pas overprovisionner le thinpool (53% utilisé déjà). Wazuh 4.14.5 all-in-one : manager + indexer (OpenSearch) + dashboard + filebeat. IP DHCP `192.168.1.221`.
- **Route Traefik `wazuh.home.example.com`** → `https://192.168.1.221:443` (`serversTransport: insecure` pour self-signed cert, pattern authentik). LAN-only via wildcard *.home.example.com.
- **Premier agent Wazuh déployé sur PVE host** (`192.168.1.90`), enregistré sous le name `pve`. Apt repo `packages.wazuh.com/4.x/apt` ajouté avec key signed-by. `WAZUH_MANAGER=192.168.1.221 WAZUH_AGENT_NAME=pve apt install wazuh-agent`.
- **CanaryTokens DNS** sur `*.home.example.com` (subdomains attractifs : vpn, backup, git, admin, mail, api, internal, prod-db, staging) → CNAME `kpzimx9d4ah5uw2pcnq4xosjg.canarytokens.com`. Records ajoutés manuellement côté Cloudflare DNS, mode "DNS only" (pas proxy CF). Vague 3 sécu - détection recon LAN/WAN.

### Fixed
- **Grafana SQLite "database is locked" récurrent** (DatasourceError firing sur alertes UCG/Loki) - cause racine : Grafana 12.x utilisait rollback journal mode (`grafana.db-journal` présent) qui sérialise reads+writes. Job interne `k8s dashboard cleanup` rentrait en collision avec scheduler d'alertes. Fix : `wal = true` ajouté à `[database]` dans `/etc/grafana/grafana.ini` + restart. `PRAGMA journal_mode` retourne maintenant `wal`. WAL permet reads concurrents pendant qu'un write progresse.
- **Wazuh agent/manager version mismatch** (manager 4.10.3 vs agent 4.14.5 depuis apt) - l'installer `wazuh-install.sh` téléchargé depuis `/4.10/` était la branch 4.10 spécifiquement, alors que l'apt repo `4.x stable` livre la dernière 4.14.5. Erreur "Agent version must be lower or equal to manager version" lors de l'enrollment. Fix : `apt install wazuh-{indexer,manager,dashboard}=4.14.5-1` après `apt-mark unhold` pour upgrade le manager au niveau de l'agent.
- **LXC 122 initialement provisionné en Debian 13** : Wazuh installer `wazuh-install.sh` requiert `software-properties-common` (Ubuntu-specific package), absent de Debian 13 trixie repos. Debian n'est pas officiellement supporté par Wazuh. Fix : destroy + recreate l'LXC avec template Ubuntu 24.04 (Wazuh supporte officiellement Ubuntu 22.04/24.04).

### Changed
- **`vm.max_map_count = 262144` sur le host PVE** (déjà à `1048576` par défaut donc OK, mais persisté dans `/etc/sysctl.conf`) - requis par OpenSearch (Wazuh indexer). Hérité par tous les LXC depuis le kernel host.

### Lessons learned
- **Wazuh installer `wazuh-install.sh` URL contient la version : `/4.10/wazuh-install.sh` installe 4.10 spécifiquement** (pas la dernière). Pour la dernière, utiliser `/4.x/wazuh-install.sh` ou aligner le tag URL avec la version de l'apt repo (4.14 actuellement). Sinon mismatch agent/manager garanti.
- **Wazuh n'est pas officiellement supporté sur Debian** (la doc liste RHEL/CentOS/Amazon Linux/Ubuntu). L'installer essaie d'installer `software-properties-common` qui n'est pas dispo Debian 13. Pour homelab Wazuh = Ubuntu 22.04 ou 24.04 sans hésiter.
- **Grafana SQLite par défaut = rollback journal mode**, pas WAL. Les locks "database is locked" sont quasi-certains dès qu'on a alerting + dashboards + background jobs (k8s cleanup, dashboard versioning). Ajouter `[database] wal = true` dans grafana.ini est un quick win standard ; pour usage sérieux passer à Postgres.
- **Wazuh services prennent ~10 min à installer en all-in-one** (manager: 1 min, indexer: 1 min, filebeat: 6 min car il génère certs et test connectivity, dashboard: 7 min). Filebeat est le bottleneck.
- **Storage choice "anti-overprovision"** : pour les services à I/O lourd mais data-heavy (Wazuh indexer growth, Loki, Sentry future), router le rootfs vers Hitachi (HDD 916 GB) plutôt que local-lvm (SSD 141 GB thinpool, déjà à 53%). HDD speed acceptable pour batch ingest, et on protège local-lvm pour les services latency-sensitive (DBs, proxies).
- **Grafana 12 background job `k8s dashboard cleanup`** s'exécute même en homelab single-binary sans Kubernetes. Il hold un lock SQLite write et bloque tout. Avec WAL c'est un non-event ; sans WAL = locks chroniques.

---

## [2026-05-06] - Vague 1 sécu Phase G+B+ : PVE Telegram fix + Vector docker_logs Coolify

### Fixed
- **Grafana → Telegram alerting actif** - première vraie alert "Cowrie SSH attempt detected" délivrée sur Telegram. Token `bottoken` initialement fourni via base64-decode de `/etc/pve/priv/notifications.cfg` arrivait corrompu (probablement trailing newline ajouté par `base64 -d` sans `-w0`). Fix : token fourni explicitement par le user, écrit via printf direct dans `/etc/grafana/provisioning/alerting/telegram.yaml`.

### Added
- **4 alert rules Grafana** provisionnées (`/etc/grafana/provisioning/alerting/alert-rules.yaml`) :
  - `cowrie-ssh-attempt` (severity critical) - fire dès qu'une session_connect Cowrie apparaît dans 5min
  - `loki-ingest-errors` (warning) - Loki rejette >50 events/5min sustained 5m
  - `host-log-gap` (warning) - un host arrête de shipper journald pour 10+ min
  - `ucg-firewall-flood` (info) - UCG syslog rate >50/s sustained 5m
- **Vector docker_logs source sur VM 300 Coolify** - Vector watch tous les containers Coolify (Coolify app, sentinel, portfolio, webapp, postgres, redis, realtime, proxy, etc.). Labels Loki : `host=coolify, service=<container_name>, source_type=docker`. User vector ajouté au groupe docker pour accès `/var/run/docker.sock`.

### Changed
- **PVE notifications Telegram** : token PVE était DÉJÀ correct (re-encodé identique), pas besoin de update. Le silence apparent vient du fait que `pvesh create /cluster/notifications/targets/telegram/test` ne produit pas de stdout - il envoie sans verbose. Notifications PVE sont donc fonctionnelles, le user les recevait silencieusement.

### Lessons learned
- **`base64 -d` sans `-w0` peut ajouter un trailing newline** au output qui corrompt un token quand utilisé dans une URL (Telegram URL avec `\n` → bot path corrompu → 401 Unauthorized). Toujours `echo -n "..." | base64 -d` ou pipe sans newline pour les secrets.
- **Grafana provisioning yaml avec heredoc bash + variable expansion** est tricky - escaping `\$VAR` vs `$VAR` détermine si l'expansion arrive côté outer ou inner shell. Préférer `printf "%s" "$VAR"` qui est moins ambigu.
- **Vector docker_logs source** détecte auto tous les containers Docker via `/var/run/docker.sock`. User vector doit être dans le groupe docker (et le socket lisible). Container labels (`container_name`, `image`, `container_id`) exposés comme champs.

---

## [2026-05-06] - Vague 1 sécu Phase F : Grafana dashboard Homelab Overview + Telegram alerting

### Added
- **Grafana Loki datasource** : UID explicite `loki` (provisioning) pour stable references dans les dashboards. Pointe vers `http://192.168.1.242:3100`.
- **Grafana dashboard provisioner** : `/etc/grafana/provisioning/dashboards/homelab.yaml` avec folder `Homelab`, watch `/var/lib/grafana/dashboards/`, allowUiUpdates true.
- **Dashboard `Homelab - Logs Overview`** (8 panels) : log volume/host time series, 4 stats (hosts shipping, UCG events/min, Cowrie sessions/h, Loki errors), 3 logs panels (errors live, UCG live, Cowrie live).
- **Grafana Telegram contact point** `telegram-homelab` provisionné via `/etc/grafana/provisioning/alerting/telegram.yaml` (mode 640, chgrp grafana). Réutilise le bot Telegram déjà configuré côté Proxmox notifications (token + chat_id décodés depuis `/etc/pve/priv/notifications.cfg` base64).
- **Notification policy default** routes tout vers `telegram-homelab` (group 30s wait, 5m interval, 4h repeat).

### Why
- Visualisation de toutes les data Loki collectées en Vague 1 - premier "single pane of glass" pour l'observability homelab.
- Telegram alerting réutilise infra existante (bot + chat) - un seul endroit pour les alerts homelab (PVE backups + Grafana alerts), simple.

### Lessons learned
- **Grafana provisioning files doivent être lisibles par le user `grafana`** - `chmod 600` exclut `grafana` user et provisioning silencieux fail avec `permission denied` dans logs grafana-server. Utiliser `chmod 640` + `chgrp grafana`.
- **Pour datasources Grafana via provisioning**, fixer un `uid:` explicite - sans ça Grafana auto-génère un UID que les dashboards JSON ne peuvent pas pré-référencer.
- **Grafana 12 alertingProvisioning** charge `contactPoints + policies` dans le même fichier yaml. La doc et l'UI montrent tout sous `Alerting → Contact points / Notification policies`.
- **Changer un `uid:` sur un datasource déjà créé** = Grafana crash boucle "Datasource provisioning error: data source not found" car Grafana refuse de changer l'UID d'une datasource existante. Fix : ajouter `deleteDatasources: - name: Loki, orgId: 1` AVANT le `datasources:` block - force delete + recreate. Bad Gateway visible côté browser car port 3000 jamais bindé.
- **Grafana plugin auto-install au boot** essaie de fetch `grafana.com` - si DNS broken (LXC avec resolv.conf pointant sur `.81` mort), boot prend +20s par plugin. Pas un crash mais slow. Persister DNS via `pct set <id> --nameserver "192.168.1.246 1.1.1.1"`.

---

## [2026-05-06] - Vague 1 sécu Phase D : intégrations Cowrie JSON + UCG syslog + fix DNS VM 117

### Added
- **Cowrie JSON → Loki** : Vector sur LXC 120 honeypot lit `/home/cowrie/cowrie/var/log/cowrie/cowrie.json` en source `file`. Labels `source_type=cowrie, service=cowrie, host=honeypot`. Raw JSON shippé, parsing au query time via `| json` LogQL.
- **UCG syslog source** sur Vector LXC 121 nsm-logs (UDP+TCP `:5140`). Type `syslog`, parse RFC5424/3164 auto. Labels `host=ucg-ultra, service={appname}, source_type=ucg-syslog`. Test logger valide pipeline. UCG-side config requise (Settings → CyberSecure → Traffic Logging → Syslog server `192.168.1.242:5140`).

### Fixed
- **VM 117 Authentik DNS resolver** : `/etc/resolv.conf` pointait sur `192.168.1.81` (mort). Réécrit avec `192.168.1.1` + `8.8.8.8` (intention initiale vue dans `/etc/network/interfaces`). Backup ancien : `/etc/resolv.conf.bak.<timestamp>`. `nslookup deb.debian.org` fonctionne à nouveau → `apt update` réparable, docker pull aussi.

### Lessons learned
- **VRL `parse_json` est fallible** - `parsed = parse_json(.message)` sans error handling = compile error E103 "unhandled fallible assignment". Soit `parse_json!()` (panic on err), soit `, err = parse_json()`, soit `?? {}`. Plus simple et idiomatic Loki : ship raw JSON, parse au query time avec `| json` LogQL operator. Moins de logique Vector à maintenir.
- **Vector `syslog` source** parse auto RFC5424/3164 et expose `appname`, `facility`, `severity`, `source_ip` comme champs. Utiliser ces champs en labels Loki pour filtrage efficace.
- **Vector lecture file** nécessite `chmod o+x` sur le PATH parent et `chmod 644` sur le file (user vector ≠ user du producteur). Sinon "permission denied" silencieux dans Vector logs.
- **Loki rejette les timestamps trop "futurs"** (default policy ~10 min ahead). UCG envoie syslog timestamps en heure locale (Europe/Paris UTC+2 DST), Vector parse comme UTC → 2h drift → Loki refuse avec "timestamp too new". Vector source `timezone:` config n'a pas d'effet ici (probablement RFC5424 vs 3164 detection). **Workaround pragmatique** : override le timestamp en transform avec `.timestamp = now()` - UCG arrive en realtime sur UDP, on s'en fout du timestamp UCG, on garde l'original dans `.ucg_original_timestamp` pour audit.
- **Loki labels ne supportent que `[a-zA-Z_][a-zA-Z0-9_]*`** - caractères spéciaux (brackets, slashes, etc.) dans un label = 400 Bad Request. Si tu utilises un field UCG comme label (ex: `appname` qui contient `[LAN_LOCAL-RET-...]`), sanitize-le ou utilise un label statique. Mieux : ship la valeur en raw, query-time parse avec `| json`.
- **Vector labels avec `{{ field }}` qui n'existe pas sur certains events** = warning template_failed + 400. Si tu as plusieurs sources hétérogènes dans le même sink, soit séparer les sinks, soit garder uniquement les labels communs aux 2.

---

## [2026-05-06] - Vague 1 sécu Phase B : Vector déployé sur 15 hosts + fix Traefik serversTransport

### Added
- **Vector 0.50.0 déployé sur tous les LXC/VM en service** :
  - LXC : 100 (adguard), 101 (frigate), 103 (traefik), 106 (immich), 107 (influxdb), 108 (grafana), 111 (glance), 113 (excalidraw), 114 (servarr), 115 (nas-files), 120 (honeypot)
  - VMs : 117 (authentik via qm guest exec), 300 (coolify via SSH)
  - Skipped : VM 102 HAOS (OS spécialisé HassOS), LXC 110 NPM (stopped, à archiver), LXC 121 nsm-logs (déjà Vector via Phase A)
- **15 hosts shippent leur journald vers Loki** (.242:3100). Verify via `curl /loki/api/v1/label/host/values` retourne 15 entries.
- **Backup vzdump pré-install** de tous les targets (12 LXC/VM, ~21 GB compressé sur backup-ssd) pour rollback instant si problème. Pattern : 1 vzdump avant toute modif d'un LXC/VM existant.
- **Resize LXC 108 grafana** : 2 GB → 4 GB rootfs (Vector ne tenait pas dans les 50 MB libres restants).
- **Resize LXC 103 traefik** : +1 GB préventif (882 MB libres avant Vector, tight).

### Fixed
- **Traefik routes `authentik` + `pve` étaient cassées** (status `disabled`, error `servers transport not found insecure@file`). Cause : le `serversTransport: insecure` est défini dans `traefik.yaml` (provider scope `traefik`/`internal`), mais Traefik v3 résout les serversTransports en priorité par provider. Les services file-provider (admin.yml) cherchaient `insecure@file` qui n'existait pas. Fix : redéfinir `insecure` dans `coolify-apps.yml` (file provider). Authentik et PVE re-fonctionnels (HTTP 200 au lieu de 404).

### Changed
- `configs/traefik/coolify-apps.yml` : ajout `serversTransports.insecure` (duplicate de la définition `traefik.yaml`, pour scope file)
- `docs/14-security-observability.md` : Vague 1 marquée Phase B done

### Why
- Centralisation logs avant Wazuh - Loki accumule maintenant les journald de tout le homelab. Toute incident analysable via 1 query Grafana.
- Backup systématique avant toucher LXC existants - règle utilisateur explicite, applique le pattern réutilisable.

### Lessons learned
- **Traefik v3 serversTransports sont scopés par provider**. Un service file-provider ne voit pas un serversTransport défini dans le static `traefik.yaml` (provider `internal`). Toujours définir le serversTransport DANS le file provider qui l'utilise. Ou renommer en `<name>@<provider>` explicite dans la référence service.
- **VM 117 Authentik a un DNS broken** (resolv.conf pointe sur `192.168.1.81` qui timeout). À fixer (issue mémorisée dans `project_recent_incidents.md`). Workaround Vector install : `curl --resolve <host>:<port>:<ip>` direct.
- **`current_boot_only: true`** est important sur Vector journald source pour éviter de backfiller toute l'historique au démarrage (rate limit Loki sinon = 429).
- **LXCs avec rootfs 2 GB (légers)** se font remplir vite quand on installe quelque chose de moyen comme Vector (~150 MB total install). Resize +2 GB préventif pour les futurs déploiements sécu.
- **`docker restart` ne re-lit pas `--env-file`** (déjà appris pour cloudflared) - même comportement pour les containers Coolify lors d'un changement de config.

---

## [2026-05-06] - Vague 1 sécu : LXC 121 nsm-logs (Loki + Vector) + datasource Grafana

### Added
- **LXC 121 `nsm-logs`** : Debian 13 unprivileged, 2 vCPU / 2 GB RAM / 20 GB disk local-lvm, IP DHCP `192.168.1.242`. Tags `nsm;logs;observability;custom`.
- **Loki 3.7.1** installé via Grafana APT repo (`apt install loki`). Single-binary mode, storage `/var/lib/loki`, listen `:3100` (HTTP) + `:9096` (gRPC). Limits bumpés (16 MB/s ingest, 32 MB burst). Retention 30d. Anonymous reporting disabled.
- **Vector 0.50.0** installé via .deb direct (timber.io repo URL plus fonctionnel - fetched `/vector/0.50.0/vector_0.50.0-1_amd64.deb`). Config minimal : source journald → transform remap (add host/service labels) → sink Loki HTTP `http://127.0.0.1:3100`. Vector user ajouté au groupe `systemd-journal`.
- **Datasource Loki dans Grafana LXC 108** via provisioning yaml (`/etc/grafana/provisioning/datasources/loki.yaml`). Pointer vers `http://192.168.1.242:3100`. Persist across Grafana restarts.
- **Pipeline end-to-end validé** : journald nsm-logs → Vector → Loki → query `{source="journald"}` retourne logs structurés avec labels (host, service, source). 437 lignes processed en 10 min de test.

### Changed
- `docs/02-inventory.md` : ajout LXC 121 nsm-logs (Loki + Vector)
- `docs/14-security-observability.md` : Vague 1 marquée partial (Loki+Vector déployés, restent NetFlow/Syslog UCG export + Phase B Vector agents)

### Why
- Fondation centralisation logs avant Wazuh (vague 2). Loki léger (~1 GB RAM) fait office de hub pour : journald de tous LXC/VM (phase B), apps Coolify stdout, Cowrie cowrie.json, futurs UCG syslog/NetFlow, webhooks Sentry/PostHog (archive long-terme).
- Stack hybride choisi (Loki + Wazuh) : ops logs vs sécu events séparés, audiences/rétentions différentes, single Grafana pane of glass.
- Vector comme agent universel future-proof : single binary à déployer partout, ship vers n'importe quel backend, single config syntax à apprendre.

### Lessons learned
- **Loki APT package = `loki` mais binaire pas dans PATH avant 1er apt install - Grafana APT repo doit être ajouté correctement** (gpg key + signed-by). Une fois ajouté, `apt install loki` setup le user `loki` (uid 102, gid 65534=nogroup) + systemd unit + démarre.
- **Vector apt repo `repositories.timber.io` n'est plus accessible** depuis le rachat par Datadog. Solution : direct `.deb` download depuis `https://packages.timber.io/vector/<version>/vector_<version>-1_amd64.deb` puis `dpkg -i`.
- **Loki "Pattern Ingester not ready"** au démarrage = wait ~15-45s avant que `/ready` retourne 200. Vector healthcheck va fail si lancé immédiatement après → retry après warmup OK.
- **Loki API : `query` (instant) vs `query_range`** - pour log queries (text), il FAUT `query_range` avec start/end nanoseconds, sinon 400 Bad Request. `query` est pour metric queries uniquement.
- **chown `loki:loki` ne marche pas** - le user loki a primary gid 65534=nogroup. Utiliser `chown -R loki:nogroup /var/lib/loki`.
- **Dupliquer une section YAML (`limits_config`)** dans le config Loki = parse error silencieux puis service stuck en "activating". Toujours merger dans la section existante.

---

## [2026-05-06] - Vague 3 sécu : Cowrie SSH honeypot LXC 120 + UCG IDS/IPS activés

### Added
- **LXC 120 `honeypot`** : Debian 13 unprivileged, 1 vCPU / 512 MB RAM / 8 GB disk local-lvm, IP DHCP `192.168.1.158`. Tags `honeypot;custom`.
- **Cowrie** (HEAD `git clone --depth=1`, version `0.1.dev1+g23fcef400`) installé en venv `/home/cowrie/cowrie/cowrie-env/`. Hostname décoy `svr04`. Listen `tcp:2222:interface=0.0.0.0`. Fake shell émulation, login accepté avec n'importe quel password.
- **systemd unit** `/etc/systemd/system/cowrie.service` (Type=simple, twistd -n cowrie sous user `cowrie`, Restart=on-failure). Enabled + auto-restart on crash.
- **iptables NAT redirect 22→2222** actif sur LXC 120 (persist via `iptables-persistent`, save dans `/etc/iptables/rules.v4`) → SSH externe sur `192.168.1.158:22` hit Cowrie au lieu de l'admin sshd.
- **Admin sshd LXC 120 désactivé** (`systemctl disable --now ssh.service ssh.socket`) → réduit attack surface du honeypot. Admin via `pct exec` depuis PVE uniquement.
- **UCG Ultra CyberSecure** activé : Intrusion Prevention ON (Suricata signatures à jour), Region Blocking pour countries non-pertinents, built-in Honeypot actif sur `192.168.1.2` (low-interaction, complémentaire de Cowrie).

### Changed
- `docs/02-inventory.md` : ajout LXC 120 honeypot
- `docs/14-security-observability.md` : Vague 3 marquée partial (UCG honeypot + Cowrie déployés ; OpenCanary + CanaryTokens + iptables redirect restent)
- `CHANGELOG` : reliquats vague 1 (NSM collector LXC) ajoutés

### Why
- Premier pas concret du stream cybersécu (passion du user, voir `docs/14-security-observability.md`).
- Cowrie = SSH honeypot avec shell émulation riche → permet d'apprendre les TTP des attaquants en LAN-only first, exposition publique optionnelle plus tard.
- UCG IDS/IPS = ROI immédiat (déjà inclus dans le hardware, juste un toggle).

### Lessons learned
- **Cowrie modern repo (HEAD)** n'a plus de script `bin/cowrie` standalone - install en pip editable (`pip install -e .`) pour que le plugin twistd soit découvert.
- **`twistd -n` ne respecte pas `--pidfile`** quand placé après le subcommand `cowrie`. Soit le mettre AVANT le subcommand, soit drop (en `-n` nodaemon le pidfile est inutile de toute façon).
- **UCG CyberSecure Enhanced** (signatures Proofpoint/Cloudflare premium) est **payant**. Le base IDS/IPS, Region Blocking, Network Scanners, Honeypot built-in restent gratuits → couvre 80% du value pour 0€.
- **UCG Ultra a un honeypot built-in low-interaction** sur l'IP `.2` du subnet par défaut. Activé par défaut. Détecte scans/connections. Cowrie LXC 120 est complémentaire (interaction riche pour SSH spécifiquement).
- **iptables NAT PREROUTING ne s'applique pas au loopback** - un test `ssh -p 22 root@127.0.0.1` depuis dans le LXC retourne "connection refused" malgré la règle. Pour tester un redirect 22→2222 il faut hit l'IP externe (`192.168.1.158`) depuis un autre host. PREROUTING ne touche que les paquets qui arrivent sur une interface réseau.
- **`systemctl disable ssh`** sur Debian 13 ne suffit pas - il faut aussi `disable ssh.socket` (socket activation). Sinon sshd se relance à la 1ère connexion.
- **iptables-persistent** sur Debian 13 = `apt install iptables-persistent`, save via `netfilter-persistent save` → `/etc/iptables/rules.v4`. Restore auto au boot.

---

## [2026-05-06] - Migration prod portfolio example.com + hardening + 3 runbooks

### Added
- **Cloudflare Tunnel `hetzner-prod`** sur `hetzner-shared-1` (cloudflared docker via Coolify Terminal, `--network host`, token en env-file `/etc/cloudflared/.env` mode 600). Public Hostnames : `prod-test.example.com` (validation), puis `example.com` + `www.example.com` (prod) → tous routent vers `localhost:80` (coolify-proxy Hetzner).
- **App Coolify `my-portfolio` sur server `hetzner-shared-1`** (en plus du déploiement test sur localhost). FQDN initial `http://prod-test.example.com`, étendu à `http://example.com` + `http://www.example.com` après validation. TLS terminé par CF Edge (Universal SSL).
- **DNS Cloudflare zone `example.com`** : records `example.com` (A) et `www` (CNAME) flippés depuis Vercel vers le tunnel CF (CNAME flattening au apex). Vercel reste actif 7 jours en fallback.
- **Cloudflare Access** sur `coolify.home.example.com` (Zero Trust → Applications → Self-hosted) :
  - App `coolify` : path `/*`, policy Allow Email OTP (admin@example.com), session 24h
  - App `coolify-webhooks-bypass` : path `/webhooks/*`, policy **Bypass** Everyone (sinon GitHub se prend l'auth → webhook fail). Path-specificity rule fait gagner `/webhooks/*` sur `/*`.
- **2FA Coolify admin** activé (Profile → Two-Factor Authentication, recovery codes dans Bitwarden).
- **Backup `.env` Coolify** dans Bitwarden Secure Note (`Coolify .env (VM 300) - 2026-05-06`).
- **Runbook `runbooks/deploy-perso-app.md`** - process complet pour déployer une app perso sur Coolify localhost (configure router LXC 103, créer app Coolify, healthcheck values, pièges connus).
- **Runbook `runbooks/onboard-client.md`** - checklist onboarding nouveau client (tier mutualized vs dedicated, CF Tunnel ingress, apps dev+prod, Uptime Kuma, doc interne hors-repo, offboarding).
- **Runbook `runbooks/promote-staging-to-prod.md`** - workflow LAN-first → Hetzner avec aval manuel : 2 apps Coolify par projet (dev `localhost` auto-deploy ON, prod `hetzner-shared-1` auto-deploy OFF), process push → review LAN → click Deploy prod.

### Changed
- `docs/02-inventory.md`, `docs/06-services.md`, `docs/11-coolify.md` : entries pour `prod-test.example.com`, `example.com`, `www.example.com` côté Hetzner. Phase 2 (Coolify) marquée done dans roadmap.

### Why
- Le portfolio example.com était hébergé sur Vercel. Le user voulait reprendre le contrôle de l'infra et établir le pattern qu'il appliquera ensuite aux sites clients (auto-deploy, monitoring, backups, scaling).
- `example.com` = "serious / business face" → choix Hetzner + CF Tunnel (architecture B confirmée, doc 11-coolify.md). Pas de risque d'impact image business si la box maison tombe.
- CF Access sur Coolify dashboard = défense en profondeur - devant l'auth Coolify own (login + 2FA), une 2e couche Email OTP sur l'edge CF. Brute force impossible avant identification email.

### Lessons learned
- **Coolify v4 auto-injecte `PORT=3000` à runtime** pour les containers d'apps (default Node-style). Ça override le `ENV PORT=...` du Dockerfile via le `${PORT}` du CMD. Soit aligner le port Coolify "Ports Exposes" sur 3000, soit set `PORT=<autre>` en env Coolify pour override.
- **`python:3.12-slim` n'inclut ni `curl` ni `wget`** (contrairement à alpine qui a busybox wget). Healthcheck Coolify HTTP requiert l'un des deux → patch Dockerfile pour ajouter `curl` dans `apt-get install`.
- **`docker restart` ne re-lit pas `--env-file`** - l'env est figé à la création du container. Pour appliquer un nouveau `.env`, il faut `docker rm -f` + `docker run -d` (pas restart).
- **Healthcheck `Host=localhost` foire sur images alpine** (résout en `::1` IPv6, mais l'app bind sur `0.0.0.0` IPv4 only → connection refused). Toujours utiliser `Host=127.0.0.1`.
- **Coolify-proxy ajoute auto un middleware `redirect-to-https` sur l'http-0 router** quand l'app a été créée d'origine en `https://`. Même si on change le FQDN en `http://` après, les labels persistent dans la DB (`custom_labels` base64). Workaround : 2 services Traefik LXC 103 (`coolify-apps-https` + `coolify-apps-http`), router de chaque app pointe vers le service adapté à son pattern de labels.
- **TUNNEL_TOKEN doit être préfixé `TUNNEL_TOKEN=` dans le env-file** - un `echo "<token>" > .env` (sans préfixe) fait planter cloudflared avec "requires the ID or name of the tunnel".
- **CF Access path-specificity** : un policy Bypass sur `coolify.home.example.com/webhooks/*` (path plus spécifique) gagne sur le policy Allow Email OTP de `coolify.home.example.com/*` (path générique). Pas besoin de chained rules dans la même app.
- **Coolify "Cloudflare Tunnel" feature dans Server settings** ne tunnel QUE le SSH du serveur (pour pas avoir d'IP publique pour management). Pour le trafic HTTP des apps, c'est indépendant - config dans CF Dashboard via Public Hostnames du tunnel + cloudflared docker manuel sur le serveur (ou Coolify Manual mode).

---

## [2026-05-05] - Migration portfolio Vercel → self-host (test LAN OK)

### Added
- **VPS Hetzner `hetzner-shared-1`** : Cloud CX 23 (2 vCPU / 4 GB / 40 GB), Falkenstein FSN1, Ubuntu 24.04 LTS, IP `203.0.113.10`, ~4,79 €/mois. Provisionné via Coolify (API Hetzner) le 2026-05-05. Destiné à mutualiser portfolio example.com + premiers sites clients via Cloudflare Tunnel.
- **Cloudflare Tunnel `homelab-coolify`** sur VM 300 (cloudflared docker, `--network host`, token en env-file `/etc/cloudflared/.env` mode 600). Expose `coolify.home.example.com/webhooks/*` + `/app/*` + `/apps/*` publiquement (path-filtered, le reste de Coolify reste invisible internet).
- **GitHub App Coolify** (id `<GITHUB_APP_ID>`, install id `<INSTALL_ID>`) sur `youruser/portfolio`. Webhook délivré via tunnel CF. Auto-deploy sur push `main`.
- **App Coolify `my-portfolio`** sur server `localhost` (VM 300), FQDN `http://test.home.example.com`, base directory `/frontend`, build pack Dockerfile (Next.js 16 standalone, Node 22 alpine). Build OK : 32 routes pré-rendues, image ~26 MB context.
- **Pattern `coolify-apps`** : nouveau fichier `configs/traefik/coolify-apps.yml` qui forward `*.home.example.com` LAN-only des apps Coolify via HTTPS interne (`serversTransport: insecure`, cert self-signed côté coolify-proxy). TLS terminé à LXC 103 avec wildcard cert.
- **Repo `youruser/portfolio`** : commit `8f16b2f` - `Dockerfile` multi-stage Next.js standalone + `output: "standalone"` dans `next.config.ts` + retrait de `@vercel/analytics` et `@vercel/speed-insights` (no-op hors Vercel) + retrait de `va.vercel-scripts.com` du CSP.

### Changed
- `instance_settings.fqdn` dans Coolify DB : `NULL` → `https://coolify.home.example.com` (sans cette valeur, l'UI bloquait la création des GitHub Apps avec "Please select a webhook endpoint")
- `applications.fqdn` (id=1, my-portfolio) : `https://test.home.example.com` → `http://test.home.example.com` pour empêcher coolify-proxy de tenter Let's Encrypt HTTP-01 (impossible en LAN-only)
- `docs/02-inventory.md` : nouvelle section "VPS distants" avec Hetzner CX23. VM 300 mention le container cloudflared.
- `docs/06-services.md` : 19 routes (au lieu de 18). Nouvelle section "Exceptions publiques (CF Tunnel)" listant les paths exposés.

### Why
- L'utilisateur veut migrer son portfolio `example.com` de Vercel vers self-host pour reprendre le contrôle de l'infra et préparer le pattern qu'il appliquera ensuite aux sites clients.
- Architecture B confirmée : projets perso → localhost (VM 300, gratuit), projets sérieux/clients → Hetzner mutualisé (~5€/mois jusqu'à saturation).
- `home.example.com` reste **LAN-first par défaut** mais accepte des **exceptions publiques** via CF Tunnel pour les chemins qui en ont besoin (webhooks). Choix de domaine cohérent avec la sémantique homelab.

### Lessons learned
- **Coolify v4 ne supporte PAS le polling natif** pour les sources Git (vérifié docs officiels). Pour de l'auto-deploy il FAUT que l'instance Coolify soit publiquement joignable d'une manière ou d'une autre. CF Tunnel avec path filter strict (uniquement `/webhooks/*`) est la solution future-proof. (Source : `coolify.io/docs/applications/ci-cd/github/setup-app`)
- **Coolify FQDN bloque la registration GitHub App** - sans `instance_settings.fqdn` configuré, l'UI ne propose pas de webhook endpoint. Set via UI (Settings → Configuration) ou direct DB.
- **CF Tunnel "Path" filter accepte `webhooks/*` sans slash devant**. L'affichage UI concatène `<host><path>` sans slash visuel (cosmétique, pas un bug fonctionnel).
- **Coolify-proxy applique auto un middleware `redirect-to-https`** sur l'entrypoint :80 du container, même si l'app FQDN est en `http://`. Bypasser via :443 + `serversTransport: insecure` côté Traefik LXC 103 (wildcard cert valide en frontal, self-signed accepté en interne).
- **Image Ubuntu cloud `noble` n'inclut PAS `qemu-guest-agent`** (déjà documenté dans le runbook coolify-install).
- **Next.js 16 a renommé `middleware.ts` → `proxy.ts`**. Les blacklists d'User-Agent (`curl`, `wget`, etc.) peuvent bloquer les healthchecks Coolify si elles ne whitelistent pas l'UA interne.

---

## [2026-05-05] - Coolify VM 300 provisionnée + exposée via Traefik

### Added
- **VM 300 `coolify`** : Ubuntu 24.04 LTS cloud, 4 vCPU / 8 GB RAM / 80 GB sur usbssd, IP `192.168.1.252` (Fixed UCG, MAC `02:00:00:00:00:1d`), OVMF + q35, vga `std` + serial0 socket
- **Coolify 4.0.0** installé (stack docker : `coolify` + `coolify-db` Postgres 15 + `coolify-redis` 7 + `coolify-realtime` Soketi)
- Route Traefik `https://coolify.home.example.com → http://192.168.1.252:8000` (router `coolify` dans `admin.yml`)
- Route Traefik **WebSocket** `https://coolify.home.example.com/app/* + /apps/* → http://192.168.1.252:6001` (router `coolify-ws` pour Soketi realtime)
- Variables `APP_URL` + `PUSHER_HOST/PORT/SCHEME` ajoutées dans `/data/coolify/source/.env` pour que le JS client tape la bonne URL WS

### Changed
- `docs/02-inventory.md` : VM 300 quitte la section "VMs planifiées" pour rejoindre les VMs actives. Allocation RAM totale passe à ~30 GB (marge ~2 GB ⚠ tendu). Disk usbssd passe à ~660 GB alloué (220 GB libre).
- `docs/06-services.md` : 18 routes (au lieu de 17), section détail Coolify ajoutée avec note sur le routing WebSocket
- `runbooks/coolify-install.md` : ajout des étapes manquantes lors de la 2ème tentative - MAC explicite, quote des tags, install qemu-guest-agent, qm rescan en cas de timeout resize, configuration Traefik 2-routers + vars Pusher

### Lessons learned
- **MAC explicite obligatoire** dans `qm create --net0 virtio=<MAC>,bridge=vmbr0` pour matcher une réservation DHCP côté UCG. Sans ça, PVE génère une MAC aléatoire.
- `--tags coolify;custom` doit être quoté (`"coolify;custom"`) sinon bash interprète le `;` comme séparateur.
- L'image Ubuntu cloud `noble` n'inclut **pas** `qemu-guest-agent` malgré ce qu'on imagine - l'installer post-boot.
- `qm resize` peut timeout sur disque RAW : le fichier est OK, mais le metadata Proxmox reste désynchronisé. `qm rescan --vmid <ID>` répare.
- Coolify v4 utilise Soketi (compat Pusher) sur :6001. Pour exposer via reverse proxy HTTPS sans cassure de l'UI : 2 routers (général + `/app/`+`/apps/` avec slashes finaux obligatoires) + vars `PUSHER_HOST/PORT/SCHEME` dans `.env`. Sans les vars, le JS client tape la mauvaise URL → warning « Cannot connect to real-time service ».
- Traefik `PathPrefix` fait du byte-prefix, pas du segment. `PathPrefix(/app)` matche aussi `/applications`. Toujours utiliser le slash final si c'est un segment qu'on veut isoler.

### À venir (moyen terme)
- Phase 3 : 1er VPS Hetzner provisionné via Coolify, 1er site client onboardé
- Phase 4 : backups off-site Backblaze B2 (~6€/mois)
- Activation Traefik forward-auth via Authentik (Phase 5)
- Phase 5 : VLANs sur UCG Ultra (mgmt / IoT / users / DMZ)

---

## [2026-05-05] - Import DHCP UCG Ultra + diagramme draw.io réseau

### Added
- `docs/assets/network-diagram.drawio` - diagramme draw.io importable : topologie physique complète avec câbles, zones WiFi Deco X55, tous les LXC/VMs Proxmox, et les 32 appareils du réseau
- `docs/13-network-diagram.md` - section topologie physique + référence au fichier draw.io

### Changed
- `docs/03-network.md` :
  - **Correction majeure** : le DHCP est servi par le **UCG Ultra** (pas la box FAI)
  - Ajout topologie physique (double NAT Bbox Lite → UCG Ultra → LAN)
  - Table DHCP complète avec les 32 appareils du réseau (export UCG Ultra 2026-05-05)
  - Catégorisation : Proxmox, réseau mesh, appareils perso, gaming, IoT, imprimantes
- `docs/02-inventory.md` :
  - Coolify VM 300 : IP réelle `192.168.1.252` (Fixed, MAC `02:00:00:00:00:1d`) - pas `192.168.1.150`
  - Frigate LXC 101 : IP confirmée `192.168.1.80` (DHCP dynamique)
  - Ajout note ⚠️ sur LXC/VM inconnu `ubuntu` (MAC `02:00:00:00:00:1a`, IP `192.168.1.86`)



## [2026-05-05] - Documentation initiale + intégration plan

### Added
- Structure de doc complète (`docs/01-10-*.md`)
- `docs/11-coolify.md` - architecture Coolify self-hosted + projets clients Hetzner
- Runbooks (`add-new-service`, `recover-vm`, `proxmox-update`, `renew-certs`, `create-lxc`, `coolify-install`)
- Configurations Traefik versionnées dans `configs/traefik/`
- README top-level avec quick links et TL;DR
- `.gitignore` + `SECRETS.example.md`
- `.md` - règles strictes commits/push + workflow tracking-friendly
- Roadmap Phases 0 → 6 alignée sur l'état réel (Phase 1 done, Phase 2 in progress)

### Changed
- `docs/02-inventory.md` : IPs précises VM 102 (192.168.1.128), LXC 110 (175) + section VMs planifiées (VM 300 Coolify)
- `docs/04-storage.md` : warning explicite "pool LVM-thin sur-provisionné 321%" - cause probable crash HAOS
- `docs/05-reverse-proxy.md` : compte Let's Encrypt account ID, path exact `cloudflare.env`, systemd override
- `docs/08-disaster-recovery.md` : récit complet du crash HAOS (trigger `qm stop` pendant ACPI timeout, triple copie backup)
- `docs/09-hardening.md` : 2 anti-patterns ajoutés (pool LVM, HDD Hitachi 35846h)
- `docs/10-roadmap.md` : refondu avec phases réelles incluant Coolify + Hetzner VPS clients

### Lessons learned (consolidées)
- Snapshots HAOS internes nécessaires en plus du vzdump PVE
- testdisk + e2fsck peuvent récupérer un FS sans restore complet
- Pool LVM-thin sur-provisionné = risque de corruption si saturation ; ZFS mirror prévu Phase 5
- Image Ubuntu cloud sur Proxmox : utiliser `vga: std` (pas `serial0`) pour que cloud-init bootstrap correctement

---

## [2026-05-04] - HAOS recovery

### Fixed
- **Crash HAOS (VM 102)** : table de partitions corrompue récupérée via `testdisk` puis `e2fsck -y` sur la partition data. **Aucune perte de data**.
- Snapshots HAOS internes (`/var/lib/vz/dump/haos-internal-backups/`) ont permis de revérifier l'intégrité config.

### Lessons learned
- Les snapshots HAOS internes ne suffisent pas pour récupérer un FS corrompu - vzdump du PVE est essentiel.
- `testdisk` + `e2fsck` peuvent récupérer un FS sans restore complet (gain de temps).

---

## [2026-05-02 → 05-04] - Migration NPM → Traefik

### Added
- LXC 103 (Traefik v3) déployé via community-script
- Wildcard cert Let's Encrypt `*.home.example.com` via DNS-01 Cloudflare
- 17 routes Traefik dans `/etc/traefik/conf.d/` (admin/data/home/media)
- AdGuard rewrite wildcard `*.home.example.com → 192.168.1.165`

### Changed
- LXC 110 (Nginx Proxy Manager) **stopped** (sera archivé après période de validation)
- Toutes les routes HTTPS internes passent désormais par Traefik

### Removed
- Certs HTTP-01 individuels (par-host) du NPM

### Why
- Wildcard cert (DNS-01) > certs par-host (HTTP-01) :
  - Pas besoin d'ouvrir 80/443 internet pour le challenge
  - Un seul cert à renouveler
  - Ajout d'un nouveau service = juste éditer un YAML, pas de challenge ACME
- File provider Traefik permet de versionner les routes dans Git

---

## Format des entrées futures

Quand tu ajoutes une entrée, classer en :
- **Added** : nouveaux services, configs, infrastructure
- **Changed** : modifications de comportement / config existante
- **Deprecated** : services en fin de vie (mais encore présents)
- **Removed** : services supprimés
- **Fixed** : bugs résolus, incidents
- **Security** : changements liés à la sécurité

Inclure si pertinent :
- **Why** : motivation derrière le changement
- **Lessons learned** : ce qu'on retire d'un incident
- **Links** : PR, issues, runbook utilisé
