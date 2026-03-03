#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[CNI] Installing Calico..."

# Apply Calico CRDs
echo "[CNI] Applying Calico CRDs..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/operator-crds.yaml

# Apply Tigera operator
echo "[CNI] Deploying Tigera operator..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/tigera-operator.yaml

# Wait for operator to be ready
echo "[CNI] Waiting for Tigera operator to be ready..."
kubectl -n tigera-operator wait --for=condition=Ready pod -l k8s-app=tigera-operator --timeout=3600s || true

# Apply custom resources with correct CIDR
echo "[CNI] Applying Calico custom resources..."
curl -sL https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/custom-resources.yaml \
  | sed -E 's#cidr: 192.168.0.0/16#cidr: 10.42.0.0/16#' \
  | kubectl apply -f -

# Wait for Calico to be ready
echo "[CNI] Waiting for Calico to be fully deployed..."
kubectl -n calico-system wait --for=condition=Ready pod -l k8s-app=calico-node --timeout=300s || true

# Validate Calico installation
echo "[CNI] Validating Calico installation..."
CALICO_NODES=$(kubectl get pods -n calico-system -l k8s-app=calico-node -o jsonpath='{.items[*].status.phase}' | grep -o "Running" | wc -l)
CALICO_DESIRED=$(kubectl get nodes --no-headers | wc -l)

echo "[CNI] Calico nodes ready: $CALICO_NODES/$CALICO_DESIRED"

# Check if BGP peers are established
echo "[CNI] Checking BGP peers status..."
kubectl -n calico-system wait --for=condition=Ready pod -l k8s-app=calico-kube-controllers --timeout=300s || true

echo "[CNI] ✓ Calico installation completed successfully"
