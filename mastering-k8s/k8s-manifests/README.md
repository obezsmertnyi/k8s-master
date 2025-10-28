# Kubernetes Manifests for Full Cluster Setup

This directory contains all necessary Kubernetes manifests to set up a complete cluster with CoreDNS, kube-proxy, and RBAC for the custom controller.

## 📁 Files

| File | Description |
|------|-------------|
| `01-namespace.yaml` | Creates `kube-system` namespace |
| `02-kubernetes-service.yaml` | Creates `kubernetes` Service and Endpoints in default namespace |
| `03-coredns.yaml` | Deploys CoreDNS for DNS resolution |
| `04-kube-proxy.yaml` | Deploys kube-proxy for Service networking |
| `05-controller-rbac.yaml` | Creates RBAC for newresource-controller (ServiceAccount, Roles, RoleBindings) |
| `apply-all.sh` | Script to apply all manifests in correct order |

## 🚀 Quick Start

### Prerequisites

1. **Start Kubernetes cluster** with TLS enabled (default):
   ```bash
   cd ../
   ./setup.sh start
   ```

   Or without TLS (insecure mode for testing):
   ```bash
   USE_TLS=false ./setup.sh start
   ```

2. kubectl configured and working

### Apply All Manifests

```bash
cd mastering-k8s/k8s-manifests

# Make script executable
chmod +x apply-all.sh

# Apply all manifests
./apply-all.sh
```

The script will:
1. Create `kubernetes` Service with your HOST_IP
2. Create `kube-system` namespace
3. Deploy CoreDNS
4. Deploy kube-proxy
5. Create RBAC for controller

### Verify Installation

```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Check kubernetes Service
kubectl get svc kubernetes
kubectl get endpoints kubernetes

# Check controller RBAC
kubectl get sa newresource-controller
kubectl get role newresource-controller-leader-election
kubectl get clusterrole newresource-controller
```

## 📋 What Each Component Does

### 1. kubernetes Service (02-kubernetes-service.yaml)

Creates the default `kubernetes` Service that points to the API server:
- **ClusterIP**: `16.0.0.1:443`
- **Target**: `HOST_IP:6443` (your API server)

This allows pods to access the API server via `https://kubernetes.default.svc.cluster.local:443`

### 2. CoreDNS (03-coredns.yaml)

Provides DNS resolution inside the cluster:
- **Service**: `kube-dns` with ClusterIP `16.0.0.10`
- **Resolves**: `*.cluster.local`, `*.svc.cluster.local`, pod DNS
- **Forwards**: External queries to `8.8.8.8` and `1.1.1.1`

### 3. kube-proxy (04-kube-proxy.yaml)

Manages network rules for Services:
- **Mode**: iptables
- **ClusterCIDR**: `173.22.0.0/16`
- **Runs as**: DaemonSet (one pod per node)

### 4. Controller RBAC (05-controller-rbac.yaml)

Creates necessary permissions for the controller:

**ServiceAccount**: `newresource-controller`

**Role** (namespace: default):
- Permissions for `coordination.k8s.io/leases` - for leader election
- Permissions for `events` - for event recording

**ClusterRole**:
- Permissions for `apps.newresource.com/newresources` - for CRD operations
- Permissions for `newresources/status` - for status updates
- Permissions for `newresources/finalizers` - for finalizer management

## 🔧 Manual Application

If you prefer to apply manifests manually:

```bash
# 1. Create namespace
kubectl apply -f 01-namespace.yaml

# 2. Create kubernetes Service (update HOST_IP first!)
# Edit 02-kubernetes-service.yaml and replace 192.168.88.142 with your HOST_IP
kubectl apply -f 02-kubernetes-service.yaml

# 3. Deploy CoreDNS (update HOST_IP in env vars first!)
# Edit 03-coredns.yaml and replace 10.0.4.23 with your HOST_IP
kubectl apply -f 03-coredns.yaml

# 4. Deploy kube-proxy
kubectl apply -f 04-kube-proxy.yaml

# 5. Create controller RBAC
kubectl apply -f 05-controller-rbac.yaml
```

## 🧪 Testing

After applying all manifests, test DNS resolution:

```bash
# Create a test pod
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes

# Expected output:
# Server:    16.0.0.10
# Address 1: 16.0.0.10 kube-dns.kube-system.svc.cluster.local
#
# Name:      kubernetes
# Address 1: 16.0.0.1 kubernetes.default.svc.cluster.local
```

## 🎯 Next Steps

After applying these manifests, you can:

1. **Run controller with leader election**:
   ```bash
   cd ../new-controller
   go run main.go --leader-elect=true --leader-election-namespace=default
   ```

2. **Check leader election lease**:
   ```bash
   kubectl get lease newresource-controller -n default
   kubectl describe lease newresource-controller -n default
   ```

3. **Run multiple controller instances** to test failover

## 🔄 Cleanup

To remove all resources:

```bash
kubectl delete -f 05-controller-rbac.yaml
kubectl delete -f 04-kube-proxy.yaml
kubectl delete -f 03-coredns.yaml
kubectl delete -f 02-kubernetes-service.yaml
kubectl delete -f 01-namespace.yaml
```

## 📚 References

- [CoreDNS Documentation](https://coredns.io/manual/toc/)
- [kube-proxy Configuration](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Leader Election](https://kubernetes.io/blog/2016/01/simple-leader-election-with-kubernetes/)
