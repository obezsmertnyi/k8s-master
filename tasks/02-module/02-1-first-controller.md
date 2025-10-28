# Task 02-1: Create, Build and Run First Custom Controller

**Level:** Basic  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** ✅ Complete

---

## 📋 Overview

This task demonstrates how to create a simple Kubernetes custom controller from scratch using controller-runtime library. The controller manages a custom resource called `NewResource` and sets its status to `Ready: true` when reconciled.

## 🎯 Learning Objectives

- Understand Kubernetes custom resources and controllers
- Learn controller-runtime library basics
- Create Custom Resource Definitions (CRDs)
- Implement reconciliation logic
- Write and run controller tests
- Deploy and test the controller

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes API Server                                  │
│  ┌────────────────────────────────────────────────┐    │
│  │  Custom Resource Definition (CRD)              │    │
│  │  - NewResource (apps.newresource.com/v1alpha1) │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Watch & Reconcile
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Custom Controller                                      │
│  ┌────────────────────────────────────────────────┐    │
│  │  NewResourceReconciler                         │    │
│  │  - Watch NewResource objects                   │    │
│  │  - Update status.ready = true                  │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Update Status
                          ▼
┌─────────────────────────────────────────────────────────┐
│  NewResource Instance                                   │
│  apiVersion: apps.newresource.com/v1alpha1              │
│  kind: NewResource                                      │
│  metadata:                                              │
│    name: example-resource                               │
│  spec:                                                  │
│    foo: "bar"                                           │
│  status:                                                │
│    ready: true  ← Updated by controller                │
└─────────────────────────────────────────────────────────┘
```

## 📦 Prerequisites

- Go 1.24.4 or later
- Kubernetes cluster (local with kind/minikube or remote)
- kubectl configured to access your cluster
- controller-gen installed: `go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest`

## 🚀 Implementation

### Project Structure

```
new-controller/
├── api/v1alpha1/              # API definitions
│   ├── groupversion.go        # Group version configuration
│   └── newresource_types.go   # NewResource CRD definition
├── config/crd/bases/          # Generated CRD manifests
│   └── apps.newresource.com_newresources.yaml
├── controllers/               # Controller logic
│   └── resource_controller.go
├── test/                      # Tests
│   ├── main_test.go
│   └── test_utils.go
├── main.go                    # Application entry point
├── go.mod                     # Go module definition
└── README.md                  # Documentation
```

### Step 1: Initialize Go Module

```bash
# Create project directory
mkdir new-controller
cd new-controller

# Initialize Go module
go mod init github.com/obezsmertnyi/k8s-master/mastering-k8s/new-controller

# Install dependencies
go get sigs.k8s.io/controller-runtime@latest
go get k8s.io/apimachinery@latest
go get k8s.io/api@latest
```

### Step 2: Define Custom Resource API

Create the API structure:

**api/v1alpha1/groupversion.go:**
```go
// +groupName=apps.newresource.com
package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

var (
	GroupVersion  = schema.GroupVersion{Group: "apps.newresource.com", Version: "v1alpha1"}
	SchemeBuilder = runtime.NewSchemeBuilder(addKnownTypes)
	AddToScheme   = SchemeBuilder.AddToScheme
)

func addKnownTypes(scheme *runtime.Scheme) error {
	scheme.AddKnownTypes(GroupVersion,
		&NewResource{},
		&NewResourceList{},
	)
	metav1.AddToGroupVersion(scheme, GroupVersion)
	return nil
}
```

**api/v1alpha1/newresource_types.go:**
```go
// +groupName=apps.newresource.com
package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
type NewResource struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   NewResourceSpec   `json:"spec,omitempty"`
	Status NewResourceStatus `json:"status,omitempty"`
}

type NewResourceSpec struct {
	Foo string `json:"foo,omitempty"`
}

type NewResourceStatus struct {
	Ready bool `json:"ready,omitempty"`
}

// +kubebuilder:object:root=true
type NewResourceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []NewResource `json:"items"`
}
```

### Step 3: Generate CRD and DeepCopy Methods

```bash
# Install controller-gen
go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest

# Generate deep copy methods
controller-gen object paths="./api/..."

# Generate CRD manifests
controller-gen crd:crdVersions=v1 paths=./... output:crd:artifacts:config=config/crd/bases
```

### Step 4: Implement Controller Logic

**controllers/resource_controller.go:**
```go
package controllers

import (
	"context"
	newv1 "github.com/obezsmertnyi/k8s-master/mastering-k8s/new-controller/api/v1alpha1"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

type NewResourceReconciler struct {
	client.Client
}

func (r *NewResourceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var resource newv1.NewResource
	if err := r.Get(ctx, req.NamespacedName, &resource); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	logger.Info("Reconciling", "name", resource.Name)

	resource.Status.Ready = true
	if err := r.Status().Update(ctx, &resource); err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (r *NewResourceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&newv1.NewResource{}).
		Complete(r)
}
```

### Step 5: Create Main Application

**main.go:**
```go
package main

import (
	"flag"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/metrics/server"

	newv1 "github.com/obezsmertnyi/k8s-master/mastering-k8s/new-controller/api/v1alpha1"
	"github.com/obezsmertnyi/k8s-master/mastering-k8s/new-controller/controllers"
)

func main() {
	var (
		metricsAddr          string
		enableLeaderElection bool
	)

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "The address the metric endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false, "Enable leader election for controller manager.")
	flag.Parse()

	scheme := runtime.NewScheme()
	utilruntime.Must(newv1.AddToScheme(scheme))

	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))

	mgr, err := manager.New(config.GetConfigOrDie(), manager.Options{
		Scheme:           scheme,
		Metrics:          server.Options{BindAddress: metricsAddr},
		LeaderElection:   enableLeaderElection,
		LeaderElectionID: "newresource-controller",
	})
	if err != nil {
		panic(err)
	}

	if err := (&controllers.NewResourceReconciler{
		Client: mgr.GetClient(),
	}).SetupWithManager(mgr); err != nil {
		panic(err)
	}

	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		panic(err)
	}
}
```

### Step 6: Build the Controller

```bash
# Download dependencies
go mod tidy

