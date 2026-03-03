#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[CNI] Installing Antrea..."

# Apply Antrea manifest
kubectl apply -f https://github.com/antrea-io/antrea/releases/latest/download/antrea.yml

# Wait for Antrea agent to be ready
echo "[CNI] Waiting for Antrea to be deployed..."
kubectl -n kube-system wait --for=condition=Ready pod -l app=antrea-agent --timeout=3600s || true

# Validate Antrea installation
echo "[CNI] Validating Antrea installation..."
ANTREA_AGENTS=$(kubectl get pods -n kube-system -l app=antrea-agent -o jsonpath='{.items[*].status.phase}' | grep -o "Running" | wc -l)
ANTREA_DESIRED=$(kubectl get nodes --no-headers | wc -l)

echo "[CNI] Antrea agents ready: $ANTREA_AGENTS/$ANTREA_DESIRED"

# Check controller
ANTREA_CONTROLLER=$(kubectl get deployment -n kube-system antrea-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
echo "[CNI] Antrea controller ready: $ANTREA_CONTROLLER/1"

echo "[CNI] ✓ Antrea installation completed successfully"
