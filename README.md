# Kubernetes Mastering Course

This repository contains completed tasks and exercises from the "Mastering Kubernetes" course.

## 📚 Course Structure

All tasks are organized in the [`tasks/`](./tasks/) directory, divided by modules.

## ✅ Completed Tasks

### Module 01: Control Plane & Node Management

| Task | Level | Status | Description | Files |
|------|-------|--------|-------------|-------|
| 01-1 | Basic | ✅ Complete | Static Pods for control plane components | [Details](./tasks/01-module/01-1.md) |
| 01-2 | Advanced | ✅ Complete | kube-apiserver profiling with flame graph | [Script](./tasks/01-module/01-2.sh), [Flame Graph](./tasks/01-module/01-2-flame.svg) |
| 01-3 | Expert | ✅ Complete | GCP Cloud Controller Manager with LoadBalancer | [Script](./tasks/01-module/01.3.sh), [Results](./tasks/01-module/01.3-done.md) |
| 01-4 | Basic | ✅ Complete | Command history practice | |
| 01-5 | Advanced | ✅ Complete | Register node to control plane via kubeconfig | [Guide](./tasks/01-module/01-5-node-registration-kubeconfig.md), [Script](./tasks/01-module/01-5-worker.sh), [Results](./tasks/01-module/01-5.png) |
| 01-6 | Expert | 📝 Planned | Register node to control plane via CSR | [Guide](./tasks/01-module/01-6-node-registration-csr.md), [Script](./tasks/01-module/01-6.sh) |

**Module 01 Highlights:**
- ✅ Deployed control plane using kubelet static pods
- ✅ Generated flame graph for kube-apiserver performance analysis
- ✅ Configured GCP Cloud Controller Manager with mock metadata server
- ✅ Successfully provisioned LoadBalancer with external IP: `34.173.163.108`

---

## 🔄 In Progress

### Module 02: Custom Kubernetes Controller

| Task | Level | Status | Description | Files |
|------|-------|--------|-------------|-------|
| 02-1 | Basic | ✅ Complete | Create, build and run first custom controller | [Guide](./tasks/02-module/02-1-first-controller.md), [Code](./mastering-k8s/new-controller/) |
| 02-2 | Advanced | ✅ Complete | Implement tests and collect controller metrics | [Guide](./tasks/02-module/02-2-tests-and-metrics.md), [Metrics Script](./tasks/02-module/02-2-check-metrics.sh) |
| 02-3 | Expert | ✅ Complete | Run controller in control plane with leader election | [Guide](./tasks/02-module/02-3-leader-election.md), [Manifests](./mastering-k8s/k8s-manifests/) |
| 02-4 | Basic | 📝 Planned | Build GitOps loop with automated image updates | [Guide](./tasks/02-module/02-4-gitops-loop.md) |
| 02-5 | Advanced | 📝 Planned | Break GitOps loop, migrate to gitless and solve imageupdate | [Guide](./tasks/02-module/02-5-gitless-imageupdate.md) |
| 02-6 | Expert | 📝 Planned | Configure ephemeral environments for GitHub PRs | [Guide](./tasks/02-module/02-6-ephemeral-environments.md) |

**Learning Path:**
- **Beginners**: Try to build a GitOps loop for an application with automated image updates (Task 02-4)
- **Experienced**: Break the GitOps loop, migrate to gitless approach and solve the imageupdate challenge (Task 02-5)
- **Advanced**: Configure ephemeral environments for GitHub Pull Requests using [Flux Operator ResourceSets](https://fluxcd.control-plane.io/operator/resourcesets/github-pull-requests/) (Task 02-6)

---

---

## 🛠 Technical Stack

- **Kubernetes:** v1.30.0
- **Container Runtime:** containerd 1.7.27
- **Cloud Provider:** Google Cloud Platform (GCP)
- **Operating System:** Ubuntu 24.04.3 LTS
- **Tools:** kubectl, kubebuilder, gcloud CLI, perf, FlameGraph

---

## 📖 Documentation

Detailed documentation for each task can be found in the respective module directories:

- [Module 01 Tasks](./tasks/01-module/)
- [Module 02 Tasks](./tasks/02-module/) _(coming soon)_

---

## 🚀 Quick Start

To explore completed tasks:

```bash
# Navigate to tasks directory
cd tasks/

# Module 01 - Control Plane Setup
cd 01-module/

# Run GCP CCM setup (Module 01-3)
source 01.3.sh
```

---

## 📝 Notes

All scripts and configurations are production-ready and follow Kubernetes best practices. Service account keys and sensitive data are stored outside the repository.

---

## 👤 Author

Completed as part of the "Mastering Kubernetes" course @ fwdays
