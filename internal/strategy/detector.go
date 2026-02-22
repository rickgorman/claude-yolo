package strategy

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Detector orchestrates strategy detection across all available strategies.
type Detector struct {
	strategiesDir string
	strategies    map[string]Strategy
}

// NewDetector creates a new strategy detector.
func NewDetector(strategiesDir string) *Detector {
	d := &Detector{
		strategiesDir: strategiesDir,
		strategies:    make(map[string]Strategy),
	}

	d.registerStrategies()
	return d
}

// registerStrategies initializes all available strategies.
func (d *Detector) registerStrategies() {
	d.strategies["rails"] = NewRailsStrategy()
	d.strategies["node"] = NewNodeStrategy()
	d.strategies["python"] = NewPythonStrategy()
	d.strategies["go"] = NewGoStrategy()
	d.strategies["rust"] = NewRustStrategy()
	d.strategies["android"] = NewAndroidStrategy()
	d.strategies["jekyll"] = NewJekyllStrategy()
	d.strategies["generic"] = NewGenericStrategy()
}

// ListStrategies returns a list of all available strategy names.
func (d *Detector) ListStrategies() []string {
	var names []string
	for name := range d.strategies {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// GetStrategy returns a strategy by name.
func (d *Detector) GetStrategy(name string) (Strategy, error) {
	strategy, ok := d.strategies[name]
	if !ok {
		return nil, fmt.Errorf("unknown strategy: %s", name)
	}
	return strategy, nil
}

// RunDetection runs detection for all strategies and returns sorted results.
func (d *Detector) RunDetection(projectPath string) ([]DetectionResult, error) {
	var results []DetectionResult

	for name, strategy := range d.strategies {
		confidence, evidence, err := strategy.Detect(projectPath)
		if err != nil {
			// Skip strategies that fail detection
			continue
		}

		if confidence > 0 {
			results = append(results, DetectionResult{
				Strategy:   name,
				Confidence: confidence,
				Evidence:   evidence,
			})
		}
	}

	// Sort by confidence (highest first)
	sort.Slice(results, func(i, j int) bool {
		return results[i].Confidence > results[j].Confidence
	})

	return results, nil
}

// RunDetectionDeep scans immediate subdirectories for strategy matches.
// Skips hidden directories and common non-project directories.
func (d *Detector) RunDetectionDeep(projectPath string) ([]DetectionResult, error) {
	skipDirs := map[string]bool{
		"node_modules": true,
		"vendor":       true,
		"tmp":          true,
		"log":          true,
		"public":       true,
		".bundle":      true,
	}

	var allResults []DetectionResult

	entries, err := os.ReadDir(projectPath)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		name := entry.Name()

		// Skip hidden directories
		if strings.HasPrefix(name, ".") {
			continue
		}

		// Skip common non-project directories
		if skipDirs[name] {
			continue
		}

		subdir := filepath.Join(projectPath, name)
		results, err := d.RunDetection(subdir)
		if err != nil {
			continue
		}

		allResults = append(allResults, results...)
	}

	// Sort by confidence (highest first)
	sort.Slice(allResults, func(i, j int) bool {
		return allResults[i].Confidence > allResults[j].Confidence
	})

	return allResults, nil
}

// DetectBestStrategy non-interactively picks the best strategy for a directory.
// Tries shallow detection first; falls back to deep scan if nothing found.
func (d *Detector) DetectBestStrategy(projectPath string) (string, error) {
	results, err := d.RunDetection(projectPath)
	if err == nil && len(results) > 0 {
		return results[0].Strategy, nil
	}

	// Try deep detection
	results, err = d.RunDetectionDeep(projectPath)
	if err == nil && len(results) > 0 {
		return results[0].Strategy, nil
	}

	return "", fmt.Errorf("no strategy detected (available: rails, node, python, go, rust, android, jekyll, generic)\n\nManually specify one with: claude-yolo --yolo --strategy <name>")
}

// runDetectScript executes a strategy's detect.sh script and parses the output.
func runDetectScript(strategiesDir, strategyName, projectPath string) (int, string, error) {
	scriptPath := filepath.Join(strategiesDir, strategyName, "detect.sh")

	// Check if detect.sh exists
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return 0, "", fmt.Errorf("detect.sh not found for strategy %s", strategyName)
	}

	cmd := exec.Command(scriptPath, projectPath)
	output, err := cmd.Output()
	if err != nil {
		return 0, "", err
	}

	// Parse output
	var confidence int
	var evidence string

	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "CONFIDENCE:") {
			confStr := strings.TrimPrefix(line, "CONFIDENCE:")
			confidence, _ = strconv.Atoi(strings.TrimSpace(confStr))
		} else if strings.HasPrefix(line, "EVIDENCE:") {
			evidence = strings.TrimPrefix(line, "EVIDENCE:")
			evidence = strings.TrimSpace(evidence)
		}
	}

	return confidence, evidence, nil
}
