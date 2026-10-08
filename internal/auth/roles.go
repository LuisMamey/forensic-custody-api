// Package auth provides Role-Based Access Control (RBAC) and JWT validation
// for digital forensic chain of custody operations.
package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Role defines the domain privileges within forensic custody workflows.
type Role string

const (
	RoleInvestigator      Role = "INVESTIGATOR"
	RoleLabAnalyst        Role = "LAB_ANALYST"
	RoleEvidenceCustodian Role = "EVIDENCE_CUSTODIAN"
	RoleAuditor           Role = "AUDITOR"
)

var (
	ErrInvalidToken = errors.New("invalid or malformed authorization token")
	ErrExpiredToken = errors.New("authorization token has expired")
	ErrForbidden    = errors.New("insufficient privileges for this forensic operation")
)

// Claims represents the authenticated identity payload within the JWT.
type Claims struct {
	Subject   string `json:"sub"`
	Role      Role   `json:"role"`
	ExpiresAt int64  `json:"exp"`
}

// TokenService signs and verifies forensic JWT tokens.
type TokenService struct {
	secret []byte
}

// NewTokenService creates a TokenService configured with an HMAC signing secret.
func NewTokenService(secret string) *TokenService {
	return &TokenService{secret: []byte(secret)}
}

// GenerateToken creates a signed JWT for the given user identity and role.
func (s *TokenService) GenerateToken(sub string, role Role, ttl time.Duration) (string, error) {
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))

	claims := Claims{
		Subject:   sub,
		Role:      role,
		ExpiresAt: time.Now().UTC().Add(ttl).Unix(),
	}
	claimsBytes, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("failed to encode claims: %w", err)
	}
	payload := base64.RawURLEncoding.EncodeToString(claimsBytes)

	signingInput := header + "." + payload
	sig := s.sign(signingInput)

	return signingInput + "." + sig, nil
}

// VerifyToken validates the JWT signature and expiration, returning parsed Claims.
func (s *TokenService) VerifyToken(tokenString string) (*Claims, error) {
	parts := strings.Split(tokenString, ".")
	if len(parts) != 3 {
		return nil, ErrInvalidToken
	}

	signingInput := parts[0] + "." + parts[1]
	expectedSig := s.sign(signingInput)
	if !hmac.Equal([]byte(parts[2]), []byte(expectedSig)) {
		return nil, ErrInvalidToken
	}

	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, ErrInvalidToken
	}

	var claims Claims
	if err := json.Unmarshal(claimsBytes, &claims); err != nil {
		return nil, ErrInvalidToken
	}

	if time.Now().UTC().Unix() > claims.ExpiresAt {
		return nil, ErrExpiredToken
	}

	return &claims, nil
}

func (s *TokenService) sign(data string) string {
	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte(data))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
