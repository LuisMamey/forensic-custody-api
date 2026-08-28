// Package models defines the domain entities, enumerations, and data structures
// used throughout the forensic custody API.
package models

import "time"

// EvidenceType represents the classification of digital forensic artifacts.
type EvidenceType string

const (
	EvidenceTypeDiskImage      EvidenceType = "DISK_IMAGE"
	EvidenceTypeMemoryDump     EvidenceType = "MEMORY_DUMP"
	EvidenceTypeNetworkCapture EvidenceType = "NETWORK_CAPTURE"
	EvidenceTypeSystemLogs     EvidenceType = "SYSTEM_LOGS"
)

// EvidenceStatus represents the lifecycle state of an evidence item.
type EvidenceStatus string

const (
	EvidenceStatusSecured       EvidenceStatus = "SECURED"
	EvidenceStatusUnderAnalysis EvidenceStatus = "UNDER_ANALYSIS"
	EvidenceStatusArchived      EvidenceStatus = "ARCHIVED"
)

// Case represents a legal forensic investigation case that groups digital evidence items.
type Case struct {
	ID               string    `json:"id"`
	CaseNumber       string    `json:"case_number"`
	Title            string    `json:"title"`
	LeadInvestigator string    `json:"lead_investigator"`
	CreatedAt        time.Time `json:"created_at"`
}

// EvidenceItem represents a specific digital artifact or piece of forensic evidence.
type EvidenceItem struct {
	ID           string         `json:"id"`
	CaseID       string         `json:"case_id"`
	Description  string         `json:"description"`
	EvidenceType EvidenceType   `json:"evidence_type"`
	SHA256Hash   string         `json:"sha256_hash"`
	StorageURI   string         `json:"storage_uri"`
	Status       EvidenceStatus `json:"status"`
	CreatedAt    time.Time      `json:"created_at"`
}

// CustodyLog records an immutable chain of custody event, ensuring traceability and data integrity.
type CustodyLog struct {
	ID                string    `json:"id"`
	EvidenceID        string    `json:"evidence_id"`
	TransferredBy     string    `json:"transferred_by"`
	TransferredTo     string    `json:"transferred_to"`
	ActionTaken       string    `json:"action_taken"`
	IntegrityVerified bool      `json:"integrity_verified"`
	Timestamp         time.Time `json:"timestamp"`
}