# Build the controller
go build -o bin/manager main.go

# Verify binary
./bin/manager --help
```

## 🧪 Testing

### Setup Test Environment

Install setup-envtest tool:

```bash
# Install setup-envtest
go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

# Download Kubernetes binaries for testing
~/go/bin/setup-envtest use -p path
```

### Run Tests

```bash
# Set KUBEBUILDER_ASSETS environment variable
export KUBEBUILDER_ASSETS=$(~/go/bin/setup-envtest use -p path)

# Run tests
go test -v ./test -count=1
```

**Expected output:**
```
=== RUN   TestMainController
=== RUN   TestMainController/test_crd_available
=== RUN   TestMainController/test_controller_startup
=== RUN   TestMainController/test_can_create_newresource
--- PASS: TestMainController (4.44s)
    --- PASS: TestMainController/test_crd_available (0.00s)
    --- PASS: TestMainController/test_controller_startup (1.00s)
    --- PASS: TestMainController/test_can_create_newresource (0.01s)
PASS
ok      github.com/obezsmertnyi/k8s-master/mastering-k8s/new-controller/test    4.461s
```

## 🚀 Deployment

### Step 1: Install CRD

```bash
# Apply CRD to cluster
kubectl apply -f config/crd/bases/apps.newresource.com_newresources.yaml

# Verify CRD is installed
kubectl get crd newresources.apps.newresource.com
```

### Step 2: Run Controller Locally

```bash
# Run controller (requires kubeconfig)
./bin/manager

# Or run with Go
go run main.go
```

**Expected output:**
```
2025-01-28T01:54:34+02:00       INFO    controller-runtime.metrics      Metrics server is starting to listen    {"addr": ":8080"}
2025-01-28T01:54:34+02:00       INFO    setup   starting manager
2025-01-28T01:54:34+02:00       INFO    controller-runtime.manager      Starting server {"name": "health probe", "addr": "[::]:8081"}
2025-01-28T01:54:34+02:00       INFO    controller-runtime.manager.controller.newresource      Starting EventSource    {"reconciler group": "apps.newresource.com", "reconciler kind": "NewResource", "source": "kind source: *v1alpha1.NewResource"}
2025-01-28T01:54:34+02:00       INFO    controller-runtime.manager.controller.newresource      Starting Controller     {"reconciler group": "apps.newresource.com", "reconciler kind": "NewResource"}
2025-01-28T01:54:34+02:00       INFO    controller-runtime.manager.controller.newresource      Starting workers        {"reconciler group": "apps.newresource.com", "reconciler kind": "NewResource", "worker count": 1}
```

### Step 3: Create Test Resource

In another terminal:

```bash
# Create a NewResource instance
cat <<EOF | kubectl apply -f -
apiVersion: apps.newresource.com/v1alpha1
kind: NewResource
metadata:
  name: example-resource
  namespace: default
spec:
  foo: "hello world"
EOF

# Verify resource was created
kubectl get newresource example-resource -o yaml
```

**Expected output:**
```yaml
apiVersion: apps.newresource.com/v1alpha1
kind: NewResource
metadata:
  name: example-resource
  namespace: default
spec:
  foo: hello world
status:
  ready: true  # ← Set by controller
```

### Step 4: Verify Controller Logs

Check controller logs to see reconciliation:

```
2025-01-28T01:55:00+02:00       INFO    controller-runtime.manager.controller.newresource      Reconciling     {"reconciler group": "apps.newresource.com", "reconciler kind": "NewResource", "name": "example-resource", "namespace": "default"}
```

## 📊 Verification

### Check Controller Status

```bash
# List all NewResource objects
kubectl get newresources -A

# Describe a specific resource
kubectl describe newresource example-resource

# Watch for changes
kubectl get newresources -w
```

### Access Metrics

The controller exposes metrics on port 8080:

```bash
# View metrics
curl http://localhost:8080/metrics

# Key metrics to look for:
# - controller_runtime_reconcile_total
# - controller_runtime_reconcile_errors_total
# - controller_runtime_reconcile_time_seconds
```

## 🎓 Key Concepts Learned

1. **Custom Resource Definitions (CRDs):**
   - Define custom Kubernetes resources
   - Use kubebuilder markers for code generation
   - Separate spec (desired state) from status (actual state)

2. **Controller Pattern:**
   - Watch for resource changes
   - Reconcile actual state to desired state
   - Handle errors gracefully

3. **Controller-Runtime Library:**
   - Manager: Orchestrates controllers and shared dependencies
   - Client: Interact with Kubernetes API
   - Reconciler: Core business logic

4. **Testing:**
   - Use envtest for integration testing
   - Test CRD availability
   - Test controller startup and reconciliation

## 🔄 Next Steps

- **Task 02-2:** Implement tests and collect controller metrics
- **Task 02-3:** Run controller with leader election
- Add validation webhooks
- Implement finalizers for cleanup
- Add more complex reconciliation logic

## 📚 References

- [Controller-Runtime Documentation](https://pkg.go.dev/sigs.k8s.io/controller-runtime)
- [Kubebuilder Book](https://book.kubebuilder.io/)
- [Kubernetes API Conventions](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md)
- [Writing Controllers](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/#custom-controllers)

---

**Status:** ✅ Complete  
**Date:** 2025-01-28  
**Tests:** All passing (3/3)
