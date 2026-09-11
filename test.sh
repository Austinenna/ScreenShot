#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/CaptureService.swift Sources/SelectionView.swift \
  Sources/Annotation.swift Sources/AnnotationView.swift Tests/CaptureSnapshotTests.swift \
  -module-cache-path "$TEST_DIR/ModuleCache" \
  -framework Cocoa -framework ScreenCaptureKit -o "$TEST_DIR/CaptureSnapshotTests"
"$TEST_DIR/CaptureSnapshotTests"
