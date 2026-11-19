# agy (the Antigravity CLI) receives the same agent harness as OMP through a
# single plugin under ~/.gemini/config/plugins and shared CLI preferences merged
# into ~/.gemini/antigravity-cli/settings.json via Home Manager's
# `programs.antigravity-cli` (`mutableSettings = true`). Other modules
# contribute its rules, skills and MCP servers through `local.agy`; this module
# adds the Hindsight memory bridge and the Camofox browser subagent, then
# installs the plugin tree by copy, because agy refuses plugin symlinks that
# point outside the plugin.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.agy;
  hindsight = import ../lib/hindsight.nix;
  pluginName = "nix-managed";
  pluginTarget = "${config.home.homeDirectory}/.gemini/config/plugins/${pluginName}";

  # The bridge reads its scope from the environment so the one definition in
  # lib/hindsight.nix configures OMP and agy alike; defaults rather than fixed
  # values let a test point a session at a scratch server or bank. The token is
  # read at each call, as the omp launcher does, so it stays out of the plugin
  # files and the Nix store. A missing token leaves memory to fail open: agy
  # still runs and the bridge logs the rejected request.
  hindsightTokenCommand = hindsight.tokenCommand {
    inherit (pkgs.stdenv.hostPlatform) isDarwin;
    sops = lib.getExe pkgs.sops;
  };
  hindsightBridge =
    pkgs.runCommand "agy-hindsight-configured"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "agy-hindsight";
      }
      ''
        makeWrapper ${lib.getExe pkgs.agy-hindsight} $out/bin/agy-hindsight \
          --set-default AGY_HINDSIGHT_API_URL ${lib.escapeShellArg hindsight.apiUrl} \
          --set-default AGY_HINDSIGHT_BANK ${lib.escapeShellArg hindsight.bank} \
          --set-default AGY_HINDSIGHT_GLOBAL_SCOPE ${if hindsight.globalScope then "1" else "0"} \
          --run ${lib.escapeShellArg ''if [ -z "''${HINDSIGHT_API_TOKEN:-}" ]; then HINDSIGHT_API_TOKEN=$(${hindsightTokenCommand} 2>/dev/null) || HINDSIGHT_API_TOKEN=; export HINDSIGHT_API_TOKEN; fi''}
      '';
  bridge = lib.getExe hindsightBridge;

  # agy accepts only these keys in a server entry; OMP's `enabled = false`
  # becomes agy's `disabled = true`.
  toAgyMcpServer =
    server:
    lib.filterAttrs (
      name: _:
      lib.elem name [
        "command"
        "args"
        "env"
        "cwd"
        "url"
        "headers"
      ]
    ) server
    // lib.optionalAttrs ((server.enabled or true) == false) { disabled = true; };

  mcpConfig = pkgs.writeText "agy-mcp_config.json" (
    builtins.toJSON {
      mcpServers = lib.mapAttrs (_: toAgyMcpServer) cfg.mcpServers // {
        hindsight = {
          command = bridge;
          args = [ "mcp" ];
        };
      };
    }
  );

  # PreInvocation runs before every model call and the bridge acts only on a
  # conversation's first one; agy aborts a hook after `timeout` seconds and a
  # Hindsight recall can take ten.
  hooksConfig = pkgs.writeText "agy-hooks.json" (
    builtins.toJSON {
      hindsight-memory = {
        PreInvocation = [
          {
            type = "command";
            command = "${bridge} hook pre-invocation";
            timeout = 30;
          }
        ];
        Stop = [
          {
            type = "command";
            command = "${bridge} hook stop";
            timeout = 10;
          }
        ];
      };
    }
  );

  pluginManifest = pkgs.writeText "agy-plugin.json" (
    builtins.toJSON {
      name = pluginName;
      displayName = "Nix-managed agent harness";
      description = "Rules, skills, MCP servers, Hindsight memory and the Camofox browser subagent from /etc/nix-darwin.";
    }
  );

  # The OMP browser agent's procedure, with its tool names translated. In agy
  # the Camofox tools keep their MCP names, `run_command` replaces `bash`, and
  # the invoking agent is reached with `send_message`.
  ompBrowserAgent = builtins.readFile ./files/agent-instructions/agents/browser.md;
  browserProcedure =
    lib.replaceStrings
      [
        "mcp__camofox_"
        "`bash`"
        "ask `Main` through `hub` with `await: true` and `timeoutMs: 120000`"
      ]
      [
        "camofox_"
        "`run_command`"
        "ask `Main`, the agent that invoked you, through `send_message`"
      ]
      (lib.concatStringsSep "\n---\n" (lib.drop 1 (lib.splitString "\n---\n" ompBrowserAgent)));
  browserAgent =
    server:
    pkgs.writeText "agy-browser-agent.md" ''
      ---
      name: browser
      description: Complete interactive Camofox web workflows end to end; use for dynamic sites, UI interaction, and grounded extraction, not ordinary informational web search.
      subagent: true
      mainAgent: false
      inheritMcp: false
      tools: [run_command]
      mcpServers:
        - name: camofox
          command: ${builtins.toJSON server.command}
          args: ${builtins.toJSON (server.args or [ ])}
          env: ${builtins.toJSON (server.env or { })}
      ---
      # browser
      ${lib.removePrefix "\n" browserProcedure}'';

  pluginFiles =
    cfg.pluginFiles
    // {
      "plugin.json" = pluginManifest;
      "hooks.json" = hooksConfig;
      "mcp_config.json" = mcpConfig;
    }
    // lib.optionalAttrs (cfg.camofoxMcpServer != null) {
      "agents/browser/agent.md" = browserAgent cfg.camofoxMcpServer;
    };
  pluginTree = pkgs.linkFarm "agy-${pluginName}-plugin" (
    lib.mapAttrsToList (name: path: { inherit name path; }) pluginFiles
  );
