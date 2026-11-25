# System-level settings that apply to every host, macOS and NixOS alike.
#
# Anything whose option type or meaning differs between the two platforms must
# NOT live here. `system.stateVersion` is the trap: nix-darwin types it as an
# integer and NixOS as a string, so it is set in modules/darwin.nix and
# modules/nixos.nix separately.
{
  config,
  lib,
  pkgs,
  packageOverlay,
  ...
}:

let
  tomlFormat = pkgs.formats.toml { };
  mcpServers = import ../lib/mcp.nix { inherit lib pkgs; };
  camofoxCfg = lib.attrByPath [ "local" "camofox" ] {
    enable = false;
    apiPort = 9377;
  } config;
  # Codex asks before every MCP tool call by default, and a non-interactive run
  # or a background subagent cannot answer, so the call fails. Every other
  # harness here runs these tools without a prompt; Codex does too.
  toCodexStdioMcp =
    server: builtins.removeAttrs server [ "type" ] // { default_tools_approval_mode = "approve"; };

  # Static machine-wide Codex configuration in /etc/codex/config.toml (Codex's
  # `system` layer, lower precedence than ~/.codex/config.toml `user` overrides
  # and CLI `-c` flags). Keeping declarative provider definitions, feature
  # toggles, and MCP store paths here lets ~/.codex/config.toml hold only Codex's
  # own mutable state ([hooks.state.*], [tui], [projects.*]) and per-user
  # overrides.
  #
  # Private proxy `base_url` values and `experimental_realtime_ws_base_url` are
  # omitted here because /etc/codex/config.toml is world-readable in the Nix
  # store and Codex ignores OPENAI_BASE_URL; `home/codex-launcher.nix` injects
  # only those URLs at runtime from environment variables (or
  # ~/.config/agents/env.sh).
  codexSystemConfig = {
    model_provider = "custom";
    service_tier = "fast";
    web_search = "live";

    features = {
      # Codex 0.158+ tries to auto-start a shared app-server daemon by installing
      # packages under ~/.codex/packages. Keep the daemon disabled so Nix owns
      # the Codex binary/version and app-server runs in-process.
      daemon_auto_start = false;
      standalone_web_search = true;
    };

    model_providers = {
      custom = {
        name = "OpenAI";
        env_key = "CODEX_CUSTOM_API_KEY";
        wire_api = "responses";
        supports_websockets = true;
        supports_standalone_web_search = true;
        http_headers = {
          x-openai-actor-authorization = "custom";
        };
        capabilities = {
          remote_compaction = "v2";
          external_web_access = true;
        };
      };

      cliproxyapi = {
        name = "OpenAI";
        env_key = "CLIPROXYAPI_API_KEY";
        wire_api = "responses";
        supports_websockets = true;
        supports_standalone_web_search = true;
        http_headers = {
          x-openai-actor-authorization = "cliproxyapi";
        };
        capabilities = {
          remote_compaction = "v2";
          external_web_access = true;
        };
      };
    };

    mcp_servers = {
      codegraph = toCodexStdioMcp mcpServers.codegraph;
    }
    // lib.optionalAttrs camofoxCfg.enable {
      camofox = toCodexStdioMcp (
        mcpServers.camofox {
          inherit (camofoxCfg) apiPort;
          client = "codex";
        }
      );
    };
  };
in
{
  # llm-agents' `overlays.shared-nixpkgs` used to be here and is deliberately
  # gone: it builds that whole set against our nixpkgs, and its binary cache
  # only answers for the revision they pinned. home/common.nix takes
  # `packages.<system>` instead, which is the build they actually uploaded.
  # The Firefox overlay is deliberately not here either — see modules/darwin.nix
  # for why it must stay off Linux.
  nixpkgs.overlays = [ packageOverlay ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "1password-cli"
      "claude-code"
      # OmO Native is published under the Sustainable Use License, which
      # permits internal use but is not an OSI licence.
      "omo"
      # getsentry/cli uses FSL-1.1-Apache-2.0. It permits internal use and
      # converts to Apache-2.0 after two years, but nixpkgs correctly classifies
      # the current release as unfree until that conversion.
      "sentry"
      # HashiCorp relicensed Terraform from MPL-2.0 to the Business Source
      # License at 1.5.x, so nixpkgs has marked it unfree ever since. Nothing
      # about the binary changed and the BUSL permits this use; it only forbids
      # offering a competing Terraform service. opentofu is the MPL fork that
      # came out of the relicensing and needs no entry here, if the licence
      # rather than the tool is what matters later.
      "terraform"
    ];

  environment.systemPackages = [
    pkgs.git
  ];

  environment.etc."codex/config.toml".source = tomlFormat.generate "codex-config.toml" codexSystemConfig;
}
