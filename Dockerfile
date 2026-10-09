# Stage 1: build a statically linked binary using the full Go toolchain.
FROM golang:1.27.2-alpine@sha256:85dc1069ac644ea3c527b177303a406eb3358192816cd7f9e5848eb658851673 AS builder

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