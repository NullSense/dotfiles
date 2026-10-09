#!/usr/bin/env bash
set -euo pipefail

# Recurring caller: ~/.config/systemd/user/vllm-update.service invokes
# ~/bin/vllm-update; this test exercises that same updater with fake commands.
# It deliberately never starts Docker, a service, a GPU process, or a model.

if [ -x "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/home/bin/vllm-update" ]; then
    updater="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/home/bin/vllm-update"
else
    updater=/home/nullsense/bin/vllm-update
fi

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local root=$1 leading_pin=$2 held_pin=$3
    mkdir -p "$root/bin/llm-servers" "$root/fake-bin"
    cat >"$root/bin/llm-servers/_vllm-image.sh" <<EOF
VLLM_IMAGE_PIN="vllm/vllm-openai:$leading_pin"
VLLM_IMAGE_PIN_HELD="vllm/vllm-openai:$held_pin"
EOF

    for wrapper in vllm-gemma4b vllm-glm-ocr vllm-nanbeige; do
        cat >"$root/bin/llm-servers/$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$CONTAINER_NAME" >>"$VLLM_TEST_DIR/wrappers.log"
while :; do /bin/sleep 60; done
EOF
        chmod +x "$root/bin/llm-servers/$wrapper"
        sed -i "2i IMAGE=\"\${VLLM_IMAGE:-\$VLLM_IMAGE_PIN_HELD}\"" "$root/bin/llm-servers/$wrapper"
    done
    for wrapper in vllm-nemotron-embed vllm-nemotron-rerank vllm-paddleocr-vl; do
        cat >"$root/bin/llm-servers/$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$CONTAINER_NAME" >>"$VLLM_TEST_DIR/wrappers.log"
while :; do /bin/sleep 60; done
EOF
        chmod +x "$root/bin/llm-servers/$wrapper"
        sed -i "2i IMAGE=\"\${VLLM_IMAGE:-\$VLLM_IMAGE_PIN}\"" "$root/bin/llm-servers/$wrapper"
    done
    cat >"$root/bin/llm-servers/vllm-qwen38" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
printf '%s %s\n' "$(basename "$0")" "$CONTAINER_NAME" >>"$VLLM_TEST_DIR/wrappers.log"
while :; do /bin/sleep 60; done
EOF
    chmod +x "$root/bin/llm-servers/vllm-qwen38"

    cat >"$root/fake-bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$VLLM_TEST_DIR/docker.log"
case "${1:-}" in
    pull) exit 0 ;;
    stop|rm) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    cat >"$root/fake-bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
if [[ "$url" == *'/tags/'* ]]; then
    printf '%s\n' '{"results":[{"name":"v0.29.0"}]}'
    exit 0
fi
if [[ "$url" == */health ]]; then
    printf 'health\n' >>"$VLLM_TEST_DIR/curl.log"
    exit 0
fi
if [[ "$url" == */v1/models ]]; then
    printf 'models\n' >>"$VLLM_TEST_DIR/curl.log"
    printf '%s\n' '{"data":[{"id":"smoke-\"quoted"}]}'
    exit 0
fi
printf '%s\n' "$url" >>"$VLLM_TEST_DIR/curl.log"
request_body=
previous=
for argument in "$@"; do
    if [[ "$previous" == '-d' ]]; then
        request_body=$argument
        break
    fi
    previous=$argument
done
if [[ -n "$request_body" ]]; then
    python3 -c 'import json,sys; json.loads(sys.argv[1])' "$request_body" \
        || exit 1
fi
if [[ -n "${VLLM_TEST_FAIL_PORT:-}" && "$url" == *":$VLLM_TEST_FAIL_PORT/"* ]]; then
    exit 1
fi
if [[ -n "${VLLM_TEST_MALFORMED_ENDPOINT:-}" && "$url" == *"$VLLM_TEST_MALFORMED_ENDPOINT" ]]; then
    case "$url" in
        */v1/embeddings) printf '%s\n' '{"data":[{"embedding":["not-a-number"]}]}' ;;
        */v1/rerank) printf '%s\n' '{"results":[{"index":1,"relevance_score":0.1}]}' ;;
        */v1/chat/completions) printf '%s\n' '{"choices":[{"message":{}}]}' ;;
    esac
    exit 0
