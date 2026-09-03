// Command api starts the HTTP server that exposes the forensic custody API.
package main

import (
	"log"
	"net/http"

	"github.com/LuisMamey/forensic-custody-api/internal/api"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// main initializes the in-memory repository, registers the HTTP routes,
// and starts the server listening on port 8080.
func main() {
	repo := storage.NewMemoryStorage()
	server := api.NewServer(repo)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)
	mux.HandleFunc("POST /cases", server.CreateCase)
	mux.HandleFunc("GET /cases", server.ListCases)
	mux.HandleFunc("POST /cases/{caseID}/evidence", server.CreateEvidence)
	mux.HandleFunc("GET /cases/{caseID}/evidence", server.ListEvidenceByCase)
	mux.HandleFunc("POST /evidence/{evidenceID}/custody-logs", server.AddCustodyLog)
	mux.HandleFunc("GET /evidence/{evidenceID}/custody-logs", server.ListCustodyLogsByEvidence)

	log.Println("listening on :8080")

	// TLS is intentionally not handled here — see docs/adr/0001-tls-termination.md.
	// nosemgrep: go.lang.security.audit.net.use-tls.use-tls
	log.Fatal(http.ListenAndServe(":8080", mux))
}

// healthHandler reports that the service is up and reachable.
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}