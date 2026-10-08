package auth_test

import (
	"testing"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/auth"
)

// FuzzVerifyToken executes coverage-guided fuzzing against the JWT parser
// to guarantee it gracefully rejects malformed or malicious inputs without panicking.
func FuzzVerifyToken(f *testing.F) {
	svc := auth.NewTokenService("fuzzing-secret-key-32-bytes-secure")

	validToken, _ := svc.GenerateToken("investigator-01", auth.RoleInvestigator, 1*time.Hour)
	f.Add(validToken)
	f.Add("")
	f.Add("..")
	f.Add("invalid.token")
	f.Add("header.payload.signature.extra")
	f.Add("eyJhbGciOiJIUzI1NiJ9.invalid-payload.invalidsig")
	f.Add(string([]byte{0x00, 0xFF, 0xFE, 0xFD}))

	f.Fuzz(func(t *testing.T, token string) {
		claims, err := svc.VerifyToken(token)
		if err == nil {
			if claims == nil || claims.Subject == "" {
				t.Errorf("token verified without error but returned empty claims")
			}
		}
	})
}
