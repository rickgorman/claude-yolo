// Package hash provides path hashing and port calculation utilities.
//
// This package is used to generate stable, short identifiers for
// projects based on their filesystem path. These hashes are used for:
//   - Container naming (yolo-{hash})
//   - Volume naming (project-specific isolation)
//   - CDP port assignment (deterministic port per project)
//
// The hash is the first 8 characters of MD5(path), providing a good
// balance between uniqueness and readability.
//
// Example usage:
//
//	// Get 8-character hash for a path
//	hash := hash.PathHash("/workspace/myproject")
//	// Returns: "a1b2c3d4"
//
//	// Get deterministic CDP port for this project
//	port := hash.CDPPortForHash(hash)
//	// Returns: 9222-9999 range
//
// Port calculation:
//   - Converts first 4 hex chars to decimal
//   - Modulo 778 to get offset (0-777)
//   - Adds to base port 9222
//   - Result: 9222-9999 range
//
// This ensures each project gets a consistent port number
// without collisions.
package hash
