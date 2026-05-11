# 08 - Disaster Recovery

> Runbooks **testés** issus d'incidents réels.

## Scénarios couverts

| # | Scénario | Runbook | Testé |
|---|----------|---------|-------|
| 1 | VM/LXC corrompue (ne boot plus) | [§1 ci-dessous](#1-vm-corrompue-cas-haos-mai-2026) | ✅ HAOS mai 2026 |
| 2 | Suppression accidentelle d'un CT | [§2](#2-restore-rapide-depuis-vzdump) | ⏳ à tester |
| 3 | SSD système Kingston HS | [§3](#3-perte-totale-du-ssd-systeme) | ⏳ à tester |
| 4 | Perte de l'usbssd T7 | [§4](#4-perte-de-lusbssd-t7) | ⏳ à tester |
| 5 | Cert TLS expiré | [§5](#5-cert-tls-expire) | ⏳ à tester |
| 6 | Reboot host : un CT ne remonte pas | [§6](#6-ct-ne-remonte-pas-au-boot) | ⏳ à tester |

---

## 1. VM corrompue (cas HAOS, mai 2026)

**Symptôme** : la VM ne boot plus, kernel panic ou FS corrompu.

### Cas réel - VM 102 HAOS (4-5 mai 2026)

**Trigger** : `qm stop 102` exécuté pendant un timeout ACPI shutdown → écriture interrompue sur la partition `hassos-data` alors que le pool LVM-thin était sur-provisionné (cf. [04-storage.md](04-storage.md)).

**Symptômes observés** :
- VM ne boote plus
- Erreurs kernel mentionnant la GPT et la partition `hassos-data` (ext4)
- Le LV existait toujours sur `pve/data` mais structure corrompue

**Procédure suivie (succès)** :
1. `testdisk` sur `/dev/pve/vm-102-disk-0` → reconstruction de la GPT primaire (perdue, GPT secondaire intacte) → écriture
2. `kpartx -av` puis `e2fsck -y` sur la partition data → réparation ext4
3. Boot validé via UI Proxmox console
4. Récupération de 3 backups HAOS internes (Apr 30, May 1, May 2) + ESPHome + Matter Server (~858 MB total)
5. **Triple copie** des backups récupérés :
   - `/root/haos-recovery/backups/` (host PVE, sur SSD système)
   - `/mnt/backup-ssd/haos-recovery/` (T5 dédié backup)
   - `/mnt/usbssd/data/files/BACKUP NAS/HAOS/` (T7, partagé via nas-files)
6. Nouvelle VM 102 HAOS 17.2 créée propre via community-script
7. Restore d'un backup `.tar` via UI HAOS (Settings → System → Backups → Upload). Backup utilisé : 2 mai 04:48 (301 MB).
8. ✅ HAOS 100% restauré sans perte fonctionnelle

**Lessons learned** :
- ⚠️ **Ne jamais** `qm stop` une VM HAOS sans avoir attendu le shutdown ACPI complet (`qm shutdown` + délai)
- Le pool LVM-thin sur-provisionné a aggravé la corruption - Phase 5 prévoit une migration ZFS
- Les snapshots HAOS internes (`/var/lib/vz/dump/haos-internal-backups/`) sont essentiels en complément du vzdump PVE
- Toujours faire une **triple copie** des backups critiques juste après une recovery

### Procédure (vécue)

```bash
# 1. Stopper la VM
qm stop 102

# 2. Identifier le LV de la VM
lvs | grep vm-102

# 3. Mapper le LV en device pour pouvoir l'inspecter depuis le host
# Le path est /dev/pve/vm-102-disk-0

# 4. Lancer testdisk pour reconstruire la table de partitions si elle a été corrompue
apt install -y testdisk
testdisk /dev/pve/vm-102-disk-0
# → Analyse → Quick Search → écrire la table reconstruite

# 5. Une fois la table OK, identifier la partition data (souvent la plus grosse)
# kpartx pour exposer les partitions :
apt install -y kpartx
kpartx -av /dev/pve/vm-102-disk-0
# → /dev/mapper/pve-vm--102--disk--0p<N>

# 6. Vérifier le FS
e2fsck -y /dev/mapper/pve-vm--102--disk--0pN

# 7. Démapper, restart la VM
kpartx -dv /dev/pve/vm-102-disk-0
qm start 102
```

### Si testdisk + e2fsck n'ont pas suffi

→ Restore depuis vzdump (cf. §2). Le crash HAOS de mai 2026 a été récupéré sans perte de data - testdisk a suffi.

### Si la VM tourne mais HAOS ne démarre pas

→ Restore d'un snapshot HAOS interne :
```bash
ls /var/lib/vz/dump/haos-internal-backups/
# Copier le .tar voulu vers la VM, puis depuis HAOS :
# Settings → Backups → Upload → Restore (config only ou full)
```

---

## 2. Restore rapide depuis vzdump

**Cas** : un CT est inutilisable (corrompu, supprimé, mauvaise config) → restore depuis le dernier vzdump.

### LXC

```bash
# Lister les backups dispos
ls -lh /mnt/backup-ssd/dump/ | grep lxc-<VMID>

# Restore (overwrite)
pct restore <VMID> /mnt/backup-ssd/dump/vzdump-lxc-<VMID>-<DATE>.tar.zst \
  --storage local-lvm \
  --force 1
pct start <VMID>
```

### VM

```bash
ls -lh /mnt/backup-ssd/dump/ | grep qemu-<VMID>

qmrestore /mnt/backup-ssd/dump/vzdump-qemu-<VMID>-<DATE>.vma.zst <VMID> \
  --storage local-lvm \
  --force
qm start <VMID>
```

### Avant un restore destructif : snapshot d'abord !

Si le CT existe encore et est juste cassé, avant de l'overwrite :
```bash
# LXC sur local-lvm
pct snapshot <VMID> pre-restore

# Sinon : vzdump immédiat
vzdump <VMID> --dumpdir /mnt/backup-ssd/dump --compress zstd --mode stop
```

---

## 3. Perte totale du SSD système

**Cas** : `/dev/sdb` (Kingston) HS - le host ne boote plus.

### Pré-requis avant l'incident

- ✅ Avoir le `backup-ssd` (T5) à jour avec vzdump
- ⛔ Ne pas oublier d'externaliser ce repo Git régulièrement (configs)
- ⛔ Avoir la liste des storages dans Git (`configs/host/storage.cfg`)

### Procédure

1. **Acquérir un nouveau SSD** (NVMe ou SATA, ≥ 256 GB)
2. **Installer Proxmox VE** dessus (USB d'install dispo dans le tiroir)
   - Hostname : `pve`
   - Network : 192.168.1.90/24, GW 192.168.1.1
3. **Recréer les storages** avec les mêmes noms :
   - `Hitachi` (dir, `/mnt/pve/Hitachi`)
   - `usbssd` (dir, `/mnt/usbssd`)
   - `backup-ssd` (dir, `/mnt/backup-ssd`)

   Restaurer `/etc/pve/storage.cfg` depuis le repo git (`configs/host/storage.cfg`).
4. **Restaurer `/etc/fstab`** depuis le repo (`configs/host/fstab`)
5. **Restaurer LXC 100 (AdGuard) en premier** (sinon plus aucune résolution `.home.example.com`)
   ```bash
   pct restore 100 /mnt/backup-ssd/dump/vzdump-lxc-100-<DATE>.tar.zst --storage Hitachi
   pct start 100
   ```
6. **Restaurer LXC 103 (Traefik)**
   ```bash
   pct restore 103 /mnt/backup-ssd/dump/vzdump-lxc-103-<DATE>.tar.zst --storage local-lvm
   pct start 103
   ```
7. **Restaurer le reste** (n'importe quel ordre)
8. **Vérifier**
   - https://pve.home.example.com → UI Proxmox OK
   - https://traefik.home.example.com → dashboard Traefik OK
   - https://uptime.home.example.com → monitoring confirme tous les services

### Cert TLS

Le wildcard cert est dans `acme.json` du LXC 103 - restauré avec le vzdump. **Pas besoin de re-générer**.

Si le cert est trop vieux pour Let's Encrypt (>90j sans renouvellement), Traefik le re-tirera automatiquement au démarrage via DNS-01 (le `CF_DNS_API_TOKEN` est dans `/etc/default/traefik`, restauré aussi).

---

## 4. Perte de l'usbssd T7

**Cas** : le SSD USB Samsung T7 (1 TB) HS / déconnecté définitivement.

**Impact** :
- LXC 107 (InfluxDB) → rootfs perdu, mais data restorable depuis vzdump
- LXC 113 (Excalidraw) → idem
- Bind mount `/mnt/usbssd/data` perdu → **bibliothèque media perdue** (Jellyfin, *arr)
  - Les *.mkv ne sont PAS dans vzdump (bind mount, externe)
  - **Phase 4 nécessaire** : sync off-site de la lib

### Procédure court-terme

1. Acheter un SSD USB de remplacement (≥ 1 TB)
2. Format ext4, monter en `/mnt/usbssd`
3. Restorer LXC 107, 113 depuis vzdump
4. Recréer `/mnt/usbssd/data` (vide → tout re-télécharger via *arr, ou restore depuis off-site Phase 4)

---

## 5. Cert TLS expiré

**Symptôme** : navigateur affiche "certificate expired" sur `*.home.example.com`.

### Diagnostic

```bash
pct exec 103 -- bash -c 'cat /etc/traefik/ssl/acme.json | jq .cloudflare.Certificates[0].domain'
pct exec 103 -- journalctl -u traefik -n 100 --no-pager | grep -i acme
```

### Causes possibles

1. `CF_DNS_API_TOKEN` invalide (révoqué, expiré, scope changé)
2. Cloudflare API rate-limited
3. Connectivité internet absente quand renouvellement tenté

### Force renew

```bash
pct exec 103 -- bash -c 'rm /etc/traefik/ssl/acme.json && systemctl restart traefik'
# Surveiller :
pct exec 103 -- journalctl -u traefik -f
# Le renew prend ~1-2 minutes (delayBeforeCheck: 30s)
```

> ⚠️ Ne supprimer `acme.json` qu'en dernier recours. Le rate limit Let's Encrypt est de 5 certs/semaine pour le même domaine.

---

## 6. CT ne remonte pas au boot

**Symptôme** : après reboot du host, un LXC reste `stopped` alors qu'il a `onboot: 1`.

### Causes fréquentes

| Cause | Diagnostic | Fix |
|-------|------------|-----|
| Bind mount source manquante | `pct start <VMID>` → erreur "no such file" | Vérifier `/mnt/usbssd` ou autre source mountée |
| FS du LV corrompu | `dmesg | grep -i error` | `e2fsck` sur le LV |
| `startup` order trop tôt (dépendance pas prête) | `cat /etc/pve/lxc/<VMID>.conf | grep startup` | Augmenter `startup: order=X,up=Y` |
| Storage indisponible (USB non-mappé) | `pvesm status` | Replug USB, `mount -a` |

### Boot dans l'ordre

L'ordre actuel attendu :
1. **Disques USB mountés** (`/etc/fstab` avec `nofail` mais...)
2. **VM 102 HAOS** (order=2, up=30 → attend 30s avant le suivant)
3. **LXC 100 AdGuard**
4. **LXC 103 Traefik**
5. Le reste

> 📋 À normaliser : ajouter `startup: order=N` à tous les CT critiques. Phase 1.5.

---

## Annexe : checklist post-DR

Après n'importe quel DR, vérifier :

- [ ] `https://pve.home.example.com` accessible
- [ ] `https://traefik.home.example.com` accessible (cert valide)
- [ ] `https://uptime.home.example.com` → tous les monitors verts
- [ ] `pct list` → tous les CT attendus en `running`
- [ ] `qm list` → toutes les VMs attendues en `running`
- [ ] Test ping `192.168.1.246` (AdGuard) et résolution `dig immich.home.example.com @192.168.1.246`
- [ ] Test load `https://immich.home.example.com` depuis un client LAN
- [ ] vzdump suivant **réussit** (vérifier le lendemain dans `/mnt/backup-ssd/dump/`)
- [ ] SMART des disques OK (`smartctl -H`)
- [ ] Mettre à jour [CHANGELOG.md](../CHANGELOG.md) avec la date + scénario
