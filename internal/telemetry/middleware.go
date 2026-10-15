package telemetry

import (
	"net/http"
	"strconv"
	"time"
)

// responseWriterInterceptor captures the HTTP status code returned by the handler.
type responseWriterInterceptor struct {
	http.ResponseWriter
	statusCode int
}

func (w *responseWriterInterceptor) WriteHeader(code int) {
	w.statusCode = code
	w.ResponseWriter.WriteHeader(code)
}

// MetricsMiddleware instruments an HTTP handler, recording request duration and count metrics.
func MetricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Do not record metrics for the metrics endpoint itself or health probe
		if r.URL.Path == "/metrics" || r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()
		interceptor := &responseWriterInterceptor{
			ResponseWriter: w,
			statusCode:     http.StatusOK, // Default if WriteHeader is omitted
		}

		next.ServeHTTP(interceptor, r)

		duration := time.Since(start).Seconds()
		statusStr := strconv.Itoa(interceptor.statusCode)

		HTTPRequestsTotal.WithLabelValues(r.Method, r.URL.Path, statusStr).Inc()
		HTTPRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
	})
}
