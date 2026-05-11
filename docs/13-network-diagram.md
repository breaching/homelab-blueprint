# 13 - Network Diagram

> Mis à jour le **2026-05-05** avec l'export DHCP UCG Ultra (32 devices). Source de vérité : [02-inventory.md](02-inventory.md) + [03-network.md](03-network.md) + [06-services.md](06-services.md).

---

## 📐 Diagramme draw.io (topologie physique + câbles)

Fichier importable dans [app.diagrams.net](https://app.diagrams.net) :

**[→ docs/assets/network-diagram.drawio](assets/network-diagram.drawio)**

> **Ouvrir** : `app.diagrams.net` → **File → Import from → Device** → sélectionner le fichier `.drawio`

Ce diagramme contient :
- Couche physique : Internet → Bbox Lite → UCG Ultra → Proxmox / Deco X55 / appareils filaires
- Zone WiFi mesh (Deco X55 #1 câblé + #2 satellite) avec tous les clients
- Tous les LXC/VMs Proxmox dans leur conteneur
- Légende couleurs (infra / IoT / perso / équipements)

---

## Topologie physique (synthèse)

```
🌐 Internet (fibre Bouygues)
    │
📡 Bouygues Bbox Lite - 192.168.2.28
    │  Ethernet WAN (double NAT)
🛡️ UCG Ultra - 192.168.1.1 (gateway + DHCP server)
    │   │     │        │         │
    │   │     │        │    autres filaires
    │  PVE   Deco X55 #1   (PC .100, Apple TV .194,
    │  .90   .31 (câblé)    Hue Bridge .108, Velux .58,
    │         │              HueSyncBox .22, K1 .154, sonnette .211)
    │    WiFi mesh ↗
    │   Deco X55 #2 (.35)
    │    +
    │    WiFi clients (Mac Studio .118, iPhone .182,
    │    Apple Laptop .250, WIN .129, Nintendo .156/.48,
    │    Roborock .96, P110 x3, Aqara FP2, EPSON .83, …)
    │
🖥️ Proxmox VE - 192.168.1.90
   ├── LXC 100 adguard       .246
   ├── LXC 101 frigate        .80
   ├── VM  102 HAOS           .128
   ├── LXC 103 traefik        .165
   ├── LXC 106 immich         .134
   ├── LXC 107 influxdb       .94
   ├── LXC 108 grafana        .85
   ├── LXC 111 glance         .76
   ├── LXC 113 excalidraw     .78
   ├── LXC 114 servarr        .88
   ├── LXC 115 nas-files      .195
   ├── VM  117 authentik      .181
   ├── VM  300 coolify        .252
   └── LXC 110 nginxproxy     .175 ⚠️ stopped
```

---

## Vue réseau logique (services)

```mermaid
flowchart TB
    Internet(["🌐 Internet"])
    Cloudflare(["☁️ Cloudflare DNS\nhome.example.com\nACME DNS-01"])

    Internet --- Box

    subgraph HOME ["🏠 LAN - 192.168.1.0/24"]

        Box["🛡️ UCG Ultra\nGateway + DHCP\n192.168.1.1"]

        subgraph CLIENTS ["Clients LAN"]
            direction LR
            PC["💻 PC / Laptop"]
            Mobile["📱 Mobile / Tablette"]
            IoT["🔌 IoT devices"]
        end

        Box -->|"DHCP push\nDNS → .246"| CLIENTS

        AdGuard["🛡️ AdGuard Home\nLXC 100 - Ubuntu\n192.168.1.246:53\n\n▸ Filtre pub/trackers\n▸ Rewrite *.home.example.com\n  → 192.168.1.165\n▸ Upstream: CF 1.1.1.1 + Quad9"]

        CLIENTS -->|"DNS query :53"| AdGuard

        subgraph PVE ["🖥️  Proxmox VE 8.x - 192.168.1.90  |  i7-6700 · 32 GB DDR4 · vmbr0"]

            Traefik["🔀 Traefik v3\nLXC 103 - Debian\n192.168.1.165\n:80 → :443\nwildcard cert *.home.example.com"]

            subgraph INFRA ["Infrastructure"]
                direction TB
                PVEui["🖥️ Proxmox UI\nhost:8006\npve.home.example.com"]
                AuthVM["🔐 Authentik IdP\nVM 117 - Debian\n192.168.1.181:443\nauthentik.home.example.com\n+\n📊 Uptime Kuma :9000\nuptime.home.example.com"]
            end

            subgraph DNS_PROXY ["DNS & Proxy"]
                direction TB
                AdGuardUI["🛡️ AdGuard UI\n(LXC 100 :80)\ndns.home.example.com"]
                TraefikDash["🔀 Traefik Dashboard\napi@internal\ntraefik.home.example.com"]
            end

            subgraph HOME_AUTO ["Home Automation"]
                HAOS["🏠 Home Assistant OS\nVM 102\n192.168.1.128:8123\nhomeassistant.home.example.com\n\n🔌 Z-Wave USB dongle\n    (USB passthrough)"]
                Frigate["📹 Frigate NVR\nLXC 101 - Debian\nDHCP\n(pas exposé Traefik)\n\n🧠 iGPU Intel HD 530\n🪸  USB Google Coral TPU\n📡 ttyUSB/ttyACM"]
            end

            subgraph MONITORING ["Monitoring"]
                direction LR
                Grafana["📈 Grafana\nLXC 108 - Debian\n192.168.1.85:3000\ngrafana.home.example.com"]
                InfluxDB["🗄️ InfluxDB v2\nLXC 107 - Debian\n192.168.1.94:8086\ninfluxdb.home.example.com\n\n💾 SSD T7 - 68 GB"]
            end

            subgraph DATA ["Data & Files"]
                direction LR
                Immich["📸 Immich\nLXC 106 - Debian\n192.168.1.134:2283\nimmich.home.example.com\n\n🧠 iGPU Intel HD 530\n💾 HDD Hitachi - bind mount"]
                NasFiles["📁 File Browser\nLXC 115 - Ubuntu\n192.168.1.195:80\nfile.home.example.com\n\n💾 SSD T7 - bind /data"]
            end

            subgraph MEDIA ["Media"]
                direction LR
                Servarr["🎬 Servarr Stack\nLXC 114 - Debian\n192.168.1.88\n\nJellyfin :8096\nJellyseerr :5055\nRadarr :7878\nSonarr :9000\nLidarr :8686\nBazarr :6767\n\n🎮 GPU GTX 1070 Ti\n💾 SSD T7 - /data\n🔒 /dev/net/tun (VPN)"]
            end

            subgraph TOOLS ["Tools"]
                direction LR
                Excalidraw["✏️ Excalidraw\nLXC 113 - Debian\n192.168.1.78:3000\ndraw.home.example.com\n\n💾 SSD T7 - 10 GB"]
                Glance["🌟 Glance Dashboard\nLXC 111 - Debian\n192.168.1.76:8080\n(pas exposé Traefik)"]
            end

        end

    end

    %% Internet → DNS
    Cloudflare -.->|"DNS-01 ACME\nwildcard cert\n*.home.example.com\n(renouvellement ~60j)"| Traefik

    %% Client → AdGuard → Traefik
    AdGuard -->|"rewrite *.home.example.com\n→ 192.168.1.165"| Traefik

    %% Traefik → backends
    Traefik -->|"pve.home.example.com\nhttps :8006"| PVEui
    Traefik -->|"authentik.home.example.com\nhttps :443\nuptime.home.example.com :9000"| AuthVM
    Traefik -->|"dns.home.example.com"| AdGuardUI
    Traefik -->|"traefik.home.example.com"| TraefikDash
    Traefik -->|"homeassistant.home.example.com\nhttp :8123"| HAOS
    Traefik -->|"grafana.home.example.com\nhttp :3000"| Grafana
    Traefik -->|"influxdb.home.example.com\nhttp :8086"| InfluxDB
    Traefik -->|"immich.home.example.com\nhttp :2283"| Immich
    Traefik -->|"file.home.example.com\nhttp :80"| NasFiles
    Traefik -->|"jellyfin / radarr / sonarr\nlidarr / bazarr / jellyseerr"| Servarr
    Traefik -->|"draw.home.example.com\nhttp :3000"| Excalidraw

    %% Internal flows
    HAOS -->|"write metrics"| InfluxDB
    Grafana -->|"read datasource"| InfluxDB

    %% Styles
    style Traefik fill:#1d4ed8,color:#fff
    style AdGuard fill:#16a34a,color:#fff
    style Cloudflare fill:#f97316,color:#fff
    style Box fill:#6b7280,color:#fff
    style PVE fill:#1e293b,color:#e2e8f0
    style Internet fill:#0f172a,color:#94a3b8
    style Servarr fill:#7c3aed,color:#fff
    style Immich fill:#0891b2,color:#fff
    style HAOS fill:#db6f1e,color:#fff
    style AuthVM fill:#be185d,color:#fff
```

---

## Flux d'une requête HTTPS (exemple : Immich)

```mermaid
sequenceDiagram
    actor User as 💻 Client LAN
    participant AG as 🛡️ AdGuard<br/>.246:53
    participant TR as 🔀 Traefik<br/>.165:443
    participant IM as 📸 Immich<br/>.134:2283
    participant CF as ☁️ Cloudflare<br/>DNS-01

    Note over CF,TR: (setup ACME - fait 1×, renouvellement auto ~60j)
    CF -->> TR: wildcard cert *.home.example.com

    User ->> AG: DNS query : immich.home.example.com
    AG -->> User: 192.168.1.165  (rewrite *.home.example.com)
    User ->> TR: TLS CONNECT :443 (présente wildcard cert)
    TR ->> IM: HTTP Host: immich.home.example.com → :2283
    IM -->> TR: 200 OK
    TR -->> User: 200 OK (TLS)
```

---

## Plan d'adressage

| Plage | Usage |
|-------|-------|
| `192.168.1.1` | Box FAI (gateway + DHCP) |
| `192.168.1.2 - .49` | Réservé infra fixe (futur) |
| `192.168.1.50 - .89` | Statique homelab |
| `192.168.1.90` | **Proxmox host** |
| `192.168.1.100 - .199` | Pool DHCP VMs/LXC |
| `192.168.1.200 - .249` | Réservations critiques |
| `192.168.1.246` | **AdGuard** (DNS, LXC 100) |
| `192.168.1.165` | **Traefik** (RP, LXC 103) |
| `192.168.1.250 - .254` | Mgmt / scratch |

---

## Stockage (host PVE)

```mermaid
flowchart LR
    subgraph STORAGE ["💾 Disques - Proxmox host"]
        SSD["Kingston SSD\n~141 GB pool\nlocal-lvm\n\nOS + LXC rootfs\n(rapide, critique)"]
        T7["Samsung T7 USB\n~916 GB\nusbssd\n\nInfluxDB (68G)\nServarr /data\nExcalidraw (10G)\nCoolify (80G)"]
        HDD["Hitachi HDD\n~916 GB\nmontage Hitachi\n\nImmich photos\nAdGuard (10G)\nGrafana (2G)"]
        T5["Samsung T5 USB\n~229 GB\nbackup-ssd\n\nVzdump backups\n(32G utilisés)"]
    end
```

---

## Hardware passthrough

| LXC/VM | Device | Usage |
|--------|--------|-------|
| LXC 101 (Frigate) | iGPU Intel HD 530 (`/dev/dri/*`) | Décodage HW vidéo |
| LXC 101 (Frigate) | USB Google Coral TPU | Object detection ML |
| LXC 101 (Frigate) | `/dev/ttyUSB*`, `/dev/ttyACM*` | Capteurs série |
| LXC 106 (Immich) | iGPU Intel HD 530 (`/dev/dri/*`) | ML smart search / faces |
| LXC 114 (Servarr) | NVIDIA GTX 1070 Ti (`/dev/nvidia*`) | Transcode Jellyfin NVENC |
| LXC 114 (Servarr) | `/dev/net/tun` | Client VPN (downloads) |
| VM 102 (HAOS) | USB Z-Wave/Zigbee dongle (`host=1-1`) | Domotique |

---

## Liens

- [01-architecture.md](01-architecture.md) - vue logique
- [02-inventory.md](02-inventory.md) - inventaire complet LXC/VMs
- [03-network.md](03-network.md) - plan d'adressage + DNS
- [05-reverse-proxy.md](05-reverse-proxy.md) - Traefik config
- [06-services.md](06-services.md) - routes + détails services
