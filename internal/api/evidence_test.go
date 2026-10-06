package api_test

import (
	"bytes"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/LuisMamey/forensic-custody-api/internal/api"
	"github.com/LuisMamey/forensic-custody-api/internal/models"
	"github.com/LuisMamey/forensic-custody-api/internal/storage"
)

func TestUploadEvidencePayload_StreamingIntegration(t *testing.T) {
	repo := storage.NewMemoryStorage()
	server := api.NewServer(repo)

	caseItem := models.Case{
		ID:               "case-corp-001",
		CaseNumber:       "INV-2026-001",
		Title:            "Ransomware Investigation",
		LeadInvestigator: "Agent Smith",
	}
	if err := repo.CreateCase(caseItem); err != nil {
		t.Fatalf("failed to create test case: %v", err)
	}

	payload := []byte("CRITICAL_MEMORY_VOLATILE_DUMP_STREAM_CONTENT")
	expected256Raw := sha256.Sum256(payload)
	expected256 := hex.EncodeToString(expected256Raw[:])

	expected512Raw := sha512.Sum512(payload)
	expected512 := hex.EncodeToString(expected512Raw[:])

	mux := http.NewServeMux()
	mux.HandleFunc("POST /cases/{caseID}/evidence/upload", server.UploadEvidencePayload)

	req := httptest.NewRequest("POST", "/cases/case-corp-001/evidence/upload", bytes.NewReader(payload))
	req.Header.Set("X-Evidence-Description", "Memory Dump Segment 1")
	req.Header.Set("X-Evidence-Type", "MEMORY_DUMP")

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}

	var created models.EvidenceItem
	if err := json.NewDecoder(rec.Body).Decode(&created); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if created.CaseID != "case-corp-001" {
		t.Errorf("expected CaseID case-corp-001, got %s", created.CaseID)
	}
	if created.SHA256Hash != expected256 {
		t.Errorf("SHA256 mismatch:\ngot  %s\nwant %s", created.SHA256Hash, expected256)
	}
	if created.SHA512Hash != expected512 {
		t.Errorf("SHA512 mismatch:\ngot  %s\nwant %s", created.SHA512Hash, expected512)
	}
	if created.SizeBytes != int64(len(payload)) {
		t.Errorf("SizeBytes mismatch: got %d, want %d", created.SizeBytes, len(payload))
	}
}
