# 01 - Architecture

## Vue d'ensemble

Single-node Proxmox VE (8.x) sur un HP ATX recyclé. Tout en LAN, derrière la box FAI. Pas d'exposition internet.

```mermaid
flowchart TB
    Internet([Internet]) --> Box["🌐 Box FAI<br/>192.168.1.1"]

    subgraph LAN ["LAN - 192.168.1.0/24"]
        Box --> Devices["📱 Clients LAN<br/>(PCs, mobiles, IoT)"]
        Devices -->|"DNS query"| AdGuard
        Box --> AdGuard["🛡️ AdGuard<br/>LXC 100<br/>192.168.1.246"]

        AdGuard -->|"*.home.example.com<br/>rewrite"| Traefik

        subgraph PVE ["🖥️ Proxmox host - 192.168.1.90"]
            Traefik["🔀 Traefik v3<br/>LXC 103<br/>192.168.1.165"]

            Traefik --> HAOS["🏠 Home Assistant<br/>VM 102"]
            Traefik --> Authentik["🔐 Authentik + Uptime<br/>VM 117"]
            Traefik --> Servarr["🎬 Servarr stack<br/>LXC 114 + GPU"]
            Traefik --> Immich["📸 Immich<br/>LXC 106"]
            Traefik --> Frigate["📹 Frigate<br/>LXC 101 + Coral"]
            Traefik --> Misc["📦 Grafana / InfluxDB /<br/>Glance / Excalidraw / nas-files"]
        end
    end

    Cloudflare([Cloudflare DNS]) -.->|"DNS-01 ACME<br/>wildcard cert"| Traefik

    style Traefik fill:#1d4ed8,color:#fff
    style AdGuard fill:#16a34a,color:#fff
    style Cloudflare fill:#f97316,color:#fff
```

## Couches logiques

```mermaid
flowchart LR
    subgraph L1 ["1. Hardware"]
        HW["i7-6700 / 32GB / 4 disks"]
    end

    subgraph L2 ["2. Hypervisor"]
        PVE["Proxmox VE 8.x<br/>vmbr0 bridge"]
    end

    subgraph L3 ["3. Workloads"]
        VMs["2 VMs<br/>(HAOS, Authentik)"]
        LXC["11 LXC<br/>(unprivileged sauf 1)"]
    end

    subgraph L4 ["4. Edge"]
        DNS["AdGuard"]
        RP["Traefik"]
    end

    subgraph L5 ["5. Identity"]
        Auth["Authentik (forward-auth)"]
    end

    L1 --> L2 --> L3 --> L4 --> L5
```

> **Note** : Authentik est déployé mais le forward-auth Traefik n'est **pas encore activé** sur les routes - c'est dans la roadmap Phase 2 (voir [10-roadmap.md](10-roadmap.md)).

## Principes de design

- **LAN-only** : aucun service exposé sur internet. Si besoin externe → VPN (WireGuard / Tailscale, Phase 4).
- **DNS-01 wildcard** : un seul cert `*.home.example.com` pour tous les services. Renouvellement auto sans ouvrir le 80/443.
- **community-scripts par défaut** : la majorité des LXC viennent de [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).
- **Unprivileged LXC** quand possible (10/11 LXC le sont). Le seul privilégié est `frigate` à cause du passthrough iGPU + Coral.
- **Storage tiered** : système rapide (Kingston SSD), data chaude (Samsung T7 USB 1TB), data froide (Hitachi HDD 1TB), backups (Samsung T5 USB 250GB).

## Flux d'une requête HTTPS

Exemple : un client LAN tape `https://immich.home.example.com` :

1. Client interroge AdGuard (192.168.1.246) via DHCP-pushed DNS
2. AdGuard a une rewrite rule `*.home.example.com → 192.168.1.165` → renvoie cette IP
3. Client ouvre TLS sur 192.168.1.165:443 (Traefik LXC 103)
4. Traefik présente le wildcard cert Let's Encrypt (validé par les CAs publics)
5. Traefik route via le `Host:` header vers `http://192.168.1.134:2283` (Immich LXC 106)
6. Réponse remonte le chemin inverse

## Single-Point-of-Failure connus

| SPOF | Impact | Mitigation actuelle | Mitigation future |
|------|--------|---------------------|-------------------|
| Proxmox host | tout le lab down | hardware mono | Phase 6 : 2nd node + cluster |
| AdGuard | aucune résolution `.home.example.com` | reboot rapide (10G LXC) | Phase 3 : AdGuard secondary |
| Traefik | toutes les URLs HTTPS down | reboot rapide (2G LXC) | acceptable, fallback IP:port direct possible |
| Box FAI | aucun DHCP, aucun internet | accepter | hors-scope |
| Kingston SSD système | tout le lab down | vzdump + backups | Phase 6 : ZFS mirror |
