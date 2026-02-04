#!/bin/bash

apt-get -yq update
apt-get install -yq \
    ca-certificates \
    curl \
    ntp \
    wireguard

DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)

# Crear directorio de configuración
mkdir -p /etc/rancher/k3s

# Crear archivo de configuración
cat > /etc/rancher/k3s/config.yaml <<EOF
datastore-endpoint: "${db_cluster_uri}"
tls-san:
  - "${k3s_lb_ip}"
disable:
  - local-storage
  - servicelb
  - traefik
  - cloud-controller
disable-cloud-controller: true
flannel-backend: "${flannel_backend}"
disable-network-policy: $([ "${flannel_backend}" = "none" ] && echo "true" || echo "false")
kubelet-arg:
  - "provider-id=digitalocean://$DROPLET_ID"
  - "cloud-provider=external"
EOF

# Solo agregar flannel-iface si no es "none"
if [ "${flannel_backend}" != "none" ]; then
    echo "flannel-iface: eth1" >> /etc/rancher/k3s/config.yaml
fi

# Solo agregar node-taint si está definido
if [ -n "${critical_taint}" ] && [ "${critical_taint}" != "" ]; then
    echo "node-taint:" >> /etc/rancher/k3s/config.yaml
    echo "  - CriticalAddonsOnly=true:NoExecute" >> /etc/rancher/k3s/config.yaml
fi

# Instalar k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - server