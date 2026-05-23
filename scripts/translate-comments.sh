#!/usr/bin/env bash
# translate-comments.sh — Translate Japanese comments in Swift files to English.
# Prefers local LM Studio; falls back to claude CLI.
# Each comment is translated individually (no batching).
#
# Usage:
#   bash scripts/translate-comments.sh <directory>
#
# The script modifies .swift files IN PLACE — run it on a disposable copy
# (e.g. the /tmp clone created by publish-public.sh), never on the source repo.
#
# Environment:
#   TRANSLATE_BACKEND=lmstudio|claude   Force a specific backend
#   TRANSLATE_MODEL=<model-id>          Override LM Studio model selection
#   TRANSLATE_CACHE=<path>              Path to translation cache JSON
#   NO_CACHE=1                          Disable cache entirely

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:?Usage: translate-comments.sh <directory>}"

# ------------------------------------------------------------------ #
# Logging
# ------------------------------------------------------------------ #

say()  { printf '\033[1;36m[translate]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[translate]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[translate]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[translate]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------ #
# Detect backend
# ------------------------------------------------------------------ #

LMSTUDIO_ENDPOINTS=(
    "http://127.0.0.1:1234"
    "http://192.0.2.22:1234"
)

PREFERRED_MODELS=(
    "ibm/granite-4-h-tiny"
    "google/gemma-3-4b"
    "google/gemma-4-26b-a4b"
    "qwen3.5-4b-mlx"
    "qwen3.5-9b-mlx"
    "llama-3.2-3b-instruct"
    "google/gemma-3-1b"
)

BACKEND="${TRANSLATE_BACKEND:-}"
LMSTUDIO_URL=""
MODEL="${TRANSLATE_MODEL:-}"

if [ "$BACKEND" != "claude" ]; then
    for ep in "${LMSTUDIO_ENDPOINTS[@]}"; do
        if curl -s --connect-timeout 3 "$ep/v1/models" >/dev/null 2>&1; then
            LMSTUDIO_URL="$ep"
            break
        fi
    done
fi

if [ -n "$LMSTUDIO_URL" ] && [ "$BACKEND" != "claude" ]; then
    BACKEND="lmstudio"
    if [ -z "$MODEL" ]; then
        AVAILABLE_MODELS=$(curl -s "$LMSTUDIO_URL/v1/models" | jq -r '.data[].id')
        for pref in "${PREFERRED_MODELS[@]}"; do
            if echo "$AVAILABLE_MODELS" | grep -qF "$pref"; then
                MODEL="$pref"
                break
            fi
        done
        [ -z "$MODEL" ] && MODEL=$(echo "$AVAILABLE_MODELS" | head -1)
    fi
    if [ -z "$MODEL" ]; then
        err "LM Studio is running but no model is loaded."
        BACKEND=""
    else
        ok "Using LM Studio at $LMSTUDIO_URL (model: $MODEL)"
    fi
fi

if [ -z "$BACKEND" ]; then
    if command -v claude >/dev/null 2>&1; then
        BACKEND="claude"
        ok "Using claude CLI (LM Studio not available)"
    else
        err "No translation backend found. Skipping."
        exit 0
    fi
fi

# ------------------------------------------------------------------ #
# Python: extract → translate one-by-one → replace
# ------------------------------------------------------------------ #

PYTHON_SCRIPT=$(cat <<'PYEOF'
import sys, re, subprocess, os, json

target_dir = sys.argv[1]
backend = sys.argv[2]
lmstudio_url = sys.argv[3] if len(sys.argv) > 3 else ""
model = sys.argv[4] if len(sys.argv) > 4 else ""
cache_path = sys.argv[5] if len(sys.argv) > 5 else ""

JP_PATTERN = re.compile(r'[ぁ-ゖァ-ヶ一-鿿]')

cache = {}
cache_hits = 0
if cache_path and os.path.isfile(cache_path):
    with open(cache_path, 'r', encoding='utf-8') as f:
        cache = json.load(f)
    print(f"Loaded {len(cache)} cached translations from {cache_path}", file=sys.stderr)

def save_cache():
    if not cache_path:
        return
    with open(cache_path, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=0, separators=(',', ':'))
    print(f"  Cache saved: {len(cache)} entries ({cache_hits} hits this run)", file=sys.stderr)

fallback_log_path = os.path.join(target_dir, ".translate-fallbacks.log")
fallback_log = []

def log_fallback(filepath, line_idx, original, lm_output, claude_output, resolved):
    fallback_log.append({
        "file": os.path.relpath(filepath, target_dir),
        "line": line_idx + 1,
        "original": original,
        "lmstudio_returned": lm_output,
        "claude_returned": claude_output,
        "resolved": resolved
    })

def flush_fallback_log():
    if not fallback_log:
        return
    with open(fallback_log_path, 'w', encoding='utf-8') as f:
        f.write(f"# translate-comments fallback log\n")
        f.write(f"# {len(fallback_log)} comments needed fallback or failed\n")
        f.write(f"# Use this to refine the system prompt for the local LLM.\n\n")
        for entry in fallback_log:
            f.write(f"## {entry['file']}:{entry['line']}\n")
            f.write(f"  original:  {entry['original']}\n")
            f.write(f"  lmstudio:  {entry['lmstudio_returned']}\n")
            f.write(f"  claude:    {entry['claude_returned']}\n")
            f.write(f"  resolved:  {entry['resolved']}\n\n")
    print(f"  Fallback log: {fallback_log_path} ({len(fallback_log)} entries)", file=sys.stderr)
SYSTEM_MSG_COMMENT = """You translate Swift code comments from Japanese to English.

Rules:
- The input mixes Japanese text with English code identifiers. Translate ALL Japanese words to English. Keep code identifiers (panel_create, NSWindow, removeDuplicates, etc.) unchanged.
- Keep the same length and tone. A short comment stays short. Do not add explanations.
- Output ONLY the English translation. No preamble like "Here is the translation:". No quotes. No markdown. No comment prefix (// or ///).
- Keep emoji, numbers, Phase numbers, and version references as-is.
- Keep `backtick` formatting around code references.
- Output exactly one line. Never split into multiple lines.
- If the input is already fully English, output it unchanged.
- 系 means "category/type of", e.g. "write 系" → "write-type" or "write operations"."""

SYSTEM_MSG_STRING = """You translate Japanese UI text from a Swift CLI application to English.

Rules:
- Translate ALL Japanese words to natural English. This is user-facing text (error messages, usage help, labels).
- Keep the same tone. Error messages stay short and direct.
- Preserve Swift string interpolation like \\(variable) exactly as-is.
- Preserve leading/trailing whitespace, newlines, and indentation exactly as-is.
- Output ONLY the English translation. No preamble. No quotes. No markdown.
- Keep emoji, numbers, version references, file paths, and command names as-is.
- Keep technical terms (preset, token, Accessibility, etc.) in English.
- If the input is already fully English, output it unchanged."""

def has_japanese(text):
    return bool(JP_PATTERN.search(text))

def find_swift_files(directory):
    result = []
    for root, dirs, files in os.walk(directory):
        for f in files:
            if f.endswith('.swift'):
                result.append(os.path.join(root, f))
    return sorted(result)

def extract_japanese_comments(filepath):
    comments = []
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    in_block = False
    for i, line in enumerate(lines):
        stripped = line.strip()

        if '/*' in stripped:
            in_block = True
        if in_block:
            if has_japanese(stripped):
                comments.append((i, stripped))
            if '*/' in stripped:
                in_block = False
            continue

        m = re.search(r'(/{2,3}\s*.*)$', line)
        if m and has_japanese(m.group(1)):
            comments.append((i, m.group(1)))

    return comments, lines

STRING_PATTERN = re.compile(r'"([^"\\]|\\.)*"')
JP_SEGMENT = re.compile(r'[ぁ-ゖァ-ヶ一-鿿][ぁ-ゖァ-ヶ一-鿿\w\s　-〿、。（）()「」『』・:：…→←×+/]+')

def extract_japanese_strings(filepath, lines):
    """Find Japanese text inside string literals (not comments)."""
    strings = []
    in_block_comment = False
    in_multiline = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if '/*' in stripped:
            in_block_comment = True
        if in_block_comment:
            if '*/' in stripped:
                in_block_comment = False
            continue
        # Skip comment-only lines
        if stripped.startswith('//'):
            continue
        # Remove inline comments before scanning strings
        code_part = re.sub(r'//.*$', '', line)
        # Handle multi-line strings (""")
        if '"""' in code_part:
            in_multiline = not in_multiline
            continue
        if in_multiline:
            # Extract each Japanese segment, not the whole line
            for m in JP_SEGMENT.finditer(line):
                seg = m.group(0).rstrip()
                if seg:
                    strings.append((i, 'segment', seg))
            continue
        # Single-line strings: extract Japanese segments from within quotes
        for m in STRING_PATTERN.finditer(code_part):
            content = m.group(0)[1:-1]  # strip quotes
            if has_japanese(content):
                for sm in JP_SEGMENT.finditer(content):
                    seg = sm.group(0).rstrip()
                    if seg:
                        strings.append((i, 'segment', seg))
    return strings

def strip_comment_prefix(text):
    if text.startswith('///'):
        return text[3:].strip()
    elif text.startswith('//'):
        return text[2:].strip()
    return text.strip()

def translate_lmstudio(japanese_text, mode="comment"):
    sys_msg = SYSTEM_MSG_STRING if mode == "string" else SYSTEM_MSG_COMMENT
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": sys_msg},
            {"role": "user", "content": japanese_text}
        ],
        "temperature": 0.1,
        "max_tokens": 512
    }
    try:
        result = subprocess.run(
            ["curl", "-s", "--connect-timeout", "5", "--max-time", "30",
             f"{lmstudio_url}/v1/chat/completions",
             "-H", "Content-Type: application/json",
             "-d", json.dumps(payload)],
            capture_output=True, text=True, timeout=60
        )
        resp = json.loads(result.stdout)
        return resp["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"    lmstudio error: {e}", file=sys.stderr)
        return None

def translate_claude(japanese_text):
    prompt = f"Translate this Japanese code comment to concise English. Preserve `backtick` code references and technical terms. Output ONLY the English translation, nothing else: {japanese_text}"
    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"    claude error: {e}", file=sys.stderr)
        return None

