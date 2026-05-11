# Runbook - Renouveler / forcer le cert TLS

## Comportement normal

Le wildcard cert `*.home.example.com` est renouvelé **automatiquement** par Traefik via DNS-01 Cloudflare ~30 jours avant expiration. **Aucune action manuelle** nécessaire dans 99% des cas.

## Comment vérifier l'état du cert

### Depuis un browser

Ouvrir `https://traefik.home.example.com`, cliquer sur le cadenas → "Connection is secure" → "Certificate is valid" → vérifier la date d'expiration.

### Depuis le LXC Traefik

```bash
pct exec 103 -- bash -c '
  cat /etc/traefik/ssl/acme.json | jq -r "
    .cloudflare.Certificates[] |
    \"Domain: \(.domain.main) | SANs: \(.domain.sans | join(\",\"))\""
'
```

### Avec openssl

```bash
echo | openssl s_client -connect traefik.home.example.com:443 -servername traefik.home.example.com 2>/dev/null | \
  openssl x509 -noout -dates
# notBefore=...
# notAfter=...
```

## Forcer un renouvellement

### Cas 1 : le cert se renouvelle pas tout seul (logs disent "skipped")

Vérifier d'abord pourquoi :

```bash
pct exec 103 -- journalctl -u traefik -n 200 --no-pager | grep -iE "acme|certificate"
```

Causes possibles :
- Le cert n'est pas encore dans la fenêtre des 30j → pas un problème, attends
- `CF_DNS_API_TOKEN` invalide / expiré → cf. cas 3 ci-dessous
- Pas d'internet sortant depuis le LXC 103 → debug réseau

### Cas 2 : le cert est complètement perdu / corrompu

Forcer une re-création complète :

```bash
# 1. Backup acme.json par sécurité
pct exec 103 -- cp /etc/traefik/ssl/acme.json /etc/traefik/ssl/acme.json.bak.$(date +%Y%m%d)

# 2. Vider acme.json (laisse JSON valide vide)
pct exec 103 -- bash -c 'echo "{}" > /etc/traefik/ssl/acme.json && chmod 600 /etc/traefik/ssl/acme.json'

# 3. Restart Traefik (déclenche un nouveau challenge DNS-01)
pct exec 103 -- systemctl restart traefik

# 4. Suivre les logs (~1-2 minutes pour générer)
pct exec 103 -- journalctl -u traefik -f
```

> ⚠️ **Attention rate limit Let's Encrypt** : 5 certs/semaine pour le même hostname. À utiliser parcimonieusement.

### Cas 3 : `CF_DNS_API_TOKEN` à régénérer

1. Aller sur Cloudflare → My Profile → API Tokens → "Create Token"
2. Custom token avec :
   - Permissions : `Zone : DNS : Edit`
   - Zone resources : `Include : Specific zone : home.example.com`
3. Copier le token

Sur le host :

```bash
# Identifier où le token est stocké
pct exec 103 -- systemctl cat traefik | grep -i environment
# Souvent : EnvironmentFile=/etc/default/traefik

# Éditer
pct exec 103 -- nano /etc/default/traefik
# Mettre à jour CF_DNS_API_TOKEN=<nouveau>

# Restart
pct exec 103 -- systemctl restart traefik

# Vérifier que les renouvellements futurs marcheront
pct exec 103 -- journalctl -u traefik -n 50 --no-pager | grep -i "starting"
```

> 🔒 **Révoquer l'ancien token** dans Cloudflare une fois validé.

## Tester un cert ponctuel sans toucher la prod

Utiliser le staging Let's Encrypt (faux cert mais pas de rate limit) :

```yaml
# Dans /etc/traefik/traefik.yaml, ajouter un 2ème resolver
certificatesResolvers:
  cloudflare-staging:
    acme:
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory
      email: contact@home.example.com
      storage: /etc/traefik/ssl/acme-staging.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 30
```

Puis utilise `certResolver: cloudflare-staging` sur une route de test. Le cert sera "fake" (le browser râlera) mais le flow ACME complet est testé.

## Diagnostic - checklist

| Symptôme | Vérifier |
|----------|----------|
| Cert refuse de se générer | `pct exec 103 -- journalctl -u traefik -n 200 --no-pager` |
| `403 Forbidden` Cloudflare API | Token mal scopé ou expiré |
| `connection refused` vers 1.1.1.1 | DNS sortant cassé du LXC 103 |
| `acme: error: 429 :: urn:ietf:params:acme:error:rateLimited` | Trop de tentatives → attendre 1 semaine ou utiliser staging |

## Alerter sur expiration imminente

Roadmap Phase 3 : Uptime Kuma a un monitor type "HTTPS Cert Expiry". Configurer :
- Monitor `traefik.home.example.com` certificat
- Alerte si `< 14 jours`
