// Command api starts the HTTP server that exposes the forensic custody API.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/api"
	"github.com/LuisMamey/forensic-custody-api/internal/auth"
	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/LuisMamey/forensic-custody-api/internal/telemetry"
)

// main initializes the in-memory repository, registers the HTTP routes,
// and starts the server listening on port 8080.
func main() {
	repo := storage.NewMemoryStorage()
	tsa := crypto.NewHTTPTSAClient("https://freetsa.org/tsr", 3*time.Second)
	server := api.NewServer(repo, tsa)

	// In a production deployment, this secret is injected via AWS Secrets Manager / ESO
	tokenSvc := auth.NewTokenService("forensic-custody-enterprise-secret-key-32b")

	// RBAC Middleware helpers
	anyAuthenticated := auth.RequireRole(tokenSvc,
		auth.RoleInvestigator,
		auth.RoleLabAnalyst,
		auth.RoleEvidenceCustodian,
		auth.RoleAuditor,
	)
	investigatorOnly := auth.RequireRole(tokenSvc, auth.RoleInvestigator)
	evidenceIntake := auth.RequireRole(tokenSvc, auth.RoleInvestigator, auth.RoleEvidenceCustodian)
	custodyTransfer := auth.RequireRole(tokenSvc, auth.RoleLabAnalyst, auth.RoleEvidenceCustodian)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)

	// Case management
	mux.Handle("POST /cases", investigatorOnly(http.HandlerFunc(server.CreateCase)))
	mux.Handle("GET /cases", anyAuthenticated(http.HandlerFunc(server.ListCases)))

	// Evidence intake and streaming
	mux.Handle("POST /cases/{caseID}/evidence", evidenceIntake(http.HandlerFunc(server.CreateEvidence)))
	mux.Handle("POST /cases/{caseID}/evidence/upload", evidenceIntake(http.HandlerFunc(server.UploadEvidencePayload)))
	mux.Handle("GET /cases/{caseID}/evidence", anyAuthenticated(http.HandlerFunc(server.ListEvidenceByCase)))

	// Custody ledger and verification
	mux.Handle("POST /evidence/{evidenceID}/custody-logs", custodyTransfer(http.HandlerFunc(server.AddCustodyLog)))
	mux.Handle("GET /evidence/{evidenceID}/custody-logs", anyAuthenticated(http.HandlerFunc(server.ListCustodyLogsByEvidence)))
	mux.Handle("GET /evidence/{evidenceID}/custody-logs/verify", anyAuthenticated(http.HandlerFunc(server.VerifyCustodyChain)))

	// Prometheus metrics endpoint
	mux.Handle("GET /metrics", promhttp.Handler())

	// TLS is intentionally terminated at the edge (AWS ALB) — see docs/adr/0001-tls-termination.md.
	// nosemgrep: go.lang.security.audit.net.use-tls.use-tls
	srv := &http.Server{
		Addr:              ":8080",
		Handler:           securityHeaders(telemetry.MetricsMiddleware(mux)),
		ReadHeaderTimeout: 5 * time.Second,  // Slowloris mitigation
		ReadTimeout:       15 * time.Second, // Max time to read request body
		WriteTimeout:      30 * time.Second, // Max time to stream response / compute crypto
		IdleTimeout:       60 * time.Second, // Keep-alive connection pool hygiene
	}

	// Trap OS termination signals for Graceful Shutdown
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Run the HTTP server in an asynchronous goroutine
	serverErrors := make(chan error, 1)
	go func() {
		log.Println("listening on :8080 (hardened net/http server)")
		// nosemgrep: go.lang.security.audit.net.use-tls.use-tls
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			serverErrors <- err
		}
	}()

	// Block until receiving a termination signal or encountering an unexpected startup error
	select {
	case err := <-serverErrors:
		log.Fatalf("server encountered unexpected fatal error: %v", err)
	case <-ctx.Done():
		log.Println("shutdown signal received, commencing graceful drain of active connections...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Printf("graceful shutdown failed, forcing server closure: %v", err)
			if closeErr := srv.Close(); closeErr != nil {
				log.Fatalf("error forcing server closure: %v", closeErr)
			}
		}
		log.Println("graceful shutdown completed successfully")
	}
}

// healthHandler reports that the service is up and reachable.
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// securityHeaders adds baseline HTTP security headers to every response.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		next.ServeHTTP(w, r)
	})
}
