# Stage 1: build a statically linked binary using the full Go toolchain.
FROM golang:1.26-alpine AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /forensic-custody-api ./cmd/api

# Stage 2: run the binary on a minimal, non-root distroless image.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /forensic-custody-api /forensic-custody-api

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/forensic-custody-api"]