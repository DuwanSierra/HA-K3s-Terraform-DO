#!/bin/bash

apt-get -yq update
apt-get install -yq \
    ca-certificates \
    curl \
    ntp

# Store Droplet ID in variable (utilises DO's Metadata Service - https://developers.digitalocean.com/documentation/metadata/)
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)

# Escribir configuración de k3s
install -d /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
tls-san:
  - "${k3s_lb_ip}"
EOF

# k3s - usa el flannel nativo (vxlan) enlazado a la interfaz privada del VPC de DigitalOcean
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - server \
    --datastore-endpoint="${db_cluster_uri}" \
    ${critical_taint} \
    --kubelet-arg="provider-id=digitalocean://$DROPLET_ID" \
    --flannel-iface=eth1 \
    --node-ip=$PRIVATE_IP \
    --disable local-storage \
    --disable servicelb \
    --disable-cloud-controller \
    ${enable_traefik} \
    --kubelet-arg="cloud-provider=external"