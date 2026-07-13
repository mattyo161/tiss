#!/usr/bin/env bash
#
# tiss test runner — executes every tests/test_*.sh and summarizes.
#
set -u
cd "$(dirname "$0")" || exit 1

total=0
failed=0
for t in test_*.sh; do
  total=$((total + 1))
  if ! bash "$t"; then
    failed=$((failed + 1))
  fi
done

echo "----------------------------------------"
if [ "$failed" -eq 0 ]; then
  echo "all $total test files passed"
else
  echo "$failed of $total test files FAILED"
  exit 1
fi
