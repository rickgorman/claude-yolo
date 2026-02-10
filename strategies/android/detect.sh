#!/usr/bin/env bash
# Detection heuristics for Android projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# Check both the root and an android/ subdirectory (React Native, Flutter, etc.)
ANDROID_DIR=""
if [[ -f "$PROJECT_DIR/build.gradle" ]] || [[ -f "$PROJECT_DIR/build.gradle.kts" ]]; then
  ANDROID_DIR="$PROJECT_DIR"
elif [[ -d "$PROJECT_DIR/android" ]]; then
  if [[ -f "$PROJECT_DIR/android/build.gradle" ]] || [[ -f "$PROJECT_DIR/android/build.gradle.kts" ]]; then
    ANDROID_DIR="$PROJECT_DIR/android"
    EVIDENCE+=("android/ subdir")
  fi
fi

# Root build.gradle(.kts)
if [[ -n "$ANDROID_DIR" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("build.gradle")
fi

# settings.gradle(.kts)
if [[ -n "$ANDROID_DIR" ]] && { [[ -f "$ANDROID_DIR/settings.gradle" ]] || [[ -f "$ANDROID_DIR/settings.gradle.kts" ]]; }; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("settings.gradle")
fi

# app/build.gradle(.kts) - strong Android signal
if [[ -n "$ANDROID_DIR" ]] && { [[ -f "$ANDROID_DIR/app/build.gradle" ]] || [[ -f "$ANDROID_DIR/app/build.gradle.kts" ]]; }; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("app/build.gradle")
fi

# AndroidManifest.xml anywhere in the tree (up to 5 levels deep)
manifest=$(find "$PROJECT_DIR" -maxdepth 5 -name "AndroidManifest.xml" -print -quit 2>/dev/null || true)
if [[ -n "$manifest" ]]; then
  CONFIDENCE=$((CONFIDENCE + 25))
  EVIDENCE+=("AndroidManifest.xml")
fi

# gradlew (in root or android/)
if [[ -f "$PROJECT_DIR/gradlew" ]] || [[ -f "${ANDROID_DIR:-__none__}/gradlew" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("gradlew")
fi

# Android plugin in build files
if [[ -n "$ANDROID_DIR" ]]; then
  if grep -rq "com.android" "$ANDROID_DIR"/build.gradle* "$ANDROID_DIR"/app/build.gradle* 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 20))
    EVIDENCE+=("com.android plugin")
  fi
fi

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
