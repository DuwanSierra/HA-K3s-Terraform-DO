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

%{ if cni_provider == "flannel" ~}
# k3s con Flannel nativo (VXLAN) enlazado a la interfaz VPC de DigitalOcean
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s -
%{ else ~}
# k3s sin CNI propio; se instalará ${cni_provider} después
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s -
%{ endif ~}

# wait for api server
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes >/dev/null 2>&1; do
    echo "Waiting for Kubernetes API"
    sleep 2
done

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

%{ if cni_provider == "calico" ~}
# ─── Calico CNI (Tigera Operator) ────────────────────────────────────────────
echo "[CNI] Instalando Calico via Tigera Operator..."

# Tigera Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml

# Esperar a que el CRD Installation esté registrado
until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do
    echo "[CNI] Esperando CRD tigera Installation..."
    sleep 5
done

# Installation CR: CIDR de k3s (10.42.0.0/16) + interfaz VPC eth1
kubectl apply -f - <<'CALICO_EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        cidr: 10.42.0.0/16
        encapsulation: VXLAN
        natOutgoing: Enabled
        nodeSelector: all()
    nodeAddressAutodetectionV4:
      interface: eth1
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
CALICO_EOF

echo "[CNI] Esperando que calico-node esté Ready (hasta 5 min)..."
kubectl wait pods -l k8s-app=calico-node -n calico-system \
    --for=condition=Ready --timeout=300s

echo "[CNI] Calico instalado correctamente"
# ─────────────────────────────────────────────────────────────────────────────
%{ endif ~}

%{ if cni_provider == "cilium" ~}
# ─── Cilium CNI (via Helm) ────────────────────────────────────────────────────
echo "[CNI] Instalando Cilium via Helm..."

# Instalar Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Agregar repositorio de Cilium
helm repo add cilium https://helm.cilium.io/
helm repo update

# Instalar Cilium con VXLAN, CIDR de k3s e interfaz VPC de DigitalOcean (eth1)
# operator.replicas=1 porque el clúster puede arrancar con un solo nodo ready
helm install cilium cilium/cilium --version 1.16.5 \
    --namespace kube-system \
    --set k8sServiceHost="$PRIVATE_IP" \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set routingMode=tunnel \
    --set tunnelProtocol=vxlan \
    --set devices=eth1 \
    --set operator.replicas=1

echo "[CNI] Esperando que cilium-agent pods estén Ready (hasta 5 min)..."
kubectl wait pods -l k8s-app=cilium -n kube-system \
    --for=condition=Ready --timeout=300s

echo "[CNI] Cilium instalado correctamente"
# ─────────────────────────────────────────────────────────────────────────────
%{ endif ~}

%{ if cni_provider == "antrea" ~}
# ─── Antrea CNI ───────────────────────────────────────────────────────────────
echo "[CNI] Instalando Antrea..."

# Descargar y aplicar manifiesto de Antrea v2.2.0
# Configurar serviceCIDR de k3s (10.43.0.0/16) y transportInterface eth1
curl -sL https://github.com/antrea-io/antrea/releases/download/v2.2.0/antrea.yml \
  | sed 's|#transportInterface: ""|transportInterface: "eth1"|' \
  | sed 's|#serviceCIDR: "10.96.0.0/12"|serviceCIDR: "10.43.0.0/16"|' \
  | kubectl apply -f -

echo "[CNI] Esperando que antrea-agent pods estén Ready (hasta 5 min)..."
kubectl wait pods -l app=antrea,component=antrea-agent -n kube-system \
    --for=condition=Ready --timeout=300s

echo "[CNI] Antrea instalado correctamente"
# ─────────────────────────────────────────────────────────────────────────────
%{ endif ~}