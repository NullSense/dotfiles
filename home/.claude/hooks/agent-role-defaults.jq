# Keep launch-time overrides from displacing the model and effort in these role definitions.
.tool_input as $input
| ($input.subagent_type // "general-purpose") as $role
| select(["general-purpose", "Plan", "Explore", "review", "correctness-review",
          "rust-idioms", "test-review", "doc-drift", "dependency-audit"] | index($role))
| select($input | has("model") or has("effort"))
| {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: ($input | del(.model, .effort))}}
