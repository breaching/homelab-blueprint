# Runbook - Créer un nouveau LXC standardisé

## Décision : LXC ou VM ?

| Critère | LXC | VM |
|---------|-----|-----|
| Léger en RAM/CPU | ✅ | ❌ |
| Démarrage rapide | ✅ (sec) | ❌ (min) |
| Kernel custom (HAOS, Talos, etc.) | ❌ | ✅ |
| Docker en interne | ⚠ (nesting=1 + privilégié recommandé) | ✅ |
| Passthrough hardware (GPU, USB, PCI) | ⚠ (cgroup config) | ✅ (proprement) |
| Snapshot rapide | ✅ (LVM-thin) | ✅ (LVM-thin) |

→ Par défaut : **LXC**. VM si pas le choix.

## Méthode 1 - community-scripts (recommandé)

Beaucoup de services sont disponibles : https://community-scripts.org/ProxmoxVE/

```bash
# Sur le host PVE :
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/<service>.sh)"
```

Suivre le wizard. Pour un setup standard du lab :
- Storage rootfs : `local-lvm` (rapide, snapshot natif)
- Network : DHCP (à fixer ensuite - voir étape "post-création")
- Tags : `community-script;<role>`

## Méthode 2 - manuel

```bash
# Choisir un VMID libre
pvesh get /cluster/nextid

# Créer le LXC
pct create <VMID> /var/lib/vz/template/cache/debian-12-standard_*.tar.zst \
  --hostname <NAME> \
  --cores 2 \
  --memory 1024 \
  --swap 512 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,firewall=1 \
  --features nesting=1 \
  --unprivileged 1 \
  --onboot 1 \
  --tags custom

pct start <VMID>
pct enter <VMID>
# Update + setup app...
exit
```

## Post-création - étapes obligatoires

### 1. Identifier l'IP

```bash
pct exec <VMID> -- ip a | grep "inet " | grep -v 127.0.0.1
```

### 2. Convertir en IP statique (recommandé pour services exposés)

```bash
pct stop <VMID>
pct set <VMID> -net0 name=eth0,bridge=vmbr0,ip=192.168.68.<X>/24,gw=192.168.1.1,hwaddr=<MAC>,type=veth
pct start <VMID>
```

> Choisir un X libre dans la range homelab (cf. [docs/03-network.md](../docs/03-network.md)).

### 3. Documenter

Ajouter une ligne dans [docs/02-inventory.md](../docs/02-inventory.md) avec :
- VMID, name, OS, vCPU, RAM, disk, storage, IP, MAC, privilégié, onboot, notes

### 4. Si exposé via Traefik

Suivre [add-new-service.md](add-new-service.md).

### 5. Si stocke de la data importante

- Vérifier que le LXC est inclus dans le job vzdump (`/etc/pve/jobs.cfg`, `--all` ou liste)
- Confirmer le backup le lendemain dans `/mnt/backup-ssd/dump/vzdump-lxc-<VMID>-*.tar.zst`

### 6. Si nécessite hardware passthrough

Voir les exemples existants dans [docs/02-inventory.md](../docs/02-inventory.md) "Détails passthrough" :
- iGPU : LXC 101 (frigate) ou 106 (immich)
- NVIDIA GPU : LXC 114 (servarr)
- USB : VM 102 (HAOS), LXC 101 (frigate)

> ⚠️ Privilégié vs unprivileged : certains passthroughs nécessitent du privilégié. Documenter pourquoi.

## Conventions

| Item | Convention |
|------|-----------|
| Hostname | minuscules, sans tirets si possible (ex : `immich`, `traefik`, `nas-files`) |
| Tags | `community-script;<role>` ou `custom;<role>` |
| Memory | minimum confortable + 50% - pas overkill |
| Disk rootfs | démarrer petit (2-8G), agrandir si besoin (`pct resize`) |
| swap | `512` par défaut |
| `features` | `nesting=1` toujours, `keyctl=1` si nginx/systemd-resolved en jeu |
| `onboot` | `1` sauf si dépendance dev (NPM par ex à `0`) |

## Limites par défaut à activer

```yaml
# /etc/pve/lxc/<VMID>.conf
cores: 2
memory: 1024
# Optionnel : limites I/O
# blkio.throttle...
```

> Phase 1.5 : audit de toutes les limites + ajouter `cpulimit` si besoin.
