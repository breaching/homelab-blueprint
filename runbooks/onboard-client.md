# Runbook - Onboarder un nouveau client

Process pour héberger un nouveau projet client. Suit le tier model défini dans [`docs/11-coolify.md`](../docs/11-coolify.md).

## Pré-onboarding

### Légal
- [ ] Contrat de prestation signé
- [ ] DPA (Data Processing Agreement) si client traite données utilisateurs UE
- [ ] Right-to-deletion (RGPD) documenté

### Tech
- [ ] Vérifier que le client maîtrise sa zone DNS (Cloudflare idéal - sinon on peut migrer la zone chez CF gratuitement)
- [ ] Évaluer la charge attendue (sites vitrine = mutualisé, app SaaS avec DB = dédié)
- [ ] Définir SLA (uptime, support response time)
- [ ] Décider tier (voir ci-dessous)

### Tier de hosting

| Tier | Ressource | Quand | Coût pour toi | Refacturé |
|---|---|---|---|---|
| **Mutualized** | App sur `hetzner-shared-1` (CX 23) | Sites vitrine, blog, petite app peu chargée. Defaut pour 80% des cas | ~5€/mois pour ~10-15 sites | ~5€ "infra" / mois / client |
| **Dedicated** | VPS Hetzner dédié (CX 23-CX 33+) | Charge sustained, isolation contractuelle, secteur sensible | ~5-15€/mois (selon size) | ~15-30€ "infra" / mois |
| **Multi-tier** | App + DB dédiée + backup B2 dédié | Critique business, audit obligatoire | Variable | Variable, sur devis |

## Étapes - Tier Mutualized (default)

### 1. Création du repo

- Si le repo est sur ton GitHub : ajouter au scope de la GitHub App Coolify (`tame-teira-...`).
- Si le repo est sur le GitHub du client : créer une nouvelle GitHub App ou utiliser une PAT/Deploy Key avec accès en lecture.

### 2. Setup Cloudflare Tunnel ingress

CF Dashboard → tunnel `hetzner-prod` → **Add public hostname** :
- Subdomain : `(vide)` pour apex `client.com`, `www` pour `www.client.com`, etc.
- Domain : `<client>.com`
- Service : HTTP `localhost:80`

Pour chaque hostname (ex. apex + www → 2 entries).

⚠ Si la zone DNS du client est sur CF mais le client ne veut pas qu'on touche à sa zone : demander qu'il ajoute manuellement les CNAMEs vers `<tunnel-id>.cfargotunnel.com`. Ou qu'il valide explicitement avant qu'on flip.

### 3. Création des apps Coolify

Suivre le workflow de [`promote-staging-to-prod.md`](promote-staging-to-prod.md) :
- App `<client>-dev` sur `localhost`, FQDN `<client>.home.example.com`
- App `<client>-prod` sur `hetzner-shared-1`, FQDN `<client>.com`, auto-deploy **OFF**

Suivre [`deploy-perso-app.md`](deploy-perso-app.md) pour les détails (Dockerfile, healthcheck, env vars).

### 4. Setup Uptime Kuma monitor

Sur VM 117 (Uptime Kuma sur :9000) :
- Add monitor → HTTP(S)
- URL : `https://<client>.com`
- Interval : 60s
- Notification : ton email
- (Si SLA contractuel) public status page partagée avec le client

### 5. Setup backups

Si le client a une DB :
- Backup dump quotidien via Coolify Scheduled Tasks ou cron côté serveur
- Push vers Backblaze B2 (Phase 4 roadmap - à compléter)
- Test restore mensuel

Si juste static :
- Backup le repo Git suffit (déjà sur GitHub)

### 6. Documentation interne

⚠ **JAMAIS dans le repo `youruser/homelab-blueprint`** (qui peut potentiellement contenir des éléments publiables un jour).

À stocker dans Bitwarden Secure Note (ou un Notion/doc privé) :
- Nom du client + contact + email
- Domaines + zones DNS gérées
- API tokens client (Cloudflare account, Stripe, etc.)
- SLA + tarification + facturation
- Checklist offboarding

### 7. Handoff au client

Donner au client :
- URL prod (`https://<client>.com`) - devrait déjà répondre
- URL staging si applicable (`<client>.home.example.com` - pas accessible internet, mais on peut leur partager via screenshare ou screenshots)
- Email de contact pour incidents
- (Optionnel) Accès Coolify read-only à leur projet - Coolify v4 supporte les teams

## Étapes - Tier Dedicated

Différences vs mutualized :

### 1. Provisionner un VPS dédié

Coolify UI → Servers → **+ New → Hetzner Cloud** :
- Token API Hetzner (le tien)
- Type : CX 23 (4 GB) ou CX 33 (8 GB) selon charge prévue
- Localisation : Falkenstein FSN1 (default)
- Nom : `hetzner-<client-slug>` (ex. `hetzner-acme`)
- Image : Ubuntu 24.04 LTS
- Private Key : `coolify-hetzner-default` (réutiliser)

### 2. Cloudflared dédié sur ce VPS

Soit CF Tunnel partagé (`hetzner-prod` avec ingress par hostname), soit tunnel dédié :
- Tunnel partagé : plus simple, 1 seul cloudflared à gérer, ingress séparées par client
- Tunnel dédié : isolation network plus stricte, recommandé si secteur sensible

Si dédié → suivre la même procédure que pour `hetzner-shared-1` (cf. CHANGELOG 2026-05-06).

### 3. Resource limits + backup dédiés

Configurer dans Coolify UI :
- Memory limit / CPU limit du container client
- Backup destination dédiée si client veut séparation contractuelle

## Offboarding

À documenter quand on aura le 1er offboarding (probablement quelqu'un qui change de prestataire ou cesse activité).

Outline :
- [ ] Backup final des données client (DB, fichiers user)
- [ ] Push backup vers le client (chiffré, méthode convenue)
- [ ] Stop containers Coolify
- [ ] Delete apps Coolify (après période grace ~30 jours)
- [ ] Remove CF Tunnel ingress
- [ ] Remove DNS records (ou les rendre au client)
- [ ] Si dédié : delete le VPS Hetzner
- [ ] Update Bitwarden : marquer le client comme offboarded + date
- [ ] Effacer les copies de données client après période rétention RGPD

## Checklist rapide

### Pour onboarder
- [ ] Contrat + DPA signés
- [ ] Tier décidé
- [ ] Repo accessible
- [ ] Tunnel CF ingress configuré
- [ ] App dev + prod créées
- [ ] Premier deploy manuel prod réussi
- [ ] Smoke test browser
- [ ] Uptime Kuma monitor actif
- [ ] Backup configuré (si applicable)
- [ ] Doc interne dans Bitwarden
- [ ] Client a reçu accès / URL / contact
