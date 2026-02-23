package hash

import (
	"testing"
)

func BenchmarkPathHash(b *testing.B) {
	path := "/Users/developer/projects/my-rails-app"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = PathHash(path)
	}
}

func BenchmarkMD5Sum(b *testing.B) {
	input := "/Users/developer/projects/my-rails-app"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = MD5Sum(input)
	}
}

func BenchmarkCDPPortForHash(b *testing.B) {
	hash := "a1b2c3d4"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = CDPPortForHash(hash)
	}
}

func BenchmarkPathHashVariousLengths(b *testing.B) {
	paths := []string{
		"/short",
		"/Users/developer/projects/app",
		"/Users/developer/projects/very-long-project-name-with-many-directories/subdir1/subdir2/subdir3",
	}

	for _, path := range paths {
		b.Run(path, func(b *testing.B) {
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				_ = PathHash(path)
			}
		})
	}
}
