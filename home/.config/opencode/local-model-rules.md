# Local model rules (Qwen3.6-35B-A3B via llama.cpp)

These rules apply when using the `llama-local` provider. They tighten behavior
because local models have less headroom than frontier models for retry loops,
context bloat, and verbose tool output.

## Tool calling
- One tool call per turn. No speculative parallel calls unless the user explicitly says batch.
- After a tool error, exactly one retry with a corrected approach. Then escalate to the user.
- Never re-read a file you just read in the same conversation — reference what you already have.
- Use `Read` with `offset` and `limit` to grab specific line ranges rather than whole files.

## Output discipline
- No "I'll now do X" preamble before tool calls. Just call the tool.
- No trailing summary after the work is done. The diff is enough.
- Stop when the task is done. Do not propose follow-up work unprompted.

## Context budget
- This is a 128k local model with persistent KV slot caching. Be efficient.
- Don't paste full file contents back to the user — reference by `path:line` instead.
- When approaching ~100k tokens, pause and ask the user whether to continue or compact.

## Thinking mode
- Thinking is enabled (`<think>`...`</think>`). Use it for hard reasoning, skip it for
  trivial restatements. Don't dump 500 tokens of thinking for "rename this variable".
