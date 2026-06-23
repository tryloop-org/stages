#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Force-update a single secret across every repo in the org.
# Overwrites existing values — use this when rotating a secret.
#
# Usage:
export SECRET_NAME="SECURITY_TOOLS_PAT"
export SECRET_VALUE=""
#bash update_secret_github.sh
#
# Requirements: gh CLI installed and authenticated (gh auth login)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ORG="tryloop-org"
NAME="${SECRET_NAME:-}"
VALUE="${SECRET_VALUE:-}"

if [ -z "$NAME" ] || [ -z "$VALUE" ]; then
  echo "✗  ERROR: Both SECRET_NAME and SECRET_VALUE must be exported before running."
  echo "   export SECRET_NAME=\"SECURITY_TOOLS_PAT\""
  echo "   export SECRET_VALUE=\"ghp_...\""
  exit 1
fi

echo "Updating secret: $NAME across all repos in $ORG"
echo ""

repos=$(gh repo list "$ORG" \
  --limit 200 \
  --no-archived \
  --json nameWithOwner \
  --jq '.[].nameWithOwner')

total=$(echo "$repos" | wc -l | tr -d ' ')
echo "Found $total repositories."
echo ""

ok=0
fail=0

for full_repo in $repos; do
  exists=$(gh secret list --repo "$full_repo" 2>/dev/null | grep -c "^${NAME}" || true)
  if gh secret set "$NAME" \
      --repo "$full_repo" \
      --body "$VALUE" 2>/dev/null; then
    if [ "$exists" -gt 0 ]; then
      echo "🔄  $full_repo — updated"
    else
      echo "✓   $full_repo — added"
    fi
    ok=$((ok + 1))
  else
    echo "✗   $full_repo — failed (no admin access)"
    fail=$((fail + 1))
  fi
done

echo ""
echo "Done. Success: $ok  Failed: $fail"
