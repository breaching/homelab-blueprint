# Runbook - Ajouter un service à Traefik

> Ajouter un service `<NEW>` au reverse proxy en < 5 minutes.

## Pré-requis

- Le service tourne déjà dans un LXC ou VM avec une IP joignable
- Tu connais le port HTTP(S) du service
- Tu as choisi un nom court : `<NEW>` (ex : `vault`, `wiki`, `n8n`)

## Étapes

### 1. Vérifier que le backend répond

```bash
curl -kI http://<IP>:<PORT>/    # ou https si self-signed
# Attendu : un code HTTP, pas un timeout
```

### 2. Choisir le bon group file

Routes regroupées par usage dans `configs/traefik/conf.d/` :

| Fichier | Quand l'utiliser |
|---------|------------------|
| `admin.yml` | Outils d'admin (proxmox, dashboards, IdP) |
| `data.yml` | Apps data (immich, grafana, file storage) |
| `home.yml` | Domotique (homeassistant) |
| `media.yml` | Stack media (jellyfin, *arr) |

→ Crée un nouveau fichier si aucun ne colle.

### 3. Ajouter la route

Éditer le fichier dans `/etc/traefik/conf.d/` du LXC 103, par exemple :

```bash
pct exec 103 -- nano /etc/traefik/conf.d/data.yml
```

Ajouter sous `http.routers` :

```yaml
    <NEW>:
      rule: "Host(`<NEW>.home.example.com`)"
      entryPoints:
        - websecure
      service: <NEW>
      tls:
        certResolver: cloudflare
        domains:
          - main: home.example.com
            sans:
              - "*.home.example.com"
```

Et sous `http.services` :

```yaml
    <NEW>:
      loadBalancer:
        servers:
          - url: "http://<IP>:<PORT>"
```

#### Cas backend HTTPS self-signed

Ajouter `serversTransport: insecure` :

```yaml
    <NEW>:
      loadBalancer:
        serversTransport: insecure
        servers:
          - url: "https://<IP>:<PORT>"
```

> Le ServersTransport `insecure` est défini globalement dans `traefik.yaml`.

### 4. Sauvegarder, Traefik reload auto

Le file provider est en `watch: true`. La modif prend effet en quelques secondes.

Vérifier :
```bash
pct exec 103 -- journalctl -u traefik -n 30 --no-pager | tail -20
# Pas d'erreur ? OK.
```

### 5. Tester

```bash
curl -I https://<NEW>.home.example.com
# Attendu : 200 / 301 / 302
```

Depuis un browser sur le LAN :
- `https://<NEW>.home.example.com` doit charger l'app avec un cert valide ✅

### 6. Mettre à jour la doc

- [ ] Ajouter une entrée dans [docs/06-services.md](../docs/06-services.md)
- [ ] Si nouveau LXC/VM : ajouter dans [docs/02-inventory.md](../docs/02-inventory.md)
- [ ] Copier le fichier Traefik mis à jour vers `configs/traefik/conf.d/<group>.yml` du repo
- [ ] Commit + push

```bash
# Sur ta machine locale (où le repo est cloné)
scp root@192.168.1.90:/etc/traefik/conf.d/data.yml configs/traefik/data.yml
git add configs/traefik/data.yml docs/06-services.md
git commit -m "feat(traefik): add <NEW> route"
git push
```

## Diagnostic si ça ne marche pas

| Symptôme | Cause probable | Fix |
|----------|----------------|-----|
| `404 page not found` | Host header pas matché | Vérifier l'orthographe `Host(...)` |
| `Bad gateway` | backend pas joignable | `curl http://<IP>:<PORT>` depuis LXC 103 (`pct exec 103 -- curl ...`) |
| Cert invalide | Race condition au premier load | Reload Traefik : `pct exec 103 -- systemctl restart traefik` |
| `<NEW>.home.example.com` ne résout pas | AdGuard pas pris en compte par le client | Vérifier DNS du client (`nslookup <NEW>.home.example.com`) |

## Cas spéciaux

### Service avec WebSocket (ex : Jellyfin, HAOS)

Traefik supporte WS/WSS nativement, **rien à ajouter** dans la plupart des cas. Si l'app casse en WS :

```yaml
    <NEW>:
      rule: "Host(`<NEW>.home.example.com`)"
      ...
      middlewares:
        - <NEW>-ws-headers

http:
  middlewares:
    <NEW>-ws-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: https
```

### Service avec assets sur path (ex : `/grafana/`)

Si l'app sert des liens absolus type `/static/...` qui doivent rester sur le subdomain root, **pas de PathPrefix**. Préférer un subdomain dédié.

### Service à exposer + protéger par Authentik

Phase 2 : ajouter le middleware `authentik@file` sur la route. Doc à venir dans `runbooks/setup-authentik-forward-auth.md`.
