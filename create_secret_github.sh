#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Set shared GitHub Actions secrets across every repo in the org.
# Skips repos that already have the secret set.
# gh auth login
# Usage:
#export DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
export VM_PASSWORD="*****"
#export VM_PROD_PASSWORD="your-prod-vm-sudo-password"
#bash create_secret_github.sh
#
# Requirements: gh CLI installed and authenticated (gh auth login)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ORG="tryloop-org"

# ── Secrets to set across ALL repos ──────────────────────────────────────────
# Add or remove entries as needed.
# Format: "SECRET_NAME=value"
declare -a SECRETS=(
  "VM_PASSWORD=${VM_PASSWORD:-}"
)

# ── Validate all secrets are provided ────────────────────────────────────────
echo "Validating secrets..."
for entry in "${SECRETS[@]}"; do
  name="${entry%%=*}"
  value="${entry#*=}"
  if [ -z "$value" ]; then
    echo "✗  ERROR: $name is not set. Export it before running this script."
    echo "   Example: export $name=\"your-value-here\""
    exit 1
  fi
  echo "✓  $name is set"
done

# ── Fetch all repos in the org ────────────────────────────────────────────────
echo ""
echo "Fetching all repos in $ORG..."
repos=$(gh repo list "$ORG" \
  --limit 200 \
  --no-archived \
  --json nameWithOwner \
  --jq '.[].nameWithOwner')

total=$(echo "$repos" | wc -l | tr -d ' ')
echo "Found $total repositories."
echo ""

# ── Loop through each repo and set each secret ───────────────────────────────
for full_repo in $repos; do
  echo "── $full_repo"
  for entry in "${SECRETS[@]}"; do
    name="${entry%%=*}"
    value="${entry#*=}"

    if gh secret list --repo "$full_repo" 2>/dev/null | grep -q "^${name}"; then
      echo "   ⏭  $name — already set, skipped"
    else
      if gh secret set "$name" \
          --repo "$full_repo" \
          --body "$value" 2>/dev/null; then
        echo "   ✓  $name — added"
      else
        echo "   ✗  $name — failed (no access to repo)"
      fi
    fi
  done
done

echo ""
echo "Done."
