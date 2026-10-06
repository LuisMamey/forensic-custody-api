package crypto_test

import (
	"crypto/sha256"
	"encoding/asn1"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
)

func TestRFC3161_RequestAndEncode(t *testing.T) {
	mockTSA := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Content-Type") != "application/timestamp-query" {
			t.Errorf("expected application/timestamp-query, got %s", r.Header.Get("Content-Type"))
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		var req crypto.TimeStampReq
		if _, err := asn1.Unmarshal(body, &req); err != nil {
			t.Errorf("failed to parse ASN.1 TimeStampReq: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		if req.Version != 1 {
			t.Errorf("expected RFC 3161 version 1, got %d", req.Version)
		}

		w.Header().Set("Content-Type", "application/timestamp-reply")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("MOCK_RFC3161_DER_TIMESTAMP_TOKEN_PAYLOAD"))
	}))
	defer mockTSA.Close()

	client := crypto.NewHTTPTSAClient(mockTSA.URL, 5*time.Second)

	rawHash := sha256.Sum256([]byte("forensic-block-payload"))
	token, err := client.RequestTimestamp(rawHash[:])
	if err != nil {
		t.Fatalf("unexpected error requesting timestamp: %v", err)
	}

	if string(token) != "MOCK_RFC3161_DER_TIMESTAMP_TOKEN_PAYLOAD" {
		t.Errorf("unexpected token content: %s", string(token))
	}

	b64 := crypto.EncodeTimestampToken(token)
	if b64 == "" {
		t.Errorf("expected non-empty Base64 token")
	}
}

func TestRFC3161_EmptyPayloadError(t *testing.T) {
	client := crypto.NewHTTPTSAClient("http://localhost", 2*time.Second)
	_, err := client.RequestTimestamp(nil)
	if err == nil {
		t.Fatal("expected error for empty payload, got nil")
	}
}
