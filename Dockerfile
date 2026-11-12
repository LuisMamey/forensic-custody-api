# Stage 1: build a statically linked binary using the full Go toolchain.
FROM golang:1.27.4-alpine@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /forensic-custody-api ./cmd/api

# Stage 2: run the binary on a minimal, non-root distroless image.
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

COPY --from=builder /forensic-custody-api /forensic-custody-api

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/forensic-custody-api"]