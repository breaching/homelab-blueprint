# Runbook - Workflow LAN-first → Hetzner avec aval manuel

Process pour développer en sécurité sur LAN puis pousser en prod sur Hetzner avec ton click explicite. Évite de pousser une régression directement en production.

## Modèle : 2 apps Coolify par projet

Pour chaque projet (perso non-trivial ou client), créer **2 applications** dans Coolify, pull du **même repo Git** :

| App | Server | Branch | FQDN | Auto-deploy |
|---|---|---|---|---|
| `<projet>-dev` | `localhost` (VM 300) | `main` (ou `develop` si workflow plus strict) | `<projet>.home.example.com` (LAN) | ✅ ON |
| `<projet>-prod` | `hetzner-shared-1` | `main` | `<client>.com` (CF Tunnel) ou `<projet>.example.com` | ❌ OFF |

→ Les push GitHub triggent le webhook qui frappe **les 2 apps**. Mais seule l'app `dev` rebuild auto. L'app `prod` reste en attente d'un Deploy manuel.

## Étape 1 - Créer l'app dev (LAN)

Suivre [`deploy-perso-app.md`](deploy-perso-app.md). Domain : `http://<projet>.home.example.com`.

Ajouter le router dans `configs/traefik/coolify-apps.yml`.

## Étape 2 - Créer l'app prod (Hetzner)

### Si client a son propre domaine

1. CF Dashboard → tunnel `hetzner-prod` (créé pour `prod-test.example.com`, voir CHANGELOG 2026-05-06) → **Add public hostname** : `<client>.com` → HTTP `localhost:80`. CF auto-crée le CNAME (overwrite si record existant - backup avant).
2. Coolify → **+ New Resource → Application** → même repo, branch `main`, base directory pareil → **server `hetzner-shared-1`** → Continue.
3. Settings :
   - Domain : `http://<client>.com` (ou plusieurs : `http://<client>.com`, `http://www.<client>.com`)
   - **Auto deploy on push : OFF** ⚠ (toggle dans General → Settings)
   - Build vars : pareil que l'app dev (mais peut-être valeurs différentes : Sentry env=production, PostHog différent token, etc.)
   - Healthcheck : pareil

### Si projet perso sans domaine externe

Domain prod = `https://<projet>.example.com` (ou autre sous-domaine de ton domaine perso). Sinon même process.

### Pourquoi 2 apps et pas 1

Coolify v4 n'a pas de notion d'environnements (dev/staging/prod) sur 1 app. Pour avoir des configs différentes (server, FQDN, env vars, branches, auto-deploy on/off), faut 2 apps distinctes.

## Workflow quotidien

```
Tu push sur main
   │
   ▼
GitHub fire le webhook → CF Tunnel → Coolify
   │
   ├─► <projet>-dev (auto deploy ON) → rebuild + deploy
   │     → Live sur https://<projet>.home.example.com en 1-3 min
   │     → Toi (et client si autorisé) review sur LAN
   │
   └─► <projet>-prod (auto deploy OFF) → reçoit le webhook mais ATTEND
         → Tu valides manuellement ce qui s'est buildé sur dev
         → Click "Deploy" dans Coolify UI prod app
         → Build + deploy → Live sur https://<client>.com
```

## Comment désactiver l'auto-deploy sur l'app prod

Dans Coolify UI → app prod → **General → Webhooks** (ou Configuration selon version) → toggle **"Auto deploy on push"** → OFF → Save.

L'app continuera de recevoir les webhooks (visible dans Deployments tab : statut `pending` ou `webhook-received`) mais ne lancera pas de build sans ton click.

## Comment "approuver" et déployer en prod

Une fois que tu as validé sur dev :
1. Coolify → app `<projet>-prod` → bouton **Deploy** (top right)
2. Coolify build + rolling update sur Hetzner
3. Site live en 2-3 min

## Rollback prod

Si la prod merde après deploy :
1. Coolify → app prod → **Deployments** tab
2. Trouve un deployment `finished` antérieur stable → click **Redeploy** dessus
3. Coolify rebuild ce SHA spécifique → rolling update

Temps de rollback : ~2 min (le temps du build + healthcheck).

Si urgent et besoin instant : flip DNS CF vers Vercel/staging (si encore dispo) en attendant.

## Checklist par projet

À cocher en début de mise en place :

- [ ] App dev créée sur `localhost`, FQDN `http://<projet>.home.example.com`, auto-deploy ON
- [ ] Router ajouté dans `configs/traefik/coolify-apps.yml` + scp+pct push vers LXC 103
- [ ] App prod créée sur `hetzner-shared-1`, FQDN `http://<client>.com`, auto-deploy **OFF**
- [ ] CF Tunnel `hetzner-prod` Public Hostname ajouté pour `<client>.com`
- [ ] CF DNS records flippés vers le tunnel (ou délégation au CNAME tunnel)
- [ ] Build vars copiées dev → prod (avec valeurs prod-spécifiques pour Sentry/PostHog/etc.)
- [ ] Healthcheck configurée des 2 côtés (mêmes valeurs sauf si différent)
- [ ] Premier deploy manuel prod → smoke test
- [ ] Ancien hébergement (Vercel/Netlify/whatever) gardé 7 jours en fallback DNS

## Conventions de nommage

- **Repo GitHub** : `<projet>` (ex. `my-portfolio`, `acme-website`)
- **App Coolify dev** : `<projet>-dev`
- **App Coolify prod** : `<projet>-prod`
- **FQDN dev** : `<projet>.home.example.com` (LAN)
- **FQDN prod client** : `<client>.com` (le vrai)
- **FQDN prod perso** : `<projet>.example.com` (si projet perso pour vitrine)
