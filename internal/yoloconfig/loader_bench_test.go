package yoloconfig

import (
	"os"
	"path/filepath"
	"testing"
)

func BenchmarkLoad(b *testing.B) {
	tmpDir := b.TempDir()
	yoloDir := filepath.Join(tmpDir, ".yolo")
	_ = os.MkdirAll(yoloDir, 0755)

	// Create config files
	_ = os.WriteFile(filepath.Join(yoloDir, "strategy"), []byte("rails"), 0644)
	_ = os.WriteFile(filepath.Join(yoloDir, "env"), []byte("RAILS_ENV=development\nDEBUG=true"), 0644)
	_ = os.WriteFile(filepath.Join(yoloDir, "ports"), []byte("3000:3000\n5432:5432"), 0644)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = Load(tmpDir, false)
	}
}

func BenchmarkLoadEnvFile(b *testing.B) {
	tmpFile := filepath.Join(b.TempDir(), "env")
	content := `RAILS_ENV=development
DATABASE_URL=postgresql://localhost/myapp
REDIS_URL=redis://localhost:6379
API_KEY=secret123
DEBUG=true
LOG_LEVEL=info`
	_ = os.WriteFile(tmpFile, []byte(content), 0644)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = loadEnvFile(tmpFile)
	}
}

func BenchmarkLoadPortsFile(b *testing.B) {
	tmpFile := filepath.Join(b.TempDir(), "ports")
	content := `3000:3000
5432:5432
6379:6379
9222:9222`
	_ = os.WriteFile(tmpFile, []byte(content), 0644)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = loadPortsFile(tmpFile)
	}
}

func BenchmarkComputeConfigHash(b *testing.B) {
	tmpDir := b.TempDir()
	yoloDir := filepath.Join(tmpDir, ".yolo")
	_ = os.MkdirAll(yoloDir, 0755)

	// Create several files
	_ = os.WriteFile(filepath.Join(yoloDir, "strategy"), []byte("rails"), 0644)
	_ = os.WriteFile(filepath.Join(yoloDir, "env"), []byte("KEY=value"), 0644)
	_ = os.WriteFile(filepath.Join(yoloDir, "ports"), []byte("3000:3000"), 0644)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = computeConfigHash(yoloDir)
	}
}
