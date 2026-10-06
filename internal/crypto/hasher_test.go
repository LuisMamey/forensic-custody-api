package crypto_test

import (
	"bytes"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"strings"
	"testing"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
)

func TestComputeDualStreamHash(t *testing.T) {
	payload := "forensic-evidence-sample-payload-2026"
	reader := strings.NewReader(payload)

	result, err := crypto.ComputeDualStreamHash(reader)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expected256Raw := sha256.Sum256([]byte(payload))
	expected256 := hex.EncodeToString(expected256Raw[:])

	expected512Raw := sha512.Sum512([]byte(payload))
	expected512 := hex.EncodeToString(expected512Raw[:])

	if result.SHA256 != expected256 {
		t.Errorf("SHA256 mismatch: got %s, want %s", result.SHA256, expected256)
	}

	if result.SHA512 != expected512 {
		t.Errorf("SHA512 mismatch: got %s, want %s", result.SHA512, expected512)
	}

	if result.BytesRead != int64(len(payload)) {
		t.Errorf("BytesRead mismatch: got %d, want %d", result.BytesRead, len(payload))
	}
}

func TestComputeDualStreamHash_EmptyPayload(t *testing.T) {
	reader := bytes.NewReader([]byte{})

	result, err := crypto.ComputeDualStreamHash(reader)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.BytesRead != 0 {
		t.Errorf("expected 0 bytes read, got %d", result.BytesRead)
	}

	empty256 := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	if result.SHA256 != empty256 {
		t.Errorf("expected empty SHA256 %s, got %s", empty256, result.SHA256)
	}
}

func TestComputeDualStreamHash_NilReader(t *testing.T) {
	_, err := crypto.ComputeDualStreamHash(nil)
	if err == nil {
		t.Fatal("expected error for nil reader, got nil")
	}
}
