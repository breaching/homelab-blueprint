# 02 - Inventory

> Snapshot pris le **2026-05-05**. Vérité actuelle = `pct list` / `qm list` sur le node.

## Hôte Proxmox

| Item | Valeur |
|------|--------|
| Hostname | `pve` |
| Domaine FQDN | `pve.home.example.com` |
| IP mgmt | `192.168.1.90/24` |
| Bridge | `vmbr0` |
| Modèle | HP ATX recyclé |
| CPU | Intel Core i7-6700 (4c/8t, Skylake, vt-d/vt-x) |
| Chipset | Q170 |
| RAM | 32 GB DDR4 |
| GPU | NVIDIA GTX 1070 Ti (passé au LXC 114 servarr) |
| iGPU | Intel HD 530 (passé au LXC 101 frigate + LXC 106 immich) |

## VMs

| VMID | Name | OS | vCPU | RAM | Disk | IP | MAC | Onboot | Notes |
|------|------|-----|------|-----|------|----|----|--------|-------|
| 102 | `haos17-2` | Home Assistant OS 17.2 | 2 | 4 GB | 32 GB (local-lvm) | `192.168.1.128` (DHCP) | `02:00:00:00:00:01` | ✅ (order=2, up=30) | UEFI + Q35, USB Z-Wave passé via `host=1-1`. Recréée le 2026-05-04 post-crash |
| 117 | `authentik` | Debian (Authentik + Uptime Kuma) | 2 | 2 GB | 22 GB (local-lvm) | `192.168.1.181` | `02:00:00:00:00:1b` | ✅ | Co-héberge Authentik (:443) + Uptime Kuma (:9000) |
| 300 | `coolify` | Ubuntu 24.04 LTS cloud | 4 | 8 GB | 80 GB (usbssd) | `192.168.1.252` (Fixed) | `02:00:00:00:00:1d` | ✅ | OVMF + q35, vga `std` + serial0 socket. Coolify 4.0.0 + container `cloudflared-coolify` (tunnel `homelab-coolify` pour webhooks publics). Voir [docs/11-coolify.md](11-coolify.md) |

## LXC

| VMID | Name | OS | vCPU | RAM | Disk | Storage | IP | MAC | Privilégié | Onboot | Notes |
|------|------|-----|------|-----|------|---------|----|----|------------|--------|-------|
| 100 | `adguard` | Ubuntu | 1 | 512 MB | 10 GB | Hitachi | `192.168.1.246` | `02:00:00:00:00:11` | ❌ | ✅ | DNS LAN |
| 101 | `frigate` | Debian | 8 | 4 GB | 20 GB | local-lvm | `192.168.1.80` (static) | `02:00:00:00:00:14` | ⚠️ partiel | ✅ | iGPU + USB Coral + ttyUSB/ttyACM. **IP statique** depuis 2026-05-07 (`pct set 101 -net0 ...,ip=192.168.1.80/24,gw=192.168.1.1`). |
| 103 | `traefik` | Debian | 1 | 512 MB | 2 GB | local-lvm | `192.168.1.165` | `02:00:00:00:00:1c` | ❌ | ✅ | Reverse proxy |
| 106 | `immich` | Debian | 4 | ~4 GB | 32 GB + bind | local-lvm + Hitachi | `192.168.1.134` | `02:00:00:00:00:17` | ❌ | ✅ | iGPU + bind `/mnt/pve/Hitachi/immich_photos` |
| 107 | `influxdb` | Debian | 2 | 2 GB | 68 GB | usbssd (T7) | `192.168.1.94` | `02:00:00:00:00:15` | ❌ | ✅ | TSDB pour HAOS/Grafana |
| 108 | `grafana` | Debian | 1 | 512 MB | 2 GB | Hitachi | `192.168.1.85` | `02:00:00:00:00:16` | ❌ | ✅ | Dashboards |
| 111 | `glance` | Debian | 1 | 512 MB | 2 GB | local-lvm | `192.168.1.76` | `02:00:00:00:00:12` | ❌ | ✅ | Dashboard de liens |
| 113 | `excalidraw` | Debian | 2 | 3 GB | 10 GB | usbssd (T7) | `192.168.1.78` | `02:00:00:00:00:19` | ❌ | ✅ | Diagrammes |
| 114 | `servarr` | Debian | 4 | 4 GB | 34 GB + bind | local-lvm + usbssd | `192.168.1.88` | `02:00:00:00:00:18` | ❌ | ✅ | GTX 1070 Ti + `/mnt/usbssd/data` → `/data` + tun |
| 115 | `nas-files` | Ubuntu | 2 | 512 MB | 4 GB + bind | local-lvm + usbssd | `192.168.1.195` | `02:00:00:00:00:13` | ❌ | ✅ | File browser sur `/mnt/usbssd/data` |
| 120 | `honeypot` | Debian 13 | 1 | 512 MB | 8 GB | local-lvm | `192.168.1.158` (DHCP) | (DHCP) | ❌ | ✅ | **Cowrie SSH honeypot** sur :2222 (vague 3 sécu - voir [docs/14-security-observability.md](14-security-observability.md)). Admin uniquement via `pct exec` (sshd désactivé). iptables NAT redirect 22→2222 actif, persist via iptables-persistent : SSH externe sur :22 hit Cowrie. |
| 121 | `nsm-logs` | Debian 13 | 2 | 2 GB | 20 GB | local-lvm | `192.168.1.242` (DHCP) | (DHCP) | ❌ | ✅ | **Loki 3.7.1** (logs centralisés, listen :3100) + **Vector 0.50.0** (agent ship sa propre journald). Phase A vague 1 sécu - base pour Vector partout (phase B). Storage `/var/lib/loki`. Retention 30d. Datasource Grafana ajoutée. |
| 122 | `wazuh` | Ubuntu 24.04 | 4 | 6 GB | 30 GB | **Hitachi** | `192.168.1.221` (DHCP) | (DHCP) | ❌ | ✅ | **Wazuh 4.14.5** all-in-one (manager + indexer/OpenSearch + dashboard + filebeat). HIDS vague 2 sécu - voir [docs/14-security-observability.md](14-security-observability.md). Rootfs sur Hitachi (HDD) **volontairement** pour pas overprovisionner local-lvm. Dashboard `wazuh.home.example.com`. Agent enrollment :1515, data :1514. Mot de passe admin dans Bitwarden. |

