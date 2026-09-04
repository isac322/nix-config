# home-manager configuration shared by every host, macOS and NixOS alike.
# This is the bulk of the setup; the per-platform files add only what genuinely
# cannot be expressed the same way on both.
{
  config,
  lib,
  pkgs,
  inputs,
  osConfig,
  ...
}:

let
  # llm-agents' own package set is used for Claude Code and Codex because its
  # cached outputs track upstream faster than nixpkgs without rebuilding their
  # Rust dependency graphs against this flake's nixpkgs revision. OMP is
  # different: upstream publishes self-contained release binaries, so
  # pkgs.omp-bin follows the official release metadata directly.
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Runtime dependencies for the shared Zinit/Oh My Zsh configuration.
  # These names are kept here so the package list and shell initialization use
  # the same derivations rather than independently reconstructing them.
  googleCloudSdk = pkgs.google-cloud-sdk.withExtraComponents [
    pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
  ];
  # nixpkgs also installs `_gcloud` under share/zsh/site-functions, which Home
  # Manager adds to fpath. The OMZ gcloud plugin is intentionally absent: it
  # only searches mutable SDK layouts and misses this packaged completion.
  python = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.pip
    pythonPackages.virtualenv
  ]);

  # Cargo reads this user-level configuration after project-local files, so
  # repositories can override any choice that does not fit their build. Store
  # paths keep GUI applications, daemons, and shells on the same toolchain.
  tomlFormat = pkgs.formats.toml { };
  rustTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
  rustLinker =
    if pkgs.stdenv.hostPlatform.isDarwin then "${pkgs.lld}/bin/ld64.lld" else lib.getExe pkgs.mold;
  cargoConfig = {
    build."rustc-wrapper" = lib.getExe pkgs.sccache;
    target.${rustTarget} = {
      linker = lib.getExe pkgs.clang;
      rustflags = [
        "-C"
        "link-arg=-fuse-ld=${rustLinker}"
      ];
    };
    profile = {
      dev = {
        debug = "line-tables-only";
        package."*".debug = false;
      };
      test = {
        debug = "line-tables-only";
        package."*".debug = false;
      };
      debugging = {
        inherits = "dev";
        debug = true;
      };
    };
  };

  # sccache starts its local server on demand. The cache stays outside the Nix
  # store, while basedirs makes equivalent worktrees share compiler results.
  sccacheConfigTarget =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/Mozilla.sccache/config"
    else
      ".config/sccache/config";
  sccacheCacheDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Caches/Mozilla.sccache"
    else
      "${config.home.homeDirectory}/.cache/sccache";
  sccacheConfig = {
    basedirs = [ config.home.homeDirectory ];
    cache.disk = {
      dir = sccacheCacheDir;
      size = 20 * 1024 * 1024 * 1024;
    };
  };

  # Zinit remains the loader, but every plugin it loads comes from the
  # flake-pinned nixpkgs closure. Absolute Nix store paths are treated as local
  # plugins, so opening a shell never clones, fetches, updates or writes plugin
  # state. The unpackaged forgit, pnpm-alias and better-npm-completion plugins
  # are intentionally omitted: lazygit already covers forgit's workflow,
  # pnpm has no official Oh My Zsh plugin and its Nix package supplies `_pnpm`,
  # and zsh already ships npm completion.
  zinitPluginInit = ''
    zinit ice depth=1
    zinit light ${pkgs.zsh-powerlevel10k}/share/zsh/themes/powerlevel10k

    zinit ice wait lucid atload"_zsh_autosuggest_start"
    zinit light ${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions

    # Upstream otherwise downloads this secondary theme on the first shell
    # startup. Seed its writable cache from the same pinned source as the Nix
    # package before the plugin loads, preserving theme behavior without
    # runtime network access.
    typeset -g FAST_WORK_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/fast-syntax-highlighting"
    command mkdir -p "$FAST_WORK_DIR"
    if [[ ! -e "$FAST_WORK_DIR/secondary_theme.zsh" ]]; then
      command rm -f "$FAST_WORK_DIR/secondary_theme.zsh"
      command ln -s ${pkgs.zsh-fast-syntax-highlighting.src}/share/free_theme.zsh \
        "$FAST_WORK_DIR/secondary_theme.zsh"
    fi

    zinit ice wait"0c" lucid
    zinit light ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting

    zinit ice wait lucid
    zinit light ${pkgs.zsh-history-substring-search}/share/zsh/plugins/zsh-history-substring-search

    zinit ice wait lucid
    zinit light ${pkgs.zsh-fzf-tab}/share/fzf-tab

    zinit ice wait lucid
    zinit light ${pkgs.zsh-autopair}/share/zsh/zsh-autopair

    zinit ice wait lucid
    zinit light ${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use

    zinit ice wait lucid
    zinit light ${pkgs.zsh-history-search-multi-word}/share/zsh/zsh-history-search-multi-word
  '';

  # The deferred compinit barrier needs a plugin-shaped no-op, not another
  # mutable Git checkout.
  zinitNull = pkgs.writeTextDir "null.plugin.zsh" "";

  # Platform plugins are injected before the shared compinit barrier. Keeping
  # the selection at evaluation time means each generated ~/.zshrc contains
  # only plugins valid for its target OS, with no runtime OSTYPE branches.
  platformZshInit =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''
        # Clipboard integration is useful on the interactive Macs and has a
        # native pbcopy/pbpaste backend. The headless NixOS server has no
        # display or clipboard provider, so do not install functions there that
        # can only fail.
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/lib/clipboard.zsh
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/copybuffer/copybuffer.plugin.zsh
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/copypath/copypath.plugin.zsh
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/copyfile/copyfile.plugin.zsh

        # Bun and uv are installed only on the Macs. Their official Oh My Zsh
        # plugins are command-guarded, add generated completion, and uv also
        # supplies its maintained alias set.
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/bun/bun.plugin.zsh
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/uv/uv.plugin.zsh

        # No additional plugin checkout is needed on Darwin. zsh's packaged
        # completion set already includes launchctl and the standard macOS
        # command definitions.
      ''
    else if pkgs.stdenv.hostPlatform.isLinux then
      ''
        # Keep systemd aliases on the platform that actually provides systemd.
        # The command-not-found plugin is intentionally omitted: this flake has
        # no package-search database, so loading a handler would only turn a
        # normal missing-command error into a broken database lookup.
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/systemd/systemd.plugin.zsh
      ''
    else
      "";

  # Keep the readable source independent of store hashes while making the
  # generated ~/.zshrc source the exact zinit package pinned by flake.lock.
  zshInit =
    builtins.replaceStrings
      [
        "@zinit@"
        "@oh-my-zsh@"
        "# @zinit-plugins@"
        "@zsh-completions@"
        "@zinit-null@"
        "# @platform-zsh@"
      ]
      [
        "${pkgs.zinit}"
        "${pkgs.oh-my-zsh}/share/oh-my-zsh"
        zinitPluginInit
        "${pkgs.zsh-completions}"
        "${zinitNull}"
        platformZshInit
      ]
      (builtins.readFile ./zsh/init.zsh);

  camofoxCfg = lib.attrByPath [ "local" "camofox" ] {
    enable = false;
    apiPort = 9377;
  } osConfig;

  # The MCP services every agent on this machine should see. OMP and Claude
  # Code accept the same server object directly; the Codex activation below
  # derives its CLI-managed entry from the same Camofox definition.
  #
  # These are definition-only remote entries. Each agent discovers OAuth
  # metadata from the endpoint and stores the resulting credential in its own
  # state, so no auth stanza is ever written back into a declared file. Vanta
  # publishes one endpoint per data region; the US host is the whole
  # declaration.
  remoteMcpServers = {
    linear = {
      type = "http";
      url = "https://mcp.linear.app/mcp";
    };

    vanta = {
      type = "http";
      url = "https://mcp.vanta.com/mcp";
    };
  };

  # The adapter is only an HTTP client to the launchd-owned Camofox singleton.
  # Its argument names the calling agent, which is how the wrapper finds that
  # agent's durable session identifier — OMP's per-terminal transcript
  # breadcrumb, Claude Code's `CLAUDE_CODE_SESSION_ID` — so `/resume` keeps the
  # same tab namespace. The user stays `omp` for every agent: that is the
  # shared cookie and profile namespace the URL handler also writes into, and
  # splitting it per agent would split the logins with it.
  camofoxMcpServer = client: {
    type = "stdio";
    command = lib.getExe pkgs.camofox-mcp-session;
    args = [ client ];
    env = {
      CAMOFOX_BASE_URL = "http://127.0.0.1:${toString camofoxCfg.apiPort}";
      CAMOFOX_USER_ID = "omp";
    };
  };

  # OMP reads one user-level MCP registry on every host. Remote services stay
  # here beside plugin-backed stdio servers so a switch produces the complete
  # registry and removes entries that are no longer declared.
  #
  # `timeout` is OMP's own field; Claude Code has no equivalent in a server
  # entry and takes its budget from `MCP_TIMEOUT` instead, so it is applied
  # here rather than in the shared definitions.
  ompMcpServers = lib.mapAttrs (_: server: server // { timeout = 120000; }) (
    {
      # An OMP plugin that happens to speak MCP. It ships inside the plugin set
      # this file installs, so it stays out of the shared definitions.
      "context-mode" = {
        type = "stdio";
        command = lib.getExe pkgs.bun;
        args = [ "${pkgs.omp-plugins}/node_modules/context-mode/server.bundle.mjs" ];
      };
    }
    // remoteMcpServers
    // lib.optionalAttrs camofoxCfg.enable { camofox = camofoxMcpServer "omp"; }
  );

  ompMcpConfig = {
    "$schema" =
      "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
    mcpServers = ompMcpServers;
  };

  # Claude Code's user-scope registry. Unlike OMP it has no declarative file to
  # own: server definitions live only in ~/.claude.json, next to onboarding
  # state, per-project history and cached account data, so the activation below
  # merges this set into that file instead of replacing it. The alternative,
  # a system-wide managed-mcp.json, takes exclusive control of MCP and would
  # suppress the claude.ai connectors and every plugin-provided server.
  claudeMcpServers =
    remoteMcpServers // lib.optionalAttrs camofoxCfg.enable { camofox = camofoxMcpServer "claude"; };

  codexCamofoxMcpServer = camofoxMcpServer "codex";

  codexCamofoxMcpAddArgs = lib.escapeShellArgs (
    lib.concatMap (name: [
      "--env"
      "${name}=${codexCamofoxMcpServer.env.${name}}"
    ]) (builtins.attrNames codexCamofoxMcpServer.env)
    ++ [
      "--"
      codexCamofoxMcpServer.command
    ]
    ++ codexCamofoxMcpServer.args
  );

  # Claude Code reads one user-level settings file on every host. Keep only the
  # explicitly shared UI and safety controls here: machine-local hooks,
  # credentials, marketplaces and model selection remain outside this file.
  claudeSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    statusLine = {
      type = "command";
      command = "PATH=${
        lib.makeBinPath [
          pkgs.bash
          pkgs.jq
          pkgs.coreutils
        ]
      } ${lib.getExe pkgs.bash} \"$HOME/.claude/statusline-command.sh\"";
    };
    language = "한국어";
    alwaysThinkingEnabled = true;
    tui = "fullscreen";
    skipDangerousModePermissionPrompt = true;
  };

  # The package exposes versions from each flake-locked upstream manifest, so
  # updating a plugin source also updates OMP's registry without a second pin.
  ompPlugins = pkgs.omp-plugins.pluginVersions;

  # omp keeps its own register of which plugins exist, and a package under
  # node_modules is invisible without an entry here. Found by watching what
  # `omp plugin link` writes: the symlink alone left `omp plugin list` empty,
  # and `~/.omp/plugins/package.json` stayed `{"dependencies": {}}` throughout —
  # this file is the whole registry.
  ompPluginsLock = {
    plugins = lib.mapAttrs (_: version: {
      inherit version;
      enabledFeatures = null;
      enabled = true;
    }) ompPlugins;
    settings = { };
  };
