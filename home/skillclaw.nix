{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.skillclaw;
  py = pkgs.python3Packages;

  skillclaw = py.buildPythonApplication {
    pname = "skillclaw";
    version = "0.4.0";
    src = inputs.skillclaw;
    pyproject = true;

    # Upstream pulls before it pushes. Nix-managed skills must not be
    # replaced by an older remote copy just before their pinned revision is
    # uploaded, so every pull merges names from this environment variable into
    # its explicit skip set. Local-only skills retain the normal pull-then-push
    # flow.
    postPatch = ''
      substituteInPlace skillclaw/skill_hub.py \
        --replace-fail \
        '        skip_set = {str(name or "").strip() for name in (skip_names or []) if str(name or "").strip()}' \
        '        skip_set = {str(name or "").strip() for name in (skip_names or []) if str(name or "").strip()}; skip_set.update(name.strip() for name in os.environ.get("SKILLCLAW_SYNC_SKIP_PULL", "").split(",") if name.strip())'
    '';

    build-system = [
      py.setuptools
      py.wheel
    ];

    dependencies = [
      py.boto3
      py.click
      py.fastapi
      py.httpx
      py.openai
      py.oss2
      py.python-dotenv
      py.pyyaml
      py.requests
      py.tiktoken
      py.uvicorn
    ];

    doCheck = false;
    pythonImportsCheck = [
      "skillclaw"
      "skillclaw.skill_hub"
      "evolve_server"
    ];

    meta = {
      description = "Shared, continuously evolving skills for AI agents";
      homepage = "https://github.com/AMAP-ML/SkillClaw";
      license = lib.licenses.mit;
      mainProgram = "skillclaw";
    };
  };

  sharedEnv = "${config.xdg.configHome}/skillclaw/shared.env";
  llmEnv = "${config.xdg.configHome}/skillclaw/llm.env";
  configFile = "${config.home.homeDirectory}/.skillclaw/config.yaml";
  skillsDir = "${config.home.homeDirectory}/.agents/skills";

  configure = pkgs.writeShellApplication {
    name = "skillclaw-configure";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      shared_env=${lib.escapeShellArg sharedEnv}
      llm_env=${lib.escapeShellArg llmEnv}
      config_file=${lib.escapeShellArg configFile}

      if [ ! -r "$shared_env" ]; then
        echo "skillclaw: missing external S3 settings in $shared_env." >&2
        exit 1
      fi

      SKILLCLAW_STORAGE_ENDPOINT=""
      SKILLCLAW_STORAGE_BUCKET=""
      SKILLCLAW_STORAGE_REGION="us-east-1"
      SKILLCLAW_STORAGE_ACCESS_KEY=""
      SKILLCLAW_STORAGE_SECRET_KEY=""
      SKILLCLAW_LLM_PROVIDER="custom"
      SKILLCLAW_LLM_API_BASE=""
      SKILLCLAW_LLM_API_KEY=""
      SKILLCLAW_LLM_MODEL_ID=""
      SKILLCLAW_LLM_API_MODE="responses"

      # This is a private, user-owned shell environment file. It is deliberately
      # outside the Nix store because it contains the shared object-store secret.
      # shellcheck disable=SC1090
      . "$shared_env"
      if [ -r "$llm_env" ]; then
        # shellcheck disable=SC1090
        . "$llm_env"
      fi

      if [ -z "$SKILLCLAW_STORAGE_ENDPOINT" ] ||
        [ -z "$SKILLCLAW_STORAGE_BUCKET" ] ||
        [ -z "$SKILLCLAW_STORAGE_REGION" ] ||
        [ -z "$SKILLCLAW_STORAGE_ACCESS_KEY" ] ||
        [ -z "$SKILLCLAW_STORAGE_SECRET_KEY" ]; then
        echo "skillclaw: $shared_env must define the S3 endpoint, bucket, region, access key, and secret key." >&2
        exit 1
      fi

      host=$(/bin/hostname -s 2>/dev/null || /bin/hostname)
      umask 077
      mkdir -p "$(dirname "$config_file")" ${lib.escapeShellArg skillsDir}
      tmp="$config_file.tmp.$$"

      jq -n \
        --arg llmProvider "$SKILLCLAW_LLM_PROVIDER" \
        --arg llmBase "$SKILLCLAW_LLM_API_BASE" \
        --arg llmKey "$SKILLCLAW_LLM_API_KEY" \
        --arg llmModel "$SKILLCLAW_LLM_MODEL_ID" \
        --arg llmMode "$SKILLCLAW_LLM_API_MODE" \
        --arg endpoint "$SKILLCLAW_STORAGE_ENDPOINT" \
        --arg bucket "$SKILLCLAW_STORAGE_BUCKET" \
        --arg region "$SKILLCLAW_STORAGE_REGION" \
        --arg accessKey "$SKILLCLAW_STORAGE_ACCESS_KEY" \
        --arg secretKey "$SKILLCLAW_STORAGE_SECRET_KEY" \
        --arg groupId ${lib.escapeShellArg cfg.groupId} \
        --arg alias "${config.home.username}@$host" \
        --arg skillsDir ${lib.escapeShellArg skillsDir} \
        --arg recordsDir ${lib.escapeShellArg "${config.home.homeDirectory}/.skillclaw/records"} \
        --argjson proxyPort ${toString cfg.proxyPort} \
        '{
          claw_type: "none",
          configure_openclaw: false,
          llm: {
            provider: $llmProvider,
            api_base: $llmBase,
            api_key: $llmKey,
            model_id: $llmModel,
            api_mode: $llmMode
          },
          proxy: {
            host: "127.0.0.1",
            port: $proxyPort,
            api_key: "",
            served_model_name: "skillclaw-model"
          },
          skills: {
            enabled: true,
            dir: $skillsDir,
            retrieval_mode: "template",
            top_k: 6
          },
          record: {
            enabled: true,
            dir: $recordsDir
          },
          prm: {
            enabled: false
          },
          sharing: {
            enabled: true,
            backend: "s3",
            endpoint: $endpoint,
            bucket: $bucket,
            access_key_id: $accessKey,
            secret_access_key: $secretKey,
            region: $region,
            group_id: $groupId,
            user_alias: $alias,
            auto_pull_on_start: false,
            session_upload_interval: 60,
            skill_reload_mode: "off",
            skill_reload_interval_seconds: 30
          },
          validation: {
            enabled: false
          },
          dashboard: {
            enabled: false
          }
        }' > "$tmp"
      mv -f "$tmp" "$config_file"
    '';
  };

  sync = pkgs.writeShellApplication {
    name = "skillclaw-sync";
    runtimeInputs = [ skillclaw ];
    text = ''
      ${lib.getExe configure}
      export SKILLCLAW_SYNC_SKIP_PULL=${lib.escapeShellArg (lib.concatStringsSep "," cfg.syncSkipPullNames)}
      exec skillclaw skills sync
    '';
  };

  proxy = pkgs.writeShellApplication {
    name = "skillclaw-proxy";
    runtimeInputs = [ skillclaw ];
    text = ''
      llm_env=${lib.escapeShellArg llmEnv}
      if [ ! -r "$llm_env" ]; then
        echo "skillclaw: missing $llm_env; proxy will retry after credentials are installed." >&2
        exit 1
      fi

      SKILLCLAW_LLM_API_BASE=""
      SKILLCLAW_LLM_API_KEY=""
      SKILLCLAW_LLM_MODEL_ID=""
      # shellcheck disable=SC1090
      . "$llm_env"
      if [ -z "$SKILLCLAW_LLM_API_BASE" ] || [ -z "$SKILLCLAW_LLM_API_KEY" ] || [ -z "$SKILLCLAW_LLM_MODEL_ID" ]; then
        echo "skillclaw: $llm_env must define API base, API key, and model ID." >&2
        exit 1
      fi

      ${lib.getExe configure}
      exec skillclaw start
    '';
  };

  evolve = pkgs.writeShellApplication {
    name = "skillclaw-evolve";
    runtimeInputs = [ skillclaw ];
    text = ''
      shared_env=${lib.escapeShellArg sharedEnv}
      llm_env=${lib.escapeShellArg llmEnv}
      if [ ! -r "$shared_env" ] || [ ! -r "$llm_env" ]; then
        echo "skillclaw-evolve: shared.env and llm.env are both required." >&2
        exit 1
      fi

      # shellcheck disable=SC1090
      . "$shared_env"
      # shellcheck disable=SC1090
      . "$llm_env"
      : "''${SKILLCLAW_STORAGE_ENDPOINT:?SKILLCLAW_STORAGE_ENDPOINT is missing}"
      : "''${SKILLCLAW_STORAGE_BUCKET:?SKILLCLAW_STORAGE_BUCKET is missing}"
      : "''${SKILLCLAW_STORAGE_REGION:?SKILLCLAW_STORAGE_REGION is missing}"
      : "''${SKILLCLAW_STORAGE_ACCESS_KEY:?SKILLCLAW_STORAGE_ACCESS_KEY is missing}"
      : "''${SKILLCLAW_STORAGE_SECRET_KEY:?SKILLCLAW_STORAGE_SECRET_KEY is missing}"
      : "''${SKILLCLAW_LLM_API_BASE:?SKILLCLAW_LLM_API_BASE is missing}"
      : "''${SKILLCLAW_LLM_API_KEY:?SKILLCLAW_LLM_API_KEY is missing}"
      : "''${SKILLCLAW_LLM_MODEL_ID:?SKILLCLAW_LLM_MODEL_ID is missing}"

      export EVOLVE_ENGINE=workflow
      export EVOLVE_STORAGE_BACKEND=s3
      export EVOLVE_STORAGE_ENDPOINT="$SKILLCLAW_STORAGE_ENDPOINT"
      export EVOLVE_STORAGE_BUCKET="$SKILLCLAW_STORAGE_BUCKET"
      export EVOLVE_STORAGE_ACCESS_KEY_ID="$SKILLCLAW_STORAGE_ACCESS_KEY"
      export EVOLVE_STORAGE_SECRET_ACCESS_KEY="$SKILLCLAW_STORAGE_SECRET_KEY"
      export EVOLVE_STORAGE_REGION="$SKILLCLAW_STORAGE_REGION"
      export EVOLVE_GROUP_ID=${lib.escapeShellArg cfg.groupId}
      export OPENAI_BASE_URL="$SKILLCLAW_LLM_API_BASE"
      export OPENAI_API_KEY="$SKILLCLAW_LLM_API_KEY"
      export EVOLVE_MODEL="''${SKILLCLAW_EVOLVE_MODEL:-$SKILLCLAW_LLM_MODEL_ID}"
      export EVOLVE_INTERVAL=${toString cfg.evolve.interval}
      export EVOLVE_HISTORY_LOG=${lib.escapeShellArg "${config.xdg.stateHome}/skillclaw/evolve-history.jsonl"}
      export EVOLVE_PROCESSED_LOG=${lib.escapeShellArg "${config.xdg.stateHome}/skillclaw/evolve-processed.json"}
      mkdir -p ${lib.escapeShellArg "${config.xdg.stateHome}/skillclaw"}

      exec ${skillclaw}/bin/skillclaw-evolve-server
    '';
  };
