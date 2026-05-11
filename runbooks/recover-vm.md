# Runbook - Recover une VM/LXC corrompue

> Procédure inspirée de la récup HAOS de mai 2026.

## Triage initial

Quand un CT/VM est en panne, déterminer la nature :

```bash
# Statut
pct status <VMID>     # ou qm status <VMID>

# Logs récents
pct exec <VMID> -- journalctl -xe   # si encore bootable
journalctl -u pve-cluster -n 100    # côté host

# I/O errors ?
dmesg | grep -i error | tail -50
smartctl -A /dev/sd<X>
```

Décide selon la nature :

| Symptôme | Action recommandée |
|----------|---------------------|
| CT boote mais une app crashe | Debug applicatif (pas DR) |
| CT ne boote pas, FS errors | → §1 Réparer le FS |
| CT ne boote pas, table partitions HS | → §2 testdisk |
| CT supprimé / dégât irréversible | → §3 Restore vzdump |
| Disque physique HS | → §4 Disk failure |

---

## §1 Réparer le FS sans restore

**Idéal quand** : la data est intacte mais le FS est en mauvais état.

### Pour un LXC sur LVM-thin

```bash
# 1. Stop le CT
pct stop <VMID>

# 2. Identifier le volume
lvs | grep vm-<VMID>
# → /dev/pve/vm-<VMID>-disk-0

# 3. e2fsck
e2fsck -y /dev/pve/vm-<VMID>-disk-0

# 4. Restart
pct start <VMID>
```

### Pour une VM (multi-partitions)

```bash
# 1. Stop
qm stop <VMID>

# 2. Mapper les partitions
apt install -y kpartx
kpartx -av /dev/pve/vm-<VMID>-disk-0
# → /dev/mapper/pve-vm--<VMID>--disk--0p1, p2, p3...

# 3. e2fsck sur la partition data (la plus grosse en général)
e2fsck -y /dev/mapper/pve-vm--<VMID>--disk--0pN

# 4. Démapper
kpartx -dv /dev/pve/vm-<VMID>-disk-0

# 5. Restart
qm start <VMID>
```

---

## §2 testdisk - table de partitions corrompue

**Idéal quand** : le FS est probablement OK mais la GPT/MBR est cassée.

```bash
# 1. Stop la VM
qm stop <VMID>

# 2. Installer testdisk
apt install -y testdisk

# 3. Lancer testdisk sur le LV
testdisk /dev/pve/vm-<VMID>-disk-0
# Menu : Proceed
# Choisir le type de table (GPT pour modernes, Intel pour BIOS legacy)
# Analyse → Quick Search
# Vérifier que les partitions retrouvées sont cohérentes
# Write → Yes
# Quit

# 4. Vérifier
fdisk -l /dev/pve/vm-<VMID>-disk-0
# Tu dois voir les partitions

# 5. e2fsck sur chaque partition (cf. §1)
kpartx -av /dev/pve/vm-<VMID>-disk-0
e2fsck -y /dev/mapper/pve-vm--<VMID>--disk--0pN
kpartx -dv /dev/pve/vm-<VMID>-disk-0

# 6. Restart
qm start <VMID>
```

> Le crash HAOS de mai 2026 a été récupéré exactement comme ça. **Pas de perte de data**.

---

## §3 Restore depuis vzdump

**Idéal quand** : le CT est foutu, dégâts trop avancés.

### Choisir le bon backup

```bash
ls -lh /mnt/backup-ssd/dump/ | grep -E "lxc-<VMID>|qemu-<VMID>"
```

Choisir une date où on est sûr que le service tournait correctement. Ne pas prendre forcément le plus récent (peut contenir le bug qui a tout cassé).

### LXC

```bash
# Avant overwrite : sauve l'état actuel au cas où
pct stop <VMID>
vzdump <VMID> --dumpdir /tmp --compress zstd --mode stop

# Restore (overwrite)
pct restore <VMID> /mnt/backup-ssd/dump/vzdump-lxc-<VMID>-<DATE>.tar.zst \
  --storage <STORAGE> \
  --force 1

pct start <VMID>
```

### VM

```bash
qm stop <VMID>

qmrestore /mnt/backup-ssd/dump/vzdump-qemu-<VMID>-<DATE>.vma.zst <VMID> \
  --storage <STORAGE> \
  --force

qm start <VMID>
```

### Restore vers un VMID alternatif (sans toucher l'original)

```bash
# Pour LXC
pct restore 999 /mnt/backup-ssd/dump/vzdump-lxc-<VMID>-<DATE>.tar.zst --storage <STORAGE>
# Réseau : il faudra adapter l'IP à la main pour éviter le conflit
pct set 999 -net0 name=eth0,bridge=vmbr0,ip=192.168.1.249/24,gw=192.168.1.1
pct start 999
```

---

## §4 Disk failure

**Symptôme** : SMART alerte, I/O errors massives, ou disque disparu de `lsblk`.

Voir aussi : [docs/08-disaster-recovery.md §3-4](../docs/08-disaster-recovery.md).

### Étapes

1. **Stop tous les CT qui touchent le disque** (cf. mapping dans [04-storage.md](../docs/04-storage.md))
2. **Backup d'urgence** : copier ce qui peut l'être encore
3. **Remplacer le disque physiquement**
4. **Recréer le storage** (mkfs + mount + ajout dans `/etc/pve/storage.cfg`)
5. **Restore les CT** depuis vzdump

---

## Post-recovery checklist

- [ ] CT/VM redémarre proprement (`pct start` / `qm start` exit 0)
- [ ] App répond sur son port (`curl http://<IP>:<PORT>`)
- [ ] Test fonctionnel basique (login, page d'accueil)
- [ ] vzdump suivant réussi (vérifier le lendemain matin)
- [ ] Logger l'incident dans [CHANGELOG.md](../CHANGELOG.md)
- [ ] Mettre à jour [docs/08-disaster-recovery.md](../docs/08-disaster-recovery.md) si nouvelle leçon
