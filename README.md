# homelab-blueprint

Single-node Proxmox VE homelab. Architecture diagrams, operational runbooks, and config templates for Traefik, AdGuard, Wazuh, and Vector. LAN-only, no internet exposure beyond a single Cloudflare Tunnel.

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Proxmox](https://img.shields.io/badge/Proxmox%20VE-8.x-orange)
![Stack](https://img.shields.io/badge/stack-Traefik%20%2B%20AdGuard%20%2B%20Wazuh-1F6FEB)
![Scope](https://img.shields.io/badge/scope-single--node%20LAN--only-lightgrey)

## TL;DR

```
Box FAI (192.168.1.1)
   |
   +--> AdGuard 192.168.1.30   <--- DNS for the whole LAN
   |       |
   |       +-> rewrite *.home.example.com -> 192.168.1.20
   |
   +--> Proxmox host 192.168.1.10
           |
           +-> Traefik 192.168.1.20:443
                 |
                 +-> 17 services on .home.example.com
```

- 1 host: recycled HP ATX, i7-6700, 32 GB RAM, Kingston SSD + Hitachi 1 TB + 2x Samsung T5/T7 USB
- 2 VMs + 11 LXC containers
- Traefik v3 with wildcard Let's Encrypt cert via Cloudflare DNS-01
- AdGuard Home for LAN DNS (split-horizon)
- Authentik for SSO, Uptime Kuma for monitoring
- Wazuh agents on PVE host + LXC honeypot + service VMs
- Vector for log shipping
- Coolify on a Hetzner CX23 VPS, exposed via Cloudflare Tunnel

## Contents

| Folder | What's there |
|---|---|
| [`docs/`](docs/) | 14 architectural docs: network, storage, services, backups, DR, hardening, roadmap, Coolify, security observability |
| [`runbooks/`](runbooks/) | Operational procedures: add a service to Traefik, recover a corrupted VM, update Proxmox, renew certs, create an LXC, onboard a Coolify client, promote staging to prod |
| [`configs/`](configs/) | Traefik dynamic configs, AdGuard rules, Wazuh agent configs + custom detection rules, Vector pipelines |
| [`diagrams/`](diagrams/) | drawio source for the network diagram |
| [`CHANGELOG.md`](CHANGELOG.md) | Real evolution log with `Lessons learned` sections from actual incidents (HAOS FS corruption, Wazuh API stuck, Coolify domain change gotchas) |

## How to use this blueprint

This is documentation, not a working setup you can `terraform apply` against. Anonymized values to find/replace if you want to use it as a starting template:

- `192.168.1.X` -> your LAN subnet (router on .1, PVE on .10, Traefik on .20, AdGuard on .30, services on .X+)
- `*.home.example.com` -> your domain (wildcard zone hosted on Cloudflare)
- `admin@home.example.com` -> your admin email
- `02:00:00:00:00:XX` MACs -> your actual NIC addresses
- `youruser/repo` GitHub paths -> your own
- `203.0.113.X` example WAN IPs -> your real public IPs

The architectural decisions (single-node vs cluster, Traefik with DNS-01 wildcard vs port-forward, AdGuard split DNS vs full public DNS, Wazuh on LXC vs VM, USB-attached backup vs PBS) are documented in [`docs/`](docs/).

## Stack reference

- Proxmox VE 8.x
- Traefik v3, Let's Encrypt wildcard via Cloudflare DNS-01
- AdGuard Home for LAN DNS
- Authentik for SSO, with Uptime Kuma behind it
- Wazuh 4.x SIEM, single-manager on a dedicated VM
- Vector for log shipping (Traefik access logs, AdGuard query log, sshd, cowrie honeypot)
- Coolify v4 self-hosted PaaS, deployed on a Hetzner CX23 VPS via Cloudflare Tunnel
- Backups via Proxmox built-in `vzdump` to an external USB SSD, with documented 3-2-1 strategy

## Doc index

1. [Architecture](docs/01-architecture.md) - vue d'ensemble + diagrammes
2. [Inventory](docs/02-inventory.md) - VMs, LXC, IPs, MACs, ressources
3. [Network](docs/03-network.md) - subnet, DNS, DHCP, plan IP
4. [Storage](docs/04-storage.md) - disques physiques, datastores Proxmox, mounts
5. [Reverse proxy & DNS](docs/05-reverse-proxy.md) - Traefik + AdGuard + Let's Encrypt
6. [Services](docs/06-services.md) - détail par service (ports, deps, URL)
7. [Backups](docs/07-backups.md) - stratégie 3-2-1 + rétention
8. [Disaster recovery](docs/08-disaster-recovery.md) - runbooks de recovery testés
9. [Hardening](docs/09-hardening.md) - état Phase 1 + checklist
10. [Roadmap](docs/10-roadmap.md) - phases 0 -> 6
11. [Coolify](docs/11-coolify.md) - self-hosted PaaS + projets clients Hetzner
12. [RPi usage](docs/12-rpi-usage.md) - Raspberry Pi auxiliary roles
13. [Network diagram](docs/13-network-diagram.md) - drawio reference
14. [Security & observability](docs/14-security-observability.md) - Wazuh, Vector, audit

## License

MIT. See [LICENSE](LICENSE).
