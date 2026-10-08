package auth

import (
	"context"
	"net/http"
	"strings"
)

type contextKey string

const userClaimsKey contextKey = "forensic_user_claims"

// RequireRole returns an HTTP middleware enforcing that the caller possesses
// one of the allowed domain roles.
func RequireRole(tokenService *TokenService, allowedRoles ...Role) func(http.Handler) http.Handler {
	allowed := make(map[Role]bool, len(allowedRoles))
	for _, r := range allowedRoles {
		allowed[r] = true
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
				http.Error(w, "missing or invalid authorization header", http.StatusUnauthorized)
				return
			}

			tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
			claims, err := tokenService.VerifyToken(tokenStr)
			if err != nil {
				if err == ErrExpiredToken {
					http.Error(w, "token expired", http.StatusUnauthorized)
					return
				}
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}

			if !allowed[claims.Role] {
				http.Error(w, "forbidden: role not authorized for this operation", http.StatusForbidden)
				return
			}

			ctx := context.WithValue(r.Context(), userClaimsKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetUserClaims retrieves authenticated user claims from request context.
func GetUserClaims(r *http.Request) (*Claims, bool) {
	claims, ok := r.Context().Value(userClaimsKey).(*Claims)
	return claims, ok
}
