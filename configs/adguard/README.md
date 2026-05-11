# AdGuard configs

## Pourquoi pas la vraie config ici

Le fichier `AdGuardHome.yaml` contient :
- Hash bcrypt du mot de passe admin
- Tokens / clés DNSCrypt si activé
- Adresses IP de clients qui pourraient être considérées comme PII

→ La vraie config **n'est pas committée**. Elle est sauvegardée via vzdump du LXC 100.

## Ce qui est committable (et doit l'être)

À reconstruire ici sous forme d'`AdGuardHome.example.yaml` :

- La structure générale (sections du YAML)
- Les **upstream DNS** (1.1.1.1, 9.9.9.9, etc.)
- Les **filter lists** activées (URLs OISD, AdGuard, etc.)
- Les **DNS rewrite** rules (au moins le wildcard `*.home.example.com → 192.168.1.165`)
- Les paramètres généraux (port, ratelimit, cache size)

À placer en commentaire ou en `<REDACTED>` :
- `users[].password` → `<BCRYPT_HASH>`
- `tls.certificate_chain` / `private_key` → `<TLS_CERT>` / `<TLS_KEY>`
- Adresses MAC/IP de clients dans `clients`

## Procédure d'export

```bash
# Sur le host PVE
pct exec 100 -- cat /opt/AdGuardHome/AdGuardHome.yaml > /tmp/adguard-raw.yaml

# Récupérer en local
scp root@192.168.1.90:/tmp/adguard-raw.yaml ./
mv adguard-raw.yaml configs/adguard/AdGuardHome.example.yaml

# Sanitize manuellement avant commit :
# - Remplacer les hashes bcrypt par <REDACTED>
# - Vérifier qu'aucun token/clé ne reste

# Commit
git add configs/adguard/AdGuardHome.example.yaml
git diff --cached configs/adguard/   # double check !
git commit -m "docs(adguard): export sanitized config"
```

## Restauration

```bash
# Restaurer depuis vzdump (préféré, garde toutes les data : stats, queries, sessions)
pct restore 100 /mnt/backup-ssd/dump/vzdump-lxc-100-<DATE>.tar.zst --storage Hitachi

# OU recréer manuellement à partir du template
pct exec 100 -- bash -c '
  systemctl stop AdGuardHome
  cp /opt/AdGuardHome/AdGuardHome.yaml /opt/AdGuardHome/AdGuardHome.yaml.bak
  # restaurer ton AdGuardHome.example.yaml + remplacer les <REDACTED>
  systemctl start AdGuardHome
'
```
