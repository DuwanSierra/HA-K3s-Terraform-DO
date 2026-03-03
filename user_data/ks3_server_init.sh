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
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${k3s_channel} K3S_TOKEN=${k3s_token} sh -s - \
    --datastore-endpoint="${db_cluster_uri}" \
    ${critical_taint} \
    --kubelet-arg="provider-id=digitalocean://$DROPLET_ID" \
    $K3S_FLANNEL_ARGS \
    --disable local-storage \
    --disable servicelb \
    --disable-cloud-controller \
    ${enable_traefik} \
    --kubelet-arg="cloud-provider=external"

# wait for api server
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes >/dev/null 2>&1; do
    echo "Waiting for Kubernetes API"
    sleep 2
done

# Copy CNI scripts to disk (content injected by Terraform from user_data/cni_*.sh)
mkdir -p /tmp/cni-scripts

cat > /tmp/cni-scripts/cni_flannel.sh <<'SCRIPT_END'
${cni_flannel_script}
SCRIPT_END

cat > /tmp/cni-scripts/cni_cilium.sh <<'SCRIPT_END'
${cni_cilium_script}
SCRIPT_END

cat > /tmp/cni-scripts/cni_calico.sh <<'SCRIPT_END'
${cni_calico_script}
SCRIPT_END

cat > /tmp/cni-scripts/cni_antrea.sh <<'SCRIPT_END'
${cni_antrea_script}
SCRIPT_END

chmod +x /tmp/cni-scripts/*.sh

# install CNI before applying additional manifests
echo "=========================================="
echo "Installing CNI: ${cni_provider}"
echo "=========================================="

case "${cni_provider}" in
    flannel)
        bash /tmp/cni-scripts/cni_flannel.sh
        ;;
    cilium)
        bash /tmp/cni-scripts/cni_cilium.sh
        ;;
    calico)
        bash /tmp/cni-scripts/cni_calico.sh
        ;;
    antrea)
        bash /tmp/cni-scripts/cni_antrea.sh
        ;;
    none|"")
        echo "[CNI] Skipping CNI install"
        ;;
    *)
        echo "[CNI] ERROR: Unknown cni_provider: ${cni_provider}"
        exit 1
        ;;
esac

echo "[CNI] =========================================="
echo "[CNI] CNI installation and validation completed"
echo "[CNI] =========================================="

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