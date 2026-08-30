package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"
	"github.com/LuisMamey/forensic-custody-api/internal/models"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// CreateEvidence handles POST /cases/{caseID}/evidence. It decodes an
// EvidenceItem from the request body, associates it with the case in the
// URL path, assigns it a new unique identifier, and stores it.
func (s *Server) CreateEvidence(w http.ResponseWriter, r *http.Request) {
	caseID := r.PathValue("caseID")

	var e models.EvidenceItem
	if err := json.NewDecoder(r.Body).Decode(&e); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	e.CaseID = caseID
	if e.Status == "" {
		e.Status = models.EvidenceStatusSecured
	}

	id, err := generateID()
	if err != nil {
		http.Error(w, "failed to generate id", http.StatusInternalServerError)
		return
	}
	e.ID = id
	e.CreatedAt = time.Now().UTC()

	if err := s.repo.CreateEvidence(e); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			http.Error(w, "case not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(e)
}

// ListEvidenceByCase handles GET /cases/{caseID}/evidence. It returns every
// evidence item associated with the given case.
func (s *Server) ListEvidenceByCase(w http.ResponseWriter, r *http.Request) {
	caseID := r.PathValue("caseID")

	items, err := s.repo.ListEvidenceByCaseID(caseID)
	if err != nil {
		http.Error(w, "failed to list evidence", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}
