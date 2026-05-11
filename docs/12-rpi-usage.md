# 12 - Usages des Raspberry Pi (2× RPi 4 + 1× RPi 3B)

> Analyse générée le **2026-05-05** - à réviser en phase 5/6.
> Contexte : infra actuelle single-node PVE (i7-6700, 32 GB), roadmap phases 1→6.

---

## Matériel disponible

| Machine | RAM | USB | Notes |
|---------|-----|-----|-------|
| RPi 4 #1 | 4 ou 8 GB | USB 3.0 | Capacité PBS / WireGuard |
| RPi 4 #2 | 4 ou 8 GB | USB 3.0 | Capacité AdGuard / PXE |
| RPi 3B | 1 GB | USB 2.0 | Trop limité pour storage - parfait pour qdevice |

---

## Répartition recommandée (alignée roadmap)

| Machine | Rôle principal | Rôle secondaire | Phase roadmap |
|---------|---------------|-----------------|---------------|
| **RPi 3B** | qdevice Proxmox cluster (tiebreaker Corosync) | - | Phase 6 |
| **RPi 4 #1** | PBS (Proxmox Backup Server) + disque USB externe | - | Phase 4 |
| **RPi 4 #2** | AdGuard Home secondary (HA DNS) | WireGuard / Tailscale exit node + PXE boot server | Phase 5 + Backlog |

> ⚠️ Le RPi 3B **ne convient pas** au PBS : son USB 2.0 est un goulot d'étranglement pour les sauvegardes. L'USB 3.0 des RPi 4 est indispensable pour ce rôle.

---

## Détail par rôle

### RPi 3B - qdevice Proxmox

- **Pourquoi** : un cluster 2 nœuds Proxmox a besoin d'un quorum witness (qdevice) pour éviter le split-brain. Le RPi 3B est cité explicitement dans la Phase 6 de la roadmap.
- **Consommation** : < 3 W, toujours allumé, ressources quasi nulles.
- **Prérequis** : `corosync-qnetd` installé sur le RPi, cluster Proxmox 2 nœuds (Phase 6).

### RPi 4 #1 - PBS (Proxmox Backup Server)

- **Pourquoi** : crée un backup target off-host sans dépendre du même chassis. PBS tourne sur Debian ARM64, supporté sur RPi 4.
- **Prérequis** : disque USB 3.0 externe (≥ 1 TB recommandé), IP statique LAN.
- **Complémentarité** : s'ajoute aux vzdump quotidiens existants vers Hitachi/backup-ssd - PBS offre la déduplication + stockage incrémental.
- **Phase roadmap** : Phase 4 (backups off-site/off-host).

### RPi 4 #2 - AdGuard secondary + WireGuard + PXE

**AdGuard Home secondary (priorité haute)**
- Miroir du LXC 100 (`192.168.1.246`), failover DHCP côté Freebox.
- Si le node PVE est down → DNS LAN tient sur le RPi.
- Sync config possible via `adguardhome-sync` (outil dédié).
- Phase roadmap : Phase 5 ("AdGuard secondary → HA DNS basique").

**WireGuard / Tailscale exit node (priorité moyenne)**
- Accès distant sécurisé sans exposer le node PVE directement.
- RPi 4 chiffre du WireGuard à ~100 Mbit/s+ sans effort.
- Seul le RPi est exposé en DMZ / port-forward Freebox.
- Backlog roadmap : "WireGuard / Tailscale pour accès distant".

**PXE boot server (priorité basse)**
- `dnsmasq` + TFTP pour réinstaller rapidement des LXC/VMs sans clé USB.
- Backlog roadmap : "PXE boot pour ré-installer les LXC plus rapidement".

---

## Usages alternatifs (non-prioritaires)

- **Gitea/Forgejo** : mirror local du repo `homelab-homelab` - continuité si GitHub est down. Backlog roadmap.
- **Home Assistant dédié** : sortir le dongle Z-Wave de la VM 102 sur un Pi bare-metal (HA plus stable). À peser vs. complexité supplémentaire.
- **Nœud monitoring léger** : Prometheus node_exporter + Loki agent pour les Pi eux-mêmes (Phase 5).

---

## Ordre de déploiement suggéré

1. **RPi 4 #2 - AdGuard secondary** (dès Phase 5 - simple, haute valeur HA)
2. **RPi 4 #1 - PBS** (dès Phase 4 - remplace backup-ssd T5 comme cible off-host)
3. **RPi 4 #2 - WireGuard** (avant ou pendant Phase 3 - accès distant utile dès que des services clients tournent)
4. **RPi 3B - qdevice** (Phase 6 - nécessite le 2nd nœud Proxmox d'abord)

---

## Liens

- [docs/10-roadmap.md](10-roadmap.md) - Phase 4 (backups), Phase 5 (hardening/HA DNS), Phase 6 (cluster)
- [docs/07-backups.md](07-backups.md) - stratégie backups actuelle
- [docs/02-inventory.md](02-inventory.md) - inventaire LXC/VMs
