# 14 - Security Observability & Hardening (long-terme)

> **Status** : 🎯 Objectif passion cybersécu - multi-mois, en parallèle des Phases 1-6 du roadmap principal. À attaquer par sessions courtes (1-2h chacune) plutôt qu'un gros bloc.

## Objectif

Construire un **mini-SOC homelab** :
1. **Visibility globale** du trafic entrant/sortant (gateway + endpoints)
2. **HIDS/EDR** sur chaque LXC/VM (file integrity, log analysis, vulnerability scan)
3. **Honeypots** pour détecter scans/intrusions internes/externes
4. **Threat intel** + corrélation alerts

C'est un projet d'apprentissage autant qu'un projet infra - chaque vague approfondit Suricata, Wazuh, MITRE ATT&CK, OSINT TI, etc.

## Plan en 4 vagues (à pacer selon dispo)

### Vague 1 - Visibility réseau (1 session)

**Status partiel** : ✅ UCG IDS/IPS activé. ✅ LXC 121 `nsm-logs` (`192.168.1.242`) avec **Loki 3.7.1** (listen :3100) + **Vector 0.50.0** (ship sa propre journald → Loki). ✅ Datasource Loki ajoutée à Grafana LXC 108 via provisioning. ✅ **Phase B done** : Vector déployé sur **15 hosts** (11 LXC + 2 VMs + nsm-logs), tous shipped vers Loki.

