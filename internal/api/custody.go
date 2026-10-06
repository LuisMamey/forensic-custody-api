package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
	"github.com/LuisMamey/forensic-custody-api/internal/models"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

// AddCustodyLog handles POST /evidence/{evidenceID}/custody-logs. It appends
// an immutable, cryptographically chained block to the evidence's custody ledger.
func (s *Server) AddCustodyLog(w http.ResponseWriter, r *http.Request) {
	evidenceID := r.PathValue("evidenceID")

	if _, err := s.repo.GetEvidenceByID(evidenceID); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			http.Error(w, "evidence not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	var entry models.CustodyLog
	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	id, err := generateID()
	if err != nil {
		http.Error(w, "failed to generate id", http.StatusInternalServerError)
		return
	}

	existingLogs, err := s.repo.ListCustodyLogsByEvidenceID(evidenceID)
	if err != nil {
		http.Error(w, "failed to inspect existing custody chain", http.StatusInternalServerError)
		return
	}

	var seq int64
	prevHash := models.GenesisHash
	if len(existingLogs) > 0 {
		lastBlock := existingLogs[len(existingLogs)-1]
		seq = lastBlock.SequenceNumber + 1
		prevHash = lastBlock.BlockHash
	}

	now := time.Now().UTC()
	blockHash := crypto.ComputeBlockHash(
		evidenceID,
		seq,
		entry.TransferredBy,
		entry.TransferredTo,
		entry.ActionTaken,
		prevHash,
		now,
	)

	entry.ID = id
	entry.EvidenceID = evidenceID
	entry.SequenceNumber = seq
	entry.PreviousHash = prevHash
	entry.BlockHash = blockHash
	entry.IntegrityVerified = true
	entry.Timestamp = now

	if err := s.repo.AddCustodyLog(entry); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(entry)
}

// ListCustodyLogsByEvidence handles GET /evidence/{evidenceID}/custody-logs.
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

// VerificationResponse represents the forensic integrity report of a custody chain.
type VerificationResponse struct {
	EvidenceID   string `json:"evidence_id"`
	TotalBlocks  int    `json:"total_blocks"`
	ChainValid   bool   `json:"chain_valid"`
	ErrorMessage string `json:"error_message,omitempty"`
}

// VerifyCustodyChain handles GET /evidence/{evidenceID}/custody-logs/verify.
// It verifies the cryptographic integrity of the entire custody chain.
func (s *Server) VerifyCustodyChain(w http.ResponseWriter, r *http.Request) {
	evidenceID := r.PathValue("evidenceID")

	logs, err := s.repo.ListCustodyLogsByEvidenceID(evidenceID)
	if err != nil {
		http.Error(w, "failed to retrieve custody logs", http.StatusInternalServerError)
		return
	}

	blocks := make([]crypto.BlockData, len(logs))
	for i, l := range logs {
		blocks[i] = crypto.BlockData{
			EvidenceID:   l.EvidenceID,
			Sequence:     l.SequenceNumber,
			From:         l.TransferredBy,
			To:           l.TransferredTo,
			Action:       l.ActionTaken,
			PreviousHash: l.PreviousHash,
			BlockHash:    l.BlockHash,
			Timestamp:    l.Timestamp,
		}
	}

	valid, verifyErr := crypto.VerifyLedgerChain(blocks, models.GenesisHash)

	resp := VerificationResponse{
		EvidenceID:  evidenceID,
		TotalBlocks: len(logs),
		ChainValid:  valid,
	}
	if verifyErr != nil {
		resp.ErrorMessage = verifyErr.Error()
	}

	w.Header().Set("Content-Type", "application/json")
	if !valid {
		w.WriteHeader(http.StatusConflict)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	json.NewEncoder(w).Encode(resp)
}
