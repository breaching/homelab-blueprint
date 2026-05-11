# 06 - Services

> 19 services exposés via Traefik. Tous accessibles depuis le LAN. **Exceptions publiques** (via Cloudflare Tunnel) listées en bas - actuellement `coolify.home.example.com/webhooks/*` + `/app*` (pour GitHub webhooks et Soketi).

## Routes Traefik

| URL | Backend | Container | Notes |
|-----|---------|-----------|-------|
| https://pve.home.example.com | https://192.168.1.90:8006 | host PVE | UI Proxmox (backend HTTPS self-signed) |
| https://traefik.home.example.com | `api@internal` | LXC 103 | Dashboard Traefik (⚠ pas d'auth) |
| https://authentik.home.example.com | https://192.168.1.181:443 | VM 117 | IdP (forward-auth pas activé encore) |
| https://uptime.home.example.com | http://192.168.1.181:9000 | VM 117 | Uptime Kuma |
| https://coolify.home.example.com | http://192.168.1.252:8000 | VM 300 | Coolify 4.0.0 (PaaS self-host) |
| https://coolify.home.example.com/app/* + /apps/* | http://192.168.1.252:6001 | VM 300 | Soketi WebSocket realtime (router `coolify-ws` priorité > `coolify`) |
| https://test.home.example.com | https://192.168.1.252:443 (coolify-proxy → container Next.js :3000) | VM 300 | **Portfolio example.com en test** (Coolify app, repo `youruser/portfolio` branche `main`, base `/frontend`, Dockerfile multi-stage Next.js 16 standalone). Pattern coolify-apps via `serversTransport: insecure` - voir `configs/traefik/coolify-apps.yml` |
| https://homeassistant.home.example.com | http://192.168.1.128:8123 | VM 102 | HAOS |
| https://immich.home.example.com | http://192.168.1.134:2283 | LXC 106 | Photos |
| https://grafana.home.example.com | http://192.168.1.85:3000 | LXC 108 | Dashboards |
| https://influxdb.home.example.com | http://192.168.1.94:8086 | LXC 107 | TSDB |
| https://dns.home.example.com | http://192.168.1.246:80 | LXC 100 | AdGuard UI |
| https://draw.home.example.com | http://192.168.1.78:3000 | LXC 113 | Excalidraw |
| https://file.home.example.com | http://192.168.1.195:80 | LXC 115 | File browser |
| https://jellyfin.home.example.com | http://192.168.1.88:8096 | LXC 114 | Jellyfin |
| https://radarr.home.example.com | http://192.168.1.88:7878 | LXC 114 | Films |
| https://sonarr.home.example.com | http://192.168.1.88:9000 | LXC 114 | Séries |
| https://lidarr.home.example.com | http://192.168.1.88:8686 | LXC 114 | Musique |
| https://bazarr.home.example.com | http://192.168.1.88:6767 | LXC 114 | Sous-titres |
| https://jellyseerr.home.example.com | http://192.168.1.88:5055 | LXC 114 | Requests |

## Détails par service

### 🏠 Home Assistant (VM 102)

- **URL** : https://homeassistant.home.example.com
- **Backend** : VM HAOS native, port 8123
- **IP** : DHCP - résolue dynamiquement (à fixer)
- **Hardware** : USB Z-Wave/Zigbee dongle passé via `usb0: host=1-1`
- **Backups** : double couche
  - Snapshots HAOS internes (config + add-ons), stockés dans `/var/lib/vz/dump/haos-internal-backups/`
  - vzdump complet de la VM
- **Dépend de** : InfluxDB (LXC 107) pour métriques long-terme
- **Add-ons probables** : ESPHome, Matter Server (cf. snapshots récents)

### 🔐 Authentik + Uptime Kuma (VM 117)

- **URLs** : https://authentik.home.example.com (IdP) + https://uptime.home.example.com (monitoring)
- **Backend** :
  - Authentik : HTTPS port 443 (self-signed)
  - Uptime Kuma : HTTP port 9000
- **IP** : 192.168.1.181 statique
- **Pourquoi VM et pas LXC** : Authentik en docker-compose lourd, plus simple en VM
- **À faire** : activer Traefik forward-auth (middleware Authentik) sur les routes sensibles (Phase 2)

### 🛡️ AdGuard (LXC 100)

