package container

import (
	"fmt"
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

func BenchmarkPortMapping_Format(b *testing.B) {
	pm := PortMapping{
		Host:      8080,
		Container: 80,
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		// Format as string manually since there's no String() method
		_ = fmt.Sprintf("%d:%d", pm.Host, pm.Container)
	}
}

func BenchmarkDetectPortConflicts(b *testing.B) {
	mappings := []PortMapping{
		{Host: 3000, Container: 3000},
		{Host: 5432, Container: 5432},
		{Host: 6379, Container: 6379},
		{Host: 9222, Container: 9222},
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = DetectPortConflicts(mappings)
	}
}