⏳ Reste : ntopng (NetFlow visu) optionnel, UCG NetFlow IPFIX export → Vector central (Vector n'a pas de source NetFlow native, faut nfacctd/goflow2). HAOS VM 102 skip (OS spécialisé). Webhooks Sentry/PostHog → Vector HTTP source (intégrations externes).

✅ **Phase D done** (intégrations) : Cowrie JSON → Vector → Loki avec parsing query-time `| json`. UCG syslog → Vector :5140 (UDP+TCP). VM 117 DNS resolver fixé.


**Goal** : voir tout le trafic qui transite par la box, alerter sur les patterns suspects.

| Item | Outil | Effort | Ressource |
|---|---|---|---|
| IDS/IPS gateway | UniFi Threat Management (Suricata-based, déjà inclus UCG Ultra) | 5 min toggle | Gratuit (UCG) |
| DPI + Traffic ID | UniFi DPI built-in | 5 min toggle | Gratuit |
| Country blocking | UniFi Threat Management | 10 min config | Gratuit |
| Syslog export depuis UCG | UCG → LXC central | 30 min | LXC nouvelle ~512 MB RAM |
| NetFlow collector | `ntopng` ou `nfsen` ou `Akvorado` (moderne) | 1h | LXC ~1 GB RAM |
| Visualisation traffic | Grafana dashboard (réutiliser LXC 108 existant) | 30 min | Inclus |

**Pré-requis recommandé** : Phase 5 du roadmap (VLANs UCG) - pour pouvoir segmenter mgmt / IoT / users / honeypot et avoir des dashboards par segment.

### Vague 2 - Endpoint monitoring (HIDS - 2 sessions)

**Status** : ✅ **LXC 122 `wazuh`** déployé 2026-05-06 (Ubuntu 24.04, 4 vCPU / 6 GB / 30 GB rootfs sur **Hitachi HDD** - _volontairement pas local-lvm_ pour pas overprovisionner). Wazuh **4.14.5** all-in-one : manager + indexer (OpenSearch) + dashboard + filebeat. IP `192.168.1.221`. Dashboard accessible via `wazuh.home.example.com` (route Traefik avec `serversTransport: insecure`).

✅ **15 agents Wazuh 4.14.5 enrolled** (100% coverage des hosts actifs) :
| ID | Host | Type |
|----|------|------|
| 001 | pve | host PVE |
| 002-013 | adguard, frigate, traefik, influxdb, grafana, glance, excalidraw, servarr, nas-files, honeypot, nsm-logs, immich | 12 LXC |
| 014, 015 | authentik, coolify | 2 VMs |

Excl HAOS VM 102 (HassOS specialisé, pas d'apt) et NPM LXC 110 (stopped, à archiver).

⏳ Reste pour finir Vague 2 : custom rules par service (PVE, Coolify, Traefik, AdGuard, HAOS, Loki, Vector), tuning dashboards Wazuh (les defaults n'ont pas tous les widgets utiles), connecter à Telegram pour alerts critiques (en plus du dashboard).


**Goal** : surveiller chaque LXC/VM individuellement (file integrity, suspicious commands, vulnerable packages).

- **Wazuh manager** sur LXC dédiée (~2 GB RAM, 1 vCPU, 20 GB disk pour les logs)
- **Wazuh agent** déployé sur chacun des ~12 LXC/VM existants (~50 MB RAM par agent, négligeable)
- **Custom rules** par service : PVE, Coolify, Traefik, AdGuard, HAOS
- **Dashboard Wazuh** + alerting email/Discord/ntfy

Wazuh = HIDS open-source mature, compatible MITRE ATT&CK, scan de vulnérabilités CVE, file integrity monitoring (FIM), config audits. Standard de fait pour homelab/SMB.

**Watch-outs (lessons learned du déploiement initial)** :
- L'URL `packages.wazuh.com/4.10/wazuh-install.sh` installe spécifiquement la branch 4.10. L'apt repo `4.x stable` livre la dernière (actuellement 4.14.5). Risque de mismatch agent/manager → l'enrollment fail avec `Agent version must be lower or equal to manager version`. Soit utiliser `/4.14/wazuh-install.sh`, soit upgrade le manager après install pour matcher.
- Wazuh n'est **pas officiellement supporté sur Debian** - l'installer requiert `software-properties-common` (Ubuntu-specific). Toujours utiliser Ubuntu 22.04/24.04 pour le manager.
- Lors d'un `apt install wazuh-indexer=X.Y.Z-1` upgrade, l'ownership des fichiers `/usr/share/wazuh-indexer/`, `/etc/wazuh-indexer/`, `/var/log/wazuh-indexer/`, `/var/lib/wazuh-indexer/` peut se faire reset à `root:root`, ce qui fait crasher le service (entrypoint pas exec par user `wazuh-indexer`). Toujours `chown -R wazuh-indexer:wazuh-indexer` après upgrade.
- Lors d'un `apt install wazuh-dashboard=X.Y.Z-1` upgrade, l'option `-o Dpkg::Options::="--force-confold"` est nécessaire pour éviter le prompt interactif sur `/etc/wazuh-dashboard/opensearch_dashboards.yml` (configuré par l'installer initial).
- **Après upgrade `wazuh-dashboard`, le binaire `node` perd son `cap_net_bind_service`** → service crash boot avec `Error: listen EACCES: permission denied 0.0.0.0:443` (port privilégié <1024 et user `wazuh-dashboard` ≠ root). Re-applier sur les **deux** binaires (le réel + le fallback) :
  ```bash
  setcap cap_net_bind_service=+ep /usr/share/wazuh-dashboard/node/bin/node
  setcap cap_net_bind_service=+ep /usr/share/wazuh-dashboard/node/fallback/bin/node
  systemctl restart wazuh-dashboard
  ```
  Note : la première install du package via `wazuh-install.sh` setcap correctement, mais un upgrade apt remplace `node` sans préserver les caps.

### Vague 3 - Honeypots (1-2 sessions)

**Status partiel** : ✅ UCG built-in honeypot actif sur `192.168.1.2` (CyberSecure → Honeypot, low-interaction). ✅ Cowrie sur LXC 120 déployé 2026-05-06 - listen `:2222`, iptables NAT redirect 22→2222 actif (persist via iptables-persistent) → SSH externe sur `192.168.1.158:22` hit Cowrie. Admin via `pct exec` uniquement (sshd LXC désactivé pour réduire attack surface).

⏳ Reste à faire pour finir cette vague : exposition publique optionnelle (port forward Freebox ou Cloudflare Spectrum / tunnel TCP), OpenCanary multi-protocol, CanaryTokens DNS.


**Goal** : détecter les attaques *avant* qu'elles touchent les vrais services. Si quelqu'un scan ton SSH honeypot, il y a 0 chance que ce soit légit → alerte immédiate.

| Type | Outil | Quoi |
|---|---|---|
| SSH/Telnet | **Cowrie** (LXC ~512 MB) | Faux SSH avec shell émulé, log toutes les commandes attaquant |
| Multi-protocol | **OpenCanary** (LXC ~256 MB) | FTP, MySQL, RDP, SMB, HTTP, etc. - détecte les scans de port |
| Files/URLs/DNS | **CanaryTokens** (service public, zéro infra) | Token "tripwire" déclenché si quelqu'un ouvre un file ou DNS query |
| Suite complète | **T-Pot** (VM dédiée ~8 GB RAM) | 20+ honeypots intégrés + ELK stack - overkill pour homelab perso, parfait pour apprentissage threat intel |

Recommandation : démarrer Cowrie + OpenCanary + CanaryTokens. T-Pot si tu veux passer en mode "full lab" ou faire des recherches.

### Vague 4 - Threat intel + SIEM avancé (2 sessions)

**Goal** : enrichir les alertes avec du contexte (IP malveillante connue ? Hash de malware ? IOC vu dans une campagne récente ?).

- **MISP** (Malware Information Sharing Platform) ou **OpenCTI** - auto-pull de feeds publics (Abuse.ch URLhaus, Feodo, ThreatFox, AlienVault OTX)
- Intégration Wazuh ↔ MISP : auto-enrichissement des alertes IDS/HIDS avec lookup TI
- Logs centralisés via **Loki + Grafana** (plus léger qu'ELK) ou OpenSearch (Wazuh-bundled)
- **Active deception** : tokens canary dans bind mounts, DNS records honeytraps

## Budget ressources sécu (full vague 1-3)

| Composant | RAM | vCPU | Disk |
|---|---|---|---|
| NSM / NetFlow collector | 1 GB | 1 | 10 GB |
| Wazuh manager | 2 GB | 1 | 20 GB |
| Honeypot (Cowrie + OpenCanary) | 1 GB | 1 | 10 GB |
| MISP/OpenCTI (vague 4 - optionnel) | 4 GB | 2 | 40 GB |
| **Total dédié sécu (vagues 1-3)** | **4 GB** | 3 | 40 GB |
| **Total avec vague 4** | **8 GB** | 5 | 80 GB |

**Watch-out** : 32 GB RAM PVE total, déjà ~30 GB alloués (cf. [`02-inventory.md`](02-inventory.md)). Faudra :
- Soit upgrade RAM (DDR4 32→64 GB sur le HP - possible si chipset Q170 le supporte)
- Soit réduire le surcommit existant (ex: HAOS 4 GB → 2 GB suffit en pratique)
- Soit dédier un 2e node Proxmox (Phase 6) - overkill pour SMB/perso mais idéal pour scaler sécu sans toucher prod

## Compétences à acquérir / approfondir

- Suricata custom rules (syntax + threat hunting patterns)
- Wazuh rules + decoders custom + groups
- KQL / OpenSearch query DSL
- MITRE ATT&CK framework - mapping détections aux techniques
- OSINT pour curation de feeds TI
- Honeypot deception design (qu'est-ce qui rend un honeypot crédible ?)

## Ressources externes à explorer

- [Wazuh docs](https://documentation.wazuh.com)
- [T-Pot honeypot suite (Telekom Security)](https://github.com/telekom-security/tpotce)
- [Security Onion](https://securityonionsolutions.com) - distrib Linux NSM/HIDS de référence
- [MITRE ATT&CK](https://attack.mitre.org)
- [CanaryTokens](https://canarytokens.org) - gratuit, zéro infra
- [Awesome Wazuh](https://github.com/wazuh/awesome-wazuh)
- [Awesome SIEM](https://github.com/cyb3rxp/awesome-soc)

## Liens avec roadmap principal

- [Phase 5 - VLANs UCG + monitoring](10-roadmap.md) : pré-requis idéal pour Vague 1 (segmenter network) + overlap Vague 2-3
- [Phase 6 - HA / 2nd node Proxmox](10-roadmap.md) : recommandé avant Vague 4 si MISP/OpenCTI lourds
- [docs/09-hardening.md](09-hardening.md) : hardening baseline (configs, perms, secrets) - complémentaire de cette doc qui couvre observability/détection

## Quick wins indépendants (à faire dans n'importe quel ordre)

Sans attendre les vagues structurées :

- Activer UniFi IDS/IPS Threat Management sur UCG Ultra (5 min)
- Déployer 1 CanaryToken DNS dans un sous-domaine inutilisé (5 min)
- UFW + fail2ban sur VM 300 + Hetzner (P1 hardening déjà identifié)
- `unattended-upgrades` auto security updates (10 min)
- Audit log review hebdomadaire UCG (`Insights → Threat Management Events`)
