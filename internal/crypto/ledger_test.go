package crypto_test

import (
	"testing"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
)

func TestVerifyLedgerChain_ValidSequence(t *testing.T) {
	genesis := "0000000000000000000000000000000000000000000000000000000000000000"
	evidenceID := "evi-test-999"

	t0 := time.Now().UTC()
	t1 := t0.Add(1 * time.Hour)
	t2 := t1.Add(2 * time.Hour)

	h0 := crypto.ComputeBlockHash(evidenceID, 0, "Officer A", "Evidence Locker", "SEIZED", genesis, t0)
	b0 := crypto.BlockData{EvidenceID: evidenceID, Sequence: 0, From: "Officer A", To: "Evidence Locker", Action: "SEIZED", PreviousHash: genesis, BlockHash: h0, Timestamp: t0}

	h1 := crypto.ComputeBlockHash(evidenceID, 1, "Evidence Locker", "Courier B", "IN_TRANSIT", h0, t1)
	b1 := crypto.BlockData{EvidenceID: evidenceID, Sequence: 1, From: "Evidence Locker", To: "Courier B", Action: "IN_TRANSIT", PreviousHash: h0, BlockHash: h1, Timestamp: t1}

	h2 := crypto.ComputeBlockHash(evidenceID, 2, "Courier B", "Forensic Lab", "DELIVERED_TO_LAB", h1, t2)
	b2 := crypto.BlockData{EvidenceID: evidenceID, Sequence: 2, From: "Courier B", To: "Forensic Lab", Action: "DELIVERED_TO_LAB", PreviousHash: h1, BlockHash: h2, Timestamp: t2}

	chain := []crypto.BlockData{b0, b1, b2}

	valid, err := crypto.VerifyLedgerChain(chain, genesis)
	if !valid || err != nil {
		t.Fatalf("expected valid chain, got error: %v", err)
	}
}

func TestVerifyLedgerChain_DetectTampering(t *testing.T) {
	genesis := "0000000000000000000000000000000000000000000000000000000000000000"
	evidenceID := "evi-tamper-001"

	t0 := time.Now().UTC()
	t1 := t0.Add(1 * time.Hour)

	h0 := crypto.ComputeBlockHash(evidenceID, 0, "Officer A", "Locker", "SEIZED", genesis, t0)
	b0 := crypto.BlockData{EvidenceID: evidenceID, Sequence: 0, From: "Officer A", To: "Locker", Action: "SEIZED", PreviousHash: genesis, BlockHash: h0, Timestamp: t0}

	h1 := crypto.ComputeBlockHash(evidenceID, 1, "Locker", "Courier", "IN_TRANSIT", h0, t1)
	b1 := crypto.BlockData{EvidenceID: evidenceID, Sequence: 1, From: "Locker", To: "Courier", Action: "IN_TRANSIT", PreviousHash: h0, BlockHash: h1, Timestamp: t1}

	b0Tampered := b0
	b0Tampered.Action = "ALTERED_ACTION_WITHOUT_REHASH"

	tamperedChain := []crypto.BlockData{b0Tampered, b1}

	valid, err := crypto.VerifyLedgerChain(tamperedChain, genesis)
	if valid || err == nil {
		t.Fatal("expected tampering detection, but chain was verified as valid")
	}
}
