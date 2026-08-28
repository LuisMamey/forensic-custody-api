package api

import (
	"crypto/rand"
	"encoding/hex"
)

// generateID returns a random 128-bit identifier encoded as a 32-character
// hexadecimal string, suitable for uniquely identifying stored resources.
func generateID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}