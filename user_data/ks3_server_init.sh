#!/bin/bash

apt-get -yq update
apt-get install -yq \
    ca-certificates \
    curl \
    ntp \
    wireguard

# Store Droplet ID in variable (utilises DO's Metadata Service)
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)

# Crear directorio de configuración de K3s
mkdir -p /etc/rancher/k3s

# Crear archivo de configuración base
cat > /etc/rancher/k3s/config.yaml <<EOF
datastore-endpoint: "${db_cluster_uri}"
tls-san:
  - "${k3s_lb_ip}"
disable:
  - local-storage
  - servicelb
  - cloud-controller
disable-cloud-controller: true
kubelet-arg:
  - "provider-id=digitalocean://$DROPLET_ID"
  - "cloud-provider=external"
EOF

# Configurar flannel según backend
if [ "${flannel_backend}" = "none" ]; then
    cat >> /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: "none"
disable-network-policy: true
EOF
else
    cat >> /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: "${flannel_backend}"
flannel-iface: "eth1"
EOF
fi

# Agregar node-taint si está definido (critical_taint debería venir como "--node-taint CriticalAddonsOnly=true:NoExecute" o vacío)
if [ -n "${critical_taint}" ] && [ "${critical_taint}" != "" ]; then
    cat >> /etc/rancher/k3s/config.yaml <<EOF
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
EOF
fi

# Configurar Traefik (enable_traefik debería venir como "--disable traefik" o vacío)
if [ "${enable_traefik}" = "--disable traefik" ]; then
    # Agregar traefik a la lista de disable si no está ya
    sed -i '/^disable:/a\  - traefik' /etc/rancher/k3s/config.yaml
fi

# Log de debug del config generado
echo "=== K3S Config Generated ===" >> /var/log/k3s-config-debug.log
cat /etc/rancher/k3s/config.yaml >> /var/log/k3s-config-debug.log

# Instalar K3s
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - server

# Esperar a que K3s esté listo
echo "Esperando a que K3s esté listo..."
until kubectl get nodes &>/dev/null; do
    echo "Esperando a que el API server esté disponible..."
    sleep 5
done

# Log de verificación de certificados
echo "=== Certificate SANs ===" >> /var/log/k3s-config-debug.log
openssl x509 -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt -text -noout | grep -A1 "Subject Alternative Name" >> /var/log/k3s-config-debug.log 2>&1

# additional manifests
while ! test -d /var/lib/rancher/k3s/server/manifests; do
    echo "Waiting for '/var/lib/rancher/k3s/server/manifests'"
    sleep 1
done

# create digitalOcean API access token secret
kubectl -n kube-system create secret generic digitalocean --from-literal=access-token=${do_token}

# create digitalocean env variables via configmap (for CCM)
kubectl -n kube-system create configmap digitalocean --from-literal=do-cluster-vpc-id=${do_cluster_vpc_id} --from-literal=public-access-firewall-name=${do_ccm_fw_name} --from-literal=public-access-firewall-tags=${do_ccm_fw_tags}

# ccm
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/do-ccm.yaml
${ccm_manifest}
EOF

# csi crds
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/crds.yaml
${csi_crds_manifest}
EOF

# csi driver
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/driver.yaml
${csi_driver_manifest}
EOF

# csi snapshot controller
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/snapshot-controller.yaml
${csi_sc_manifest}
EOF

# csi snapshot validation webhook
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/snapshot-validation-webhook.yaml
${csi_sc_manifest}
EOF

# kubernetes dashboard
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/k8s-dashboard.yaml
${k8s_dashboard}
EOF

# install certmanager
${cert_manager}

# traefik ingress
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/traefik-custom.yaml
${traefik_ingress}
EOF

# nginx ingress
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/ingress-nginx.yaml
${nginx_ingress}
EOF

# kong ingress controller with postgres
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/kong-all-in-one-postgres.yaml
${kong_ingress_postgres}
EOF

# kong ingress controller db-less
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/kong-all-in-one-dbless.yaml
${kong_ingress_dbless}
EOF

# system upgrade controller
base64 -d <<'EOF' | zcat | sudo tee /var/lib/rancher/k3s/server/manifests/system-upgrade-controller.yaml
${sys_upgrade_ctrl}
EOF