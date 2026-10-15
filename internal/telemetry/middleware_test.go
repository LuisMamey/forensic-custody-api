package telemetry_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/LuisMamey/forensic-custody-api/internal/telemetry"
)

func TestMetricsMiddleware_RecordsMetricsAndExposesEndpoint(t *testing.T) {
	mux := http.NewServeMux()

	// Sample business endpoint
	mux.HandleFunc("GET /test-endpoint", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	// Prometheus metrics endpoint
	mux.Handle("GET /metrics", promhttp.Handler())

	// Wrap mux with telemetry middleware
	handler := telemetry.MetricsMiddleware(mux)

	// 1. Simulate a request to the business endpoint to trigger metric emission
	req := httptest.NewRequest(http.MethodGet, "/test-endpoint", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	// 2. Fetch the /metrics endpoint and verify Prometheus text format
	metricsReq := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	metricsRec := httptest.NewRecorder()
	handler.ServeHTTP(metricsRec, metricsReq)

	if metricsRec.Code != http.StatusOK {
		t.Fatalf("expected /metrics status 200, got %d", metricsRec.Code)
	}

	body := metricsRec.Body.String()

	// Verify our custom metric names exist in the Prometheus output
	expectedMetrics := []string{
		"forensic_http_requests_total",
		"forensic_http_request_duration_seconds",
		"path=\"/test-endpoint\"",
		"status=\"200\"",
	}

	for _, expected := range expectedMetrics {
		if !strings.Contains(body, expected) {
			t.Errorf("expected /metrics to contain %q, but was not found", expected)
		}
	}
}
