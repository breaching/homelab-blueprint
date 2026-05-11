# 10 - Roadmap

> Phases successives. Une phase = un set de chantiers cohérents qu'on termine avant de passer à la suivante.

## ✅ Phase 0 - Foundation (terminée)

- Single-node Proxmox déployé
- 11 LXC + 2 VMs en service
- Storage tiered (SSD système / HDD data froide / SSD USB chaud / SSD USB backup)
- vzdump quotidien fonctionnel

## ✅ Phase 1 - Stabilisation (DONE)

### 1.1 HAOS Recovery (4-5 mai 2026) ✅

- VM 102 HAOS 17 a crashé suite à `qm stop` forcé pendant timeout ACPI shutdown
- Recovery via `testdisk` (récupération GPT primaire) + `e2fsck` (réparation ext4 hassos-data)
- 3 backups HA récupérés (Apr 30, May 1, May 2) + ESPHome + Matter Server
- Triple copie sécurité : `/root/haos-recovery/backups/`, `/mnt/backup-ssd/haos-recovery/`, `/mnt/usbssd/data/files/BACKUP NAS/HAOS/`
- Nouvelle VM 102 HAOS 17.2 créée via community-script + restore .tar via UI HAOS
- Voir [docs/08-disaster-recovery.md](08-disaster-recovery.md) pour détails

### 1.2 LXC 114 Servarr Cleanup ✅

- Disque : 26G/34G (80%) → 18G/34G (55%), -8 GB
- Pool LVM : 58.84% → 48.83%
- Suppressions images : `jellyseerr:latest`, `jellyseerr:develop`, `jellyfin lscr.io`, `komga`, `readarr`
- Log rotation Docker : `/etc/docker/daemon.json` max-size 10m max-file 3
- Truncate logs gluetun (1.5 GB)
- Services VPN-dépendants stoppés (gluetun, qbittorrent, nzbget, prowlarr, tdarr - `docker update --restart=no`)
- `pct fstrim 114` → 15.5 GiB physique libérés

### 1.3 Migration NPM → Traefik ✅

- Cloudflare API token créé (`Zone:DNS:Edit + Zone:Read` sur `home.example.com`), chmod 600
- Traefik configuré avec entryPoints web/websecure + DNS-01 Cloudflare resolver
- Wildcard cert `*.home.example.com` obtenu (LE R12, validité 90j, auto-renew)
- 17 routes migrées dans 4 fichiers `conf.d/`
- Switch DNS atomique dans AdGuard
- NPM stoppé, backup conf : `/root/traefik-backup-YYYYMMDD/`

### 1.4 Documentation initiale ✅ (5 mai 2026)

- Repo `youruser/homelab-blueprint` (privé)
- 11 docs + 6 runbooks + configs Traefik versionnées
- .md avec règles strictes commits/push

## 🚧 Phase 1 - Reliquats (basse priorité)

| # | Tâche | Effort | État |
|---|-------|--------|------|
| 1.5 | Cleanup vzdump orphelins (~19 GB dans `/mnt/pve/Hitachi/dump/`) | 15 min | ⏸️ |
| 1.6 | Cleanup volumes LVM orphelins (VM 999 + ancienne 102) | 10 min | ⏸️ |
| 1.7 | QEMU agent fix VM 117 (interface Docker bridge buggée - pas critique) | 20 min | ⏸️ |
| 1.8 | Subscription nag Proxmox (patch UI) | 5 min | ⏸️ |
| 1.9 | Destroy LXC 110 NPM (attendre 1 semaine post-migration → ~12 mai 2026) | 2 min | 📅 daté |
| 1.10 | Notifications Telegram pour cert renewal failures Traefik | 30 min | ⏸️ |
| 1.11 | Cleanup hosts Windows (retirer lignes test `192.168.1.165 ...`) | 2 min | ⏸️ |
| 1.12 | IPs statiques pour LXC 101 (frigate) + VM 102 (HAOS) | 15 min | ⏸️ |
| 1.13 | `startup: order=N` cohérent sur tous les CT critiques | 15 min | ⏸️ |
| 1.14 | Restore-test mensuel automatisé | 1h | ⏸️ |

## 🚧 Phase 2 - Coolify install (EN COURS)