- **URL admin** : https://dns.home.example.com
- **Listen DNS** : 192.168.1.246:53 (TCP/UDP)
- **Rewrites** : 1 règle wildcard (cf. [05-reverse-proxy.md](05-reverse-proxy.md))
- **Storage** : Hitachi 10G (peu d'IO)
- **Critique** : si down, plus aucun `.home.example.com` ne résout. Failover possible via `/etc/hosts`.

### 📹 Frigate (LXC 101)

- **URL** : pas exposée via Traefik actuellement (à ajouter ?)
- **Backend** : DHCP, port 5000 par défaut
- **Hardware** : iGPU Intel HD 530 (HW decode) + USB Coral (TPU object detection)
- **Storage** : 20G local-lvm pour rootfs ; les enregistrements vidéo nécessitent un mount externe (à configurer si pas déjà fait)
- **À documenter** : où sont stockés les recordings

### 🔀 Traefik (LXC 103)

Voir [05-reverse-proxy.md](05-reverse-proxy.md).

### 📸 Immich (LXC 106)

- **URL** : https://immich.home.example.com
- **Backend** : 192.168.1.134:2283
- **Hardware** : iGPU passé pour ML (smart search, face detection)
- **Storage photos** : bind mount `/mnt/pve/Hitachi/immich_photos` → `/mnt/media/photos` (HDD 1TB)
- **DB** : Postgres + Redis embarqués dans le LXC
- **Dépend de** : aucun (autonome)

### 📊 InfluxDB (LXC 107)

- **URL** : https://influxdb.home.example.com (UI v2)
- **Backend** : 192.168.1.94:8086
- **Storage** : 68G sur usbssd (T7) - IO patterns favorables au SSD
- **Consommateurs** : Home Assistant (write), Grafana (read)

### 📈 Grafana (LXC 108)

- **URL** : https://grafana.home.example.com
- **Backend** : 192.168.1.85:3000
- **Datasources** : InfluxDB (107)
- **Storage** : 2G sur Hitachi (peu d'IO, juste config + dashboards SQLite)

### 🗄️ Nginx Proxy Manager (LXC 110) - DEPRECATED

- **Status** : `stopped`
- **Action** : à archiver via vzdump puis `pct destroy 110` après période de validation Traefik (~1 mois sans incident)
- Voir [docs/05-reverse-proxy.md](05-reverse-proxy.md) section "Migration NPM → Traefik"

### 🌟 Glance (LXC 111)

- **URL** : pas dans Traefik actuellement (à ajouter en `home.home.example.com` ?)
- **Backend** : 192.168.1.76:8080
- **Rôle** : dashboard de liens (homepage homelab)

### ✏️ Excalidraw (LXC 113)

- **URL** : https://draw.home.example.com
- **Backend** : 192.168.1.78:3000
- **Storage** : 10G sur usbssd
- **Notes** : self-hosted Excalidraw + collab server

### 🎬 Servarr stack (LXC 114)

Tout-en-un : Jellyfin + Radarr + Sonarr + Lidarr + Bazarr + Jellyseerr.

| Service | Port | URL |
|---------|------|-----|
| Jellyfin | 8096 | https://jellyfin.home.example.com |
| Radarr | 7878 | https://radarr.home.example.com |
| Sonarr | 9000 | https://sonarr.home.example.com |
| Lidarr | 8686 | https://lidarr.home.example.com |
| Bazarr | 6767 | https://bazarr.home.example.com |
| Jellyseerr | 5055 | https://jellyseerr.home.example.com |

- **IP** : 192.168.1.88 statique
- **Hardware** : NVIDIA GTX 1070 Ti (transcode Jellyfin / NVENC)
- **Storage media** : `/mnt/usbssd/data` → `/data` (SSD T7, 1 TB)
- **VPN** : `/dev/net/tun` mounté → un client VPN tourne pour les downloads (à confirmer/documenter)

### 🚀 Coolify (VM 300)

- **URL** : https://coolify.home.example.com (LAN)
- **Backend** : http://192.168.1.252:8000
- **Version** : Coolify 4.0.0 (installée 2026-05-05)
- **Stack docker** : `coolify` (app, port 8000→8080) + `coolify-db` (Postgres 15) + `coolify-redis` (7) + `coolify-realtime` (websockets 6001-6002)
- **Volume data** : `/data/coolify/` (sur disque VM 80G usbssd)
- **`.env`** : `/data/coolify/source/.env` - clés de chiffrement des secrets stockés dans Coolify → **backup obligatoire** dans Bitwarden (sans ça, perte des secrets clients en cas de crash)
- **Architecture** : voir [11-coolify.md](11-coolify.md). Cette instance pilote des VPS Hetzner pour héberger des sites clients via Cloudflare Tunnel.
- **Dépend de** : aucun pour le run. Hetzner API + Cloudflare API à configurer côté UI Coolify.
- **Particularité WebSocket** : Coolify utilise Soketi (compat Pusher) sur :6001 pour les events realtime UI. Pour que ça marche derrière Traefik, on a 2 routers : `coolify` (paths généraux → :8000) et `coolify-ws` (`/app/*` + `/apps/*` → :6001). `.env` configure `APP_URL=https://coolify.home.example.com` + `PUSHER_HOST/PORT/SCHEME` pour que le JS client tape la bonne URL. **Important** : utiliser `PathPrefix(/app/)` avec slash, sinon `/applications` (UI Coolify) est mal routé.

### 🚀 Portfolio test (VM 300, app Coolify)

- **URL** : https://test.home.example.com (LAN-only)
- **App Coolify id 1**, FQDN `http://test.home.example.com` (HTTP côté coolify-proxy pour éviter sa boucle redirect-to-https)
- **Repo** : `youruser/portfolio` branche `main`, base directory `/frontend`, build pack Dockerfile (Next.js 16 standalone, Node 22 alpine multi-stage)
- **Build vars** : 6 `NEXT_PUBLIC_*` (Formspree, PostHog, Sentry DSN, Calendly) - toutes inlinées au build via `ARG` du Dockerfile
- **Pipeline réseau** : Browser → AdGuard `*.home.example.com → .165` → Traefik LXC 103 (TLS wildcard) → HTTPS → coolify-proxy:443 (cert self-signed, skipVerify) → container Next.js :3000
- **Auto-deploy** : push `main` → webhook GitHub `coolify.home.example.com/webhooks/...` (via tunnel CF) → Coolify rebuild + rolling update
- **Statut** : test phase. Bascule prod prévue plus tard sur `example.com` côté Hetzner CX23 (`hetzner-shared-1`) avec Cloudflare Tunnel public

### 📁 nas-files (LXC 115)

- **URL** : https://file.home.example.com
- **Backend** : 192.168.1.195:80 (file browser HTTP)
- **Storage** : même bind `/mnt/usbssd/data` que servarr → expose les fichiers en read/write web

## Services internes (non-exposés via Traefik)

- **Frigate** : à exposer ou laisser direct sur IP:port ?
- **Glance** : idem
- **Postgres/Redis** : embarqués dans LXC, pas exposés

## Convention pour ajouter un service

Voir [`runbooks/add-new-service.md`](../runbooks/add-new-service.md).

Résumé :
1. Déployer le LXC/VM (community-scripts ou manuel)
2. Noter IP + port dans [02-inventory.md](02-inventory.md) et [06-services.md](06-services.md)
3. Ajouter une route dans le bon fichier `configs/traefik/conf.d/<group>.yml`
4. Reload Traefik (auto via watch)
5. Tester `https://<nom>.home.example.com`

## Exceptions publiques (CF Tunnel)

`home.example.com` est **LAN-first**. Mais certains chemins doivent être joignables depuis internet (webhooks GitHub, etc.) - exposés via le tunnel Cloudflare `homelab-coolify` (cloudflared docker sur VM 300).

Routes publiques actuelles :

| Path | Service interne | Pourquoi |
|---|---|---|
| `coolify.home.example.com/webhooks/*` | `localhost:8000` | Réception des events GitHub (push → auto-deploy) |
| `coolify.home.example.com/app/*` | `localhost:6001` | WebSocket Soketi pour l'UI Coolify quand le browser fait DoH (bypass AdGuard) |
| `coolify.home.example.com/apps/*` | `localhost:6001` | API HTTP Pusher pour publish events |

Tout le reste de Coolify (`/login`, `/dashboard`, etc.) reste **invisible depuis internet** - path filter strict côté CF Tunnel.
