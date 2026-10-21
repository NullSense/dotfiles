#!/usr/bin/env bash
# Recurring invocation: README.md's tests/*.sh regression interface.
# Capture the real wrapper argv; never launch Docker or a model.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch_parent="${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp/oracle-nemotron35-contract"
mkdir -p "$scratch_parent"
case "$(stat -f -c '%T' "$scratch_parent")" in
  tmpfs|ramfs) printf 'contract fixture must be disk-backed\n' >&2; exit 1 ;;
esac
scratch=$(mktemp -d "$scratch_parent/run.XXXXXX")
trap 'agent-clean path "$scratch"' EXIT
mkdir -p "$scratch/fake-bin"
cat >"$scratch/fake-bin/docker" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

assert sys.argv[1] == "run", sys.argv[1:]
Path(os.environ["NEMOTRON_TEST_ARGV"]).write_text(json.dumps(sys.argv[1:]))
PY
chmod +x "$scratch/fake-bin/docker"
repository=nvidia/Nemotron-3.5-Embed-1B-NVFP4
revision=198164478bd2c4f2d3311d64eb563bc8564e0e6d
NEMOTRON_TEST_ARGV="$scratch/argv.json" \
  VLLM_IMAGE=vllm/vllm-openai:v0.32.0 \
  SERVED_NAME="$repository@$revision" REVISION="$revision" \
  VLLM_CACHE_ROOT_HOST="$scratch/cache" VLLM_DRIVER_COMPAT_ROOT="$scratch/no-driver" \
  PATH="$scratch/fake-bin:$PATH" \
  "$root/home/bin/llm-servers/vllm-nemotron35-embed"
python3 - "$scratch/argv.json" "$repository" "$revision" <<'PY'
import json
import sys
from pathlib import Path

args = json.loads(Path(sys.argv[1]).read_text())
names = []
for arg in args[args.index("--served-model-name") + 1:]:
    if arg.startswith("--"):
        break
    names.append(arg)
repository, revision = sys.argv[2:]
assert names[0] == f"{repository}@{revision}", names
assert repository in names, f"Sift's repository-only model request would be rejected: {names}"
assert len(names) == len(set(names)), names
assert args[args.index("--runner") + 1] == "pooling"
print("PASS: Nemotron accepts Sift text model name and preserves pinned identity")
PY
