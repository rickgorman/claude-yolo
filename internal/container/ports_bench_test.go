package container

import (
	"testing"
)

func BenchmarkParsePortMapping(b *testing.B) {
	portSpecs := []string{
		"3000:3000",
		"8080:80",
		"127.0.0.1:5432:5432",
	}

	for _, spec := range portSpecs {
		b.Run(spec, func(b *testing.B) {
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				_, _ = ParsePortMapping(spec)
			}
		})
	}
}

func BenchmarkPortMapping_String(b *testing.B) {
	pm := PortMapping{
		HostIP:        "127.0.0.1",
		HostPort:      8080,
		ContainerPort: 80,
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = pm.String()
	}
}

func BenchmarkFindConflicts(b *testing.B) {
	mappings := []PortMapping{
		{HostPort: 3000, ContainerPort: 3000},
		{HostPort: 5432, ContainerPort: 5432},
		{HostPort: 6379, ContainerPort: 6379},
		{HostPort: 9222, ContainerPort: 9222},
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = FindConflicts(mappings)
	}
}

func BenchmarkSuggestAlternativePort(b *testing.B) {
	port := 3000

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = SuggestAlternativePort(port)
	}
}