fi
if [[ "${VLLM_TEST_EMBED_DIMS_MISMATCH:-}" == 1 && "$url" == */v1/embeddings ]]; then
    printf '%s\n' '{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3]}]}'
    exit 0
fi
case "$url" in
    */v1/embeddings) printf '%s\n' '{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3,0.4]}]}' ;;
    */v1/rerank) printf '%s\n' '{"results":[{"index":0,"relevance_score":0.1}]}' ;;
    */v1/chat/completions)
        if [[ "${VLLM_TEST_THINKING_ONLY:-}" == 1 ]]; then
            printf '%s\n' '{"choices":[{"message":{"content":null,"reasoning":"thinking"}}]}'
        else
            printf '%s\n' '{"choices":[{"message":{"content":"ok"}}]}'
        fi
        ;;
    *) exit 1 ;;
esac
EOF
    cat >"$root/fake-bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$root/fake-bin/docker" "$root/fake-bin/curl" "$root/fake-bin/sleep"
}

run_case() {
    local leading_pin=$1 held_pin=$2 fail_port=${3:-} output_file=$4 root=$5 status=0
    make_fixture "$root" "$leading_pin" "$held_pin"
    : >"$root/wrappers.log"
    : >"$root/docker.log"
    : >"$root/curl.log"
    if VLLM_TEST_DIR="$root" VLLM_TEST_FAIL_PORT="$fail_port" \
        VLLM_TEST_MALFORMED_ENDPOINT="${VLLM_TEST_MALFORMED_ENDPOINT:-}" \
        VLLM_TEST_THINKING_ONLY="${VLLM_TEST_THINKING_ONLY:-}" TMPDIR="$root" \
        PATH="$root/fake-bin:$PATH" "$updater" --servers-dir "$root/bin/llm-servers" --apply >"$output_file" 2>&1; then
        status=0
    else
        status=$?
    fi
    printf '%s' "$status"
}

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# Regression 1: with the leading pin already current, a held pin and a direct
# digest still make the configured inventory pending. The former updater printed
# “leading pin up to date” and exited successfully without mentioning Qwen.
current_root="$tmp/current"
mkdir -p "$current_root"
current_output="$tmp/current.out"
make_fixture "$current_root" v0.29.0 v0.26.0
if PATH="$current_root/fake-bin:$PATH" VLLM_TEST_DIR="$current_root" \
    "$updater" --servers-dir "$current_root/bin/llm-servers" >"$current_output" 2>&1; then
    :
else
    fail 'check-only inventory unexpectedly failed'
fi
grep -Fq 'digest pins : [vllm-qwen38]' "$current_output" \
    || fail 'check-only inventory omitted the direct digest wrapper'
grep -Fq 'configured inventory pending' "$current_output" \
    || fail 'check-only inventory claimed current while held/digest owners lagged'
if grep -Fq 'leading pin up to date' "$current_output"; then
    fail 'check-only inventory retained the false all-current message'
fi

# Regression 4: the live pin file annotates the leading pin with a trailing
# rollback comment. The parser must accept trailing comments and surrounding
# whitespace; the former updater exited "could not parse VLLM_IMAGE_PIN" in both
# check and --apply mode, so neither pin could be read or advanced.
commented_root="$tmp/commented"
commented_output="$tmp/commented.out"
make_fixture "$commented_root" v0.28.0 v0.26.0
printf '%s\n' \
    '# leading tier, annotated like the live file' \
    'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.28.0"   # 2026-10-06 (was v0.27.0; rollback = restore .bak)' \
    $'  VLLM_IMAGE_PIN_HELD="vllm/vllm-openai:v0.26.0"\t' \
    >"$commented_root/bin/llm-servers/_vllm-image.sh"
PATH="$commented_root/fake-bin:$PATH" VLLM_TEST_DIR="$commented_root" \
    "$updater" --servers-dir "$commented_root/bin/llm-servers" >"$commented_output" 2>&1 \
    || fail "commented pin file failed check mode: $(cat "$commented_output")"
grep -Fq 'leading pin : v0.28.0 ' "$commented_output" \
    || fail 'commented leading pin was not parsed'
