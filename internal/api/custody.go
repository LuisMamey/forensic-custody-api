package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/models"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// AddCustodyLog handles POST /evidence/{evidenceID}/custody-logs. It decodes
// a CustodyLog from the request body, associates it with the evidence item
// in the URL path, assigns it a new unique identifier and timestamp, and
// appends it to the chain of custody.
func (s *Server) AddCustodyLog(w http.ResponseWriter, r *http.Request) {
	evidenceID := r.PathValue("evidenceID")

	var entry models.CustodyLog
	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	entry.EvidenceID = evidenceID

	id, err := generateID()
	if err != nil {
		http.Error(w, "failed to generate id", http.StatusInternalServerError)
		return
	}
	entry.ID = id
	entry.Timestamp = time.Now().UTC()

	if err := s.repo.AddCustodyLog(entry); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			http.Error(w, "evidence not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(entry)
}

// ListCustodyLogsByEvidence handles GET /evidence/{evidenceID}/custody-logs.
// It returns the full chain of custody for the given evidence item.
func (s *Server) ListCustodyLogsByEvidence(w http.ResponseWriter, r *http.Request) {
	evidenceID := r.PathValue("evidenceID")

	logs, err := s.repo.ListCustodyLogsByEvidenceID(evidenceID)
	if err != nil {
		http.Error(w, "failed to list custody logs", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(logs)
}
