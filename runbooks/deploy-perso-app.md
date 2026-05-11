# Runbook - Déployer une app perso sur Coolify localhost (LAN-only)

Pattern validé pour les projets perso (portfolio, expérimentations, outils). Sert sur un sous-domaine `*.home.example.com` accessible uniquement depuis le LAN.

Pour les projets clients (production publique sur Hetzner + tunnel CF), voir [`onboard-client.md`](onboard-client.md). Pour le workflow dev (localhost) → prod (Hetzner) avec aval manuel, voir [`promote-staging-to-prod.md`](promote-staging-to-prod.md).

## Pré-requis

- Repo GitHub accessible par la GitHub App Coolify (`tame-teira-...`, voir `docs/11-coolify.md`)
- Server `localhost` opérationnel dans Coolify (VM 300)
- Sous-domaine `<sub>.home.example.com` libre (pas en collision avec services existants)
- Repo a un `Dockerfile` à la racine du base directory (ou Nixpacks détecté correctement)

## Procédure

### 1. Pré-ajouter le router Traefik LXC 103

Édite `configs/traefik/coolify-apps.yml` (dans le repo) → ajoute un router :

```yaml
http:
  routers:
    <sub>-app:
      rule: "Host(`<sub>.home.example.com`)"
      entryPoints:
        - websecure
      service: coolify-apps-http   # voir choix ci-dessous
      tls:
        certResolver: cloudflare
        domains:
          - main: home.example.com
            sans:
              - "*.home.example.com"
```

**Choix du service** :
- `coolify-apps-http` (port 80 de coolify-proxy) → si l'app sera créée d'origine en `http://` dans Coolify (recommandé)
- `coolify-apps-https` (port 443 + insecureSkipVerify) → si l'app a été créée en `https://` puis FQDN changé (legacy / cas exceptionnels)

Push + scp le file vers LXC 103 :

```bash
scp configs/traefik/coolify-apps.yml root@192.168.1.90:/tmp/
ssh root@192.168.1.90 "pct push 103 /tmp/coolify-apps.yml /etc/traefik/conf.d/coolify-apps.yml && rm /tmp/coolify-apps.yml"
```

Traefik recharge auto via file provider. Pas besoin de restart.

### 2. Créer l'app dans Coolify UI

**+ New Resource → Application** dans le projet de ton choix :

| Champ | Valeur |
|---|---|
| Source | GitHub App `tame-teira-...` |
| Repository | `youruser/<repo>` |
| Branch | `main` |
| Base Directory | `/` (ou sous-dossier si monorepo, ex. `/frontend`) |
| Build Pack | **Dockerfile** (préféré - plus reproductible que Nixpacks) |
| Destination Server | `localhost` |

→ Continue.

### 3. Settings de l'app