grep -Fq 'held pin    : v0.26.0 ' "$commented_output" \
    || fail 'indented held pin with trailing whitespace was not parsed'
: >"$commented_root/wrappers.log"; : >"$commented_root/docker.log"; : >"$commented_root/curl.log"
VLLM_TEST_DIR="$commented_root" TMPDIR="$commented_root" PATH="$commented_root/fake-bin:$PATH" \
    "$updater" --servers-dir "$commented_root/bin/llm-servers" --apply >"$commented_output" 2>&1 || true
grep -Fq 'leading vLLM pin bumped v0.28.0 → v0.29.0' "$commented_output" \
    || fail 'commented leading pin did not advance under --apply'
grep -Fqx 'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.29.0"' \
    "$commented_root/bin/llm-servers/_vllm-image.sh" \
    || fail 'commented leading pin line was not rewritten'
grep -Fq 'VLLM_IMAGE_PIN_HELD="vllm/vllm-openai:v0.26.0"' \
    "$commented_root/bin/llm-servers/_vllm-image.sh" \
    || fail 'held pin changed while bumping a commented leading pin'

# A missing --servers-dir argument is CLI validation, and must fail before the
# updater performs the Docker Hub query or any wrapper/model operation.
validation_root="$tmp/validation"
make_fixture "$validation_root" v0.29.0 v0.26.0
: >"$validation_root/curl.log"
if PATH="$validation_root/fake-bin:$PATH" VLLM_TEST_DIR="$validation_root" \
    "$updater" --servers-dir >"$tmp/validation.out" 2>&1; then
    fail 'missing --servers-dir argument was accepted'
fi
grep -Fq 'usage: vllm-update' "$tmp/validation.out" \
    || fail 'missing --servers-dir argument did not produce usage output'
[[ ! -s "$validation_root/curl.log" ]] \
    || fail 'missing --servers-dir argument reached the HTTP latest query'

# Regression 2: leading can advance, but held/digest owners remain pending and
# therefore --apply must fail. The old updater returned success here.
apply_root="$tmp/apply"
apply_output="$tmp/apply.out"
status=$(run_case v0.28.0 v0.26.0 '' "$apply_output" "$apply_root")
[[ "$status" == 1 ]] || fail "partial apply returned status $status instead of 1"
grep -Fq 'leading vLLM pin bumped v0.28.0 → v0.29.0' "$apply_output" \
    || fail 'partial apply did not report the leading pin transition'
grep -Fq 'held/digest owners remain pending' "$apply_output" \
    || fail 'partial apply falsely claimed complete coverage'
grep -Fq 'vllm-qwen38' "$apply_output" \
    || fail 'partial apply did not report the digest owner'
grep -Fqx 'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.29.0"' \
    "$apply_root/bin/llm-servers/_vllm-image.sh" \
    || fail 'leading pin did not advance in the existing apply path'
grep -Fqx 'VLLM_IMAGE_PIN_HELD="vllm/vllm-openai:v0.26.0"' \
    "$apply_root/bin/llm-servers/_vllm-image.sh" \
    || fail 'held pin was changed by the updater'
grep -Fq 'vllm/vllm-openai@sha256:aaaaaaaa' "$apply_root/bin/llm-servers/vllm-qwen38" \
    || fail 'digest-owned wrapper was changed by the updater'

# Regression 3: the live _vllm-image.sh is a dotfiles symlink. Bumping the pin
# must edit the tracked target in place; a plain `sed -i` replaces the link with
# an untracked regular file and the repo silently stops seeing pin changes.
link_root="$tmp/symlinked"
link_output="$tmp/symlinked.out"
make_fixture "$link_root" v0.28.0 v0.26.0
mkdir -p "$link_root/repo"
mv "$link_root/bin/llm-servers/_vllm-image.sh" "$link_root/repo/_vllm-image.sh"
ln -s "$link_root/repo/_vllm-image.sh" "$link_root/bin/llm-servers/_vllm-image.sh"
: >"$link_root/wrappers.log"; : >"$link_root/docker.log"; : >"$link_root/curl.log"
VLLM_TEST_DIR="$link_root" TMPDIR="$link_root" PATH="$link_root/fake-bin:$PATH" \
    "$updater" --servers-dir "$link_root/bin/llm-servers" --apply >"$link_output" 2>&1 || true
