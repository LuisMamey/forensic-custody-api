// Package crypto provides cryptographic utilities for digital forensic integrity,
// ensuring dual-hash stream computation and tamper-evident guarantees.
package crypto

import (
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"fmt"
	"io"
)

// DualHashResult holds the cryptographic digest results and byte count
// computed during evidence streaming ingestion.
type DualHashResult struct {
	SHA256    string
	SHA512    string
	BytesRead int64
}

// ComputeDualStreamHash reads from r until EOF, simultaneously computing
// SHA-256 and SHA-512 hashes in a single pass without buffering the entire
// payload into memory.
func ComputeDualStreamHash(r io.Reader) (DualHashResult, error) {
	if r == nil {
		return DualHashResult{}, fmt.Errorf("reader cannot be nil")
	}

	h256 := sha256.New()
	h512 := sha512.New()

	multiWriter := io.MultiWriter(h256, h512)

	n, err := io.Copy(multiWriter, r)
	if err != nil {
		return DualHashResult{}, fmt.Errorf("failed to compute stream hashes: %w", err)
	}

	return DualHashResult{
		SHA256:    hex.EncodeToString(h256.Sum(nil)),
		SHA512:    hex.EncodeToString(h512.Sum(nil)),
		BytesRead: n,
	}, nil
}
