// controllers/resource_controller.go
package controllers

import (
	"context"
	"time"

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
	startTime := time.Now()

	// Defer metrics recording
	defer func() {
		duration := time.Since(startTime).Seconds()
		ReconcileDuration.WithLabelValues("newresource").Observe(duration)
	}()

	var resource newv1.NewResource
	if err := r.Get(ctx, req.NamespacedName, &resource); err != nil {
		if client.IgnoreNotFound(err) != nil {
			ReconcileErrors.WithLabelValues("newresource", "get_error").Inc()
			ReconcileTotal.WithLabelValues("newresource", "error").Inc()
			return ctrl.Result{}, err
		}
		// Resource not found, likely deleted
		ReconcileTotal.WithLabelValues("newresource", "not_found").Inc()
		return ctrl.Result{}, nil
	}

	logger.Info("Reconciling", "name", resource.Name, "namespace", resource.Namespace)

	// Update status
	resource.Status.Ready = true
	if err := r.Status().Update(ctx, &resource); err != nil {
		ReconcileErrors.WithLabelValues("newresource", "status_update_error").Inc()
		ReconcileTotal.WithLabelValues("newresource", "error").Inc()
		return ctrl.Result{}, err
	}

	// Update ready gauge
	ResourcesReady.WithLabelValues(resource.Namespace).Inc()

	// Record successful reconciliation
	ReconcileTotal.WithLabelValues("newresource", "success").Inc()

	return ctrl.Result{}, nil
}

func (r *NewResourceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&newv1.NewResource{}).
		Complete(r)
}
