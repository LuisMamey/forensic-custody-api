package crypto

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// ComputeBlockHash computes a deterministic SHA-256 hash of a custody event,
// binding the previous block's hash to ensure immutable chaining.
func ComputeBlockHash(evidenceID string, seq int64, from, to, action string, prevHash string, ts time.Time) string {
	record := fmt.Sprintf("%s|%d|%s|%s|%s|%s|%s",
		evidenceID,
		seq,
		from,
		to,
		action,
		prevHash,
		ts.UTC().Format(time.RFC3339Nano),
	)

	h := sha256.Sum256([]byte(record))
	return hex.EncodeToString(h[:])
}

type BlockData struct {
	EvidenceID   string
	Sequence     int64
	From         string
	To           string
	Action       string
	PreviousHash string
	BlockHash    string
	Timestamp    time.Time
}

// VerifyLedgerChain walks the entire chain from block 0 to N, verifying:
// 1. Block 0 starts with the expected genesis hash.
// 2. Each block correctly references the previous block's hash.
// 3. Each block's content recalculates to its declared BlockHash.
// Returns an error at the exact index where tampering or corruption is detected.
func VerifyLedgerChain(chain []BlockData, genesisHash string) (bool, error) {
	if len(chain) == 0 {
		return true, nil
	}

	for i, block := range chain {
		if block.Sequence != int64(i) {
			return false, fmt.Errorf("sequence mismatch at block %d: expected %d, got %d", i, i, block.Sequence)
		}

		if i == 0 {
			if block.PreviousHash != genesisHash {
				return false, fmt.Errorf("block 0 previous hash mismatch: expected genesis %s, got %s", genesisHash, block.PreviousHash)
			}
		} else {
			expectedPrev := chain[i-1].BlockHash
			if block.PreviousHash != expectedPrev {
				return false, fmt.Errorf("chain broken at block %d: declared previous hash %s does not match block %d hash %s",
					i, block.PreviousHash, i-1, expectedPrev)
			}
		}

		recalculatedHash := ComputeBlockHash(
			block.EvidenceID,
			block.Sequence,
			block.From,
			block.To,
			block.Action,
			block.PreviousHash,
			block.Timestamp,
		)

		if block.BlockHash != recalculatedHash {
			return false, fmt.Errorf("tamper detected at block %d: recalculated hash %s does not match recorded hash %s",
				i, recalculatedHash, block.BlockHash)
		}
	}

	return true, nil
}
