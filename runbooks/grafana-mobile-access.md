# Grafana mobile access - exposer le dashboard "My Day Homelab" au téléphone

> Objectif : ouvrir https://grafana.home.example.com depuis 4G hors LAN et bookmark le dashboard `my-day-homelab` sur l'écran d'accueil. Optionnel : app Grafana iOS/Android.

## État actuel (LAN-only)

- Grafana tourne sur LXC 108 (`192.168.1.85:3000`)
- Traefik LXC 103 expose `grafana.home.example.com` en TLS via cert wildcard
- AdGuard rewrite `*.home.example.com → 192.168.1.165` (Traefik) pour résolution LAN
- DNS public → `grafana.home.example.com` n'existe pas → inaccessible hors LAN

## Option A : CF Tunnel public hostname (recommandé)

### Étapes côté Cloudflare Zero Trust dashboard

1. Aller sur https://one.dash.cloudflare.com → Zero Trust → Networks → Tunnels
2. Sélectionner le tunnel `homelab-coolify` (utilisé par VM 300 cloudflared-coolify)
3. Onglet **Public Hostname** → **Add a public hostname**
4. Renseigner :
   - **Subdomain** : `grafana`
   - **Domain** : `home.example.com`
   - **Path** : (vide)
   - **Service** : `HTTP`
   - **URL** : `192.168.1.165:80` (Traefik) - Traefik résout le Host header `grafana.home.example.com` et route vers LXC 108
5. **Additional application settings → HTTP Settings** :
   - **HTTP Host Header** : `grafana.home.example.com`
   - **TLS → No TLS Verify** : on (Traefik fait le TLS termination, ici on parle HTTP entre cloudflared et Traefik)
6. **Save hostname**

Cloudflare crée automatiquement le CNAME `grafana.home.example.com → <tunnel-uuid>.cfargotunnel.com` dans la zone DNS.

### Vérification publique

```bash
curl -sI https://grafana.home.example.com/login | head -10
# Doit retourner 200 + cf-ray header
```

Depuis 4G téléphone : ouvrir https://grafana.home.example.com → page de login Grafana.

## Option B : CF Access devant Grafana (recommandé pour usage mobile sans password)

Sans CF Access : seul rempart = login admin Grafana (password). OK mais friction mobile.
Avec CF Access Email OTP : login par email, session 24h, beaucoup plus pratique.

### Setup

1. Zero Trust → Access → Applications → **Add an application**
2. Type : **Self-hosted**
3. **Application name** : `Grafana Homelab`
4. **Session duration** : `24 hours`
5. **Application domain** :
   - **Subdomain** : `grafana`
   - **Domain** : `home.example.com`
6. Suivant → **Add policy**
   - **Policy name** : `solo`
   - **Action** : Allow
   - **Configure rules** : Include → Emails → `you@example.com`
7. Save

Bonus : configurer Grafana en mode `auth.proxy` ou `auth.cloudflare` pour skip le login Grafana une fois auth CF passée (pas critique pour MVP).

## Option C : App Grafana mobile

iOS : https://apps.apple.com/app/grafana/id1581581253
Android : https://play.google.com/store/apps/details?id=com.grafana.app

1. Install → Add server
2. URL : `https://grafana.home.example.com`
3. Sign in : credentials Grafana admin
4. Naviguer → Dashboards → folder Homelab → **My Day Homelab**
5. Pin / favorite pour accès rapide

## Bookmark home screen (sans app)

iOS Safari :
1. Login sur https://grafana.home.example.com → ouvrir le dashboard `my-day-homelab`
2. Share → **Add to Home Screen**
3. Nom : `Homelab`
4. Tap → ouvre direct le dashboard

Android Chrome :
1. Login + ouvrir dashboard
2. Menu ⋮ → **Add to Home screen**
3. Confirmer

## Troubleshooting

| Symptôme | Cause | Fix |
|---|---|---|
| `Cf challenge` puis erreur 1033 | Tunnel down sur VM 300 | `qm guest exec 300 -- docker restart cloudflared-coolify` |
| 502 Bad Gateway via grafana.home.example.com | Traefik down ou Grafana LXC down | `pct exec 103 -- systemctl status traefik` + `pct exec 108 -- systemctl status grafana-server` |
| Login Grafana refuse credentials | Password reset Grafana | `pct exec 108 -- grafana-cli admin reset-admin-password <newpwd>` |
| Dashboard panels "No data" | Datasource down | UI Grafana → Configuration → Datasources → Test |

## Coût Cloudflare

CF Tunnel = gratuit (free plan). CF Access Free plan = 50 users free.

## Sécu

- TLS terminé côté Cloudflare edge + côté Traefik (cert Let's Encrypt wildcard `*.home.example.com`)
- Tunnel UUID + token isolé du LAN
- En option, CF Access ajoute MFA via OTP (sans le password Grafana)
- Logs CF disponibles dans Zero Trust dashboard pour audit
