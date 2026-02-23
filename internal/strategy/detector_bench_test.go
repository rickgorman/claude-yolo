package strategy

import (
	"os"
	"path/filepath"
	"testing"
)

func BenchmarkDetectBestStrategy(b *testing.B) {
	// Create a temporary directory with Rails markers
	tmpDir := b.TempDir()

	// Create Rails markers
	_ = os.WriteFile(filepath.Join(tmpDir, "Gemfile"), []byte("source 'https://rubygems.org'\ngem 'rails'"), 0644)
	_ = os.WriteFile(filepath.Join(tmpDir, "config.ru"), []byte("# Rails app"), 0644)
	_ = os.MkdirAll(filepath.Join(tmpDir, "app", "controllers"), 0755)

	strategiesDir := filepath.Join("..", "..", "strategies")
	detector := NewDetector(strategiesDir)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = detector.DetectBestStrategy(tmpDir)
	}
}

func BenchmarkGetStrategy(b *testing.B) {
	strategiesDir := filepath.Join("..", "..", "strategies")
	detector := NewDetector(strategiesDir)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = detector.GetStrategy("rails")
	}
}

func BenchmarkRunDetectionQuick(b *testing.B) {
	tmpDir := b.TempDir()

	// Create Rails markers
	_ = os.WriteFile(filepath.Join(tmpDir, "Gemfile"), []byte("gem 'rails'"), 0644)
	_ = os.MkdirAll(filepath.Join(tmpDir, "app"), 0755)

	strategiesDir := filepath.Join("..", "..", "strategies")
	detector := NewDetector(strategiesDir)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = detector.RunDetectionQuick(tmpDir)
	}
}