> Doc dédiée : [docs/11-coolify.md](11-coolify.md) | Runbook : [runbooks/coolify-install.md](../runbooks/coolify-install.md)

### Décisions prises ✅

- **Architecture B** : Traefik LXC 103 (LAN home.example.com) + Coolify Traefik interne (sites clients via Cloudflare Tunnel)
- **OS** : Ubuntu 24.04 LTS cloud image
- **Resources** : 4 vCPU / 8 GB RAM / 80 GB disk
- **Storage** : `usbssd` (T7 Shield)
- **Méthode install** : manuelle

### Issue rencontrée (5 mai 2026) ❌

- VM 300 créée (disque 80 G, SSH keys, cloud-init configuré)
- Boot OK mais cloud-init n'a jamais répondu (pas d'IPv4 DHCP, qga timeout)
- Cause : `vga: serial0` empêche cloud-init Ubuntu d'écrire sur tty1
- VM 300 supprimée pour repartir propre

### À faire

- [ ] Recréer VM 300 avec `vga: std` (pas `serial0`) - cf. runbook
- [ ] Re-importer image Ubuntu 24.04 cloud
- [ ] Cloud-init avec SSH keys
- [ ] Démarrer + valider via UI Proxmox console (noVNC)
- [ ] SSH puis `curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash`
- [ ] Route Traefik `coolify.home.example.com` → `<IP_COOLIFY>:8000`
- [ ] Setup admin Coolify via UI

**Critère sortie** : UI Coolify accessible via `https://coolify.home.example.com`, 1er déploiement test OK.

## 🔮 Phase 3 - Premiers déploiements

| Projet | Domaine | Type | Notes |
|--------|---------|------|-------|
| Mealie + Postgres (recettes perso) | `mealie.home.example.com` | LAN | Premier test, app stateful |
| Site vitrine client A | `clientA.com` | Public via CF Tunnel | Premier client onboardé |
| Site vitrine client B | `clientB.fr` | Public via CF Tunnel | Idem |

### Tâches

- [ ] Tester Mealie sur Coolify local (LAN-only)
- [ ] Provisionner 1er VPS Hetzner via Coolify (intégration native)
- [ ] Setup Cloudflare Tunnel pour exposition publique sans port forward Freebox
- [ ] Onboarder le 1er client : doc workflow `runbooks/onboard-client.md`
- [ ] Monitoring : monitor Uptime Kuma par domaine client

**Critère sortie** : 1 site client en prod accessible via CF Tunnel, 99% uptime sur 30j.

## 🔮 Phase 4 - Backups off-site (3-2-1 complet)

**Objectif** : survivre à un incendie / vol du host.

- [ ] Choix solution : `rclone` + Backblaze B2 (~6€/mois pour 1 TB)
- [ ] Encrypt avec `age` ou `gpg` (clés stockées hors-cloud)
- [ ] Sync delta quotidien `/mnt/pve/Hitachi/dump/*.zst` → B2 chiffré
- [ ] Sync séparé pour la bibliothèque Immich (`/mnt/pve/Hitachi/immich_photos/`)
- [ ] Sync DB clients depuis VPS Hetzner → B2
- [ ] Rotation : 7 jours / 4 semaines / 12 mois
- [ ] Test restore mensuel documenté + exécuté
- [ ] Coût mensuel + budget annuel documenté

**Critère sortie** : si le host brûle demain, restore complet possible en < 24h.

## 🔮 Phase 5 - Hardening & Monitoring

**Objectif** : limiter blast radius + visibilité totale.

### Réseau

- [ ] Switch managé (UniFi USW-Lite-8-PoE ou équivalent)
- [ ] VLANs :
  - VLAN 10 `mgmt` (PVE, AdGuard, Traefik, Coolify)
  - VLAN 20 `services` (autres LXC/VMs lab)
  - VLAN 30 `iot` (HAOS + appareils IoT)
  - VLAN 40 `users` (laptops, mobiles, TV)
  - VLAN 50 `dmz-clients` (apps clients hors-Hetzner si jamais on en héberge en local)
- [ ] Firewall PVE Datacenter actif + rules per-CT

### Storage

- [ ] **ZFS mirror** sur 2 SSD (remplacer LVM-thin sur-provisionné - voir [docs/04-storage.md](04-storage.md))

