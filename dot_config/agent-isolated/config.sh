# Per-host overrides for ~/bin/agent-isolated.
#
# This file is sourced near the end of the wrapper. Use it to extend the
# sandbox without modifying the wrapper itself. All variables are optional;
# leave them commented to use defaults.
#
# EXTRA_BWRAP_ARGS — bwrap flags to append verbatim. Use to add extra binds,
# tmpfs masks, env vars, etc. Each token is one array element (no shell
# splitting), so quote spaces correctly.
#
# Example: give the sandbox read-write access to a project tree outside
# $HOME, mask one more secret-bearing dir, and pass through one extra
# env var:
#
# EXTRA_BWRAP_ARGS=(
#     --bind     "/srv/work"               "/srv/work"
#     --tmpfs    "$HOME/.config/some-app"
#     --setenv   MY_PROJECT_FOO            "$MY_PROJECT_FOO"
# )

# EXTRA_BWRAP_ARGS=()