[[ -L "$link_root/bin/llm-servers/_vllm-image.sh" ]] \
    || fail 'pin bump replaced the _vllm-image.sh symlink with a regular file'
grep -Fqx 'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.29.0"' "$link_root/repo/_vllm-image.sh" \
    || fail 'pin bump did not reach the symlink target'

# Every recognized wrapper is exercised through readiness followed by its real
# route contract, while all smoke containers receive isolated names.
for endpoint in /v1/embeddings /v1/rerank /v1/chat/completions; do
    grep -Fq "$endpoint" "$apply_root/curl.log" \
        || fail "request gate never exercised $endpoint"
done
[[ $(grep -c '^models$' "$apply_root/curl.log") == 7 ]] \
    || fail 'request gate did not query /v1/models for every wrapper'
[[ $(wc -l <"$apply_root/wrappers.log") == 7 ]] \
    || fail 'smoke inventory did not launch all seven wrappers'
awk '{print $2}' "$apply_root/wrappers.log" | sort -u | awk 'END { exit !(NR == 7) }' \
    || fail 'smoke containers did not receive unique names'
grep -Eq 'vllm-smoke-' "$apply_root/docker.log" \
    && fail 'smoke path retained a legacy collision-prone name'
awk 'BEGIN { stopped = 0; bad = 0 }
     /^stop / { stopped = 1 }
     /^rm / && !stopped { bad = 1 }
     END { exit bad }' "$apply_root/docker.log" \
    || fail 'smoke path pre-deleted before its isolated wrapper completed'
[[ $(grep -c '^stop ' "$apply_root/docker.log") == 7 ]] \
    || fail 'trap cleanup did not stop every isolated smoke container'
[[ $(grep -c '^rm -f ' "$apply_root/docker.log") == 7 ]] \
    || fail 'trap cleanup did not remove every isolated smoke container'
if compgen -G "$apply_root/vllm-update-smoke-*.log" >/dev/null; then
    fail 'smoke logs were not removed after their result was reported'
fi

# Malformed but HTTP-successful responses must fail the route contract. These
# target the three leading ports so each malformed shape is gate-relevant.
malformed_index=0
for spec in '/v1/embeddings:8099' '/v1/rerank:8100' '/v1/chat/completions:8101'; do
    malformed_endpoint=${spec%:*}
    malformed_root="$tmp/malformed-$malformed_index"
    malformed_output="$tmp/malformed-$malformed_index.out"
    export VLLM_TEST_MALFORMED_ENDPOINT="$malformed_endpoint"
    status=$(run_case v0.28.0 v0.26.0 '' "$malformed_output" "$malformed_root")
    [[ "$status" == 1 ]] || fail "malformed $malformed_endpoint response was accepted"
    grep -Fqx 'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.28.0"' \
        "$malformed_root/bin/llm-servers/_vllm-image.sh" \
        || fail "malformed $malformed_endpoint response still advanced the leading pin"
    ((malformed_index += 1))
done
unset VLLM_TEST_MALFORMED_ENDPOINT

# Nanbeige's default thinking mode can return null content while carrying the
# answer in its recognized reasoning field. That is a valid minimal response;
# it must still pass the leading gate.
thinking_root="$tmp/thinking-only"
thinking_output="$tmp/thinking-only.out"
export VLLM_TEST_THINKING_ONLY=1
status=$(run_case v0.28.0 v0.26.0 '' "$thinking_output" "$thinking_root")
[[ "$status" == 1 ]] || fail 'thinking-only response unexpectedly reported complete ownership'
grep -Fq 'leading vLLM pin bumped v0.28.0 → v0.29.0' "$thinking_output" \
    || fail 'thinking-only response with reasoning was rejected by the chat gate'
unset VLLM_TEST_THINKING_ONLY

# A request failure in the digest wrapper remains a nonzero, explicit partial
# result even when every leading wrapper passes.
failed_root="$tmp/failure"
failed_output="$tmp/failure.out"
status=$(run_case v0.28.0 v0.26.0 8105 "$failed_output" "$failed_root")
[[ "$status" == 1 ]] || fail "digest request failure returned status $status"
grep -Fq 'vllm-qwen38' "$failed_output" \
    || fail 'digest request failure was not attributed to Qwen'
