# CNI Installation Scripts

Este directorio contiene los scripts de inicialización para k3s con soporte para múltiples proveedores de CNI (Container Network Interface).

## Archivos

### Script Principal
- **ks3_server_init.sh** - Script principal de inicialización que:
  - Instala k3s
  - Espera a que el API server esté listo
  - Crea scripts de CNI en `/tmp/cni-scripts/`
  - Ejecuta el script CNI correspondiente basado en la variable `cni_provider`
  - Aplica manifiestos adicionales (CCM, CSI, Ingress, Dashboard, etc.)

### Scripts de CNI Individuales
Los siguientes scripts se generan automáticamente en `/tmp/cni-scripts/`:

- **cni_flannel.sh** - Instalación de Flannel
  - Aplica manifest de Flannel
  - Espera a que los pods estén listos (300s timeout)
  - Valida e imprime estado

- **cni_cilium.sh** - Instalación de Cilium
  - Descarga Cilium CLI
  - Ejecuta instalación de Cilium
  - Espera deployment (300s timeout)
  - Valida estado con `cilium status`

- **cni_calico.sh** - Instalación de Calico
  - Aplica CRDs de Calico
  - Despliega operador Tigera
  - Aplica custom resources con CIDR personalizado (10.42.0.0/16)
  - Valida nodos y controlador

- **cni_antrea.sh** - Instalación de Antrea
  - Aplica manifest de Antrea
  - Espera agents y controlador
  - Valida agents en cada nodo

## Uso con Terraform

### Variables de Terraform Necesarias

```hcl
variable "cni_provider" {
  description = "CNI provider to use: flannel, cilium, calico, antrea, or none"
  type        = string
  default     = "flannel"
}
```

### Ejemplo de Aplicación

```bash
terraform apply -var="cni_provider=calico"
```

### Opciones de CNI Soportadas

1. **flannel** - CNI por defecto, ligero y simple
2. **cilium** - eBPF-basado, alto rendimiento
3. **calico** - Enterprise-ready con BGP
4. **antrea** - VMware, soporte para microsegmentación
5. **none** - Sin CNI (solo para casos especiales)

## Validación y Logs

### Durante la Ejecución

Cada script imprime:
- `[CNI] Installing <provider>...` - Inicio de instalación
- `[CNI] Waiting for...` - Espera de readiness
- `[CNI] Validating...` - Validación de estado
- `[CNI] ✓ <provider> installation completed successfully` - Confirmación de éxito

### Ver Logs de user_data

```bash
# En la instancia de DigitalOcean
tail -f /var/log/cloud-init-output.log
```

### Verificar Estado del CNI

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Ver pods del CNI
kubectl get pods -A | grep -i <cni_provider>

# Ver nodos
kubectl get nodes -o wide

# Verificar conectividad
kubectl get pods -A
```

## Características Clave

1. **Separación de Responsabilidades** - Cada CNI tiene su propio script
2. **Validación Automática** - Cada script espera a que los recursos estén listos
3. **Timeouts Configurables** - 300 segundos por defecto
4. **Logging Consistente** - Prefijo `[CNI]` para fácil identificación
5. **Manejo de Errores** - `set -e` para detener en caso de error

## Notas Importantes

- Los scripts se crean dinámicamente desde el script principal usando heredocs
- Todos los scripts exportan `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
- Los timeouts son de 300 segundos para dar tiempo a que los recursos se desplieguen
- El CIDR para Calico está configurado a `10.42.0.0/16` (k3s default)
- Los scripts manejan arquitecturas tanto amd64 como arm64 (Cilium)

## Troubleshooting

### El CNI no se instala
```bash
# Verificar que k3s está corriendo
kubectl get nodes
# Ver logs del script
tail -f /var/log/cloud-init-output.log
```

### Pods del CNI no están listos
```bash
kubectl describe pod -n <namespace> <pod_name>
kubectl logs -n <namespace> <pod_name>
```

### Cambiar CNI Después de Instalación
Se recomienda recrear el cluster, ya que cambiar CNI después de la instalación puede ser complejo.

## Autores y Notas

Estos scripts están optimizados para DigitalOcean con K3s y soporte para:
- DigitalOcean Cloud Controller Manager (CCM)
- DigitalOcean CSI Driver
- Ingress Controllers (Traefik, Nginx, Kong)
- Kubernetes Dashboard
- Cert Manager
- System Upgrade Controller
