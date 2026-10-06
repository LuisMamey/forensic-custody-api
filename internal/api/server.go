// Package api implements the HTTP handlers that expose the forensic
// custody domain (cases, evidence, and custody logs) over REST.
package api

import (
	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// Server encapsulates HTTP handlers and dependencies for the forensic API.
type Server struct {
	repo      storage.Repository
	tsaClient crypto.TSAClient
}

// NewServer initializes a new Server with required dependencies.
func NewServer(repo storage.Repository, tsaClient crypto.TSAClient) *Server {
	return &Server{
		repo:      repo,
		tsaClient: tsaClient,
	}
}