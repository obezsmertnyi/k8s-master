# Task 02-2: Implement Tests and Collect Controller Metrics

**Level:** Advanced  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** ✅ Complete

---

## 📋 Overview

This task focuses on running existing tests from [Task 02-1](./02-1-first-controller.md) and exploring the built-in metrics that controller-runtime automatically exposes.

## 🎯 Objectives

- Run controller tests with envtest
- Check test coverage
- Explore built-in Prometheus metrics

## 📦 Prerequisites

- Completed [Task 02-1](./02-1-first-controller.md)
- setup-envtest installed

## 🧪 Running Tests

### Run All Tests

```bash
cd mastering-k8s/new-controller

# Set KUBEBUILDER_ASSETS
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

### Check Test Coverage

```bash
# Run tests with coverage
go test ./test -coverprofile=coverage.out

# View coverage report
go tool cover -func=coverage.out

# Open HTML coverage report
go tool cover -html=coverage.out
```

## 📊 Exploring Metrics

### Start Controller

```bash
# Run controller
go run main.go
```

Controller exposes metrics on `http://localhost:8080/metrics`

### View Metrics

Use the provided script:

```bash
chmod +x ../../tasks/02-module/02-2-check-metrics.sh
../../tasks/02-module/02-2-check-metrics.sh
```

Or manually:

```bash
# View all newresource controller metrics
curl -s http://localhost:8080/metrics | grep newresource

# View specific metrics
curl -s http://localhost:8080/metrics | grep controller_runtime_reconcile_time_seconds
curl -s http://localhost:8080/metrics | grep controller_runtime_reconcile_errors_total
curl -s http://localhost:8080/metrics | grep controller_runtime_active_workers
```

### Built-in Metrics Available

Controller-runtime automatically exposes these metrics:

**Reconciliation Metrics:**
- `controller_runtime_reconcile_time_seconds` - reconciliation duration (histogram)
- `controller_runtime_reconcile_errors_total` - total reconciliation errors
- `controller_runtime_reconcile_panics_total` - total panics during reconciliation
- `controller_runtime_terminal_reconcile_errors_total` - terminal errors

**Worker Metrics:**
- `controller_runtime_active_workers` - number of active workers
- `controller_runtime_max_concurrent_reconciles` - max concurrent reconciliations

**Workqueue Metrics:**
- `workqueue_adds_total` - total items added to queue
- `workqueue_depth` - current queue depth
- `workqueue_queue_duration_seconds` - time items spend in queue
- `workqueue_work_duration_seconds` - time to process items

**Example Output:**
```prometheus
controller_runtime_active_workers{controller="newresource"} 0
controller_runtime_max_concurrent_reconciles{controller="newresource"} 1
controller_runtime_reconcile_errors_total{controller="newresource"} 0
controller_runtime_reconcile_time_seconds_bucket{controller="newresource",le="0.005"} 1
controller_runtime_reconcile_time_seconds_bucket{controller="newresource",le="0.01"} 2
controller_runtime_reconcile_time_seconds_sum{controller="newresource"} 0.015
controller_runtime_reconcile_time_seconds_count{controller="newresource"} 2
```

## 🎓 Key Takeaways

1. **Tests:** Controller has integration tests that run with envtest
2. **Metrics:** Controller-runtime automatically exposes Prometheus metrics
3. **Monitoring:** Metrics are available at `:8080/metrics` endpoint
4. **Coverage:** Can measure test coverage with `go test -coverprofile`

## 🔄 Next Steps

- **Task 02-3:** Run controller with leader election
- Set up Prometheus to scrape metrics
- Create Grafana dashboards
- Add alerting rules

## 📚 References

- [Controller-Runtime Metrics](https://book.kubebuilder.io/reference/metrics.html)
- [Testing Controllers](https://book.kubebuilder.io/cronjob-tutorial/writing-tests.html)
- [Prometheus Metrics Types](https://prometheus.io/docs/concepts/metric_types/)

---

**Status:** ✅ Complete  
**Date:** 2025-01-28
