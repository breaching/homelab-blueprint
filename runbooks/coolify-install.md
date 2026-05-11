# Runbook - Installer Coolify sur Proxmox (VM 300)

> Procédure d'installation manuelle d'une VM Ubuntu 24.04 cloud + Coolify, avec les pièges identifiés lors de la 1ère tentative (2026-05-05).

## Contexte

- VM 300 dédiée à Coolify (orchestration self-host)
- Image cloud Ubuntu 24.04 LTS (`noble-server-cloudimg-amd64.img`)
- Stockage `usbssd` (T7 Shield, 80 G alloués)
- Boot UEFI (OVMF)

## ⚠️ Lessons learned (1ère + 2ème tentatives, 2026-05-05)

| # | Piège | Symptôme | Fix |
|---|-------|----------|-----|
| 1 | `vga: serial0` sur image cloud Ubuntu | Cloud-init n'écrit jamais sur tty1 → pas de DHCP IP, qga timeout | **Utiliser `vga: std`** dès la création |
| 2 | Cloud-init non vérifié avant SSH | On attend SSH, mais boot a échoué silencieusement | **Toujours valider le boot via UI Proxmox console (noVNC) avant d'attendre SSH** |
| 3 | Pas de console de fallback | Aucun moyen de debug si SSH down | Ajouter `serial0: socket` **en plus** de `vga: std` (pas en remplacement) |
| 4 | MAC aléatoire générée par PVE → la réservation UCG ne matche pas | DHCP attribue une IP autre que `.252` | **Forcer la MAC** dans `--net0 virtio=02:00:00:00:00:1d,bridge=vmbr0` |
| 5 | `--tags coolify;custom` non quoté | Bash interprète `;` comme séparateur, tag non posé | **Toujours quoter** : `--tags "coolify;custom"` |
| 6 | `qemu-guest-agent` absent de l'image Ubuntu cloud `noble` | `qm guest cmd ...` retourne "QEMU guest agent is not running" même boot OK | `apt install -y qemu-guest-agent` post-boot (cf. étape 5b) |
| 7 | `qm resize ... 80G` peut timeout sur disque RAW | Le fichier disque atteint la bonne taille mais le metadata Proxmox reste à l'ancienne valeur | Lancer `qm rescan --vmid 300` pour resync metadata ↔ filesystem |

## Pré-requis

- Image Ubuntu 24.04 cloud déjà téléchargée :
  ```bash
  ls /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img
  # Si absent :
  cd /var/lib/vz/template/iso/
  wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  ```
- Clés SSH publiques (RSA + ed25519) dans un fichier :
  ```bash
  cat > /tmp/coolify-sshkeys <<'EOF'
  ssh-ed25519 AAAA... user@hostname
  ssh-rsa AAAA... user@hostname
  EOF
  chmod 600 /tmp/coolify-sshkeys
  ```

## Procédure

### 1. Créer la VM 300

```bash
qm create 300 \
  --name coolify \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --efidisk0 usbssd:0,efitype=4m \
  --scsihw virtio-scsi-single \
  --net0 virtio=02:00:00:00:00:1d,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1 \
  --vga std \
  --serial0 socket \
  --onboot 1 \
  --tags "coolify;custom"
```

> **Important** :
> - `--vga std` (pas `serial0`). Garder `serial0: socket` en parallèle pour avoir une console de fallback.
> - **MAC explicite** `02:00:00:00:00:1d` pour matcher la réservation Fixed IP `.252` côté UCG Ultra. Sans ça, PVE génère une MAC aléatoire et le DHCP donne une IP arbitraire.
> - **Quoter le tag** `"coolify;custom"` - sinon bash interprète `;` comme séparateur de commande.

### 2. Importer le disque cloud

```bash
qm importdisk 300 /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img usbssd
qm set 300 --scsi0 usbssd:300/vm-300-disk-1.raw,discard=on,ssd=1
qm resize 300 scsi0 80G
qm set 300 --boot order=scsi0

# ⚠ Si `qm resize` retourne "got timeout", le fichier disque est bien à 80G
# mais le metadata Proxmox reste à l'ancienne taille. Resync :
qm rescan --vmid 300
qm config 300 | grep '^scsi0'   # vérifier size=80G
```

### 3. Cloud-init

```bash
# Ajouter le drive cloud-init
qm set 300 --ide2 usbssd:cloudinit

# Configurer
qm set 300 --ciuser ubuntu --sshkeys /tmp/coolify-sshkeys
qm set 300 --ipconfig0 ip=dhcp     # ou ip=192.168.1.252/24,gw=192.168.1.1
qm cloudinit update 300
```

> **IP réservée côté UCG Ultra** : `192.168.1.252` (Fixed, MAC `02:00:00:00:00:1d`).
> Avec `ip=dhcp`, le UCG attribue automatiquement cette IP grâce à la réservation MAC.
> Pour forcer en static côté VM (defense in depth) :
> ```bash
> qm set 300 --ipconfig0 ip=192.168.1.252/24,gw=192.168.1.1
> ```

### 4. Démarrer + valider le boot

```bash
qm start 300

# IMMÉDIATEMENT - vérifier le boot via console
# Dans l'UI Proxmox : VM 300 → Console (noVNC)
# Tu dois voir le boot Ubuntu, puis cloud-init logs, puis le prompt login
# Si écran noir : le vga est mal configuré → stop, fix, retry
```

