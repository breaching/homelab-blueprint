# Coolify v4 - Domain change gotcha (compose pas régen au save)

## Symptôme

- Tu changes la FQDN d'une app Coolify v4 (ex: `http://prod-test.example.com` → `http://example.com`)
- Tu cliques **Save**
- Tu cliques **Redeploy** ou **Force Rebuild**
- Le déploy "réussit" (status finished)
- MAIS le site sur la nouvelle FQDN renvoie **404** depuis coolify-proxy
- Investigation : le `docker-compose.yaml` côté serveur (`/data/coolify/applications/<uuid>/docker-compose.yaml`) **garde l'ancienne FQDN** dans les Traefik labels (`Host(\`old.example.com\`)`)

## Cause

Coolify v4 a un bug (au moins en build de mai 2026) : si tu modifies le champ **Domains** mais que tu cliques Save sans avoir effectivement "vidé" le champ d'abord, Coolify considère que rien n'a changé et **ne régénère pas le docker-compose.yaml** au prochain deploy. Ni Redeploy ni Force Rebuild ne forcent la régen - ils utilisent le compose existant tel quel.

DB column `applications.fqdn` est mise à jour, mais ce qui pilote le deploy = le compose.yaml généré sur le serveur cible, pas la DB directement.

## Fix

Dans Coolify UI → app → Configuration → champ **Domains** :
1. **Effacer COMPLÈTEMENT** le contenu (Ctrl+A + Delete)
2. Click ailleurs ou Save → Coolify enregistre "domains vide"
3. Re-coller la valeur souhaitée (ex: `http://example.com,http://www.example.com`)
4. **Save**
5. **Redeploy**

Ce double-save flag le state comme "dirty" et force la regen du compose.yaml côté serveur cible avec les nouveaux Host rules Traefik.

## Diagnostic - confirmer que c'est ce bug

Sur le serveur cible (Hetzner ou autre destination Coolify) :
```bash
cat /data/coolify/applications/<APP_UUID>/docker-compose.yaml | grep -E "Host\(|traefik"
```

Si tu vois l'ancienne FQDN au lieu de la nouvelle → ce bug.

## Workaround alternatif (si bug persiste)

CF Tunnel **HTTP Host Header rewrite** :
- Dans Public Hostnames CF Tunnel pour la nouvelle FQDN
- Additional application settings → HTTP Settings → **HTTP Host Header** : tape l'ANCIENNE FQDN (ex: `prod-test.example.com`)
- coolify-proxy reçoit Host: ancienne-fqdn → matche son rule existant → route correctement
- User voit la nouvelle FQDN dans le browser (Host header est interne au tunnel)

Hack mais marche tant que tu ne peux pas convaincre Coolify de regen le compose.

## Apparu à

2026-05-07 lors de la migration `prod-test.example.com` → `example.com` après abandon Vercel. Coolify v4.0.0.
