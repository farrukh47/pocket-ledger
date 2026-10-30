#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --platforms=android --org com.farrukh --project-name pocket_ledger --no-pub .
rm -f test/widget_test.dart
flutter pub get