grep -Fq 'held/digest owners remain pending' "$failed_output" \
    || fail 'digest request failure lost partial-result truthfulness'

# Regression 5: a wrapper that declares vLLM's pooling runner is an embedder and
# must receive the embedding probe, whatever its name. The former gate chose the
# probe from a fixed name list, so vllm-embeddinggemma2 (digest-pinned,
# `--runner pooling`) fell through to a chat completion it cannot serve. A chat
# wrapper that merely MENTIONS the flag in a comment must stay on the chat probe.
pooling_root="$tmp/pooling"
pooling_output="$tmp/pooling.out"
make_fixture "$pooling_root" v0.28.0 v0.26.0
cat >"$pooling_root/bin/llm-servers/vllm-embeddinggemma2" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
SERVE_ARGS=(--runner pooling --dtype bfloat16)
printf '%s %s\n' "$(basename "$0")" "$CONTAINER_NAME" >>"$VLLM_TEST_DIR/wrappers.log"
while :; do /bin/sleep 60; done
EOF
chmod +x "$pooling_root/bin/llm-servers/vllm-embeddinggemma2"
sed -i '2i # not a pooling model: --runner pooling would be wrong here' \
    "$pooling_root/bin/llm-servers/vllm-qwen38"
: >"$pooling_root/wrappers.log"; : >"$pooling_root/docker.log"; : >"$pooling_root/curl.log"
VLLM_TEST_DIR="$pooling_root" TMPDIR="$pooling_root" PATH="$pooling_root/fake-bin:$PATH" \
    "$updater" --servers-dir "$pooling_root/bin/llm-servers" --apply >"$pooling_output" 2>&1 || true
# Digest owners are smoked in glob order after 3 leading + 3 held wrappers:
# vllm-embeddinggemma2 on 8105, vllm-qwen38 on 8106.
grep -Fqx 'http://127.0.0.1:8105/v1/embeddings' "$pooling_root/curl.log" \
    || fail 'declared pooling wrapper did not receive the embedding probe'
grep -Fq ':8105/v1/chat/completions' "$pooling_root/curl.log" \
    && fail 'declared pooling wrapper was sent a chat completion'
grep -Fqx 'http://127.0.0.1:8106/v1/chat/completions' "$pooling_root/curl.log" \
    || fail 'chat digest wrapper lost its chat probe'
grep -Fq '✓ vllm-embeddinggemma2 answers on v0.29.0' "$pooling_output" \
    || fail 'declared pooling wrapper did not pass its embedding probe'
PATH="$pooling_root/fake-bin:$PATH" VLLM_TEST_DIR="$pooling_root" \
    "$updater" --servers-dir "$pooling_root/bin/llm-servers" >"$pooling_output" 2>&1 \
    || fail "check mode failed with a declared pooling wrapper: $(cat "$pooling_output")"
grep -Fq 'vllm-embeddinggemma2=embedding' "$pooling_output" \
    || fail 'check mode did not report the embedding probe for the declared pooling wrapper'
grep -Fq 'vllm-qwen38=chat' "$pooling_output" \
    || fail 'a commented runner mention moved a chat wrapper off the chat probe'

# The embedding probe sends a two-input batch and requires two vectors of one
# positive dimension. A ragged batch is a broken pooling contract even when every
# value is finite, and it must hold the leading pin back.
mismatch_root="$tmp/embed-dims"
mismatch_output="$tmp/embed-dims.out"
export VLLM_TEST_EMBED_DIMS_MISMATCH=1
status=$(run_case v0.28.0 v0.26.0 '' "$mismatch_output" "$mismatch_root")
unset VLLM_TEST_EMBED_DIMS_MISMATCH
[[ "$status" == 1 ]] || fail 'ragged embedding batch was accepted'
grep -Fqx 'VLLM_IMAGE_PIN="vllm/vllm-openai:v0.28.0"' \
    "$mismatch_root/bin/llm-servers/_vllm-image.sh" \
    || fail 'ragged embedding batch still advanced the leading pin'

printf 'PASS: vllm-update inventory, request-gate, and cleanup contract\n'
