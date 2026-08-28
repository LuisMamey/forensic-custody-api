// Package api implements the HTTP handlers that expose the forensic
// custody domain (cases, evidence, and custody logs) over REST.
package api

import (
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// Server holds the dependencies shared by all HTTP handlers.
type Server struct {
	repo storage.Repository
}

// NewServer creates a Server backed by the given repository.
func NewServer(repo storage.Repository) *Server {
	return &Server{repo: repo}
}