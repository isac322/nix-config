# Reviewed skills and generated on-demand policy skills are copied into each
# harness's native personal skill tree. Per-target registries remove stale
# Nix-owned names without touching mutable user skills.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  sharedSkillsDir = "${homeDir}/.agents/skills";
  claudeSkillsDir = "${homeDir}/.claude/skills";
  managedStateDir = "${config.xdg.stateHome}/nix-managed-agent";
  segments = import ./agent-instruction-segments.nix;
  segmentList = lib.mapAttrsToList (name: value: value // { inherit name; }) segments;

  localSkillsDir = ./skills;
  localSkillSources = lib.mapAttrs (name: _: localSkillsDir + "/${name}") (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );
  externalSkillSources = {
    comment-writer = "${inputs.gentle-ai}/skills/comment-writer";
    humanizer = inputs.humanizer;
    writing-clearly-and-concisely = "${inputs.agent-toolkit}/skills/writing-clearly-and-concisely";
  };
  regularSkillSources = externalSkillSources // localSkillSources;

  policySkillSource =
    segment:
    pkgs.writeTextDir "SKILL.md" ''
      ---
      name: ${segment.name}
      description: ${builtins.toJSON segment.description}
      ---

      ${lib.removeSuffix "\n" (builtins.readFile segment.source)}
    '';
  policySkillSourcesFor =
    harness:
    builtins.listToAttrs (
      map
        (segment: {
          name = segment.name;
          value = policySkillSource segment;
        })
        (
          lib.filter (segment: segment.class == "onDemand" && lib.elem harness segment.harnesses) segmentList
        )
    );
  sharedPolicySkillSources = policySkillSourcesFor "codex";
  claudePolicySkillSources = policySkillSourcesFor "claude";
  sharedSkillSources = regularSkillSources // sharedPolicySkillSources;
  claudeSkillSources = regularSkillSources // claudePolicySkillSources;

  regularSkillNameCollisions = lib.intersectLists (builtins.attrNames externalSkillSources) (
    builtins.attrNames localSkillSources
  );
  sharedPolicyNameCollisions = lib.intersectLists (builtins.attrNames regularSkillSources) (
    builtins.attrNames sharedPolicySkillSources
  );
  claudePolicyNameCollisions = lib.intersectLists (builtins.attrNames regularSkillSources) (
    builtins.attrNames claudePolicySkillSources
  );

  installManagedSkills =
    targetDir: registryPath: registryName: trustLegacyRegistry: sources:
    let
      names = builtins.attrNames sources;
      registrySource = pkgs.writeText registryName (lib.concatMapStrings (name: "${name}\n") names);
      installSkill = name: source: ''
        target="$skillsTarget/${name}"
        if [ -L "$target" ] || [ -e "$target" ]; then
          ${pkgs.coreutils}/bin/rm -rf "$target"
        fi
        ${pkgs.coreutils}/bin/mkdir -p "$target"
        ${lib.getExe pkgs.rsync} --archive --copy-links --delete ${lib.escapeShellArg "${source}/"} "$target/"
        ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX,go-w "$target"
      '';
    in
    ''
      skillsTarget=${lib.escapeShellArg targetDir}
      skillsRegistry=${lib.escapeShellArg registryPath}
      if [ -L "$skillsTarget" ] || { [ -e "$skillsTarget" ] && [ ! -d "$skillsTarget" ]; }; then
        ${pkgs.coreutils}/bin/rm -f "$skillsTarget"
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$skillsTarget"
      legacySkillsRegistry="$skillsTarget/.nix-managed-skills"
      cleanupSkillsRegistry=
      if [ -r "$skillsRegistry" ]; then
        cleanupSkillsRegistry="$skillsRegistry"
      fi
      ${lib.optionalString trustLegacyRegistry ''
        if [ -z "$cleanupSkillsRegistry" ] && [ -f "$legacySkillsRegistry" ] && [ ! -L "$legacySkillsRegistry" ]; then
          cleanupSkillsRegistry="$legacySkillsRegistry"
        fi
      ''}
      if [ -n "$cleanupSkillsRegistry" ]; then
        while IFS= read -r managedName; do
          case "$managedName" in
            ""|.*|*/*) continue ;;
          esac
          ${pkgs.coreutils}/bin/rm -rf "$skillsTarget/$managedName"
        done < "$cleanupSkillsRegistry"
      fi
      if [ -L "$legacySkillsRegistry" ] || [ -f "$legacySkillsRegistry" ]; then
        ${pkgs.coreutils}/bin/rm -f "$legacySkillsRegistry"
      fi
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList installSkill sources)}
      ${pkgs.coreutils}/bin/install -m 0600 ${lib.escapeShellArg registrySource} "$skillsRegistry"
    '';
in
{
  assertions = [
    {
      assertion = regularSkillNameCollisions == [ ];
      message = "Repository-owned agent skills collide with pinned external skills: ${lib.concatStringsSep ", " regularSkillNameCollisions}";
    }
    {
      assertion = sharedPolicyNameCollisions == [ ];
      message = "Generated Codex policy skills collide with regular global skills: ${lib.concatStringsSep ", " sharedPolicyNameCollisions}";
    }
    {
      assertion = claudePolicyNameCollisions == [ ];
      message = "Generated Claude policy skills collide with regular global skills: ${lib.concatStringsSep ", " claudePolicyNameCollisions}";
    }
  ]
  ++ lib.mapAttrsToList (name: source: {
    assertion = builtins.pathExists "${source}/SKILL.md";
    message = "Agent skill '${name}' does not contain SKILL.md";
  }) regularSkillSources;

  # SkillClaw synchronizes only the shared ~/.agents/skills tree. Every
  # Nix-managed name there is protected from pull replacement but remains
  # eligible for push to the shared backend.
  local.skillclaw.syncSkipPullNames = builtins.attrNames sharedSkillSources;
  home.sessionVariables.SKILLCLAW_SYNC_SKIP_PULL = lib.concatStringsSep "," (
    builtins.attrNames sharedSkillSources
  );

  home.activation.installNixManagedAgentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    managedStateDir=${lib.escapeShellArg managedStateDir}
    ${pkgs.coreutils}/bin/install -d -m 0700 "$managedStateDir"
    ${installManagedSkills sharedSkillsDir "${managedStateDir}/shared-skills"
      "nix-managed-shared-skills"
      false
      sharedSkillSources
    }
    ${installManagedSkills claudeSkillsDir "${managedStateDir}/claude-skills"
      "nix-managed-claude-skills"
      true
      claudeSkillSources
    }
  '';
}
