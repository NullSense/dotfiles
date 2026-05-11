import type { Plugin } from "@opencode-ai/plugin"

// Opencode → Hyprland attention pill connector.
//
// Thin connector. All tagging logic lives in ~/.claude/hooks/attention.sh,
// which auto-detects the agent (claude / codex / opencode / gemini /
// copilot / aider) from the process tree and finds the parent terminal's
// Hyprland window. The same script is invoked from Claude's settings.json
// and Codex's hooks.json — single source of truth for the hyprctl tag
// dance and the agent-id vocabulary.
//
// Semantics mirror Claude's (Notification → set, Stop → clear):
//
//   permission.ask    SET     agent is BLOCKED on a user decision
//   session.error     SET     agent crashed / errored, needs eyes
//   session.idle      CLEAR   turn ended, no longer blocking
//
// Idle covers the "permission was replied, agent finished" case too —
// when the user replies, opencode goes busy → idle, so idle fires last
// and clears the tag.

export const AttentionPlugin: Plugin = async ({ $ }) => {
  const HOOK = `${process.env.HOME}/.claude/hooks/attention.sh`

  // Fail fast if the connector script isn't there. Don't crash opencode —
  // just refuse to register handlers, the bar's idle glyph stays visible.
  try {
    await $`test -x ${HOOK}`.quiet()
  } catch {
    console.warn(`[attention] hook script missing or not executable: ${HOOK} — plugin disabled`)
    return {}
  }

  const fire = async (action: "set" | "clear") => {
    // .nothrow() — never let an attention update bubble up and kill the
    // turn. If hyprctl/jq fails the bar simply doesn't update.
    // Explicit `opencode` override so process-tree detection can't
    // mis-attribute when the plugin is invoked from a wrapper shell.
    try {
      await $`bash ${HOOK} ${action} opencode`.quiet().nothrow()
    } catch {
      // swallow — see above
    }
  }

  return {
    event: async ({ event }) => {
      switch (event?.type) {
        case "permission.ask":
        case "session.error":
          return fire("set")
        case "session.idle":
          return fire("clear")
      }
    },
  }
}