in
{
  options.local.skillclaw = {
    enable = lib.mkEnableOption "SkillClaw client installation and shared skill synchronization";

    groupId = lib.mkOption {
      type = lib.types.str;
      default = "omp";
      description = "SkillClaw shared group namespace.";
    };

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 30000;
      description = "Loopback-only local SkillClaw proxy port.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Seconds between bidirectional shared-skill syncs.";
    };

    syncSkipPullNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Local skill names preserved during the pull half of bidirectional synchronization.";
    };

    evolve = {
      enable = lib.mkEnableOption "the single SkillClaw evolve worker using the external S3 backend";

      interval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Seconds between SkillClaw evolve cycles.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          skillclaw
          configure
          sync
        ];

        home.activation.skillclawCredentialNotice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ ! -r ${lib.escapeShellArg sharedEnv} ]; then
            echo "  SkillClaw is installed but shared sync is waiting for external S3 settings in ${sharedEnv}." >&2
          fi
        '';
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.skillclaw-proxy = {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe proxy) ];
            RunAtLoad = true;
            KeepAlive.SuccessfulExit = false;
            ThrottleInterval = cfg.syncInterval;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-proxy.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-proxy.log";
          };
        };

        launchd.agents.skillclaw-sync = {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe sync) ];
            RunAtLoad = true;
            StartInterval = cfg.syncInterval;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-sync.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-sync.log";
          };
        };
      })

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        systemd.user.services.skillclaw-proxy = {
          Unit.Description = "SkillClaw local proxy";
          Service = {
            ExecStart = lib.getExe proxy;
            Restart = "on-failure";
            RestartSec = cfg.syncInterval;
          };
          Install.WantedBy = [ "default.target" ];
        };

        systemd.user.services.skillclaw-sync = {
          Unit.Description = "Synchronize shared SkillClaw skills";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe sync;
          };
        };

        systemd.user.timers.skillclaw-sync = {
          Unit.Description = "Periodically synchronize shared SkillClaw skills";
          Timer = {
            OnBootSec = "2m";
            OnUnitActiveSec = "${toString cfg.syncInterval}s";
            RandomizedDelaySec = "60s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      })

      (lib.mkIf cfg.evolve.enable {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isDarwin;
            message = "local.skillclaw.evolve.enable currently targets the server Mac.";
          }
        ];

        home.packages = [ evolve ];

        launchd.agents.skillclaw-evolve = {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe evolve) ];
            RunAtLoad = true;
            KeepAlive.SuccessfulExit = false;
            ThrottleInterval = cfg.syncInterval;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-evolve.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/skillclaw-evolve.log";
          };
        };
      })
    ]
  );
}
