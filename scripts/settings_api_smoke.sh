#!/bin/bash
# settings_api_smoke.sh - For the currently running FloatingMacro body
# Setting panel category endpoint operation confirmation script.
#
# Assumption:
# FloatingMacro.app is running with the Control API at 127.0.0.1:17430.
# Listening
# Bearer token that
# /Library/Application Support/FloatingMacro/control_api_token
# Saved when automatically generated at launch time
#
# Usage:
#   bash scripts/settings_api_smoke.sh

set -e

API_URL="http://127.0.0.1:17430"
PRESET_NAME="default"

TOKEN_FILE="$HOME/Library/Application Support/FloatingMacro/control_api_token"
if [ -r "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
else
    # Fallback to Keychain Mirror
    TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w 2>/dev/null || true)
fi
if [ -z "$TOKEN" ]; then
  echo "✗ Failed to fetch Bearer token"
  echo "  Expected file: $TOKEN_FILE"
  echo "  Or Keychain entry: service=FloatingMacro account=ControlAPIToken"
  exit 1
fi
AUTH_HEADER="Authorization: Bearer $TOKEN"

echo "===== Settings Test API Automation ====="

# Phase 1: API Connection Check
echo -e "\n[Phase 1] Checking API connectivity..."
if ! curl -s -H "$AUTH_HEADER" "$API_URL/tools" > /dev/null 2>&1; then
  echo "✗ API server is not responding at $API_URL"
  echo "  Please ensure FloatingMacro app is running and Control API is listening."
  exit 1
fi
echo "✓ API server is responding"

# Phase 2: Tool Discovery
echo -e "\n[Phase 2] Tool discovery..."
TOOLS=$(curl -s -H "$AUTH_HEADER" "$API_URL/tools" | jq '.tools[] | select(.name | startswith("settings_")) | .name' 2>/dev/null | wc -l)
echo "  Found $TOOLS settings-related tools:"
curl -s -H "$AUTH_HEADER" "$API_URL/tools" | jq '.tools[] | select(.name | startswith("settings_")) | .name' 2>/dev/null || true

if [ "$TOOLS" -ge 4 ]; then
  echo "✓ Found $TOOLS settings tools (expected at least 4)"
else
  echo "⚠ Found $TOOLS settings tools (expected at least 4)"
fi

# Phase 3: Each endpoint
echo -e "\n[Phase 3] Testing endpoints..."

# 3.1: Open settings
echo "  3.1: POST /settings/open..."
RESP=$(curl -s -X POST -H "$AUTH_HEADER" "$API_URL/settings/open")
if echo "$RESP" | jq -e '.visible == true' > /dev/null 2>/dev/null; then
  echo "  ✓ Settings window opened"
else
  echo "  ✗ Failed to open settings"
  echo "    Response: $RESP"
fi
sleep 0.2

# 3.2: Select button
echo "  3.2: POST /settings/select-button..."
BUTTON_ID=$(curl -s -H "$AUTH_HEADER" "$API_URL/preset/current" 2>/dev/null | jq -r '.preset.groups[0].buttons[0].id // "button-1"' 2>/dev/null)
echo "    Using button ID: $BUTTON_ID"
RESP=$(curl -s -X POST "$API_URL/settings/select-button" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$BUTTON_ID\"}")
if echo "$RESP" | jq -e ".id == \"$BUTTON_ID\"" > /dev/null 2>/dev/null; then
  echo "  ✓ Button selected: $BUTTON_ID"
else
  echo "  ✗ Failed to select button"
  echo "    Response: $RESP"
fi
sleep 0.2

# 3.3: Select group
echo "  3.3: POST /settings/select-group..."
GROUP_ID=$(curl -s -H "$AUTH_HEADER" "$API_URL/preset/current" 2>/dev/null | jq -r '.preset.groups[0].id // "group-1"' 2>/dev/null)
echo "    Using group ID: $GROUP_ID"
RESP=$(curl -s -X POST "$API_URL/settings/select-group" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$GROUP_ID\"}")
if echo "$RESP" | jq -e ".id == \"$GROUP_ID\"" > /dev/null 2>/dev/null; then
  echo "  ✓ Group selected: $GROUP_ID"
else
  echo "  ✗ Failed to select group"
  echo "    Response: $RESP"
fi
sleep 0.2

# 3.4: Open app icon picker
echo "  3.4: POST /settings/open-app-icon-picker..."
RESP=$(curl -s -X POST -H "$AUTH_HEADER" "$API_URL/settings/open-app-icon-picker")
if echo "$RESP" | jq -e '.opened == true' > /dev/null 2>/dev/null; then
  echo "  ✓ App icon picker opened"
else
  echo "  ⚠ App icon picker response: $RESP"
fi
sleep 0.2

# 3.5: Set action type
echo "  3.5: POST /settings/set-action-type..."
for TYPE in text key launch terminal; do
  RESP=$(curl -s -X POST "$API_URL/settings/set-action-type" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"$TYPE\"}")
  if echo "$RESP" | jq -e ".type == \"$TYPE\"" > /dev/null 2>/dev/null; then
    echo "    ✓ Action type set to: $TYPE"
  else
    echo "    ✗ Failed to set action type: $TYPE"
    echo "      Response: $RESP"
  fi
  sleep 0.2
done

# Phase 4: Error Cases
echo -e "\n[Phase 4] Error handling..."

# 4.1: Invalid type
echo "  4.1: Invalid type value..."
RESP=$(curl -s -X POST "$API_URL/settings/set-action-type" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"type":"invalid"}')
if echo "$RESP" | jq -e '.error' > /dev/null 2>/dev/null; then
  echo "  ✓ Invalid type correctly rejected"
else
  echo "  ⚠ Response: $RESP"
fi

# 4.2: Missing required field
echo "  4.2: Missing required field..."
RESP=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/settings/select-button" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{}')
HTTP_CODE=$(echo "$RESP" | tail -n 1)
BODY=$(echo "$RESP" | head -n -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo "  ✓ Missing field correctly rejected (HTTP 400)"
else
  echo "  ⚠ Expected HTTP 400, got $HTTP_CODE"
  echo "    Response: $BODY"
fi

echo -e "\n===== Test run completed ====="
