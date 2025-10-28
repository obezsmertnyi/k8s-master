# Task 02-3: Run Controller in Control Plane with Leader Election

**Level:** Expert  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** 📝 Planned

---

## 📋 Overview

This task demonstrates how to run the custom controller with leader election enabled. Leader election ensures that only one instance of the controller is active at a time, which is critical for production deployments with multiple replicas.

**Note:** The controller now supports `--leader-election-namespace` parameter for running leader election locally (out-of-cluster).

## 🎯 Objectives

- Understand leader election concepts
- Learn about Lease objects in Kubernetes
- Understand how failover works
- Prepare for production deployment

## 📦 Prerequisites

- Completed [Task 02-1](./02-1-first-controller.md) and [Task 02-2](./02-2-tests-and-metrics.md)
- Understanding of Kubernetes RBAC
- Basic knowledge of high availability concepts

## 🏗️ Leader Election Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                     │
│                                                         │
│  ┌──────────────────┐      ┌──────────────────┐       │
│  │  Controller      │      │  Controller      │       │
│  │  Instance 1      │      │  Instance 2      │       │
│  │  (LEADER) ✅     │      │  (STANDBY) ⏸️    │       │
│  └──────────────────┘      └──────────────────┘       │
│           │                          │                 │
│           │    Lease Object          │                 │
│           └──────────┬───────────────┘                 │
│                      ▼                                 │
│           ┌────────────────────┐                       │
│           │  coordination.k8s.io/v1                   │
│           │  Lease: newresource-controller            │
│           │  - holder: instance-1                     │
│           │  - renewTime: 2025-01-28T02:15:00Z       │
│           └────────────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

## 🚀 How Leader Election Works

### Controller Configuration

The controller in `main.go` already has leader election support:

```go
flag.BoolVar(&enableLeaderElection, "leader-elect", false, 
    "Enable leader election for controller manager.")

mgr, err := manager.New(config.GetConfigOrDie(), manager.Options{
    Scheme:           scheme,
    Metrics:          server.Options{BindAddress: metricsAddr},
    LeaderElection:   enableLeaderElection,
    LeaderElectionID: "newresource-controller",
})
```

When `--leader-elect=true` is set:
1. Controller tries to acquire a **Lease** object
2. If successful → becomes **Leader** and starts reconciling
3. If not → becomes **Standby** and waits

### Lease Object

Leader election uses Kubernetes `Lease` resource:

```yaml
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: newresource-controller
  namespace: default
spec:
  holderIdentity: "hostname_random-id"
  leaseDurationSeconds: 15
  renewTime: "2025-01-28T02:15:30.123456Z"
```

- **holderIdentity**: Which controller instance is the leader
- **leaseDurationSeconds**: How long the lease is valid (default: 15s)
- **renewTime**: When the leader last renewed the lease

### Failover Process

1. **Leader** renews lease every ~10 seconds
2. If leader crashes/stops → lease expires after 15 seconds
3. **Standby** detects expired lease
4. **Standby** acquires lease and becomes new **Leader**
5. New leader starts reconciling resources

Total failover time: **~15-30 seconds**

## 🚀 Practical Testing

### Step 0: Setup Kubernetes Cluster Components

Before running the controller with leader election, you need to set up the cluster with necessary components (CoreDNS, kube-proxy, RBAC).

```bash
cd mastering-k8s/k8s-manifests

# Make script executable
chmod +x apply-all.sh

# Apply all manifests (CoreDNS, kube-proxy, kubernetes Service, controller RBAC)
./apply-all.sh
```

This will create:
- `kubernetes` Service and Endpoints (for API server access)
- CoreDNS (for DNS resolution)
- kube-proxy (for Service networking)
- RBAC for controller (ServiceAccount, Roles, RoleBindings)

**Verify installation:**
```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Check controller RBAC
kubectl get sa newresource-controller -n default
kubectl get role newresource-controller-leader-election -n default
```

### Step 1: Run First Controller Instance

Open first terminal:

```bash
cd mastering-k8s/new-controller

# Run with leader election enabled
go run main.go --leader-elect=true --leader-election-namespace=default
```

