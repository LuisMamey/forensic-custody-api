package api

import (
	"encoding/json"
	"net/http"

	"github.com/LuisMamey/forensic-custody-api/internal/models"
)

// CreateCase handles POST /cases. It decodes a Case from the request body,
// assigns it a new unique identifier, stores it, and responds with the
// created resource as JSON.
func (s *Server) CreateCase(w http.ResponseWriter, r *http.Request) {
	var c models.Case
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	id, err := generateID()
	if err != nil {
		http.Error(w, "failed to generate id", http.StatusInternalServerError)
		return
	}
	c.ID = id

	if err := s.repo.CreateCase(c); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(c)
}

// ListCases handles GET /cases. It returns every registered case as JSON.
func (s *Server) ListCases(w http.ResponseWriter, r *http.Request) {
	cases, err := s.repo.ListCases()
	if err != nil {
		http.Error(w, "failed to list cases", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(cases)
}
