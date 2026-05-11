# Configurations versionnées

Configs essentielles du homelab versionnées dans Git pour permettre :
- Code review des changements
- Rollback rapide
- Recovery après réinstallation

## Structure

```
configs/
├── traefik/         # Reverse proxy (file provider)
│   ├── traefik.yaml # Config statique (entrypoints, ACME, etc.)
│   ├── admin.yml    # Routes admin (pve, traefik, authentik, uptime)
│   ├── data.yml     # Routes data (immich, grafana, ...)
│   ├── home.yml     # Routes domotique (homeassistant)
│   └── media.yml    # Routes media (jellyfin, *arr)
├── adguard/         # DNS + filtrage (à exporter)
│   └── README.md    # Guide d'export sanitized
└── host/            # Configs du host PVE (à exporter)
    └── README.md
```

## Sanitization

⚠️ **Aucun secret ne doit être committé**. Avant de versionner une config :

| Config | Secrets potentiels | Action |
|--------|-------------------|--------|
| Traefik `traefik.yaml` | aucun (le `CF_DNS_API_TOKEN` est dans `/etc/default/traefik`) | safe to commit |
| Traefik `conf.d/*.yml` | aucun (URLs internes seulement) | safe to commit |
| AdGuard `AdGuardHome.yaml` | bcrypt hashes admin, clés DNSCrypt | **redact avant commit** |
| `/etc/network/interfaces` | aucun en LAN-only | safe to commit |
| `/etc/fstab` | aucun | safe to commit |
| `/etc/pve/storage.cfg` | aucun | safe to commit |

## Synchronisation host → repo

Workflow manuel pour l'instant (Phase 1.5 : automatiser via script) :

```bash
# Depuis machine locale où le repo est cloné
HOST=root@192.168.1.90

# Traefik
scp $HOST:/etc/traefik/traefik.yaml configs/traefik/traefik.yaml
scp $HOST:/etc/traefik/conf.d/*.yml configs/traefik/

# Host PVE
scp $HOST:/etc/network/interfaces configs/host/interfaces
scp $HOST:/etc/fstab configs/host/fstab
scp $HOST:/etc/pve/storage.cfg configs/host/storage.cfg
scp $HOST:/etc/pve/jobs.cfg configs/host/jobs.cfg

# AdGuard (sanitize manuellement avant commit !)
scp $HOST:/var/lib/lxc/100/rootfs/opt/AdGuardHome/AdGuardHome.yaml /tmp/adguard-raw.yaml
# → ouvrir /tmp/adguard-raw.yaml, REDACT les bcrypt et clés, sauvegarder dans configs/adguard/AdGuardHome.example.yaml
```

> Idéal Phase 1.5 : un script `scripts/export-configs.sh` qui automatise ça avec sanitization.
