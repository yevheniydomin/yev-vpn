# --- Stage 1: Build amneziawg-go (userspace WireGuard with obfuscation) ---
FROM golang:1.24-bookworm AS awg-build
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git /src
WORKDIR /src
RUN go build -o /usr/local/bin/amneziawg-go .

# --- Stage 2: Runtime ---
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System deps + AmneziaWG tools (single layer to avoid cache issues)
RUN apt-get update && apt-get install -y \
    curl jq qrencode iptables openssl iproute2 procps unzip \
    software-properties-common ca-certificates \
    && add-apt-repository -y ppa:amnezia/ppa \
    && apt-get update \
    && apt-get install -y amneziawg-tools \
    && rm -rf /var/lib/apt/lists/*

# XRay (unzip is available now)
RUN bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install \
    && /usr/local/bin/xray version

# AmneziaWG userspace binary
COPY --from=awg-build /usr/local/bin/amneziawg-go /usr/local/bin/amneziawg-go

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME /data

ENTRYPOINT ["/entrypoint.sh"]
