#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
echo "== Secret scan (tracked files) =="
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo "FAIL: .env is tracked"; fail=1
fi
if git ls-files --error-unmatch backend.hcl >/dev/null 2>&1; then
  echo "FAIL: backend.hcl should not be tracked"; fail=1
fi
if git ls-files '*.tfstate' '*.tfstate.*' 'errored.tfstate' 2>/dev/null | grep -q .; then
  echo "FAIL: tfstate tracked"; fail=1
fi
patterns=('AKIA[0-9A-Z]{16}' 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' 'sk_live_[0-9a-zA-Z]+')
for pattern in "${patterns[@]}"; do
  matches="$(git grep -l -E "$pattern" -- ':!*.lock' ':!*.md' 2>/dev/null || true)"
  if [ -n "$matches" ]; then
    echo "FAIL: secret pattern:"; echo "$matches"; fail=1
  fi
done
if [ "$fail" -ne 0 ]; then exit 1; fi
echo "PASS: security gate (infra-k8s light)"