| Section | Valeur |
|---|---|
| **Domains** | **`http://<sub>.home.example.com`** ⚠ (HTTP pas HTTPS - sinon coolify-proxy tente Let's Encrypt qui échoue en LAN) |
| **Ports Exposes** | Port que ton container écoute réellement (ex. `3000` Next.js, `8000` FastAPI). Coolify peut auto-injecter `PORT=3000` à runtime, vérifier que ton Dockerfile y est aligné (sinon hardcode le port dans le CMD ou set ENV). |
| **Build-time Env vars** | Cocher "Build Time" sur les `NEXT_PUBLIC_*` ou autres vars inlinées au build. Vars runtime (DB URLs, API keys lus à l'exec) → décocher. |
| **Healthchecks** | Voir section dédiée ci-dessous |

### 4. Healthcheck (recommandé)

Coolify exécute la check via curl/wget dans le container. Pré-requis : `curl` ou `wget` doivent exister dans l'image.

| Champ | Valeur typique |
|---|---|
| Type | `HTTP` |
| Method | `GET` |
| Scheme | `http` |
| **Host** | **`127.0.0.1`** ⚠ (pas `localhost` - éviter le pièegé IPv6 :: → connection refused sur image alpine) |
| Port | port interne du container (3000, 8000, …) |
| Path | endpoint léger qui retourne 200 sans auth (ex. `/favicon.ico`, `/openapi.json`, `/health`) |
| Status code | `200` |
| Response Text | **VIDE** (sinon doit grep une string spécifique dans le body) |
| Interval | `30` |
| Timeout | `5` |
| Retries | `3` |
| Start Period | `30` (ou `60` pour app lourde - Python + libs natives) |

**Watch-out par image** :
- `node:22-alpine` : a `wget` (busybox), pas `curl` → check OK avec `Host=127.0.0.1`
- `python:3.12-slim` : ni `curl` ni `wget` → ajouter `curl` dans `apt-get install` du Dockerfile
- Image custom avec middleware blacklistant `curl`/`wget` UA (ex. `proxy.ts` Next) → utiliser un path exclu du middleware (ex. `/favicon.ico` ou `/_next/static/...`)

### 5. Deploy

Click **Deploy** → tail les logs Coolify (Deployments → live).

Étapes attendues :
- Git clone (commit SHA du HEAD branche `main`)
- Docker build (npm ci + npm run build pour Next, ou pip install pour Python, etc.)
- Container start
- Healthcheck pass après start period
- Rolling update : nouveau container healthy → ancien stop

Tu vois `(healthy)` dans `docker ps` côté VM 300.

### 6. Test final

Depuis n'importe quel device LAN : `https://<sub>.home.example.com` → app charge avec cert wildcard valide.

### 7. Auto-deploy sur push

Auto activé par défaut si Source = GitHub App. À chaque push sur `main` :
1. GitHub fire un webhook sur `coolify.home.example.com/webhooks/source/github/events/<uuid>`
2. CF Tunnel route → Coolify reçoit + queue un deploy
3. Build + rolling update en 1-3 min

Pour désactiver l'auto-deploy : app Settings → toggle "Auto deploy on push" OFF (utile pour les apps prod, voir `promote-staging-to-prod.md`).

## Pièges connus

| Symptôme | Cause | Fix |
|---|---|---|
| `Please select a webhook endpoint` quand tu crées la GitHub App | `instance_settings.fqdn` pas configuré | UI Settings → Configuration → Instance Domain = `https://coolify.home.example.com` |
| Healthcheck `curl: not found` | Image runtime n'a pas curl | Patch Dockerfile (apt install curl) ou disable healthcheck |
| Healthcheck `wget: connection refused` | `Host=localhost` résout en IPv6 ::1 mais l'app bind sur 0.0.0.0 (IPv4 only) | Changer `Host` → `127.0.0.1` |
| Site sert du 302 vers https en boucle infinie | App créée en `https://` puis FQDN changé en `http://` - labels Coolify ont gardé `redirect-to-https` middleware | Recréer l'app fresh en `http://` d'origine, OU utiliser `coolify-apps-https` service dans coolify-apps.yml |
| `https://<sub>.home.example.com` retourne `no available server` | Container expose pas le port que Coolify pense, OU container down | Vérifier `Ports Exposes` Coolify == port réel du container. Vérifier `docker ps` côté VM 300. |
| Container démarre mais `Coolify port 8000 mais container sur 3000` | Coolify injecte auto `PORT=3000` à runtime, override `ENV PORT=8000` du Dockerfile | Mettre `Ports Exposes=3000` dans Coolify, OU set env var `PORT=8000` dans Coolify (override le default), OU hardcode port dans Dockerfile CMD |

## Maj de la doc après déploiement

- `docs/02-inventory.md` : ajouter une ligne dans la table app si jamais elle prend des ressources notables
- `docs/06-services.md` : ajouter la route + brève description du service
- `configs/traefik/coolify-apps.yml` : commit le router (déjà fait à l'étape 1)
- `CHANGELOG.md` : entrée Added avec date

## Rollback / cleanup

Pour supprimer l'app :
1. Coolify UI → app → Danger → Delete (delete container + image)
2. Retirer le router de `configs/traefik/coolify-apps.yml` + scp + ssh push vers LXC 103
3. Update docs
