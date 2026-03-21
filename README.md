# Family VPN — Censorship-Resistant VPN in a Docker Container

Self-hosted VPN designed to bypass Russian TSPU/DPI censorship. Runs as a single Docker container on any Linux server.

## How It Works

Two VPN protocols run inside one container:

| Protocol               | Port     | What DPI Sees                       |
| ---------------------- | -------- | ----------------------------------- |
| **XRay VLESS+Reality** | 443/TCP  | Normal HTTPS to microsoft.com       |
| **AmneziaWG**          | 8443/UDP | Random noise (obfuscated WireGuard) |

Standard VPNs (OpenVPN, WireGuard) are trivially blocked by Russia's TSPU. These two protocols are currently undetectable.

## Cost

| Provider                       | Monthly Cost      |
| ------------------------------ | ----------------- |
| **Oracle Cloud (always free)** | **$0**            |
| Hetzner / Vultr / DigitalOcean | ~$4-5             |
| AWS free tier (12 months)      | ~$3.65 (IPv4 fee) |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 24+ with Compose plugin
- A Linux server with a public IP (any cloud or VPS)
- For OCI automated deploy: [Terraform](https://www.terraform.io/downloads) 1.0+ and [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)

## Quick Start — Any Server with Docker

SSH into your server, then:

```bash
git clone <your-repo-url>
cd family-vpn

# Build the image (~5 min first time, ~30s after)
make build

# Start VPN
make up

# Get client configs (VLESS link + AmneziaWG configs)
make configs
```

That's it. Share the VLESS link or QR code with family.

## Quick Start — Oracle Cloud (Free Forever)

Fully automated. Terraform creates the VM, installs Docker, builds and starts the VPN.

### 1. Create OCI account

Sign up at [cloud.oracle.com](https://cloud.oracle.com) (Always Free tier, no credit card required after trial).

### 2. Set up OCI CLI

```bash
brew install oci-cli        # macOS
# or: pip install oci-cli   # Linux

oci setup config            # follow prompts, pick a region close to your users
```

### 3. Generate SSH key (for debugging only)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oracle-vpn -N ""
```

### 4. Deploy

```bash
make deploy
```

This will:

- Create a free-tier VM (VM.Standard.E2.1.Micro, 1GB RAM)
- Install Docker via cloud-init
- Build and start the VPN container
- Takes ~10 minutes total

### 5. Get client configs

Wait for the build to finish, then:

```bash
make cloud-configs
```

Or SSH in to check progress:

```bash
make status
```

### Customizing OCI deploy

```bash
# Use ARM shape (more powerful, but often "Out of host capacity")
make deploy SHAPE=VM.Standard.A1.Flex

# Try a different availability domain if you get capacity errors
make deploy AD_INDEX=0   # or 1, 2
```

## Client Setup

### VLESS+Reality (Primary — use this first)

[Hiddify](https://hiddify.com) is recommended — open-source (GPLv3), built on the [sing-box](https://github.com/SagerNet/sing-box) core. Created by Iranian anti-censorship activists during the 2022 Mahsa Amini protests. Code is fully auditable on [GitHub](https://github.com/hiddify).

| Platform    | App                                                                      | How to Connect              |
| ----------- | ------------------------------------------------------------------------ | --------------------------- |
| **Android** | [Hiddify](https://play.google.com/store/apps/details?id=app.hiddify.com) | Scan QR or paste VLESS link |
| **iOS**     | [Hiddify](https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532)     | Scan QR or paste VLESS link |
| **Windows** | [Hiddify](https://github.com/hiddify/hiddify-app/releases)               | Paste VLESS link            |
| **macOS**   | [Hiddify](https://github.com/hiddify/hiddify-app/releases)               | Paste VLESS link            |
| **Linux**   | [Hiddify](https://github.com/hiddify/hiddify-app/releases)               | Paste VLESS link            |

### AmneziaWG (Fallback — if VLESS stops working)

| Platform | App                               | How to Connect                 |
| -------- | --------------------------------- | ------------------------------ |
| **All**  | [AmneziaVPN](https://amnezia.org) | Import `.conf` file or scan QR |

> **Note:** AmneziaVPN is the only client that supports the AmneziaWG protocol. It's developed by anti-censorship activists (Russian-speaking diaspora, not state-affiliated). The code is fully open-source and auditable on [GitHub](https://github.com/amnezia-vpn).

### For family members

1. Install the app (see tables above)
2. Get the QR code or link from the VPN admin
3. Scan QR or paste the link
4. Tap Connect

## Configuration

Override defaults via environment variables in `docker-compose.yml` or a `.env` file:

| Variable       | Default           | Description                                  |
| -------------- | ----------------- | -------------------------------------------- |
| `CLIENT_COUNT` | 5                 | Number of client configs to generate         |
| `XRAY_SNI`     | www.microsoft.com | Domain to impersonate (must support TLS 1.3) |
| `XRAY_PORT`    | 443               | XRay listen port                             |
| `AWG_PORT`     | 8443              | AmneziaWG listen port                        |
| `DNS`          | 1.1.1.1,8.8.8.8   | DNS servers for clients                      |
| `SERVER_IP`    | auto-detected     | Override if auto-detection fails             |

Good alternative SNI targets: `gateway.icloud.com`, `dl.google.com`, `www.samsung.com`

## Commands

```bash
# ── Local Docker ──
make build          # Build image
make up             # Start VPN
make down           # Stop VPN
make configs        # Print client configs
make logs           # Follow logs
make restart        # Restart (regenerates configs with current IP)
make reset          # Wipe all keys and data, start fresh

# ── Oracle Cloud ──
make deploy         # Create VM + deploy VPN
make destroy        # Tear down everything
make status         # Check if VPN is running
make cloud-configs  # Get client configs from cloud instance
make cloud-logs     # Follow VPN logs on cloud instance
```

## How Data Persists

- **Keys and secrets** are stored in a Docker volume (`vpn-data`)
- Generated once on first start, reused on every restart
- `make restart` regenerates configs (picks up new IP) but keeps the same keys
- `make reset` wipes everything — new keys, new configs

## If the Server IP Gets Blocked

1. Destroy and redeploy: `make destroy && make deploy`
2. Get new configs: `make cloud-configs`
3. Send updated configs to family

The new instance gets a new IP automatically.

## Architecture

```
Family Device                        VPN Server
    │                                    │
    ├── VLESS+Reality (port 443) ───────►│──► Internet
    │   (looks like HTTPS to DPI)        │
    └── AmneziaWG (port 8443) ─────────►│──► Internet
        (random noise to DPI)            │
```

## File Structure

```
├── docker/
│   ├── Dockerfile          # Multi-stage: builds amneziawg-go + installs XRay
│   └── entrypoint.sh       # Key generation, config writing, service startup
├── docker-compose.yml      # Single-command deploy
├── oracle-cloud/
│   ├── main.tf             # VCN + instance + cloud-init
│   ├── variables.tf        # Configurable: shape, region, AD
│   ├── outputs.tf          # IP, SSH command, config retrieval
│   └── cloud-init-docker.yaml.tpl  # Installs Docker, embeds files, starts VPN
├── Makefile                # All commands
└── README.md
```

## Troubleshooting

**VPN not connecting:**

```bash
make status     # or: make logs
```

**Cloud-init still running (just deployed):**

```bash
ssh -i ~/.ssh/oracle-vpn ubuntu@SERVER_IP 'cloud-init status'
# "running" = still building, "done" = finished
```

**Container restarting:**

```bash
ssh -i ~/.ssh/oracle-vpn ubuntu@SERVER_IP 'sudo docker logs family-vpn --tail 50'
```

**"Out of host capacity" on OCI:**
Try a different availability domain:

```bash
make deploy AD_INDEX=0   # or 1
```

## Security

- All keys are generated **inside the container** at first start — never in source control
- VPN secrets persist in a Docker volume, not on the filesystem
- BitTorrent is blocked (prevents abuse)
- No traffic logging (`access: "none"` in XRay config)
- SSH is optional (only needed for debugging)

## License

MIT
