package auth_test

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/auth"
)

func TestRBAC_AccessControlMatrix(t *testing.T) {
	svc := auth.NewTokenService("super-secret-test-key-32-bytes!!")

	handler := auth.RequireRole(svc, auth.RoleInvestigator, auth.RoleEvidenceCustodian)(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, _ := auth.GetUserClaims(r)
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("authorized: " + claims.Subject))
		}),
	)

	invToken, _ := svc.GenerateToken("agent-47", auth.RoleInvestigator, 1*time.Hour)
	req1 := httptest.NewRequest("GET", "/protected", nil)
	req1.Header.Set("Authorization", "Bearer "+invToken)
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Errorf("expected 200 OK for investigator, got %d", rec1.Code)
	}

	auditorToken, _ := svc.GenerateToken("auditor-01", auth.RoleAuditor, 1*time.Hour)
	req2 := httptest.NewRequest("GET", "/protected", nil)
	req2.Header.Set("Authorization", "Bearer "+auditorToken)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for auditor, got %d", rec2.Code)
	}

	req3 := httptest.NewRequest("GET", "/protected", nil)
	rec3 := httptest.NewRecorder()
	handler.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for missing token, got %d", rec3.Code)
	}

	req4 := httptest.NewRequest("GET", "/protected", nil)
	req4.Header.Set("Authorization", "Bearer "+invToken+"tampered")
	rec4 := httptest.NewRecorder()
	handler.ServeHTTP(rec4, req4)
	if rec4.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for tampered token, got %d", rec4.Code)
	}
}
