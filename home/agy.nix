# agy (the Antigravity CLI) receives the same agent harness as OMP through a
# single plugin under ~/.gemini/config/plugins. Other modules contribute its
# rules, skills and MCP servers through `local.agy`; this module adds the
# Hindsight memory bridge and the Camofox browser subagent, then installs the
# whole tree by copy, because agy refuses plugin symlinks that point outside
# the plugin.
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
  # values let a test point a session at a scratch server or bank.
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
          --set-default AGY_HINDSIGHT_GLOBAL_SCOPE ${if hindsight.globalScope then "1" else "0"}
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
  };
}
