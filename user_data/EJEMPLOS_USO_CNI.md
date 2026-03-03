# Ejemplo de Uso: Instalación de K3s con Diferentes CNI

Este ejemplo muestra cómo provisionar un cluster HA K3s en DigitalOcean con diferentes proveedores de CNI.

## Opción 1: Calico (Recomendado para Producción)

```bash
terraform apply \
  -var="cni_provider=calico" \
  -var="k3s_channel=stable" \
  -var="region=nyc3"
```

**Características:**
- BGP puro sin overlay
- Microsegmentación avanzada
- Excelente rendimiento
- Enterprise-ready

**Validación:**
```bash
ssh root@<server-ip> 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -n calico-system'
```

## Opción 2: Flannel (Default, Más Ligero)

```bash
terraform apply \
  -var="cni_provider=flannel" \
  -var="k3s_channel=stable"
```

**Características:**
- Muy ligero (ideal para dev/test)
- Simple de configurar
- Bajo overhead de recursos
- UDP overlay

**Validación:**
```bash
ssh root@<server-ip> 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -n kube-flannel'
```

## Opción 3: Cilium (Alto Rendimiento)

```bash
terraform apply \
  -var="cni_provider=cilium" \
  -var="k3s_channel=latest"
```

**Características:**
- eBPF-based
- Observabilidad avanzada
- Alto rendimiento
- Seguridad a nivel de aplicación

**Validación:**
```bash
ssh root@<server-ip> 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -n kube-system -l app=cilium'
```

## Opción 4: Antrea (VMware Network)

```bash
terraform apply \
  -var="cni_provider=antrea" \
  -var="k3s_channel=stable"
```

**Características:**
- Soporte para microsegmentación
- OpenFlow-based
- Buena compatibilidad con VMware
- Política de red avanzada

**Validación:**
```bash
ssh root@<server-ip> 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -n kube-system -l app=antrea-agent'
```

## Opción 5: Sin CNI (Solo para Casos Especiales)

```bash
terraform apply \
  -var="cni_provider=none"
```

**Uso:**
- Solo para testing
- No hay conectividad pod a pod
- Debes instalar tu propio CNI manualmente

## Monitoreo en Tiempo Real

Mientras Terraform está aplicando los cambios, puedes monitorear en otra terminal:

```bash
# 1. SSH a la instancia
ssh -i ~/.ssh/do_key root@<droplet-ip>

# 2. Ver logs en tiempo real
tail -f /var/log/cloud-init-output.log | grep -E "\[CNI\]|Waiting|Error"

# 3. En otra terminal, cuando esté listo, verificar estado
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
watch kubectl get pods -A
watch kubectl get nodes -o wide
```

## Comparativa de CNI

| Aspecto | Flannel | Cilium | Calico | Antrea |
|--------|---------|--------|--------|--------|
| Complejidad | Baja | Media | Media | Media |
| Rendimiento | Medio | Alto | Muy Alto | Alto |
| Overhead | Bajo | Bajo | Muy Bajo | Bajo |
| Política Red | Básica | Avanzada | Avanzada | Avanzada |
| Soporte DO | ✓ | ✓ | ✓ | ✓ |
| Recomendado | Dev/Test | Prod High-Perf | Prod Enterprise | Prod Special |
| BGP | No | No | Sí | No |
| eBPF | No | Sí | No | No |

## Cambiar CNI Después de Instalación

**⚠️ NO RECOMENDADO** - Puede causar problemas de conectividad

Si es absolutamente necesario:

1. Backup de datos
2. Limpiar CNI anterior
3. Reinstalar k3s con nuevo CNI
4. **Mejor: Recrear el cluster**

## Ejemplos Completos

### Terraform.tfvars para Calico

```hcl
region              = "nyc3"
droplet_image       = "debian-12-x64"
server_size         = "s-2vcpu-4gb"
agent_size          = "s-2vcpu-4gb"
k3s_channel         = "stable"
cni_provider        = "calico"
enable_ingress      = true
ingress             = "traefik"
cert_manager        = true
k8s_dashboard       = true
```

### Terraform.tfvars para Cilium

```hcl
region              = "nyc3"
droplet_image       = "debian-12-x64"
server_size         = "s-3vcpu-6gb"  # Cilium necesita más recursos
agent_size          = "s-3vcpu-6gb"
k3s_channel         = "latest"
cni_provider        = "cilium"
enable_ingress      = true
ingress             = "nginx"
cert_manager        = true
k8s_dashboard       = true
```

## Logs Esperados

### Calico - Exitoso

```
==========================================
Installing CNI: calico
==========================================
[CNI] Installing Calico...
[CNI] Applying Calico CRDs...
[CNI] Deploying Tigera operator...
[CNI] Waiting for Tigera operator to be ready...
[CNI] Applying Calico custom resources...
[CNI] Waiting for Calico to be fully deployed...
[CNI] Validating Calico installation...
[CNI] Calico nodes ready: 3/3
[CNI] Checking BGP peers status...
[CNI] ✓ Calico installation completed successfully
==========================================
[CNI] CNI installation and validation completed
==========================================
```

### Flannel - Exitoso

```
==========================================
Installing CNI: flannel
==========================================
[CNI] Installing Flannel...
[CNI] Waiting for Flannel to be deployed...
[CNI] Validating Flannel installation...
[CNI] Flannel status: Ready=1, Desired=1
[CNI] ✓ Flannel installation completed successfully
==========================================
[CNI] CNI installation and validation completed
==========================================
```

## Validaciones Post-Instalación

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 1. Ver todos los nodos
kubectl get nodes -o wide

# 2. Ver todos los pods
kubectl get pods -A

# 3. Verificar conectividad entre pods
kubectl run test-pod --image=busybox --restart=Never -- sleep 3600
kubectl exec -it test-pod -- wget -O- <otro-pod-ip>

# 4. Verificar servicios
kubectl get svc -A

# 5. Ver estado de networking
kubectl get networkpolicies -A

# 6. Para Calico: Ver BGP peers
kubectl exec -it -n calico-system <calico-node-pod> -- calicoctl node status

# 7. Para Cilium: Ver estado
cilium status --wait
```

## Troubleshooting

### Pods no tienen IP

```bash
# Verificar que el CNI está corriendo
kubectl get pods -A | grep -E "calico|flannel|cilium|antrea"

# Revisar logs del CNI
kubectl logs -n calico-system -l app=calico-node --tail=50
```

### Nodos no están listos

```bash
# Describir el nodo
kubectl describe node <node-name>

# Ver condiciones
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions

# Revisar logs del kubelet
journalctl -u k3s -f
```

### Timeout en instalación del CNI

```bash
# Aumentar timeout en /tmp/cni-scripts/*.sh
# Cambiar: --timeout=300s por --timeout=600s

# O verificar recursos
kubectl top nodes
kubectl top pods -A
```

## Performance Tuning por CNI

### Calico

```bash
# Aumentar BGP keepalive
kubectl patch bgpconfig default --type=merge \
  -p '{"spec": {"logSeverityScreen": "Info"}}'
```

### Cilium

```bash
# Habilitar IP masquerading
kubectl set env -n kube-system ds/cilium CILIUM_MASQUERADE_MODE=hybrid
```

### Flannel

```bash
# Cambiar backend a vxlan para mejor rendimiento
# Modificar en el manifest y reiniciar
```

## Referencias

- [Calico Documentation](https://docs.tigera.io/calico)
- [Cilium Documentation](https://docs.cilium.io/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)
- [Antrea Documentation](https://antrea.io/)
- [K3s Documentation](https://docs.k3s.io/)