**Expected output:**
```
2025-10-28T02:34:27+02:00       INFO    controller-runtime.metrics      Starting metrics server
I1028 02:34:27.249340 1601273 leaderelection.go:257] attempting to acquire leader lease default/newresource-controller...
I1028 02:34:27.350000 1601273 leaderelection.go:267] successfully acquired lease default/newresource-controller
2025-10-28T02:34:27+02:00       INFO    Starting Controller
2025-10-28T02:34:27+02:00       INFO    Starting workers
```

The controller becomes the **Leader** and starts reconciling!

### Step 2: Run Second Controller Instance

Open second terminal:

```bash
cd mastering-k8s/new-controller

# Run second instance with different metrics port
go run main.go --leader-elect=true --leader-election-namespace=default --metrics-bind-address=:8081
```

**Expected output:**
```
2025-10-28T02:35:00+02:00       INFO    controller-runtime.metrics      Starting metrics server
I1028 02:35:00.123456 1601274 leaderelection.go:257] attempting to acquire leader lease default/newresource-controller...
```

The second controller waits as **Standby** - it will NOT start workers until it becomes the leader.

### Step 3: Verify Lease Object

In third terminal:

```bash
# Check lease was created
kubectl get lease newresource-controller -n default

# View lease details
kubectl describe lease newresource-controller -n default
```

You'll see the **Holder Identity** showing which controller instance is the leader.

### Step 4: Test Failover

Kill the first controller (Ctrl+C in first terminal) and watch the second terminal:

```
I1028 02:36:00.789012 1601274 leaderelection.go:267] successfully acquired lease default/newresource-controller
2025-10-28T02:36:00+02:00       INFO    Starting Controller
2025-10-28T02:36:00+02:00       INFO    Starting workers
```

The standby controller becomes the leader within ~15 seconds! ✅

## 🧪 Understanding Leader Election in Practice

### Checking Lease Objects

When controllers run with leader election, they create Lease objects:

```bash
# List all leases
kubectl get lease -A

# View specific lease
kubectl describe lease newresource-controller -n default
```

The **Holder Identity** field shows which controller instance is currently the leader.

### Production Deployment Example

In production, you would deploy multiple controller replicas:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newresource-controller
spec:
  replicas: 3  # Multiple replicas for HA
  template:
    spec:
      containers:
      - name: manager
        image: newresource-controller:latest
        args:
        - --leader-elect=true  # Enable leader election
```

**What happens:**
- All 3 pods start
- One pod acquires the lease → becomes **Leader**
- Other 2 pods wait → become **Standby**
- Only the leader reconciles resources
- If leader pod dies → standby takes over within ~15-30 seconds

### Why Leader Election is Important

**Without leader election:**
- Multiple controllers reconcile the same resource
- Race conditions and conflicts
- Duplicate operations (e.g., creating resources twice)

**With leader election:**
- Only one controller is active
- No conflicts or race conditions
- Automatic failover for high availability

## 🎓 Key Concepts

1. **Leader Election:**
   - Only one controller instance is active (leader)
   - Other instances are on standby
   - Automatic failover if leader fails

2. **Lease Object:**
   - Stored in `coordination.k8s.io/v1` API
   - Contains holder identity and renew time
   - Default lease duration: 15 seconds

3. **High Availability:**
   - Multiple controller replicas for redundancy
   - Fast failover (typically <30 seconds)
   - No duplicate reconciliations

4. **RBAC Requirements:**
   - ServiceAccount for controller
   - Role for lease management
   - ClusterRole for CRD operations

## 🔄 Next Steps

- **Task 02-4:** Build GitOps loop with automated image updates
- Add health checks and readiness probes
- Implement graceful shutdown
- Set up monitoring and alerting
- Deploy to production cluster

## 📚 References

- [Leader Election](https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/leaderelection)
- [Lease API](https://kubernetes.io/docs/reference/kubernetes-api/cluster-resources/lease-v1/)
- [Controller HA](https://book.kubebuilder.io/reference/watching-resources/externally-managed.html)

---

**Prerequisites:** Tasks 02-1 and 02-2 completed  
**Estimated Time:** 2-3 hours
