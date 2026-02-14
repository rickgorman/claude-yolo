#!/usr/bin/env bash
# Detection heuristics for Generic environment
#
# Generic is never auto-detected — it must be selected manually
# via --strategy generic or from the full strategy list.
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

echo "CONFIDENCE:0"
echo "EVIDENCE:manual selection only"
