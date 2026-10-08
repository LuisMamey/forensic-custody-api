package crypto_test

import (
	"testing"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/crypto"
)

// FuzzVerifyLedgerChain tests ledger chain verification with mutative inputs
// to ensure no malformed block combinations trigger runtime panics.
func FuzzVerifyLedgerChain(f *testing.F) {
	genesis := "0000000000000000000000000000000000000000000000000000000000000000"

	f.Add("evi-001", int64(0), "Officer A", "Locker", "SEIZED", genesis, int64(1700000000))
	f.Add("", int64(-1), "", "", "", "", int64(0))
	f.Add("malformed", int64(999999), "A", "B", "ACTION", "invalid-hash", int64(-500))

	f.Fuzz(func(t *testing.T, eviID string, seq int64, from, to, action, prevHash string, unixSec int64) {
		ts := time.Unix(unixSec, 0).UTC()
		blockHash := crypto.ComputeBlockHash(eviID, seq, from, to, action, prevHash, ts)

		chain := []crypto.BlockData{
			{
				EvidenceID:   eviID,
				Sequence:     seq,
				From:         from,
				To:           to,
				Action:       action,
				PreviousHash: prevHash,
				BlockHash:    blockHash,
				Timestamp:    ts,
			},
		}

		_, _ = crypto.VerifyLedgerChain(chain, genesis)
	})
}