### Monitoring

- [ ] Prometheus + node_exporter sur tous les LXC/VMs + host
- [ ] Loki + Promtail pour collecte logs
- [ ] Dashboards Grafana standardisés :
  - [ ] Host PVE (CPU, RAM, disk I/O, load)
  - [ ] SMART par device
  - [ ] Traefik (req/s, codes HTTP, latency)
  - [ ] Coolify (deployments, errors, resources)
  - [ ] HAOS (sensor count, automation count)
- [ ] Alerting Uptime Kuma → Telegram/Discord
- [ ] AdGuard secondary → HA DNS basique
- [ ] cron `smartctl` + log InfluxDB → alerte si dégradation

### IdP / SSO

- [ ] Authentik forward-auth Traefik sur :
  - [ ] `traefik.home.example.com`
  - [ ] `dns.home.example.com`
  - [ ] `coolify.home.example.com`
  - [ ] `pve.home.example.com` (2nd layer)
  - [ ] tous les *arr
- [ ] 2FA TOTP forcé sur compte admin Authentik
- [ ] Comptes utilisateurs séparés (1 par membre famille)

**Critère sortie** : un LXC compromis ne peut pas scanner les IoT, et toutes les UI admin sont derrière Authentik+2FA.

## 🎯 Stream parallèle - Security Observability (long-terme)

**Objectif passion cybersécu** - voir [`docs/14-security-observability.md`](14-security-observability.md) pour le plan complet en 4 vagues :

1. Visibility réseau (UCG IDS/IPS + NetFlow/Syslog + ntopng)
2. HIDS endpoint (Wazuh manager + agents sur tous les LXC/VM)
3. Honeypots (Cowrie SSH + OpenCanary multi-protocol + CanaryTokens)
4. Threat intel + SIEM (MISP/OpenCTI + Loki/Grafana + active deception)

À pacer en sessions courtes (1-2h) en parallèle des Phases 5-6. Pré-requis recommandé : VLANs UCG (Phase 5) pour segmenter avant d'attacher les sondes.

## 🔮 Phase 6 - IaC & Cluster HA

**Objectif** : reproductibilité + élimination du SPOF host.

### Documentation as Code

- [ ] Ansible playbooks pour reproduire le homelab
- [ ] Inventory Ansible alimenté par les fichiers de ce repo
- [ ] CI/CD : pre-commit hook qui valide les YAML Traefik avant push

### High Availability

- [ ] 2nd node Proxmox (mini-PC type N100, ≥ 32 GB RAM)
- [ ] Cluster 2-node + qdevice (Raspberry Pi)
- [ ] Réplication LVM-thin / ZFS pour CT critiques
- [ ] PBS (Proxmox Backup Server) sur 2nd node ou autre machine
- [ ] HA group : AdGuard + Traefik + Authentik + Coolify
- [ ] Failover testé : éteindre node primaire 1h → tout reste up

**Critère sortie** : éteindre le node primaire 1h ne casse rien d'observable.

## Backlog non-priorisé

- [ ] WireGuard / Tailscale pour accès distant (probablement avant Phase 2)
- [ ] Documentation des intégrations HAOS (devices, automations)
- [ ] Migration HDD Hitachi → 2× SSD ZFS mirror (fin de vie HDD prévisible - 35846h power-on)
- [ ] Frigate avec Coral.ai → tester upgrade vers RKNN ou autre
- [ ] PostgreSQL central (Patroni ?) au lieu d'embedded par service
- [ ] PXE boot pour ré-installer les LXC plus rapidement
- [ ] Gitea/Forgejo en LXC pour mirror ce repo en local

## Métriques de succès globales

| Indicateur | Aujourd'hui | Cible Phase 6 |
|------------|-------------|---------------|
| MTTR (un service down) | ~30 min | < 5 min (HA) |
| RTO (restore complet host) | ~6h | < 1h |
| RPO (perte de data max) | 24h | 1h |
| % services avec 2FA | ~10% (HAOS, PVE) | 100% |
| % logs centralisés | 0% | 100% |
| Tests restore validés | 0 | mensuel auto |
| Sites clients hébergés | 0 | 3-5 (Phase 3) |
