# Canonical personal instructions, composed per harness and installed as plain
# files at each harness's discovery path. Activation regenerates every target
# from this repository, so edits made to deployed files are overwritten.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  instructionDir = ./files/agent-instructions;
  homeDir = config.home.homeDirectory;
  ompAgentDir = "${homeDir}/.omp/agent";

  markdownFiles =
    dir:
    map (name: dir + "/${name}") (
      lib.filter (name: lib.hasSuffix ".md" name) (builtins.attrNames (builtins.readDir dir))
    );

  compose =
    name: paths:
    pkgs.writeText name (
      lib.concatMapStringsSep "\n\n" (path: lib.removeSuffix "\n" (builtins.readFile path)) paths + "\n"
    );

  commonAgents = markdownFiles (instructionDir + "/agents");
  harnessAgents = harness: commonAgents ++ [ (instructionDir + "/harness/${harness}.md") ];

  deployedFiles = [
    {
      target = "${ompAgentDir}/AGENTS.md";
      source = compose "omp-AGENTS.md" (harnessAgents "omp");
    }
    {
      target = "${homeDir}/.claude/CLAUDE.md";
      source = compose "claude-CLAUDE.md" (harnessAgents "claude");
    }
    {
      target = "${homeDir}/.codex/AGENTS.md";
      source = compose "codex-AGENTS.md" (harnessAgents "codex");
    }
    {
      target = "${ompAgentDir}/PERSONALITY.md";
      source = compose "omp-PERSONALITY.md" (markdownFiles (instructionDir + "/personality"));
    }
    {
      target = "${ompAgentDir}/RULES.md";
      source = compose "omp-RULES.md" (markdownFiles (instructionDir + "/sticky"));
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
in
{
  home.activation.installNixManagedAgentInstructions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${lib.concatMapStringsSep "\n" installFile deployedFiles}

    rulesTarget=${lib.escapeShellArg "${ompAgentDir}/rules"}
    if [ -L "$rulesTarget" ] || { [ -e "$rulesTarget" ] && [ ! -d "$rulesTarget" ]; }; then
      ${pkgs.coreutils}/bin/rm -f "$rulesTarget"
    fi
    ${pkgs.coreutils}/bin/mkdir -p "$rulesTarget"
    ${lib.getExe pkgs.rsync} --archive --copy-links --delete \
      ${lib.escapeShellArg "${instructionDir}/rules/"} "$rulesTarget/"
    ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX,go-w "$rulesTarget"
  '';
}