Attendre 1-2 minutes que cloud-init finisse. Vérifier l'IP :

```bash
qm guest cmd 300 network-get-interfaces 2>/dev/null
# OU si qga pas prêt :
arp -an | grep -i "$(qm config 300 | grep -oP 'virtio=\K[^,]+')"
```

### 5. SSH dans la VM

```bash
ssh ubuntu@192.168.1.252   # ou IP attribuée
# Si "Permission denied (publickey)" → cloud-init n'a pas appliqué les SSH keys
# Vérifier : `cat /var/log/cloud-init-output.log` via console
```

### 5b. Installer qemu-guest-agent

L'image cloud `noble` ne contient PAS `qemu-guest-agent` malgré le flag `--agent=1`.
À installer dans la VM dès que SSH répond :

```bash
sudo apt-get update -qq
sudo apt-get install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
# Côté PVE, vérifier :
qm guest cmd 300 network-get-interfaces | head
```

### 6. Installer Coolify

```bash
# DANS la VM
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

L'installeur :
- Installe Docker + Compose
- Setup la base Coolify (Postgres + Redis + Traefik interne)
- Démarre les services
- Affiche l'URL d'accès (par défaut http://<IP>:8000)

### 7. Configuration initiale via UI

1. Ouvrir http://192.168.1.252:8000 dans un navigateur LAN
2. Créer le compte admin (email + mot de passe fort → **stocker dans Bitwarden**)
3. Configurer SSH server : ajouter `localhost` comme premier serveur
4. Tester un déploiement minimal (image Docker hello-world)

### 8. Exposer via Traefik

Sur le LXC 103 (Traefik), éditer `/etc/traefik/conf.d/admin.yml` (Coolify = service infra, pas un fichier dédié) et ajouter **2 routers** + 2 services :

```yaml
routers:
  coolify:
    rule: "Host(`coolify.home.example.com`)"
    entryPoints: [websecure]
    service: coolify
    tls:
      certResolver: cloudflare
      domains:
        - main: home.example.com
          sans: ["*.home.example.com"]

  coolify-ws:
    rule: "Host(`coolify.home.example.com`) && (PathPrefix(`/app/`) || PathPrefix(`/apps/`))"
    entryPoints: [websecure]
    service: coolify-ws
    tls:
      certResolver: cloudflare
      domains:
        - main: home.example.com
          sans: ["*.home.example.com"]

services:
  coolify:
    loadBalancer:
      servers:
        - url: "http://192.168.1.252:8000"
  coolify-ws:
    loadBalancer:
      servers:
        - url: "http://192.168.1.252:6001"
```

> ⚠ **`/app/` et `/apps/` avec slash final obligatoire**. Sans le slash, Traefik fait du byte-prefix matching et `/applications` (UI Coolify) est mal routé vers Soketi → 404 partout dans l'UI.

Ajouter ensuite dans `/data/coolify/source/.env` (sur la VM) :

```bash
APP_URL=https://coolify.home.example.com
PUSHER_HOST=coolify.home.example.com
PUSHER_PORT=443
PUSHER_SCHEME=https
```

Puis recreate le container coolify pour charger les nouvelles vars :

```bash
sudo bash -c "cd /data/coolify/source && \
  docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --force-recreate coolify"
```

Sans ces 4 vars, l'UI affiche le warning « Cannot connect to real-time service » même si le routing Traefik est correct (le JS client tape sur la mauvaise URL).

### 9. Documenter

- [ ] Mettre à jour [docs/02-inventory.md](../docs/02-inventory.md) - ajouter VM 300
- [ ] Mettre à jour [docs/06-services.md](../docs/06-services.md) - ajouter `coolify.home.example.com` + route WS
- [ ] Copier `admin.yml` à jour dans `configs/traefik/`
- [ ] Update CHANGELOG

## Diagnostic

### Boot ne finit pas

```bash
# Console Proxmox (noVNC) → voir où ça plante
# Souvent : pas de DHCP, pas de cloud-init, pas de tty1
# → vérifier vga: std (pas serial0), efidisk0 présent
```

### SSH refuse la clé

```bash
# Via console Proxmox, login en console (cloud-init ne crée pas de mdp par défaut)
# → impossible : il faut soit
#    1. Re-créer la VM avec un --cipassword (déconseillé)
#    2. Ré-importer disque + relancer cloud-init avec sshkeys correctes
```

### Cloud-init stuck

```bash
# Via console
sudo journalctl -u cloud-init -n 200
sudo cat /var/log/cloud-init-output.log
```

### Coolify install échoue

```bash
# Sur la VM
curl -v https://cdn.coollabs.io/coolify/install.sh | head -50
# Vérifier l'accès internet sortant + DNS
# Vérifier docker (curl -fsSL https://get.docker.com | sh si manquant)
```

## Rollback

```bash
qm stop 300
qm destroy 300 --purge
# Puis recommencer à l'étape 1
```

## Post-install - étapes suivantes

Voir [docs/11-coolify.md](../docs/11-coolify.md) section "Reliquats / TODO" pour la suite (Mealie test, premier VPS Hetzner, etc.).
