#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[quality] Running lightweight quality checks"

if command -v swiftlint >/dev/null 2>&1; then
  echo "[quality] swiftlint found, running lint"
  swiftlint lint --config .swiftlint.yml
else
  echo "[quality] swiftlint not installed, skipping lint"
fi

MAX_SWIFT_FILE_LINES=1500
has_violation=0

while read -r lines path; do
  if [[ "${path}" == "total" ]]; then
    continue
  fi
  if (( lines > MAX_SWIFT_FILE_LINES )); then
    echo "[quality] ERROR: ${path} has ${lines} lines (limit ${MAX_SWIFT_FILE_LINES})"
    has_violation=1
  fi
done < <(find Sources Tests -type f -name '*.swift' -exec wc -l {} +)

if (( has_violation == 1 )); then
  exit 1
fi

echo "[quality] Quality checks passed"
