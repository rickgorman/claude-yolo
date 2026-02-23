package strategy

// GenericStrategy implements the Strategy interface for generic projects.
// This is a fallback strategy that provides minimal Docker environment.
type GenericStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewGenericStrategy creates a new Generic strategy.
func NewGenericStrategy() *GenericStrategy {
	return &GenericStrategy{
		BaseStrategy:  BaseStrategy{name: "generic"},
		strategiesDir: "strategies",
	}
}

// Detect always returns 0 confidence for Generic (manual selection only).
func (s *GenericStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	return 0, "manual selection only", nil
}

// Volumes returns the Docker volumes needed for Generic (none).
func (s *GenericStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{}
}

// EnvVars returns the environment variables needed for Generic (none).
func (s *GenericStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	return []EnvVar{}, nil
}

// DefaultPorts returns the default port mappings for Generic (none).
func (s *GenericStrategy) DefaultPorts() []PortMapping {
	return []PortMapping{}
}

// InfoMessage returns the info message to display when starting Generic container.
func (s *GenericStrategy) InfoMessage(projectPath string) (string, error) {
	return "Generic · no language runtime", nil
}
