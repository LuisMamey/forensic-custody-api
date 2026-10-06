package crypto

import (
	"bytes"
	"crypto/rand"
	"encoding/asn1"
	"encoding/base64"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"time"
)

// OID for SHA-256 in RFC 3161 ASN.1 structures (id-sha256).
var oidSHA256 = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 2, 1}

// MessageImprint corresponds to RFC 3161 MessageImprint ASN.1 sequence.
type MessageImprint struct {
	HashAlgorithm AlgorithmIdentifier
	HashedMessage []byte
}

// AlgorithmIdentifier identifies the cryptographic algorithm used.
type AlgorithmIdentifier struct {
	Algorithm  asn1.ObjectIdentifier
	Parameters asn1.RawValue `asn1:"optional"`
}

// TimeStampReq represents the RFC 3161 TimeStampReq structure.
type TimeStampReq struct {
	Version        int
	MessageImprint MessageImprint
	ReqPolicy      asn1.ObjectIdentifier `asn1:"optional"`
	Nonce          *big.Int              `asn1:"optional"`
	CertReq        bool                  `asn1:"optional,default:true"`
}

// TSAClient defines the contract for obtaining trusted RFC 3161 timestamps.
type TSAClient interface {
	RequestTimestamp(hashBytes []byte) ([]byte, error)
}

// HTTPTSAClient implements TSAClient over standard RFC 3161 HTTP transport.
type HTTPTSAClient struct {
	URL        string
	HTTPClient *http.Client
}

// NewHTTPTSAClient creates an RFC 3161 client targeting a TSA endpoint.
func NewHTTPTSAClient(url string, timeout time.Duration) *HTTPTSAClient {
	return &HTTPTSAClient{
		URL: url,
		HTTPClient: &http.Client{
			Timeout: timeout,
		},
	}
}

// RequestTimestamp sends an RFC 3161 request for hashBytes and returns the raw DER response token.
func (c *HTTPTSAClient) RequestTimestamp(hashBytes []byte) ([]byte, error) {
	if len(hashBytes) == 0 {
		return nil, fmt.Errorf("hash payload cannot be empty")
	}

	nonce, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 64))
	if err != nil {
		return nil, fmt.Errorf("failed to generate cryptographic nonce: %w", err)
	}

	reqData := TimeStampReq{
		Version: 1,
		MessageImprint: MessageImprint{
			HashAlgorithm: AlgorithmIdentifier{
				Algorithm: oidSHA256,
			},
			HashedMessage: hashBytes,
		},
		Nonce:   nonce,
		CertReq: true,
	}

	derBytes, err := asn1.Marshal(reqData)
	if err != nil {
		return nil, fmt.Errorf("failed to encode RFC 3161 ASN.1 request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", c.URL, bytes.NewReader(derBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create HTTP TSA request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/timestamp-query")

	resp, err := c.HTTPClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("TSA server request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("TSA server returned unexpected HTTP status: %d", resp.StatusCode)
	}

	tokenBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read TSA response: %w", err)
	}

	return tokenBytes, nil
}

// EncodeTimestampToken encodes the raw DER timestamp token into standard Base64 string for storage.
func EncodeTimestampToken(der []byte) string {
	return base64.StdEncoding.EncodeToString(der)
}