in
{
  imports = [
    ./agent-instructions.nix
    ./agent-skills.nix
    ./skillclaw.nix
  ];

  # Every node runs a local SkillClaw client and synchronizes the shared
  # ~/.agents/skills tree used by OMP and Codex. Claude receives a Nix-generated
  # copy under ~/.claude/skills; only the unattended server role evolves shared skills.
  local.skillclaw.enable = true;

  # Clear what would otherwise make the plugin links below fail on a machine
  # that has run omp before, or that carries an older generation of this
  # configuration. Both cases cost a second switch to notice and a third to fix.
  #
  # `node_modules` has to be a real directory, because each plugin is linked
  # *inside* it. An earlier version of this pointed the directory itself at the
  # store, and a symlink left there makes every per-plugin link fail silently.
  #
  # The register is written by omp on its first run, and home-manager never
  # overwrites a file it did not create — so a machine that has already run omp
  # keeps omp's copy, and every plugin declared here stays invisible. Removing
  # it first is what makes this work from an untouched machine in one switch.
  home.activation.ompPluginsPrepare = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    plugins="$HOME/.omp/plugins"

    if [ -L "$plugins/node_modules" ]; then
      $DRY_RUN_CMD rm -f "$plugins/node_modules"
    fi

    if [ -e "$plugins/omp-plugins.lock.json" ] && [ ! -L "$plugins/omp-plugins.lock.json" ]; then
      $DRY_RUN_CMD rm -f "$plugins/omp-plugins.lock.json"
    fi
  '';

  # Claude Code keeps its user-scope MCP servers in ~/.claude.json, a file it
  # rewrites itself, so this is a merge rather than a home.file link: the
  # `mcpServers` key is replaced wholesale and every sibling key — onboarding
  # state, per-project history, cached account data — is carried through
  # untouched. Replacing the key rather than merging into it is what makes the
  # declaration authoritative, the same way the OMP registry is: a server
  # dropped from Nix leaves Claude Code on the next switch, and a server added
  # by hand with `claude mcp add --scope user` does not survive one.
  #
  # An unchanged registry is left alone rather than rewritten, so a switch
  # while Claude Code is running does not race it for the file.
  home.activation.claudeMcpRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config="$HOME/.claude.json"
    servers=${lib.escapeShellArg (builtins.toJSON claudeMcpServers)}
    jq=${lib.getExe pkgs.jq}

    if [ -f "$config" ] && "$jq" -e --argjson servers "$servers" \
      '(.mcpServers // {}) == $servers' "$config" > /dev/null; then
      :
    elif [ -n "$DRY_RUN_CMD" ]; then
      echo "claude-mcp-registry: would write mcpServers into $config." >&2
    else
      # 0600, matching what Claude Code creates itself: the file holds an
      # OAuth account record even before any MCP server is declared.
      umask 077
      [ -f "$config" ] || echo '{}' > "$config"

      # The rename only happens once jq has produced the whole document, so a
      # corrupt or unreadable ~/.claude.json fails the switch instead of being
      # replaced by a truncated one.
      tmp=$(${pkgs.coreutils}/bin/mktemp "$config.hm-XXXXXX")

      if "$jq" --argjson servers "$servers" '.mcpServers = $servers' "$config" > "$tmp"; then
        ${pkgs.coreutils}/bin/mv -f "$tmp" "$config"
      else
        ${pkgs.coreutils}/bin/rm -f "$tmp"
        echo "claude-mcp-registry: could not rewrite $config; left unchanged." >&2
        exit 1
      fi
    fi
  '';

  # Codex owns ~/.codex/config.toml and preserves comments and unrelated
  # tables when its MCP commands edit one server. Compare the complete
  # Camofox stdio definition before calling those commands: exact state is a
  # no-op, stale state replaces only camofox, and disabling Camofox removes
  # only that entry.
  home.activation.codexCamofoxMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    codex=${lib.escapeShellArg (lib.getExe agents.codex)}
    jq=${lib.escapeShellArg (lib.getExe pkgs.jq)}
    command=${lib.escapeShellArg codexCamofoxMcpServer.command}
    args=${lib.escapeShellArg (builtins.toJSON codexCamofoxMcpServer.args)}
    env=${lib.escapeShellArg (builtins.toJSON codexCamofoxMcpServer.env)}

    ${
      if camofoxCfg.enable then
        ''
          current=""
          present=0
          exact=0

          if current=$("$codex" mcp get camofox --json 2>/dev/null); then
            present=1
            if printf '%s\n' "$current" | "$jq" -e \
              --arg command "$command" \
              --argjson args "$args" \
              --argjson env "$env" \
              '.transport.type == "stdio"
                and .transport.command == $command
                and .transport.args == $args
                and .transport.env == $env' > /dev/null; then
              exact=1
            fi
          fi

          if [ "$exact" -eq 1 ]; then
            :
          elif [ -n "$DRY_RUN_CMD" ]; then
            if [ "$present" -eq 1 ]; then
              echo "codex-camofox-mcp: would replace stale camofox entry." >&2
            else
              echo "codex-camofox-mcp: would add camofox entry." >&2
            fi
          else
            if [ "$present" -eq 1 ]; then
              "$codex" mcp remove camofox
            fi
            "$codex" mcp add camofox ${codexCamofoxMcpAddArgs}
          fi
        ''
      else
        ''
          if "$codex" mcp get camofox --json > /dev/null 2>&1; then
            if [ -n "$DRY_RUN_CMD" ]; then
              echo "codex-camofox-mcp: would remove camofox entry." >&2
            else
              "$codex" mcp remove camofox
            fi
          fi
        ''
    }
  '';

  home.stateVersion = "26.05";

  # In module-aware Go, GOPATH is the root for module and checksum caches.
  # Keep that root under XDG_CACHE_HOME. GOMODCACHE then needs no override:
  # Go derives it as $GOPATH/pkg/mod. `go install` output is durable, so GOBIN
  # stays in the conventional user bin path instead of under the cache root.
  # Session variables also leave Go's mutable GOENV file available for
  # unrelated `go env -w` settings.
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
  home.sessionVariables = {
    GOBIN = "${config.home.homeDirectory}/.local/bin";
    GOPATH = "${config.home.homeDirectory}/.cache/go";
  };

  home.packages = [
    # Every command invoked directly by the managed zshrc. Keeping this set
    # beside the configuration makes a fresh machine usable on its first shell
    # rather than after a second round of "command not found" fixes.
    pkgs.bat
    pkgs.bottom
    pkgs.doggo
    pkgs.duf
    pkgs.dust
    pkgs.eza
    pkgs.fd
    pkgs.fzf
    pkgs.htop
    pkgs.lazygit
    pkgs.navi
    pkgs.procs
    pkgs.ripgrep
    pkgs.tealdeer
    pkgs.zinit
    pkgs.zoxide

    # External commands used by the shared Zinit and Oh My Zsh plugins. A
    # plugin that only defines aliases is still broken if its target command is
    # absent, so these travel with the shell configuration on every host.
    pkgs.awscli2
    pkgs.azure-cli
    pkgs.curl
    pkgs.docker-client
    pkgs.docker-compose
    pkgs.gh
    pkgs.git-crypt
    pkgs.go
    # These packages install `_gcloud`, `_gsutil`, and `_pnpm` into the profile
    # completion path; the deferred compinit below loads them without an OMZ
    # wrapper.
    googleCloudSdk
    pkgs.kubernetes-helm
    pkgs.nodejs_24
    pkgs.pnpm
    python
    pkgs.rsync
    pkgs.terraform

    # Backends advertised by OMZ's `extract` function. macOS and NixOS already
    # provide tar and bzip2; these make the remaining archive formats and
    # accelerated paths explicit. gzip also supplies the `uncompress` command
    # used for legacy .Z files; nixpkgs' ncompress renames that binary.
    pkgs.binutils
    pkgs.cabextract
    pkgs.cpio
    pkgs.gzip
    pkgs.lzip
    pkgs.lz4
    pkgs.lrzip
    pkgs.p7zip
    pkgs.pbzip2
    pkgs.pigz
    pkgs.pixz
    pkgs.qpdf
    pkgs.rpm
    pkgs.unar
    pkgs.unzip
    pkgs.xz
    pkgs.zpaq
    pkgs.zstd

    # Keep these runtimes available in interactive profiles. The statusLine
    # command above also embeds their store paths, so Dock/Spotlight launches
    # do not depend on a Home Manager PATH or fall back to macOS /bin/bash 3.2.
    pkgs.bash
    pkgs.jq

    # llm-agents tracks these two upstreams daily and supplies matching cached
    # outputs for every platform this configuration manages.
    agents.claude-code
    agents.codex

    # Official OMP standalone binaries. The release metadata flake input moves
    # version, platform asset, and sha256 digest together.
    pkgs.omp-bin

    # Gajae Code is also an agent harness, tracking verified upstream release
    # binaries via flake input rather than the llm-agents input.
    pkgs.gajae-code

    # BearDrive's CLI is useful on every node, but joining a project is mutable
    # per-user state: `bdrive init` selects a folder and hub, authenticates, and
    # installs the upstream login item. Nix supplies the pinned executable only
    # and never guesses which local directory a machine should synchronize.
    pkgs.beardrive

    # Observability CLIs, for the coding agents above to query telemetry with
    # rather than being handed screenshots of dashboards. They go on every
    # machine for the same reason claude-code does: the agent runs wherever
    # the work is.
    #
    # Two are not the obvious attribute. `promtool` is in prometheus's `cli`
    # output, so plain `pkgs.prometheus` would install the server and no tool
    # at all; `tempo-cli` is a local trim of the Tempo package — see
    # pkgs/overlay.nix. Sentry's current `sentry` CLI, posthog-cli, axiom-cli
    # and langfuse-cli are absent from nixpkgs and packaged in pkgs/.
    pkgs.tempo-cli
    pkgs.prometheus.cli
    pkgs.sentry
    pkgs.posthog-cli
    pkgs.axiom-cli
    pkgs.langfuse-cli

    # The services those same agents have to act on rather than just read.
    # `gws` is Google's Workspace CLI — @googleworkspace/cli upstream — and
    # `stripe-cli` installs `stripe`. The overlay makes `pkgs.slack-cli` the
    # Slack app CLI rather than nixpkgs's unrelated webhook script.
    pkgs.slack-cli
    pkgs.wrangler
    pkgs.stripe-cli
    pkgs.gws

    # Every machine, because a cluster is reached from wherever someone happens
    # to be — including the NixOS server, which is a machine that runs services
    # and therefore a machine where something goes wrong.
    #
    # It carries no cluster configuration and none belongs here. The same
    # shared package set includes gcloud with gke-gcloud-auth-plugin, so a
    # kubeconfig generated by `gcloud container clusters get-credentials`
    # remains usable by k9s and kubectl on every host.
    pkgs.k9s

    # And the client itself, which until now was not declared anywhere. On the
    # Macs `kubectl` was /usr/local/bin/kubectl, a symlink OrbStack installs into
    # its own app bundle — so the version moved when OrbStack did, and the NixOS
    # server had none at all. That is the same objection this repository makes to
    # rustup and to `omp plugin install`: the tool on a machine was whatever
    # something else last put there rather than what flake.lock pins.
    #
    # This changes which binary answers on the Macs. Nix profiles come before
    # /usr/local/bin on the PATH nix-darwin installs, so `kubectl` becomes the
    # pinned one — 1.36.3 here against OrbStack's 1.33.9. kubectl supports one
    # minor version of skew in either direction against the API server, and
    # OrbStack's own cluster tracks its bundled version, so the gap is worth
    # watching if that cluster is the one being used.
    pkgs.kubectl

    # Workflow files are edited from whichever machine the work is on, and a
    # broken one is only found by pushing it. actionlint reads them statically —
    # it parses the workflow schema, checks `runs-on` labels and `${{ }}`
    # expressions, and runs shellcheck over `run:` blocks — so the mistake is
    # caught before a commit rather than by a red run afterwards.
    #
    # It needs no configuration and no repository state, which is why it belongs
    # next to the other tools here rather than in a devshell. hadolint is the
    # same shape of tool for Dockerfiles and is still Mac-only in
    # home/darwin.nix; nobody has asked for it away from a Mac.
    pkgs.actionlint

    # Shared native-build tools, configured below as Cargo defaults. Native
    # Darwin builds use LLD's Mach-O linker; mold-unwrapped remains available
    # there for ELF work because nixpkgs' Darwin wrapper injects rejected ld64
    # flags. Linux Cargo builds use the normal mold wrapper.
    pkgs.sccache
    pkgs.lld
    (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.mold-unwrapped else pkgs.mold)
  ];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Byeonghoon Yoo";
      email = "bhyoo@bhyoo.com";
    };
  };

  # zinit and every command this initialization invokes are installed above.
  # The plugins themselves remain ordinary user-writable zinit state, while
  # the initialization and prompt configuration are immutable Home Manager
  # inputs. Completion is initialized by zicompinit in the managed file; an
  # eager Home Manager compinit would do the same work twice and race turbo
  # plugins that contribute completion functions.
  programs.zsh = {
    enable = true;
    enableCompletion = false;

    # The escape hatch for values this repository must not carry. Everything
    # Nix writes ends up in the world-readable store and in this repository's
    # history, so an LLM gateway token — or a proxy URL with basic auth —
    # belongs in a file Nix only agrees to read. Nix owns the source lines
    # below; the file itself is created and edited by hand and is never linked,
    # generated or deleted by a switch, so there is nothing for one to conflict
    # with.
    #
    # The environment is the one place every agent here already looks. Claude
    # Code takes `ANTHROPIC_BASE_URL` and its token from it directly; Codex
    # keeps the endpoint in its own unmanaged config.toml and resolves only the
    # key through the variable that provider's `env_key` names. Its absence is
    # the normal state on a host that talks to the vendors directly.
    #
    # `.zshenv` rather than `.zshrc`: an agent started from a script or an
    # editor gets no interactive shell, and Home Manager appends `envExtra`
    # outside the `[[ ! -o login ]]` guard around its own body, so a login
    # shell reads it too.
    envExtra = ''
      if [ -r "$HOME/.config/agents/env.sh" ]; then
        . "$HOME/.config/agents/env.sh"
      fi
    '';

    initContent = lib.mkAfter zshInit;
  };

  # On macOS this shadows Apple's /usr/bin/vim, which cannot be touched: it
  # lives on the sealed read-only system volume. Nix profiles come first on the
  # PATH nix-darwin installs, so this wins. On NixOS there is nothing to shadow.
  programs.vim = {
    enable = true;
    defaultEditor = true;

    # vim-sensible is not listed. home-manager's module sets it in its own
    # `config`, not merely as the option's default, and `plugins` is a list —
    # so definitions concatenate instead of overriding, and naming it here only
    # loads it twice. It supplies the uncontroversial baseline (backspace,
    # smarttab, complete-=i, incsearch, ruler, laststatus, wildmenu, autoread,
    # tabpagemax, formatoptions+=j, matchit ...) so none of that is repeated
    # below. Where the settings here overlap, they win: nixpkgs patches
    # sensible's `s:MaySet` to skip any option already set from /nix/store.
    #
    # Vim ships syntax files for most languages but not for Nix, and this
    # configuration is the thing most often edited here.
    plugins = [ pkgs.vimPlugins.vim-nix ];

    # Only the options home-manager knows about; everything else is extraConfig.
    settings = {
      background = "dark";
      number = true;
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
      ignorecase = true;
      smartcase = true;
      hidden = true;
      # Not left to vim-sensible: `set nocompatible` on line 2 of the generated
      # vimrc already moves 'history' to its non-vi default of 200, and because
      # that line lives under /nix/store, sensible's `s:MaySet` treats it as
      # user-set and skips its own history=1000.
      history = 1000;
      undofile = true;
      # Keep scratch files out of the directory being edited. The trailing `//`
      # makes Vim encode the full path into the file name, so same-named files in
      # different directories do not collide.
      undodir = [ "~/.vim/undo//" ];
      directory = [ "~/.vim/swap//" ];
      backupdir = [ "~/.vim/backup//" ];
    };

    extraConfig = ''
      " First: 'encoding' must be set before any option holding multi-byte text
      " (listchars below), otherwise those values are reinterpreted.
      set encoding=utf-8
      set fileformats=unix,dos,mac

      " Keep mouse events in the terminal so dragging selects terminal text.
      set mouse=

      syntax enable
      filetype plugin indent on

      " Colours. `silent!` so a Vim without this scheme still starts cleanly.
      if has('termguicolors') && $COLORTERM =~# 'truecolor\|24bit'
        set termguicolors
      endif
      silent! colorscheme habamax

      " Search. sensible gives incsearch and a <C-L> mapping to clear highlight;
      " hlsearch itself is deliberately not part of its baseline.
      set hlsearch
      nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

      " Indenting
      set autoindent
      set smartindent
      set softtabstop=2
      set shiftround

      " Display. scrolloff/sidescrolloff/listchars override sensible's more
      " conservative values (1, 2, and an ASCII-only listchars).
      set showcmd
      set cursorline
      set scrolloff=3
      set sidescrolloff=5
      set linebreak
      set list
      set listchars=tab:»·,trail:·,nbsp:␣,extends:›,precedes:‹

      " Completion in : and insert mode (sensible enables wildmenu itself).
      set wildmode=longest:full,full
      set completeopt=menuone,longest

      set updatetime=300

      " Share the system clipboard where this Vim was built with support for it.
      " Guarded rather than assumed: a headless server build has -clipboard.
      if has('clipboard')
        set clipboard=unnamed
      endif

      " Reopen a file at the line it was left on.
      autocmd BufReadPost *
        \ if line("'\"") >= 1 && line("'\"") <= line("$") && &filetype !~# 'commit'
        \ |   execute "normal! g`\""
        \ | endif
    '';
  };

  # omp's plugins, decided here rather than by `omp plugin install`.
  #
  # One symlink per plugin, not one for the whole directory, and the difference
  # is not stylistic. omp counts an entry under ~/.omp/plugins/node_modules only
  # when it is a symlink — the shape `omp plugin link` leaves behind. Pointing
  # the directory itself at a store tree put all 144 packages in place and
  # `omp plugin list` reported none of them, because they were then ordinary
  # directories.
  #
  # Their dependencies still resolve: Node walks up from the *real* path of the
  # importing file, which is inside the store tree, where every dependency the
  # lockfile pinned is a sibling. That is why pkgs/omp-plugins builds one tree
  # rather than one derivation per plugin.
  #
  # The trade, unchanged: these entries are store paths, so `omp plugin install`
  # cannot replace them. Adding a plugin is a single package entry in
  # pkgs/omp-plugins/default.nix.
  home.file = {
    # Generated once by p10k's wizard, then shared unchanged by every host.
    # `force` migrates an existing mutable ~/.p10k.zsh to the declarative copy.
    ".p10k.zsh" = {
      source = ./zsh/p10k.zsh;
      force = true;
    };

    # Shared Claude Code UI behavior. `force` replaces mutable settings written
    # by previous Claude/Orca runs, leaving exactly the selected keys above.
    ".claude/settings.json" = {
      text = builtins.toJSON claudeSettings;
      force = true;
    };

    ".claude/statusline-command.sh" = {
      source = ./claude/statusline-command.sh;
      executable = true;
      force = true;
    };

    # Global Rust defaults. Project-local Cargo configuration takes precedence,
    # and `cargo build --profile debugging` restores full dev debug information.
    ".cargo/config.toml" = {
      source = tomlFormat.generate "cargo-config.toml" cargoConfig;
      force = true;
    };

    # Upstream's native config location differs by OS. A bounded persistent
    # cache makes clean worktrees and branch changes reusable without a daemon.
    "${sccacheConfigTarget}" = {
      source = tomlFormat.generate "sccache-config.toml" sccacheConfig;
      force = true;
    };

    # Vim does not create these itself; without them undo/swap/backup silently
    # fail.
    ".vim/undo/.keep".text = "";
    ".vim/swap/.keep".text = "";
    ".vim/backup/.keep".text = "";

  }
  // {
    # The complete user-level MCP registry. `force` performs the one-time
    # migration from the mutable file that context-mode originally created.
    # OAuth credentials are stored separately, so remote authentication never
    # puts secrets in this world-readable Nix store file.
    ".omp/agent/mcp.json" = {
      text = builtins.toJSON ompMcpConfig;
      force = true;
    };

    # Agent instruction routing generates the OMP configuration in
    # home/agent-instructions.nix so ignored policy-skill names cannot drift
    # from the canonical segment manifest.

    # The register, next to the links it describes. Written whole, so it also
    # decides what is *not* installed — a plugin dropped from the set above
    # leaves omp on the next switch rather than lingering.
    ".omp/plugins/omp-plugins.lock.json".text = builtins.toJSON ompPluginsLock;
  }
  // builtins.listToAttrs (
    map (name: {
      name = ".omp/plugins/node_modules/${name}";
      value.source = "${pkgs.omp-plugins}/node_modules/${name}";
    }) (builtins.attrNames ompPlugins)
  );
}