in
{
  options.local.agy = {
    pluginFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Files and directories of the Nix-managed agy plugin, keyed by their path inside it.";
    };
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = "MCP servers in OMP's schema that agy's main agent sees.";
    };
    camofoxMcpServer = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
      default = null;
      description = "Camofox MCP server owned by the browser subagent alone; null leaves the subagent out.";
    };
  };

  config = {
    assertions = [
      {
        assertion = hindsight.scoping == "per-project-tagged";
        message = "pkgs/agy-hindsight implements only Hindsight's per-project-tagged scoping.";
      }
      {
        assertion =
          !lib.any (needle: lib.hasInfix needle browserProcedure) [
            "mcp__"
            "`hub`"
            "`bash`"
          ];
        message = "home/agy.nix no longer translates every OMP tool name in agents/browser.md.";
      }
    ];

    # Store files all carry the 1970 epoch mtime, so rsync's size-and-mtime
    # quick check would skip a changed file of equal size; compare content.
    home.activation.installAgyPlugin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg pluginTarget}
      run ${lib.getExe pkgs.rsync} --recursive --copy-links --delete --checksum --perms \
        --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
        ${pluginTree}/ ${lib.escapeShellArg pluginTarget}/
    '';

    programs.antigravity-cli = {
      enable = true;
      mutableSettings = true;
      # Merge only shared UI, default model, and execution defaults over
      # ~/.gemini/antigravity-cli/settings.json so runtime `/model` overrides
      # and Orca/agy `trustedWorkspaces` entries survive a switch.
      # `altScreenMode = "default"` keeps conversation scrolling in the
      # terminal's native scrollback, avoiding agy's hardcoded alt-screen
      # wheel acceleration (`1 + floor(sqrt(streak))` within 150 ms).
      settings = {
        "$schema" = "https://antigravity.google/schemas/v1/settings.json";
        altScreenMode = "default";
        clearScrollbackOnResize = false;
        useTerminalCursor = true;
        pickerGrouping = "grouped";
        showFeedbackSurvey = false;
        showTips = false;
        model = "Orchestrator (Neon)";
        notifications = true;
        agentMode = "accept-edits";
        toolPermission = "always-proceed";
        allowNonWorkspaceAccess = true;
      };
      # Under `always-proceed` + `allowNonWorkspaceAccess = true`, guard only
      # raw private keys and SSH/GPG keyrings; leave `allow`/`ask` null so
      # runtime grants in mutable settings survive a switch.
      permissions.deny = [
        "write_file(${config.home.homeDirectory}/.ssh)"
        "write_file(${config.home.homeDirectory}/.gnupg)"
        "read_file(${config.home.homeDirectory}/.gnupg/private-keys-v1.d)"
        "read_file(${config.home.homeDirectory}/.config/sops/age)"
      ];
    };
  };
}