def has_claude():
    try:
        subprocess.run(["claude", "--version"], capture_output=True, timeout=5)
        return True
    except Exception:
        return False

_claude_available = None

def translate_one(comment_text, filepath="", line_idx=0, mode="comment"):
    global _claude_available, cache_hits
    if mode == "comment":
        text = strip_comment_prefix(comment_text)
    else:
        text = comment_text

    if text in cache:
        cache_hits += 1
        return cache[text]

    def is_good(result):
        if not result:
            return False
        if has_japanese(result):
            return False
        if result.strip() == text.strip():
            return False
        return True

    if backend == "lmstudio":
        lm_result = translate_lmstudio(text, mode=mode)
        if is_good(lm_result):
            cache[text] = lm_result
            return lm_result
        if _claude_available is None:
            _claude_available = has_claude()
        claude_result = None
        if _claude_available:
            claude_result = translate_claude(text)
        resolved = "claude" if is_good(claude_result) else "failed"
        log_fallback(filepath, line_idx, comment_text, lm_result or "(empty)", claude_result or "(not available)", resolved)
        if resolved == "claude":
            cache[text] = claude_result
            return claude_result
        return None
    else:
        translated = translate_claude(text)
        if is_good(translated):
            cache[text] = translated
            return translated
        return None

def apply_translation(lines, line_idx, original_comment, translated):
    old_line = lines[line_idx]

    if original_comment.startswith('///'):
        prefix = '///'
    elif original_comment.startswith('//'):
        prefix = '//'
    else:
        lines[line_idx] = old_line.replace(original_comment, translated)
        return True

    new_comment = f"{prefix} {translated}"
    comment_start = old_line.find(original_comment)
    if comment_start >= 0:
        lines[line_idx] = old_line[:comment_start] + new_comment + "\n"
        return True
    return False

