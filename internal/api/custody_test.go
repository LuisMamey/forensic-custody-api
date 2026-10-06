package api_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/LuisMamey/forensic-custody-api/internal/api"
	"github.com/LuisMamey/forensic-custody-api/internal/models"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

func TestCustodyLedger_ChainedIntegration(t *testing.T) {
	repo := storage.NewMemoryStorage()
	server := api.NewServer(repo)

	caseItem := models.Case{ID: "case-001", Title: "Investigation Alpha"}
	if err := repo.CreateCase(caseItem); err != nil {
		t.Fatalf("failed to create case: %v", err)
	}

	evidenceItem := models.EvidenceItem{ID: "evi-001", CaseID: "case-001", Description: "SSD Drive"}
	if err := repo.CreateEvidence(evidenceItem); err != nil {
		t.Fatalf("failed to create evidence: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /evidence/{evidenceID}/custody-logs", server.AddCustodyLog)
	mux.HandleFunc("GET /evidence/{evidenceID}/custody-logs/verify", server.VerifyCustodyChain)

	payload0, _ := json.Marshal(models.CustodyLog{
		TransferredBy: "Officer A",
		TransferredTo: "Evidence Locker",
		ActionTaken:   "SEIZED",
	})
	req0 := httptest.NewRequest("POST", "/evidence/evi-001/custody-logs", bytes.NewReader(payload0))
	rec0 := httptest.NewRecorder()
	mux.ServeHTTP(rec0, req0)

	if rec0.Code != http.StatusCreated {
		t.Fatalf("block 0 failed: %s", rec0.Body.String())
	}

	var block0 models.CustodyLog
	json.NewDecoder(rec0.Body).Decode(&block0)

	if block0.SequenceNumber != 0 {
		t.Errorf("expected seq 0, got %d", block0.SequenceNumber)
	}
	if block0.PreviousHash != models.GenesisHash {
		t.Errorf("expected genesis hash, got %s", block0.PreviousHash)
	}

	payload1, _ := json.Marshal(models.CustodyLog{
		TransferredBy: "Evidence Locker",
		TransferredTo: "Courier B",
		ActionTaken:   "IN_TRANSIT",
	})
	req1 := httptest.NewRequest("POST", "/evidence/evi-001/custody-logs", bytes.NewReader(payload1))
	rec1 := httptest.NewRecorder()
	mux.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("block 1 failed: %s", rec1.Body.String())
	}

	var block1 models.CustodyLog
	json.NewDecoder(rec1.Body).Decode(&block1)

	if block1.SequenceNumber != 1 {
		t.Errorf("expected seq 1, got %d", block1.SequenceNumber)
	}
	if block1.PreviousHash != block0.BlockHash {
		t.Errorf("chain mismatch: block 1 previous_hash %s != block 0 block_hash %s", block1.PreviousHash, block0.BlockHash)
	}

	verifyReq := httptest.NewRequest("GET", "/evidence/evi-001/custody-logs/verify", nil)
	verifyRec := httptest.NewRecorder()
	mux.ServeHTTP(verifyRec, verifyReq)

	if verifyRec.Code != http.StatusOK {
		t.Fatalf("verification endpoint failed: %s", verifyRec.Body.String())
	}

	var report api.VerificationResponse
	json.NewDecoder(verifyRec.Body).Decode(&report)

	if !report.ChainValid {
		t.Errorf("expected chain_valid true, got false. Error: %s", report.ErrorMessage)
	}
	if report.TotalBlocks != 2 {
		t.Errorf("expected 2 total blocks, got %d", report.TotalBlocks)
	}
}
