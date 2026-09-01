# Canonical instruction segments are classified once, then compiled to each
# harness's strongest supported delivery surface. Harnesses without a native
# surface receive the same body through their session context or skill tree.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  segments = import ./agent-instruction-segments.nix;
  homeDir = config.home.homeDirectory;
  ompAgentDir = "${homeDir}/.omp/agent";
  managedStateDir = "${config.xdg.stateHome}/nix-managed-agent";
  validClasses = [
    "context"
    "persistent"
    "onDemand"
    "critical"
    "personality"
  ];
  validHarnesses = [
    "omp"
    "claude"
    "codex"
  ];
  classRank = {
    context = 10;
    persistent = 20;
    onDemand = 30;
    critical = 40;
    personality = 50;
  };
  segmentList = lib.mapAttrsToList (name: value: value // { inherit name; }) segments;
  sortedSegments = lib.sort (
    left: right:
    let
      leftRank = classRank.${left.class};
      rightRank = classRank.${right.class};
    in
    if leftRank != rightRank then
      leftRank < rightRank
    else if left.order != right.order then
      left.order < right.order
    else
      builtins.lessThan left.name right.name
  ) segmentList;
  selectSegments =
    harness: classes:
    lib.filter (
      segment: lib.elem harness segment.harnesses && lib.elem segment.class classes
    ) sortedSegments;
  compose =
    name: selected:
    pkgs.writeText name (
      lib.concatMapStringsSep "\n\n" (
        segment: lib.removeSuffix "\n" (builtins.readFile segment.source)
      ) selected
      + "\n"
    );
  renderOmpRule =
    segment:
    pkgs.writeText "omp-rule-${segment.name}.md" (
      ''
        ---
        description: ${builtins.toJSON segment.description}
      ''
      + lib.optionalString (segment.class == "critical") "alwaysApply: true\n"
      + ''
        ---

        ${lib.removeSuffix "\n" (builtins.readFile segment.source)}
      ''
    );
  ompRuleSegments = selectSegments "omp" [
    "onDemand"
    "critical"
  ];
  ompRuleSources = builtins.listToAttrs (
    map (segment: {
      name = "${segment.name}.md";
      value = renderOmpRule segment;
    }) ompRuleSegments
  );
  ompRuleNames = builtins.attrNames ompRuleSources;
  ompRulesRegistry = pkgs.writeText "nix-managed-omp-rules" (
    lib.concatMapStrings (name: "${name}\n") ompRuleNames
  );
  preRegistryOmpRulesRegistry = pkgs.writeText "nix-managed-pre-registry-omp-rules" (
    lib.concatMapStrings (name: "${name}\n") [
      "destructive-operations.md"
      "public-api.md"
      "pull-request-creation.md"
      "pull-request-merge.md"
      "pull-request-review-handling.md"
      "verification.md"
    ]
  );

  claudeRuleSegments = selectSegments "claude" [
    "persistent"
    "critical"
  ];
  claudeRuleFileName =
    segment:
    let
      priority = if segment.class == "persistent" then "10" else "20";
    in
    "${priority}-${toString segment.order}-${segment.name}.md";
  claudeRuleSources = builtins.listToAttrs (
    map (segment: {
      name = claudeRuleFileName segment;
      value = pkgs.writeText "claude-rule-${segment.name}.md" (builtins.readFile segment.source);
    }) claudeRuleSegments
  );
  claudeRuleNames = builtins.attrNames claudeRuleSources;
  claudeRulesRegistry = pkgs.writeText "nix-managed-claude-rules" (
    lib.concatMapStrings (name: "${name}\n") claudeRuleNames
  );

  policySkillNames = map (segment: segment.name) (
    lib.filter (segment: segment.class == "onDemand") sortedSegments
  );
  ompConfigBase = builtins.readFile ./files/omp-agent-config.yml;
  ompConfig = pkgs.writeText "omp-agent-config.yml" (
    lib.removeSuffix "\n" ompConfigBase
    + "\n"
    + ''
      skills:
        enableClaudeUser: false
        ignoredSkills:
    ''
    + lib.concatMapStrings (name: "    - ${builtins.toJSON name}\n") policySkillNames
  );

  deployedFiles = [
    {
      target = "${ompAgentDir}/AGENTS.md";
      source = compose "omp-AGENTS.md" (selectSegments "omp" [ "context" ]);
    }
    {
      target = "${homeDir}/.claude/CLAUDE.md";
      source = compose "claude-CLAUDE.md" (selectSegments "claude" [ "context" ]);
    }
    {
      target = "${homeDir}/.codex/AGENTS.md";
      source = compose "codex-AGENTS.md" (
        selectSegments "codex" [
          "context"
          "persistent"
          "critical"
        ]
      );
    }
    {
      target = "${ompAgentDir}/PERSONALITY.md";
      source = compose "omp-PERSONALITY.md" (selectSegments "omp" [ "personality" ]);
    }
    {
      target = "${ompAgentDir}/RULES.md";
      source = compose "omp-RULES.md" (selectSegments "omp" [ "persistent" ]);
    }
  ];
  installFile =
    {
      target,
      source,
    }:
    ''
      target=${lib.escapeShellArg target}
      if [ -L "$target" ] || [ -d "$target" ]; then
        ${pkgs.coreutils}/bin/rm -rf "$target"
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
      ${pkgs.coreutils}/bin/install -m 0644 ${lib.escapeShellArg source} "$target"
    '';
  installOmpRule = name: source: ''
    target="$rulesTarget/${name}"
    if [ -L "$target" ] || [ -e "$target" ]; then
      ${pkgs.coreutils}/bin/rm -rf "$target"
    fi
    ${pkgs.coreutils}/bin/install -m 0644 ${lib.escapeShellArg source} "$target"
  '';
  installClaudeRule = name: source: ''
    target="$claudeRulesTarget/${name}"
    if [ -L "$target" ] || [ -e "$target" ]; then
      ${pkgs.coreutils}/bin/rm -rf "$target"
    fi
    ${pkgs.coreutils}/bin/install -m 0644 ${lib.escapeShellArg source} "$target"
  '';

  segmentSources = map (segment: toString segment.source) segmentList;
  invalidSegments = lib.filter (
    segment:
    !lib.elem segment.class validClasses
    || segment.harnesses == [ ]
    || !lib.all (harness: lib.elem harness validHarnesses) segment.harnesses
    || !builtins.isInt segment.order
    || segment.order < 100
    || segment.order > 999
    || builtins.match "[a-z0-9][a-z0-9-]*" segment.name == null
    || !builtins.pathExists segment.source
    || lib.hasPrefix "---\n" (builtins.readFile segment.source)
    || (
      lib.elem segment.class [
        "onDemand"
        "critical"
      ]
      && (!(segment ? description) || segment.description == "" || lib.hasInfix "\n" segment.description)
    )
    || (segment.class == "personality" && segment.harnesses != [ "omp" ])
  ) segmentList;
in
{
  assertions = [
    {
      assertion = invalidSegments == [ ];
      message = "Invalid agent instruction segments: ${
        lib.concatStringsSep ", " (map (segment: segment.name) invalidSegments)
      }";
    }
    {
      assertion = builtins.length segmentSources == builtins.length (lib.unique segmentSources);
      message = "Agent instruction segments must not share a canonical body file.";
    }
    {
      assertion = !(lib.hasInfix "\nskills:" ompConfigBase || lib.hasPrefix "skills:" ompConfigBase);
      message = "OMP skill routing is generated by home/agent-instructions.nix; remove the static skills section from omp-agent-config.yml.";
    }
  ];

  home.file.".omp/agent/config.yml" = {
    source = ompConfig;
    force = true;
  };

  home.activation.installNixManagedAgentInstructions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${lib.concatMapStringsSep "\n" installFile deployedFiles}
    managedStateDir=${lib.escapeShellArg managedStateDir}
    ${pkgs.coreutils}/bin/install -d -m 0700 "$managedStateDir"

    rulesTarget=${lib.escapeShellArg "${ompAgentDir}/rules"}
    rulesRegistry="$managedStateDir/omp-rules"
    if [ -L "$rulesTarget" ] || { [ -e "$rulesTarget" ] && [ ! -d "$rulesTarget" ]; }; then
      ${pkgs.coreutils}/bin/rm -f "$rulesTarget"
    fi
    ${pkgs.coreutils}/bin/mkdir -p "$rulesTarget"
    legacyRulesRegistry="$rulesTarget/.nix-managed-rules"
    if [ -r "$rulesRegistry" ]; then
      cleanupRulesRegistry="$rulesRegistry"
    elif [ -f "$legacyRulesRegistry" ] && [ ! -L "$legacyRulesRegistry" ]; then
      cleanupRulesRegistry="$legacyRulesRegistry"
    else
      # Before registry support, rsync --delete owned these known rule names.
      cleanupRulesRegistry=${lib.escapeShellArg preRegistryOmpRulesRegistry}
    fi
    while IFS= read -r managedName; do
      case "$managedName" in
        ""|.*|*/*) continue ;;
      esac
      ${pkgs.coreutils}/bin/rm -rf "$rulesTarget/$managedName"
    done < "$cleanupRulesRegistry"
    if [ -L "$legacyRulesRegistry" ] || [ -f "$legacyRulesRegistry" ]; then
      ${pkgs.coreutils}/bin/rm -f "$legacyRulesRegistry"
    fi
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList installOmpRule ompRuleSources)}
    ${pkgs.coreutils}/bin/install -m 0600 ${lib.escapeShellArg ompRulesRegistry} "$rulesRegistry"
    ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX,go-w "$rulesTarget"

    claudeRulesTarget=${lib.escapeShellArg "${homeDir}/.claude/rules"}
    claudeRulesRegistry="$managedStateDir/claude-rules"
    if [ -L "$claudeRulesTarget" ] || { [ -e "$claudeRulesTarget" ] && [ ! -d "$claudeRulesTarget" ]; }; then
      ${pkgs.coreutils}/bin/rm -f "$claudeRulesTarget"
    fi
    ${pkgs.coreutils}/bin/mkdir -p "$claudeRulesTarget"
    legacyClaudeRulesRegistry="$claudeRulesTarget/.nix-managed-rules"
    cleanupClaudeRulesRegistry=
    if [ -r "$claudeRulesRegistry" ]; then
      cleanupClaudeRulesRegistry="$claudeRulesRegistry"
    elif [ -f "$legacyClaudeRulesRegistry" ] && [ ! -L "$legacyClaudeRulesRegistry" ]; then
      cleanupClaudeRulesRegistry="$legacyClaudeRulesRegistry"
    fi
    if [ -n "$cleanupClaudeRulesRegistry" ]; then
      while IFS= read -r managedName; do
        case "$managedName" in
          ""|.*|*/*) continue ;;
        esac
        ${pkgs.coreutils}/bin/rm -rf "$claudeRulesTarget/$managedName"
      done < "$cleanupClaudeRulesRegistry"
    fi
    if [ -L "$legacyClaudeRulesRegistry" ] || [ -f "$legacyClaudeRulesRegistry" ]; then
      ${pkgs.coreutils}/bin/rm -f "$legacyClaudeRulesRegistry"
    fi
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList installClaudeRule claudeRuleSources)}
    ${pkgs.coreutils}/bin/install -m 0600 ${lib.escapeShellArg claudeRulesRegistry} "$claudeRulesRegistry"
    ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX,go-w "$claudeRulesTarget"
  '';
}