### Détails passthrough

**LXC 101 (frigate)**
```
dev0: /dev/dri/renderD128,gid=104        # iGPU render
dev1: /dev/dri/card0,gid=44              # iGPU card
lxc.cgroup2.devices.allow: c 188:* rwm   # ttyUSB
lxc.cgroup2.devices.allow: c 189:* rwm   # ttyACM
lxc.mount.entry: /dev/serial/by-id ...
lxc.mount.entry: /dev/ttyUSB[01] ...     # Coral USB / autres
lxc.mount.entry: /dev/ttyACM[01] ...
```

**LXC 106 (immich)**
```
mp0: /mnt/pve/Hitachi/immich_photos,mp=/mnt/media/photos
lxc.mount.entry: /dev/dri/card0 ...
lxc.mount.entry: /dev/dri/renderD128 ... # iGPU pour ML
```

**LXC 114 (servarr)**
```
mp0: /mnt/usbssd/data,mp=/data           # bind mount media
lxc.cgroup2.devices.allow: c 195:* rwm   # nvidia
lxc.cgroup2.devices.allow: c 508:* rwm   # nvidia-uvm
lxc.mount.entry: /dev/nvidia0 ...
lxc.mount.entry: /dev/nvidiactl ...
lxc.mount.entry: /dev/nvidia-uvm ...
lxc.mount.entry: /dev/nvidia-uvm-tools ...
lxc.cgroup2.devices.allow: c 10:200 rwm  # /dev/net/tun (VPN)
lxc.mount.entry: /dev/net/tun ...
```

**VM 102 (HAOS)**
```
usb0: host=1-1                            # Z-Wave / Zigbee dongle
```

## VPS distants (managed by Coolify)

| Provider | Nom Coolify | Type | IP publique | Localisation | OS | Coût | Notes |
|----------|-------------|------|-------------|--------------|-----|------|-------|
| Hetzner Cloud | `hetzner-shared-1` | CX 23 (2 vCPU x86 / 4 GB / 40 GB) | `203.0.113.10` | Falkenstein DE (FSN1) | Ubuntu 24.04 LTS | ~4,79 €/mois | Mutualisé pour sites perso et clients via Coolify + Cloudflare Tunnel. Provisionné 2026-05-05 via API Hetzner. **Apps actives 2026-05-07** : my-portfolio (example.com + www.example.com, prod, migré de Vercel). Tunnel CF UUID `00000000-0000-0000-0000-000000000001` route le trafic public vers coolify-proxy:80. Containers : `cloudflared-prod` (tunnel), `coolify-proxy` (Traefik interne), apps clients ajoutées au fil de l'eau. |

## VMs planifiées / en cours

_(aucune actuellement - VM 300 Coolify provisionnée 2026-05-05, voir VMs actives ; Hetzner CX23 ajouté 2026-05-05, voir VPS distants)_

> ✅ **LXC inconnu identifié 2026-05-07** : MAC `02:00:00:00:00:1a`, IP `192.168.1.86`, hostname `ubuntu` = stale DHCP entry d'un ancien workload PVE supprimé (OUI `BC:24:11` = Proxmox virtio-net). Hôte offline, lease expiré. Aucune action infrastructure - à nettoyer dans UCG → Settings → Networks → Default → Clients → forget.

> ⏳ **VM 102 HAOS** (`192.168.1.128`) : encore DHCP. À fixer via UCG Settings → Networks → Default → Clients → reserve `192.168.1.128` for MAC `02:00:00:00:00:01` (HAOS gère son réseau, pas via cloud-init).

## Allocation des ressources (pour estimer la marge)

| Ressource | Total host | Alloué (sum) | Marge |
|-----------|-----------|--------------|-------|
| vCPU (8 threads) | 8 | 35 logique | overcommit ~4.4× - OK pour homelab |
| RAM | 32 GB | ~36 GB nominal post-Wazuh | overcommit léger - usage réel ~22-25 GB (OpenSearch heap fixé) ⚠️ tension croissante |
| Disk (local-lvm) | 141 GB pool | ~78 GB (53%) | ~63 GB libre - **ne pas overprovisionner**, services lourds → Hitachi |
| Disk (Hitachi) | 916 GB | ~340 GB | ~570 GB libre (rootfs LXC 122 wazuh + immich photos + nextcloud) |
| Disk (usbssd T7) | 916 GB | 660 GB | 220 GB libre |
| Disk (backup-ssd T5) | 229 GB | 32 GB | 186 GB libre |

## Convention de tags Proxmox

- `community-script` : déployé via `community-scripts/ProxmoxVE`
- Un tag de rôle : `proxy`, `dns`, `monitoring`, `nvr`, `dashboard`, `diagrams`
- À adopter pour tous les LXC custom : `custom`