# ------------------------------------------------------------------ #
# Main
# ------------------------------------------------------------------ #

swift_files = find_swift_files(target_dir)
total_files = len(swift_files)
translated_total = 0
comment_total = 0
string_total = 0
string_translated_total = 0

print(f"Found {total_files} Swift files to scan (backend: {backend})", file=sys.stderr)

for fi, filepath in enumerate(swift_files):
    comments, lines = extract_japanese_comments(filepath)
    jp_strings = extract_japanese_strings(filepath, lines)
    if not comments and not jp_strings:
        continue

    rel = os.path.relpath(filepath, target_dir)
    file_changed = False

    # --- Comments ---
    if comments:
        comment_total += len(comments)
        translated_count = 0
        print(f"  [{fi+1}/{total_files}] {rel}: {len(comments)} comments", file=sys.stderr)

        for ci, (line_idx, original_comment) in enumerate(comments):
            if (ci + 1) % 10 == 0 or ci == 0:
                print(f"    {ci+1}/{len(comments)}...", file=sys.stderr)
            translated = translate_one(original_comment, filepath, line_idx)
            if translated:
                apply_translation(lines, line_idx, original_comment, translated)
                translated_count += 1

        translated_total += translated_count
        if translated_count > 0:
            file_changed = True
        print(f"    -> {translated_count}/{len(comments)} comments translated", file=sys.stderr)

    # --- String literals ---
    if jp_strings:
        string_total += len(jp_strings)
        str_count = 0
        print(f"  [{fi+1}/{total_files}] {rel}: {len(jp_strings)} strings", file=sys.stderr)

        for si, (line_idx, kind, original) in enumerate(jp_strings):
            if (si + 1) % 10 == 0 or si == 0:
                print(f"    str {si+1}/{len(jp_strings)}...", file=sys.stderr)
            translated = translate_one(original, filepath, line_idx, mode="string")
            if translated:
                old_line = lines[line_idx]
                lines[line_idx] = old_line.replace(original, translated, 1)
                str_count += 1

        string_translated_total += str_count
        if str_count > 0:
            file_changed = True
        print(f"    -> {str_count}/{len(jp_strings)} strings translated", file=sys.stderr)

    if file_changed:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(lines)

