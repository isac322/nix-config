# Agent Skills whose upstream revisions are pinned by flake.lock.
#
# The activation copies the selected skill directory, rather than linking it
# into the Nix store. This matches `skills add --global --agent amp --copy` and
# leaves SkillClaw able to read and synchronize the standard
# ~/.agents/skills tree. A later switch restores these Nix-owned names exactly
# from the pinned sources, including removing files that appeared locally.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  skillsDir = "${config.home.homeDirectory}/.agents/skills";

  # These skills are owned by a repository's .agents/skills tree. Keep stale
  # user-global copies and SkillClaw pulls from shadowing the project source.
  projectOnlySkillNames = [ "instruction-architect" ];

  localSkillsDir = ./skills;
  localSkillSources = lib.mapAttrs (name: _: localSkillsDir + "/${name}") (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );

  # External skills are pinned by flake.lock. Every direct child of
  # home/skills is repository-owned and joins the same deployment automatically.
  externalSkillSources = {
    comment-writer = "${inputs.gentle-ai}/skills/comment-writer";
    humanizer = inputs.humanizer;
    writing-clearly-and-concisely = "${inputs.agent-toolkit}/skills/writing-clearly-and-concisely";
  };
  skillNameCollisions = lib.intersectLists (builtins.attrNames externalSkillSources) (
    builtins.attrNames localSkillSources
  );
  skillSources = externalSkillSources // localSkillSources;
  projectOnlySkillCollisions = lib.intersectLists projectOnlySkillNames (
    builtins.attrNames skillSources
  );

  installSkill =
    name: source:
    let
      target = "${skillsDir}/${name}";
    in
    ''
      target=${lib.escapeShellArg target}
      if [ -L "$target" ] || { [ -e "$target" ] && [ ! -d "$target" ]; }; then
        ${pkgs.coreutils}/bin/rm -f "$target"
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$target"
      ${lib.getExe pkgs.rsync} --archive --copy-links --delete ${lib.escapeShellArg "${source}/"} "$target/"
      ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX,go-w "$target"
    '';
  removeGlobalSkill =
    name:
    let
      target = "${skillsDir}/${name}";
    in
    ''
      target=${lib.escapeShellArg target}
      if [ -L "$target" ] || [ -e "$target" ]; then
        ${pkgs.coreutils}/bin/rm -rf "$target"
      fi
    '';

in
{
  assertions = [
    {
      assertion = skillNameCollisions == [ ];
      message = "Repository-owned agent skills collide with pinned external skills: ${lib.concatStringsSep ", " skillNameCollisions}";
    }
    {
      assertion = projectOnlySkillCollisions == [ ];
      message = "Project-only agent skills must not be deployed globally: ${lib.concatStringsSep ", " projectOnlySkillCollisions}";
    }
  ]
  ++ lib.mapAttrsToList (name: source: {
    assertion = builtins.pathExists "${source}/SKILL.md";
    message = "Agent skill '${name}' does not contain SKILL.md";
  }) skillSources;

  # Protect pinned global skills from replacement and prevent project-only
  # names from being pulled into the user-global skill tree.
  local.skillclaw.syncSkipPullNames = builtins.attrNames skillSources ++ projectOnlySkillNames;
  home.sessionVariables.SKILLCLAW_SYNC_SKIP_PULL = lib.concatStringsSep "," (
    builtins.attrNames skillSources ++ projectOnlySkillNames
  );

  home.activation.installNixManagedAgentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg skillsDir}
    ${lib.concatMapStringsSep "\n" removeGlobalSkill projectOnlySkillNames}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList installSkill skillSources)}
  '';
}
