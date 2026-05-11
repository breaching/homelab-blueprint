# 07 - Backups

## Stratégie 3-2-1 (état cible)

> **3** copies - **2** supports différents - **1** off-site

| Copie | État actuel | Cible |
|-------|-------------|-------|
| 1. Production (live VM/LXC) | ✅ sur Kingston SSD + Hitachi + T7 | identique |
| 2. Backup local SSD T5 | ✅ vzdump quotidien | rétention 14j → garder + ajouter checksum |
| 3. Off-site | ⛔ **pas en place** | Phase 4 : Backblaze B2 / rclone vers cloud |

⚠️ **Le 3-2-1 n'est pas encore complet** - l'off-site est une priorité de la Phase 4 du roadmap.

## vzdump quotidien

Configuré dans Proxmox UI → Datacenter → Backup.

| Paramètre | Valeur |
|-----------|--------|
| Storage | `backup-ssd` (Samsung T5, `/mnt/backup-ssd`) |
| Schedule | quotidien à 00:00 (cf. logs `vzdump-lxc-100-2026_05_04-00_00_07.log`) |
| Compression | zstd |
| Mode | snapshot (LVM-thin) ou suspend (autres) |
| Cible | toutes les VMs/LXC |
| Rétention | à vérifier - actuellement on voit ~3-4 archives par CT |

### Vérifier la config actuelle

```bash
cat /etc/pve/jobs.cfg
# Voir aussi : Datacenter → Backup dans l'UI
```

### Lister les backups d'un CT

```bash
ls -lh /mnt/backup-ssd/dump/ | grep "lxc-114"
```

### Restaurer un backup

```bash
# LXC
pct restore <newid> /mnt/backup-ssd/dump/vzdump-lxc-114-XXXX.tar.zst --storage local-lvm

# VM
qmrestore /mnt/backup-ssd/dump/vzdump-qemu-102-XXXX.vma.zst <newid> --storage local-lvm
```

> Voir [`runbooks/recover-vm.md`](../runbooks/recover-vm.md) pour la procédure complète.

## Snapshots HAOS (couche supplémentaire)

HAOS fait des snapshots **internes** quotidiens (config + add-ons + DB), exportés vers le host Proxmox dans :

```
/var/lib/vz/dump/haos-internal-backups/
├── Automatic_backup_2026.4.4_2026-04-30_05.05_12002109.tar
├── Automatic_backup_2026.4.4_2026-05-01_04.58_23001891.tar
├── Automatic_backup_2026.4.4_2026-05-02_04.48_18001498.tar
├── ESPHome_Device_Builder_2026.3.0_...tar
└── Matter_Server_8.2.2_...tar
```

Ces snapshots ont **sauvé la mise** lors du crash HAOS de mai 2026 (cf. [08-disaster-recovery.md](08-disaster-recovery.md)).

> Le snapshot interne HAOS contient la config et les data add-ons, **pas** l'OS HAOS lui-même. Pour récupérer l'OS, il faut le vzdump de la VM 102.

## Configs critiques externalisées

En plus des vzdump, les configs suivantes méritent un export Git :

| Config | Source | Destination Git |
|--------|--------|-----------------|
| Traefik static | `pct exec 103 -- cat /etc/traefik/traefik.yaml` | `configs/traefik/traefik.yaml` |
| Traefik routes | `pct exec 103 -- ls /etc/traefik/conf.d/` | `configs/traefik/*.yml` |
| AdGuard | `pct exec 100 -- cat /opt/AdGuardHome/AdGuardHome.yaml` | `configs/adguard/AdGuardHome.example.yaml` (sanitized) |
| /etc/network/interfaces | host | `configs/host/interfaces` |
| /etc/fstab | host | `configs/host/fstab` |
| /etc/pve/storage.cfg | host | `configs/host/storage.cfg` |
| Backup jobs | `cat /etc/pve/jobs.cfg` | `configs/host/jobs.cfg` |

> Script à écrire : `scripts/export-configs.sh` (Phase 1.5) qui collecte tout.

## Calendrier conseillé

| Fréquence | Action |
|-----------|--------|
| Quotidien | vzdump auto (déjà actif) |
| Hebdo | revue de la rétention `du -sh /mnt/backup-ssd/dump/*` |
| Hebdo | snapshots HAOS auto (côté HAOS) |
| Avant tout upgrade | snapshot manuel (`qm snapshot` ou `pct snapshot`) |
| Mensuel | restore-test sur 1 LXC random vers ID temporaire |
| Trimestriel | export complet de `configs/` vers Git |
| Annuel | rotation matériel : check SMART de tous les disques |

## Restore tests

🚨 **Un backup non-testé n'existe pas.**

Roadmap (Phase 1.5) : automatiser un restore-test mensuel :
1. Pick un LXC random (sauf 100/103 - critiques)
2. Restore vers VMID 9XX
3. Boot, vérif basique, destroy

Script `scripts/test-restore.sh` à écrire.

## Off-site (cible Phase 4)

Options envisagées :
- **rclone → Backblaze B2** : ~$5/mois pour ~1TB. Encryption client-side via `rclone crypt`.
- **rclone → Hetzner Storage Box** : alternative européenne (EUR), 100GB pour ~3€.
- **2nd Proxmox node distant** : + cher en hardware mais permet `pve-zsync`.

Critères :
- Encrypt avant upload (clés stockées hors-cloud)
- Daily delta sync de `/mnt/backup-ssd/dump/`
- Rétention longue (90j+) côté off-site

## Que sauvegarder en priorité ?

Si le `backup-ssd` se remplit et qu'on doit prioriser :

1. **VM 117** (Authentik + Uptime Kuma) - DB users, codes 2FA, history monitoring
2. **VM 102** (HAOS) - automations, intégrations, history
3. **LXC 100** (AdGuard) - listes custom, rewrites, stats
4. **LXC 103** (Traefik) - routes (mais aussi versionné Git)
5. **LXC 106** (Immich) - DB métadonnées (les photos elles-mêmes sont sur Hitachi, à backup séparément vers off-site)
6. Le reste : reproductible via community-scripts + reconfig manuelle

## Photos Immich - backup des originaux

Les photos vivent dans `/mnt/pve/Hitachi/immich_photos/` (pas dans le rootfs LXC). vzdump du LXC 106 n'inclut **pas** la bibliothèque photo.

Stratégie séparée nécessaire :
- Sync `/mnt/pve/Hitachi/immich_photos/` → off-site (encrypted) - Phase 4
- Optionnel : copy locale sur usbssd via `rsync --link-dest` pour avoir 2 copies sur le host
