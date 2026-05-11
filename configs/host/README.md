# Host PVE configs

À exporter et committer ici depuis le host Proxmox :

## Fichiers à versionner

| Fichier (host path) | Cible repo | Contenu sensible ? |
|---------------------|------------|---------------------|
| `/etc/network/interfaces` | `interfaces` | Non (LAN seulement) |
| `/etc/fstab` | `fstab` | Non |
| `/etc/pve/storage.cfg` | `storage.cfg` | Non |
| `/etc/pve/jobs.cfg` | `jobs.cfg` | Non |
| `/etc/pve/datacenter.cfg` | `datacenter.cfg` | Non |
| `/etc/hosts` | `hosts` | Non (LAN) |
| Liste des CT/VM (`pct list` + `qm list`) | `inventory.txt` | Non |

## Fichiers à NE PAS versionner

- `/etc/pve/priv/*` - clés Corosync, secrets cluster
- `/etc/ssh/sshd_config` ne contient pas de secret en soi mais vérifier
- `/root/.ssh/*` - clés SSH

## Procédure d'export

```bash
HOST=root@192.168.1.90
mkdir -p configs/host
scp $HOST:/etc/network/interfaces configs/host/interfaces
scp $HOST:/etc/fstab configs/host/fstab
scp $HOST:/etc/pve/storage.cfg configs/host/storage.cfg
scp $HOST:/etc/pve/jobs.cfg configs/host/jobs.cfg
scp $HOST:/etc/pve/datacenter.cfg configs/host/datacenter.cfg

# Snapshot de la config CT/VM courante
ssh $HOST 'pct list && echo "---" && qm list' > configs/host/inventory.txt

git add configs/host/
git status configs/host/
# Vérifier qu'aucun secret n'est inclus avant commit
git commit -m "docs(host): export PVE host configs"
```
