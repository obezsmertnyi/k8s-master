package controllers

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var (
	// ReconcileTotal counts total reconciliations
	ReconcileTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "newresource_reconcile_total",
			Help: "Total number of reconciliations per controller",
		},
		[]string{"controller", "result"},
	)

	// ReconcileDuration tracks reconciliation duration
	ReconcileDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "newresource_reconcile_duration_seconds",
			Help:    "Duration of reconciliations in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"controller"},
	)

	// ReconcileErrors counts reconciliation errors
	ReconcileErrors = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "newresource_reconcile_errors_total",
			Help: "Total number of reconciliation errors",
		},
		[]string{"controller", "error_type"},
	)

	// ResourcesReady tracks number of ready resources
	ResourcesReady = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "newresource_resources_ready",
			Help: "Number of NewResource objects with ready status",
		},
		[]string{"namespace"},
	)
)

func init() {
	// Register custom metrics with the global prometheus registry
	metrics.Registry.MustRegister(
		ReconcileTotal,
		ReconcileDuration,
		ReconcileErrors,
		ResourcesReady,
	)
}
