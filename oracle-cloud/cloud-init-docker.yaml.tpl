#cloud-config
# Family VPN — Docker-based deployment via cloud-init
# No SSH required. Fully automated.

swap:
  filename: /swapfile
  size: 2147483648  # 2GB — needed for Docker build on 1GB instances
  maxsize: 2147483648

package_update: true

packages:
  - ca-certificates
  - curl

runcmd:
  - |
    set -ex

    # ── Install Docker ──
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # ── Write project files (base64-encoded by Terraform) ──
    mkdir -p /opt/family-vpn/docker

    echo '${dockerfile_b64}' | base64 -d > /opt/family-vpn/docker/Dockerfile
    echo '${entrypoint_b64}' | base64 -d > /opt/family-vpn/docker/entrypoint.sh
    echo '${compose_b64}'    | base64 -d > /opt/family-vpn/docker-compose.yml

    chmod +x /opt/family-vpn/docker/entrypoint.sh

    # ── Open firewall ports (OCI Ubuntu blocks non-SSH by default) ──
    iptables -I INPUT 4 -p tcp --dport 443 -m state --state NEW -j ACCEPT
    iptables -I INPUT 5 -p udp --dport 8443 -j ACCEPT
    netfilter-persistent save

    # ── Build and start ──
    cd /opt/family-vpn
    docker compose build
    docker compose up -d

    echo "=== VPN deployment complete at $(date) ===" >> /var/log/vpn-deploy.log
