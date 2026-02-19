#!/bin/bash

apt-get -yq update
apt-get install -yq \
    ca-certificates \
    curl \
    ntp \
    wireguard

# Store Droplet ID in variable (utilises DO's Metadata Service - https://developers.digitalocean.com/documentation/metadata/)
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)

# Configurar flags de k3s basado en flannel_backend
K3S_FLANNEL_ARGS="--flannel-backend=none --disable-network-policy"

# Escribir configuración de k3s
install -d /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
tls-san:
  - "${k3s_lb_ip}"
EOF

# k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - server \
    --datastore-endpoint="${db_cluster_uri}" \
    ${critical_taint} \
    --kubelet-arg="provider-id=digitalocean://$DROPLET_ID" \
    $K3S_FLANNEL_ARGS \
    --disable local-storage \
    --disable servicelb \
    --disable-cloud-controller \
    ${enable_traefik} \
    --kubelet-arg="cloud-provider=external"