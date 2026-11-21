# Shared local stdio MCP server definitions referenced by both system-level
# Codex configuration (modules/common.nix -> /etc/codex/config.toml) and
# per-user agent registries (home/common.nix).
{ lib, pkgs }:

{
  # OMP loads pi-codegraph from ~/.omp/plugins so its session extension can
  # bind omitted projectPath to ctx.cwd and inject workspace status. Claude
  # Code and Codex run the same package's stdio MCP entry point directly; all
  # three share ~/.config/pi-codegraph and one daemon under ~/.cache/pi-codegraph/daemon.
  codegraph = {
    type = "stdio";
    command = "${pkgs.omp-plugins.plugins."@isac322/pi-codegraph"}/dist/bin/codegraph-mcp.js";
  };

  # The adapter is only an HTTP client to the launchd-owned Camofox singleton.
  # Its argument names the calling agent, which is how the wrapper finds that
  # agent's durable session identifier — OMP's per-terminal transcript
  # breadcrumb, Claude Code's `CLAUDE_CODE_SESSION_ID` — so `/resume` keeps the
  # same tab namespace. The user stays `omp` for every agent: that is the
  # shared cookie and profile namespace the URL handler also writes into, and
  # splitting it per agent would split the logins with it.
  camofox =
    {
      apiPort ? 9377,
      client,
    }:
    {
      type = "stdio";
      command = lib.getExe pkgs.camofox-mcp-session;
      args = [ client ];
      env = {
        CAMOFOX_BASE_URL = "http://127.0.0.1:${toString apiPort}";
        CAMOFOX_USER_ID = "omp";
      };
    };
}
