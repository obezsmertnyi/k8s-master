#!/bin/bash

# Script to check controller metrics
# Task 02-2: Implement tests and collect controller metrics

echo "=== Checking Controller Metrics ==="
echo ""

# Check if controller is running
if ! curl -s http://localhost:8080/metrics > /dev/null 2>&1; then
    echo "Controller is not running on localhost:8080"
    echo "Please start the controller first:"
    echo "  cd mastering-k8s/new-controller"
    echo "  go run main.go"
    exit 1
fi

echo "Controller is running"
echo ""

# Display controller-runtime metrics for newresource controller
echo "=== NewResource Controller Metrics ==="
echo ""

echo "All NewResource Metrics:"
curl -s http://localhost:8080/metrics | grep "newresource"
echo ""

echo "=== Built-in Controller-Runtime Metrics ==="
echo ""

echo "Reconciliation Time:"
curl -s http://localhost:8080/metrics | grep "controller_runtime_reconcile_time_seconds" | grep "newresource"
echo ""

echo "Reconciliation Errors:"
curl -s http://localhost:8080/metrics | grep "controller_runtime_reconcile_errors_total" | grep "newresource"
echo ""

echo "Active Workers:"
curl -s http://localhost:8080/metrics | grep "controller_runtime_active_workers" | grep "newresource"
echo ""

echo "Workqueue Metrics:"
curl -s http://localhost:8080/metrics | grep "^workqueue" | head -10
echo ""

echo "=== All Metrics Available at: http://localhost:8080/metrics ==="