flush_fallback_log()
save_cache()
print(f"\nDone: {translated_total}/{comment_total} comments, {string_translated_total}/{string_total} strings translated", file=sys.stderr)
PYEOF
)

# ------------------------------------------------------------------ #
# Run
# ------------------------------------------------------------------ #

say "Translating Japanese comments in $TARGET_DIR"

SWIFT_COUNT=$(find "$TARGET_DIR" -name '*.swift' | wc -l | tr -d ' ')
say "Found $SWIFT_COUNT Swift files to process"

CACHE_FILE="${TRANSLATE_CACHE:-$HERE/.translate-cache.json}"
if [ "${NO_CACHE:-0}" = "1" ]; then
    CACHE_FILE=""
    warn "Cache disabled (NO_CACHE=1)"
elif [ -f "$CACHE_FILE" ]; then
    CACHE_ENTRIES=$(python3 -c "import json; print(len(json.load(open('$CACHE_FILE'))))" 2>/dev/null || echo 0)
    ok "Translation cache: $CACHE_FILE ($CACHE_ENTRIES entries)"
fi

if [ "$BACKEND" = "lmstudio" ]; then
    python3 -c "$PYTHON_SCRIPT" "$TARGET_DIR" "$BACKEND" "$LMSTUDIO_URL" "$MODEL" "$CACHE_FILE"
else
    python3 -c "$PYTHON_SCRIPT" "$TARGET_DIR" "$BACKEND" "" "" "$CACHE_FILE"
fi

ok "Comment translation complete"
