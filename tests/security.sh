#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/config/omarchy-notion" "$test_dir/runtime"
chmod 700 "$test_dir/runtime"
jq -n '{database_id:"database",data_source_id:"source",url:"https://www.notion.so/database"}' \
  > "$test_dir/config/omarchy-notion/config.json"

grep -Fq 'captureProcess.stdinEnabled = true' "$repo_dir/NotionCapture.qml"
grep -Fq 'stdinEnabled = false' "$repo_dir/NotionCapture.qml"

cat > "$test_dir/bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' test-token
EOF

cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
request=" $* "
if [[ $request == *"test-token"* || $request == *"sensitive-body-marker"* ]]; then
  printf '%s\n' 'credential or body leaked into curl argv' >&2
  exit 90
fi
response=${MOCK_CURL_RESPONSE:-success}
if [[ $request == *"/file_uploads/upload/send"* ]]; then
  response=${MOCK_UPLOAD_RESPONSE:-upload_success}
elif [[ $request == *"/file_uploads "* ]]; then
  response=upload_created
fi
case $response in
  success)
    printf '%s\n' '{"id":"page","url":"https://www.notion.so/page","created_time":"2026-08-23T00:00:00Z"}'
    ;;
  upload_created)
    printf '%s\n' '{"id":"upload"}'
    ;;
  upload_success)
    printf '%s\n' '{"status":"uploaded"}'
    ;;
  oversized)
    head -c $((16 * 1024 * 1024)) /dev/zero | tr '\0' x
    ;;
  error)
    printf '%s\n' '{"message":"safe remote error"}'
    exit 22
    ;;
  control_error)
    printf '%s\n' '{"message":"unsafe\u001b]0;changed title\u0007 error"}'
    exit 22
    ;;
esac
EOF
chmod 700 "$test_dir/bin/secret-tool" "$test_dir/bin/curl"

run_notion() {
  PATH="$test_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$test_dir/config" \
    XDG_RUNTIME_DIR="$test_dir/runtime" \
    "$repo_dir/omarchy-notion" "$@"
}

assert_no_response_temp() {
  if find "$test_dir/runtime" -type f -name 'omarchy-notion-response-*' | grep -q .; then
    printf '%s\n' 'bounded response temporary file was not removed' >&2
    exit 1
  fi
}

success=$(run_notion capture --title Test --body sensitive-body-marker)
[[ $(jq -r .id <<<"$success") == page ]]

jq '.url="https://app.notion.com/database"' "$test_dir/config/omarchy-notion/config.json" \
  > "$test_dir/config/omarchy-notion/config.json.new"
mv "$test_dir/config/omarchy-notion/config.json.new" "$test_dir/config/omarchy-notion/config.json"
[[ $(run_notion status | jq -r .url) == "https://app.notion.com/database" ]]

if MOCK_CURL_RESPONSE=oversized run_notion capture --title Test \
    >"$test_dir/oversized.out" 2>"$test_dir/oversized.err"; then
  printf '%s\n' 'oversized response unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'response exceeded the 2097152-byte limit' "$test_dir/oversized.err"
[[ ! -s "$test_dir/oversized.out" ]]
assert_no_response_temp

if MOCK_CURL_RESPONSE=error run_notion capture --title Test \
    >"$test_dir/error.out" 2>"$test_dir/error.err"; then
  printf '%s\n' 'HTTP error unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'Notion API request failed: safe remote error' "$test_dir/error.err"
[[ ! -s "$test_dir/error.out" ]]

if MOCK_CURL_RESPONSE=control_error run_notion capture --title Test \
    >"$test_dir/control.out" 2>"$test_dir/control.err"; then
  printf '%s\n' 'control-character HTTP error unexpectedly succeeded' >&2
  exit 1
fi
if LC_ALL=C grep -q $'\033\|\007' "$test_dir/control.err"; then
  printf '%s\n' 'remote error retained terminal control characters' >&2
  exit 1
fi
grep -Fq 'Notion API request failed: unsafe ]0;changed title  error' "$test_dir/control.err"

printf '\x89PNG\r\n\x1a\n' > "$test_dir/image.png"
if MOCK_UPLOAD_RESPONSE=oversized run_notion capture --title Test \
    --json <<<"$(jq -cn --arg image "$test_dir/image.png" \
      '{title:"Test",image_path:$image}')" \
    >"$test_dir/upload.out" 2>"$test_dir/upload.err"; then
  printf '%s\n' 'oversized upload response unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'response exceeded the 2097152-byte limit' "$test_dir/upload.err"
[[ ! -s "$test_dir/upload.out" ]]
assert_no_response_temp

jq '.url="file:///tmp/untrusted.desktop"' "$test_dir/config/omarchy-notion/config.json" \
  > "$test_dir/config/omarchy-notion/config.json.new"
mv "$test_dir/config/omarchy-notion/config.json.new" "$test_dir/config/omarchy-notion/config.json"
[[ $(run_notion status | jq -r .url) == "" ]]
if run_notion open >"$test_dir/open.out" 2>"$test_dir/open.err"; then
  printf '%s\n' 'unsafe database URL unexpectedly opened' >&2
  exit 1
fi
grep -Fq 'configured database URL is not a valid Notion HTTPS URL' "$test_dir/open.err"

printf '%s\n' 'security tests passed'
