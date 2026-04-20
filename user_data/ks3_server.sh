#!/bin/bash

apt-get -yq update
apt-get install -yq \
    ca-certificates \
    curl \
    ntp

# Store Droplet ID in variable (utilises DO's Metadata Service - https://developers.digitalocean.com/documentation/metadata/)
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

# Escribir configuración de k3s
install -d /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
tls-san:
  - "${k3s_lb_ip}"
datastore-endpoint: "${db_cluster_uri}"
%{ if cni_provider == "flannel" ~}
flannel-iface: eth1
%{ else ~}
flannel-backend: none
disable-network-policy: true
%{ endif ~}
node-ip: $PRIVATE_IP
advertise-address: $PRIVATE_IP
node-external-ip: $PUBLIC_IP
disable:
  - local-storage
  - servicelb
%{ if disable_traefik ~}
  - traefik
%{ endif ~}
disable-cloud-controller: true
kubelet-arg:
  - "provider-id=digitalocean://$DROPLET_ID"
  - "cloud-provider=external"
%{ if server_taint_criticalonly ~}
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
%{ endif ~}
EOF

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - server