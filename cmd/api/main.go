// Command api starts the HTTP server that exposes the forensic custody API.
package main

import (
	"log"
	"net/http"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
	"github.com/LuisMamey/forensic-custody-api/internal/api"
	"github.com/LuisMamey/forensic-custody-api/internal/auth"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
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

	log.Println("listening on :8080")

	// TLS is intentionally not handled here — see docs/adr/0001-tls-termination.md.
	// nosemgrep: go.lang.security.audit.net.use-tls.use-tls
	log.Fatal(http.ListenAndServe(":8080", securityHeaders(mux)))
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
