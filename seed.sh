#!/usr/bin/env bash
# Seed IS_A claims for ATProto apps from apps.json
# Usage: cd /var/www/html/appviews && bash seed.sh
# Auth:  Set TOKEN env var, or the script will register/login automatically.
#        TOKEN=<jwt> bash seed.sh

set -euo pipefail

API_BASE="https://live.linkedtrust.us"
API="$API_BASE/api/claims"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: sudo apt install jq" >&2
  exit 1
fi

if [[ ! -f "$SCRIPT_DIR/apps.json" ]]; then
  echo "Error: apps.json not found in $SCRIPT_DIR" >&2
  exit 1
fi

# Get or reuse auth token
if [[ -z "${TOKEN:-}" ]]; then
  echo "No TOKEN set — registering seed account..."
  auth_resp=$(curl -s -X POST "$API_BASE/auth/signup" \
    -H "Content-Type: application/json" \
    -d '{"email":"appviews-seed@linkedtrust.us","password":"appviews2026","name":"AppViews Seed"}')
  TOKEN=$(echo "$auth_resp" | jq -r '.accessToken // empty')
  if [[ -z "$TOKEN" ]]; then
    # Try login if already registered
    auth_resp=$(curl -s -X POST "$API_BASE/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"email":"appviews-seed@linkedtrust.us","password":"appviews2026"}')
    TOKEN=$(echo "$auth_resp" | jq -r '.accessToken // empty')
  fi
  if [[ -z "$TOKEN" ]]; then
    echo "Error: Could not authenticate. Set TOKEN env var manually." >&2
    exit 1
  fi
  echo "Authenticated."
fi

echo "Seeding IS_A claims from apps.json..."
echo "API: $API"
echo "---"

count=0
errors=0

jq -c '.[]' "$SCRIPT_DIR/apps.json" | while read -r app; do
  uri=$(echo "$app" | jq -r '.uri')
  type=$(echo "$app" | jq -r '.type')
  name=$(echo "$app" | jq -r '.name')
  desc=$(echo "$app" | jq -r '.description')
  concept="https://linkedclaims.com/concepts/$type"

  echo -n "[$name] $uri -> $type ... "

  response=$(curl -s -w "\n%{http_code}" -X POST "$API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$(jq -n \
      --arg subject "$uri" \
      --arg claim "IS_A" \
      --arg object "$concept" \
      --arg statement "$desc" \
      '{subject: $subject, claim: $claim, object: $object, statement: $statement}')")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    echo "OK ($(echo "$body" | jq -r '.claim.id // "created"'))"
    ((count++)) || true
  elif [[ "$http_code" == "409" ]]; then
    echo "SKIP (duplicate)"
  else
    echo "ERROR ($http_code): $(echo "$body" | jq -r '.message // .error // "unknown"')"
    ((errors++)) || true
  fi
done

echo "---"
echo "Done. Created: $count, Errors: $errors"
