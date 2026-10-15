// Package telemetry provides Prometheus metrics and OpenTelemetry-aligned instrumentation
// for the forensic custody API microservice.
package telemetry

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// HTTPRequestsTotal counts the total number of HTTP requests processed, partitioned by method, path, and status code.
	HTTPRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "forensic_http_requests_total",
			Help: "Total number of HTTP requests processed by the forensic API.",
		},
		[]string{"method", "path", "status"},
	)

	// HTTPRequestDuration tracks request latencies in seconds with SLI/SLO aligned histogram buckets.
	HTTPRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "forensic_http_request_duration_seconds",
			Help:    "Latency of HTTP requests in seconds.",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0},
		},
		[]string{"method", "path"},
	)

	// CryptoHashingDuration measures the duration of dual streaming hash computation (SHA-256 + SHA-512).
	CryptoHashingDuration = promauto.NewHistogram(
		prometheus.HistogramOpts{
			Name:    "forensic_crypto_hashing_duration_seconds",
			Help:    "Duration of evidence payload dual-hash streaming computation.",
			Buckets: []float64{0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 10.0},
		},
	)

	// CustodyTransitionsTotal tracks the total number of custody transitions executed across states.
	CustodyTransitionsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "forensic_custody_transitions_total",
			Help: "Total number of evidence custody chain state transitions.",
		},
		[]string{"action", "status"},
	)
)
