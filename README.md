# Kubernetes Mastering Course

This repository contains completed tasks and exercises from the "Mastering Kubernetes" course.

## 📚 Course Structure

All tasks are organized in the [`tasks/`](./tasks/) directory, divided by modules.

## ✅ Completed Tasks

### Module 01: Control Plane Setup

| Task | Level | Status | Description | Files |
|------|-------|--------|-------------|-------|
| 01-1 | Basic | ✅ Complete | Static Pods for control plane components | [Details](./tasks/01-module/01-1.md) |
| 01-2 | Advanced | ✅ Complete | kube-apiserver profiling with flame graph | [Script](./tasks/01-module/01-2.sh), [Flame Graph](./tasks/01-module/01-2-flame.svg) |
| 01-3 | Expert | ✅ Complete | GCP Cloud Controller Manager with LoadBalancer | [Script](./tasks/01-module/01.3.sh), [Results](./tasks/01-module/01.3-done.md) |

**Module 01 Highlights:**
- ✅ Deployed control plane using kubelet static pods
- ✅ Generated flame graph for kube-apiserver performance analysis
- ✅ Configured GCP Cloud Controller Manager with mock metadata server
- ✅ Successfully provisioned LoadBalancer with external IP: `34.173.163.108`

---

## 🔄 In Progress

### Module 02: Custom Kubernetes Controller

| Task | Level | Status | Description |
|------|-------|--------|-------------|
| 02-1 | Basic | 📝 Planned | Create, build and run first custom controller |
| 02-2 | Advanced | 📝 Planned | Implement tests and collect controller metrics |
| 02-3 | Expert | 📝 Planned | Run controller in control plane with leader election |

---

### Module 03: GitOps with FluxCD

| Task | Level | Status | Description |
|------|-------|--------|-------------|
| 03-1 | Basic | 📝 Planned | Build GitOps loop with automated image updates |
| 03-2 | Advanced | 📝 Planned | Break GitOps loop, migrate to gitless and solve imageupdate |
| 03-3 | Expert | 📝 Planned | Configure ephemeral environments for GitHub PRs |

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
