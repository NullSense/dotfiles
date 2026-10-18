# Local Postiz

Open http://localhost:4007/auth/login. The local account is `nullsense@postiz.local`;
`postiz-local password-copy` copies its password without printing it. The clipboard
is marked sensitive and stays available until replaced or cleared with
`wl-copy --clear`, including when desktop clipboard watchers read it first.
Credentials live in `~/.local/state/postiz/` with owner-only permissions.

The live clipboard regression check uses dummy text and clears the clipboard:
`python3 ~/.dotfiles/tests/postiz-local-clipboard-test.py`.

`postiz-local up`, `down`, `status`, `check`, `logs [service]`, and `open` operate this
installation. `down` preserves data volumes. `systemctl --user enable --now
postiz-local.service` enables login startup; disable it with `systemctl --user
disable --now postiz-local.service`. Docker's restart policy also restores running
containers after a Docker restart.

`postiz auth:status`, `postiz integrations:list`, and `postiz posts:list` use the
local instance automatically. Postiz is pinned to v2.25.1 and its official CLI to
2.0.25. The CLI is installed in
`~/.local/share/postiz/cli/`. Local API credentials are loaded by the wrapper,
not stored in shell startup files. Do not use the cloud OAuth login flow here.

Postiz MCP is registered in `~/.config/litellm/config-mcp.yaml`. Agent clients use
the existing http://127.0.0.1:4001/mcp/ gateway; the Postiz upstream is reached at
http://127.0.0.1:4007/api/mcp with a private environment-supplied bearer token.
The official `postiz` skill is installed in `~/.agents/skills/postiz` and linked
into the local agent skill directories.

Only port 4007 is published, on IPv4 loopback. Postgres, Redis and Temporal have
no host ports. All data volumes use Docker's disk-backed storage. Temporal uses
Postgres visibility, so Elasticsearch and the optional Temporal UI/admin tools
are omitted. Temporal's sample custom search attributes are disabled so Postiz's
`organizationId` and `postId` fit within SQL visibility's three Text slots.
`postiz-local check` verifies those actual attributes, the backend registration
boundary, and authenticated channel discovery. CPU, memory and log sizes are
bounded in `compose.yaml`.

This setup supplies no social provider credentials and configures no paid AI,
video, design-editor or email services. Connecting a social account is a separate
step. Instagram media and OAuth callbacks may need public HTTPS later; do not
expose this HTTP localhost configuration as-is. Draft and schedule only content
the user has authorized for publication.

Upstream references: https://github.com/gitroomhq/postiz-docker-compose,
https://github.com/temporalio/docker-compose/blob/main/docker-compose-postgres.yml,
https://docs.postiz.com/cli/authentication,
https://docs.postiz.com/mcp/introduction.
