# 04 - Storage

## Disques physiques

| Device | Modèle | Taille | Type | Usage | Health |
|--------|--------|--------|------|-------|--------|
| `/dev/sdb` | Kingston SKC600 | 256 GB | SSD SATA | Système Proxmox + LVM-thin | ✅ PASSED |
| `/dev/sda` | Hitachi HDS721010CLA632 | 1 TB | HDD SATA 7200 RPM | Storage `Hitachi` (data froide) | ✅ PASSED |
| `/dev/sdc` | Samsung Portable SSD T7 Shield | 1 TB | SSD USB | Storage `usbssd` (data chaude) | ✅ PASSED |
| `/dev/sdd` | Samsung Portable SSD T5 | 250 GB | SSD USB | Storage `backup-ssd` | ✅ PASSED |

### Numéros de série (utile pour RMA / debug)

| Device | Serial |
|--------|--------|
| sda (Hitachi) | `JP2940N019B4GD` |
| sdb (Kingston) | `50026B77835F82FC` |
| sdc (T7 Shield) | `S6YGNS0W602083A` |
| sdd (T5) | `S49TNP0M108292J` |

### SMART

Vérifier régulièrement :
```bash
for d in sda sdb sdc sdd; do
  echo "=== /dev/$d ==="
  smartctl -H /dev/$d 2>/dev/null | grep -E "result|FAILING"
done
```

> 📅 À automatiser : un cron hebdo qui envoie un mail si un disque dégrade. Roadmap Phase 1.5.

## Layout du SSD système (`/dev/sdb`)

```
sdb1   1007 KiB  BIOS boot (legacy, inutilisé en UEFI)
sdb2      1 GiB  /boot/efi (EFI System Partition)
sdb3   237.5 GiB Volume PV LVM
  └─pve (VG)
      ├─pve-swap          8 GiB    swap
      ├─pve-root         69.4 GiB  /
      └─pve-data        141.2 GiB  thin pool (LVs des VMs/LXC sur local-lvm)
```

Le thin pool `pve-data` est à **48.84% utilisé** au moment du snapshot.

### ⚠️ Pool LVM-thin sur-provisionné - risque connu

```
Capacité physique :  141 GB
Capacité allouée  :  374 GB (sum des disks VMs/LXC virtuels)
Ratio overcommit  :  321 %
```

Cause probable du **crash HAOS du 4 mai 2026** : un pic d'écriture sur un volume thin alors que le pool physique était proche de la saturation a corrompu la table de partitions de la VM 102.

**Mitigation immédiate** :
- Surveiller `Data%` du pool : `lvs pve/data` doit rester < 85%
- Activer un monitor (Phase 5) qui alerte si `Data% > 80%`
- Avant de créer un nouveau volume, vérifier l'espace dispo réel

**Mitigation cible** (Phase 5/6) :
- Migrer vers **ZFS mirror** sur 2 SSD dédiés (data integrity + checksums + snapshots cohérents)
- Voir [docs/10-roadmap.md](10-roadmap.md) Phase 5 → Storage

## Storages Proxmox

| Name | Type | Path / device | Capacité | Utilisé | Usage |
|------|------|---------------|----------|---------|-------|
| `local` | dir | `/var/lib/vz` | 68 GB (sur `/`) | 33 GB (48%) | ISOs, templates, vzdump éphémères |
| `local-lvm` | lvmthin | `pve/data` | 141 GB | 69 GB (49%) | Disques VMs/LXC rapides |
| `Hitachi` | dir | `/mnt/pve/Hitachi` | 916 GB | 279 GB (30%) | LXC volumes peu sollicités + Immich photos |
| `usbssd` | dir | `/mnt/usbssd` | 916 GB | 580 GB (63%) | LXC volumes rapides + média Servarr |
| `backup-ssd` | dir | `/mnt/backup-ssd` | 229 GB | 32 GB (14%) | vzdump (rétention courte) |

## Mapping VM/LXC → Storage

| Storage | VMs/LXC qui y résident |
|---------|------------------------|
| `local-lvm` | 101 (frigate), 102 (HAOS), 103 (traefik), 106 (immich rootfs), 110 (NPM stopped), 111 (glance), 114 (servarr rootfs), 115 (nas-files rootfs), 117 (authentik) |
| `Hitachi` | 100 (adguard), 108 (grafana) + bind mount Immich photos |
| `usbssd` (T7) | 107 (influxdb), 113 (excalidraw) + bind mounts Servarr/nas-files (`/data`) |
| `backup-ssd` (T5) | uniquement vzdump |

## Mounts hôte (extrait `df -h`)

```
/dev/mapper/pve-root   68G   33G   32G  52% /
/dev/sdb2            1022M  8.8M 1014M   1% /boot/efi
/dev/sdc1             916G  580G  291G  67% /mnt/usbssd
/dev/sda1             916G  279G  591G  33% /mnt/pve/Hitachi
/dev/sdd              229G   32G  186G  15% /mnt/backup-ssd
```

> Note : `/dev/sdd` est monté **sans table de partition** (FS direct). C'est volontaire pour le backup-ssd. Si on remplace ce disque, garder le même schéma.

## Bind mounts importants (data partagée)

| Source (host) | Mount point (LXC) | LXC | Pourquoi |
|---------------|-------------------|-----|----------|
| `/mnt/pve/Hitachi/immich_photos` | `/mnt/media/photos` | 106 (immich) | Bibliothèque Immich sur HDD (gros volume, accès séquentiel) |
| `/mnt/usbssd/data` | `/data` | 114 (servarr) | Bibliothèque Jellyfin/*arr - accès aléatoire SSD nécessaire |
| `/mnt/usbssd/data` | `/data` | 115 (nas-files) | Même data que servarr, exposé via file browser |

> ⚠️ Le partage de `/mnt/usbssd/data` entre LXC 114 et 115 est intentionnel (même UID via unprivileged mapping). Si on ajoute un 3ème consommateur, vérifier les UIDs.

## SSD USB - fiabilité

Le T7 Shield et le T5 sont en USB. Risques :
- **Disconnect spontané** sur reboot host → reconnaître via `udev` rule + auto-mount via `/etc/fstab` avec `nofail`.
- **TRIM** : USB Mass Storage ne supporte pas TRIM par défaut. Vérifier que le disque est en UAS (`lsusb -t`).
- **Wear** : surveiller via SMART NVMe sur T7 (`smartctl -A /dev/sdc`).

## fstab (à archiver depuis le host)

> 📋 **À récupérer** : copier `/etc/fstab` du host dans `configs/host/fstab` après cette session.

## Snapshots

- `local-lvm` est en LVM-thin → **snapshots gratuits et instantanés**. Utilisé pour `pct snapshot` / `qm snapshot`.
- `Hitachi`, `usbssd`, `backup-ssd` sont en `dir` → **pas de snapshot natif**. Pour ces volumes : passer par vzdump.

> Conséquence : avant un upgrade risqué d'une VM stockée sur `local-lvm` (HAOS, Authentik, *arr), faire `qm snapshot 102 pre-update` ou `pct snapshot 114 pre-update`. Pour les LXC sur `Hitachi`/`usbssd`, passer par `vzdump`.
