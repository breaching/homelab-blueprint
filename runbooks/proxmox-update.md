# Runbook - Update Proxmox

## Cadence recommandée

- **Mineurs** (security patches) : toutes les 2-4 semaines
- **Majeurs** (8.x → 8.y) : 1× / trimestre, lire les release notes
- **Major upgrade** (8 → 9) : à part, voir https://pve.proxmox.com/wiki/Upgrade_from_8_to_9

## Avant tout update

1. **Snapshot des CT critiques** (si sur LVM-thin)
   ```bash
   for id in 100 103 117 102; do
     pct snapshot $id pre-update-$(date +%Y%m%d) 2>/dev/null || \
       qm snapshot $id pre-update-$(date +%Y%m%d) 2>/dev/null
   done
   ```

2. **vzdump complet ad-hoc** (en plus du quotidien)
   ```bash
   vzdump --all --dumpdir /mnt/backup-ssd/dump --compress zstd --mode snapshot
   ```

3. **Vérifier place disque**
   ```bash
   df -h /
   df -h /mnt/backup-ssd
   ```

4. **Annoncer à la famille** : "Internet/HAOS dispos potentiellement pendant 30 min" 😬

## Update mineur (apt)

```bash
# Lister les updates dispos
apt update
apt list --upgradable

# Update
apt full-upgrade -y

# Si kernel : reboot nécessaire
[ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED"
```

> **Astuce** : utiliser `pveupdate` qui gère les repos enterprise/no-subscription proprement.

## Reboot du host

```bash
# Vérifier qu'un reboot est OK
who -b           # uptime actuel
pct list         # quelques CT à arrêter ?

# Reboot
shutdown -r now
```

Le boot devrait remonter tous les CT avec `onboot: 1`. Vérifier ensuite :

```bash
pct list
qm list
```

Et tester :
- https://pve.home.example.com (UI)
- https://traefik.home.example.com (cert + dashboard)
- Quelques services type immich, jellyfin, homeassistant

## Update des LXC

Pour les LXC déployés via community-scripts, il y a généralement un script `update.sh`. Sinon :

```bash
pct exec <VMID> -- bash -c "apt update && apt full-upgrade -y && apt autoremove -y"
```

Pour Traefik : généralement géré par le script community-scripts.

## Update HAOS (VM 102)

Géré **depuis HAOS** (Settings → System → Updates). HAOS fait son snapshot interne avant.

> ⚠️ Avant un update OS HAOS majeur : faire aussi un `qm snapshot 102 pre-haos-update` côté Proxmox.

## Rollback si l'update casse tout

### Si snapshot disponible (LVM-thin)

```bash
pct rollback <VMID> pre-update-<DATE>
# ou
qm rollback <VMID> pre-update-<DATE>
```

### Si pas de snapshot mais vzdump frais

Voir [recover-vm.md §3](recover-vm.md#3-restore-depuis-vzdump).

### Si le host PVE lui-même est cassé après update

Boot en kernel précédent (GRUB → Advanced → kernel précédent), puis :

```bash
# Identifier les paquets installés récemment
zcat /var/log/apt/history.log.*.gz | grep "Start-Date.*$(date +%Y-%m-%d)" -A 1
# ou
grep "$(date +%Y-%m-%d)" /var/log/apt/history.log

# Rétrograder un paquet
apt install <pkg>=<version>
```

## Post-update checklist

- [ ] Tous les CT/VM redémarrés et `running`
- [ ] https://pve.home.example.com → UI accessible
- [ ] Cert TLS toujours valide (vérifier dans browser)
- [ ] Uptime Kuma : tous les monitors verts
- [ ] Aucun message `apt list --upgradable` restant
- [ ] Supprimer les snapshots `pre-update-*` après 48h sans incident :
  ```bash
  for id in 100 103 117 102; do
    pct delsnapshot $id pre-update-<DATE> 2>/dev/null
    qm delsnapshot $id pre-update-<DATE> 2>/dev/null
  done
  ```
- [ ] Logger dans [CHANGELOG.md](../CHANGELOG.md) la version finale

## Quand reporter un update

- ⛔ Pas d'update si vzdump < 24h pas dispo
- ⛔ Pas d'update si on est en plein événement famille (vacances, dîner, etc.)
- ⛔ Pas d'update sur HAOS si une automation critique va déclencher dans la prochaine heure (ex : alarme, chauffage)
