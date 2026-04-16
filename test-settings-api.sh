#!/bin/bash
set -e

API_URL="http://127.0.0.1:14159"
PRESET_NAME="default"

echo "===== Settings Test API Automation ====="

# フェーズ 1: API 接続確認
echo -e "\n[Phase 1] Checking API connectivity..."
if ! curl -s "$API_URL/tools" > /dev/null 2>&1; then
  echo "✗ API server is not responding at $API_URL"
  echo "  Please ensure FloatingMacro app is running and Control API is listening."
  exit 1
fi
echo "✓ API server is responding"

# フェーズ 2: ツールディスカバリー
echo -e "\n[Phase 2] Tool discovery..."
TOOLS=$(curl -s "$API_URL/tools" | jq '.tools[] | select(.name | startswith("settings_")) | .name' 2>/dev/null | wc -l)
echo "  Found $TOOLS settings-related tools:"
curl -s "$API_URL/tools" | jq '.tools[] | select(.name | startswith("settings_")) | .name' 2>/dev/null || true

if [ "$TOOLS" -ge 4 ]; then
  echo "✓ Found $TOOLS settings tools (expected at least 4)"
else
  echo "⚠ Found $TOOLS settings tools (expected at least 4)"
fi

# フェーズ 3: 各エンドポイント
echo -e "\n[Phase 3] Testing endpoints..."

# 3.1: Open settings
echo "  3.1: POST /settings/open..."
RESP=$(curl -s -X POST "$API_URL/settings/open")
if echo "$RESP" | jq -e '.visible == true' > /dev/null 2>/dev/null; then
  echo "  ✓ Settings window opened"
else
  echo "  ✗ Failed to open settings"
  echo "    Response: $RESP"
fi
sleep 0.2

# 3.2: Select button
echo "  3.2: POST /settings/select-button..."
BUTTON_ID=$(curl -s "$API_URL/preset/current" 2>/dev/null | jq -r '.preset.groups[0].buttons[0].id // "button-1"' 2>/dev/null)
echo "    Using button ID: $BUTTON_ID"
RESP=$(curl -s -X POST "$API_URL/settings/select-button" \
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
GROUP_ID=$(curl -s "$API_URL/preset/current" 2>/dev/null | jq -r '.preset.groups[0].id // "group-1"' 2>/dev/null)
echo "    Using group ID: $GROUP_ID"
RESP=$(curl -s -X POST "$API_URL/settings/select-group" \
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
RESP=$(curl -s -X POST "$API_URL/settings/open-app-icon-picker")
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

# フェーズ 4: エラーケース
echo -e "\n[Phase 4] Error handling..."

# 4.1: Invalid type
echo "  4.1: Invalid type value..."
RESP=$(curl -s -X POST "$API_URL/settings/set-action-type" \
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
