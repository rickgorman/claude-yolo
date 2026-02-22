// Package hash provides hashing utilities for path-based identifiers.
package hash

import (
	"crypto/md5"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io"
)

// PathHash generates an 8-character hash from a path string.
// It tries md5, md5sum, or sha1 depending on availability.
// This maintains compatibility with the bash version which uses:
// md5 | cut -c1-8 or md5sum | cut -c1-8 or shasum | cut -c1-8
func PathHash(path string) string {
	// Use MD5 for consistency with bash script behavior
	hasher := md5.New()
	_, _ = io.WriteString(hasher, path)
	fullHash := hex.EncodeToString(hasher.Sum(nil))
	return fullHash[:8]
}

// CDPPortForHash calculates a Chrome DevTools Protocol port from a hash.
// Formula: 9222 + (first 4 hex chars as decimal) % 778
// This ensures unique ports per worktree while staying in a reasonable range.
func CDPPortForHash(hash string) int {
	if len(hash) < 4 {
		return 9222
	}

	// Convert first 4 hex characters to decimal
	var dec uint64
	_, _ = fmt.Sscanf(hash[:4], "%x", &dec)

	// Apply modulo and add to base port
	return 9222 + int(dec%778)
}

// MD5Sum returns the full MD5 hash of a string.
func MD5Sum(s string) string {
	hasher := md5.New()
	_, _ = io.WriteString(hasher, s)
	return hex.EncodeToString(hasher.Sum(nil))
}

// SHA1Sum returns the full SHA1 hash of a string.
func SHA1Sum(s string) string {
	hasher := sha1.New()
	_, _ = io.WriteString(hasher, s)
	return hex.EncodeToString(hasher.Sum(nil))
}
