// Package storage defines persistence interfaces and thread-safe in-memory
// implementations for forensic records and chain of custody logs.
package storage

import (
	"errors"
	"sync"
	"time"

	"github.com/LuisMamey/forensic-custody-api/internal/models"
)

var (
	// ErrNotFound indicates that the requested resource does not exist.
	ErrNotFound = errors.New("resource not found")
	// ErrConflict indicates that a resource with the same unique identifier already exists.
	ErrConflict = errors.New("resource already exists")
)

// Repository defines the contract for persisting and retrieving forensic data.
type Repository interface {
	CreateCase(c models.Case) error
	GetCaseByID(id string) (models.Case, error)
	ListCases() ([]models.Case, error)

	CreateEvidence(e models.EvidenceItem) error
	GetEvidenceByID(id string) (models.EvidenceItem, error)
	ListEvidenceByCaseID(caseID string) ([]models.EvidenceItem, error)

	AddCustodyLog(log models.CustodyLog) error
	ListCustodyLogsByEvidenceID(evidenceID string) ([]models.CustodyLog, error)
}

// MemoryStorage provides a thread-safe, in-memory implementation of Repository.
type MemoryStorage struct {
	mu          sync.RWMutex
	cases       map[string]models.Case
	evidence    map[string]models.EvidenceItem
	custodyLogs map[string][]models.CustodyLog
}

// NewMemoryStorage initializes and returns a ready-to-use MemoryStorage instance.
func NewMemoryStorage() *MemoryStorage {
	return &MemoryStorage{
		cases:       make(map[string]models.Case),
		evidence:    make(map[string]models.EvidenceItem),
		custodyLogs: make(map[string][]models.CustodyLog),
	}
}

// CreateCase stores a new investigation case.
func (s *MemoryStorage) CreateCase(c models.Case) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.cases[c.ID]; exists {
		return ErrConflict
	}

	c.CreatedAt = time.Now().UTC()
	s.cases[c.ID] = c
	return nil
}

// GetCaseByID retrieves a single case by its unique identifier.
func (s *MemoryStorage) GetCaseByID(id string) (models.Case, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	c, exists := s.cases[id]
	if !exists {
		return models.Case{}, ErrNotFound
	}
	return c, nil
}

// ListCases returns all registered forensic investigation cases.
func (s *MemoryStorage) ListCases() ([]models.Case, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	list := make([]models.Case, 0, len(s.cases))
	for _, c := range s.cases {
		list = append(list, c)
	}
	return list, nil
}

// CreateEvidence stores a new evidence item associated with an existing case.
func (s *MemoryStorage) CreateEvidence(e models.EvidenceItem) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.cases[e.CaseID]; !exists {
		return ErrNotFound
	}
	if _, exists := s.evidence[e.ID]; exists {
		return ErrConflict
	}

	e.CreatedAt = time.Now().UTC()
	s.evidence[e.ID] = e
	return nil
}

// GetEvidenceByID retrieves a single evidence item by its unique identifier.
func (s *MemoryStorage) GetEvidenceByID(id string) (models.EvidenceItem, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	e, exists := s.evidence[id]
	if !exists {
		return models.EvidenceItem{}, ErrNotFound
	}
	return e, nil
}

// ListEvidenceByCaseID retrieves all evidence items belonging to a specific case.
func (s *MemoryStorage) ListEvidenceByCaseID(caseID string) ([]models.EvidenceItem, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var list []models.EvidenceItem
	for _, e := range s.evidence {
		if e.CaseID == caseID {
			list = append(list, e)
		}
	}
	return list, nil
}

// AddCustodyLog appends a new immutable log entry to the chain of custody.
func (s *MemoryStorage) AddCustodyLog(log models.CustodyLog) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.evidence[log.EvidenceID]; !exists {
		return ErrNotFound
	}

	log.Timestamp = time.Now().UTC()
	s.custodyLogs[log.EvidenceID] = append(s.custodyLogs[log.EvidenceID], log)
	return nil
}

// ListCustodyLogsByEvidenceID retrieves the full chain of custody log for a given evidence item.
func (s *MemoryStorage) ListCustodyLogsByEvidenceID(evidenceID string) ([]models.CustodyLog, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	logs, exists := s.custodyLogs[evidenceID]
	if !exists {
		return []models.CustodyLog{}, nil
	}
	return logs, nil
}
