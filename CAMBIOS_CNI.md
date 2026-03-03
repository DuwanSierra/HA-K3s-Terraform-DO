# Cambios Realizados - Separación de Scripts CNI

## Resumen

Se ha refactorizado la instalación de CNI en el script `ks3_server_init.sh` para:

1. **Separar la lógica de CNI en scripts independientes**
2. **Agregar validación y logging mejorado**
3. **Facilitar monitoreo y debugging**

## Cambios Principales

### 1. Script Principal Modificado: `ks3_server_init.sh`

**Cambios:**
- Ahora crea scripts CNI dinámicos en `/tmp/cni-scripts/` usando heredocs
- Cada script CNI se genera con validación y logging completo
- Se ejecutan de forma modular según el valor de `cni_provider`
- Logging consistente con prefijo `[CNI]` para identificación fácil
- Mejor manejo de errores con `set -e`

**Estructura de Llamada:**
```bash
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
esac
```

### 2. Scripts CNI Individuales Creados

Se han creado scripts independientes en `/user_data/` que también están embebidos en el script principal:

- **cni_flannel.sh** - Instalación de Flannel con validación
- **cni_cilium.sh** - Instalación de Cilium con verificación de estado
- **cni_calico.sh** - Instalación de Calico con validación de nodos
- **cni_antrea.sh** - Instalación de Antrea con verificación de agents

**Características de cada script:**
- ✅ Validación de instalación completa
- ✅ Timeouts configurables (300 segundos por defecto)
- ✅ Logging detallado con prefijo `[CNI]`
- ✅ Compatibilidad con múltiples arquitecturas (amd64/arm64)
- ✅ Manejo de errores explícito

### 3. Script de Monitoreo: `monitor_cni_installation.sh`

Nuevo script para verificar y monitorear la instalación:

```bash
./monitor_cni_installation.sh flannel
./monitor_cni_installation.sh calico
./monitor_cni_installation.sh cilium
./monitor_cni_installation.sh antrea
```

**Funcionalidades:**
- Colores en la salida (verde/rojo)
- Verificación de readiness de pods
- Estado de deployments y daemonsets
- Información de nodos y BGP peers
- Timeout manejo automático

### 4. Documentación: `CNI_README.md`

Documentación completa con:
- Explicación de cada script
- Uso con Terraform
- Validación y logs
- Troubleshooting
- Notas importantes

## Flujo de Ejecución

```
ks3_server_init.sh
├── Instala k3s
├── Espera API server
├── Crea /tmp/cni-scripts/
│   ├── cni_flannel.sh
│   ├── cni_cilium.sh
│   ├── cni_calico.sh
│   └── cni_antrea.sh
├── Ejecuta script CNI seleccionado
│   └── [CNI] Validación y logging completo
├── Configura manifiestos (CCM, CSI, Ingress, etc)
└── Finaliza
```

## Uso con Terraform

```hcl
# Seleccionar CNI mediante variable
variable "cni_provider" {
  description = "CNI provider: flannel, cilium, calico, antrea, none"
  type        = string
  default     = "calico"
}

# En la configuración del droplet
terraform apply -var="cni_provider=calico"
```

## Validación en Consola

### Durante la Instalación

Los logs mostrarán:
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
[CNI] Calico nodes ready: 1/1
[CNI] Checking BGP peers status...
[CNI] ✓ Calico installation completed successfully
==========================================
[CNI] CNI installation and validation completed
==========================================
```

### Después de la Instalación

```bash
# En la instancia
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Ver logs completos
tail -f /var/log/cloud-init-output.log | grep "\[CNI\]"

# Verificar estado del CNI
kubectl get pods -A | grep -i calico
kubectl get nodes -o wide

# Monitorear (si el script está disponible)
bash /tmp/cni-scripts/monitor_cni_installation.sh calico
```

## Ventajas de esta Implementación

1. **Modularidad** - Cada CNI tiene su propia lógica
2. **Validación Automática** - Se verifica que el CNI esté completamente instalado
3. **Debugging Facilitado** - Logs claros y específicos del CNI
4. **Reutilización** - Scripts pueden ejecutarse manualmente si es necesario
5. **Escalabilidad** - Fácil agregar nuevos CNI
6. **Monitoreo** - Script de monitoreo para verificar estado en tiempo real
7. **Documentación** - Documentación completa integrada

## Archivos Modificados/Creados

```
user_data/
├── ks3_server_init.sh          [MODIFICADO] - Script principal refactorizado
├── cni_flannel.sh               [NUEVO] - Script Flannel independiente
├── cni_cilium.sh                [NUEVO] - Script Cilium independiente
├── cni_calico.sh                [NUEVO] - Script Calico independiente
├── cni_antrea.sh                [NUEVO] - Script Antrea independiente
├── monitor_cni_installation.sh  [NUEVO] - Script de monitoreo
└── CNI_README.md                [NUEVO] - Documentación
```

## Notas Importantes

- Los scripts de CNI se generan dinámicamente en `/tmp/cni-scripts/` en la instancia
- También existen como archivos independientes en el repositorio para referencia
- El CIDR para Calico está fijo a `10.42.0.0/16` (default de k3s)
- Los timeouts son suficientemente amplios (300s) para clusters pequeños
- La validación se hace con `kubectl wait` que es muy confiable
- Compatible con DigitalOcean, CCM y CSI

## Testing Recomendado

```bash
# 1. Provisionar cluster con Calico
terraform apply -var="cni_provider=calico"

# 2. Esperar a que complete (15-20 minutos típicamente)

# 3. Verificar logs
ssh root@<droplet-ip> 'tail -f /var/log/cloud-init-output.log | grep CNI'

# 4. Validar estado final
ssh root@<droplet-ip> 'kubectl get pods -A | grep calico'
ssh root@<droplet-ip> 'kubectl get nodes -o wide'

# 5. Probar con otro CNI (recomendado: crear nuevo cluster)
terraform apply -var="cni_provider=cilium"
```

## Troubleshooting

### CNI no se instala
```bash
# Verificar que k3s está corriendo
sudo systemctl status k3s

# Ver logs completos
sudo tail -f /var/log/cloud-init-output.log
```

### Pods del CNI no están Ready
```bash
# Describir pod
kubectl describe pod -n <namespace> <pod-name>

# Ver logs
kubectl logs -n <namespace> <pod-name>
```

### Validar instalación manual
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
bash /tmp/cni-scripts/cni_calico.sh  # Ejecutar script específico
```
