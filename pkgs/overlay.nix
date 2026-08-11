# Packages this configuration needs that nixpkgs does not have.
#
# They are added through an overlay rather than referenced as bare paths so
# that `pkgs.posthog-cli` works everywhere `pkgs` does — including inside
# home-manager modules, which never see this directory.
final: _prev: {
  posthog-cli = final.callPackage ./posthog-cli/package.nix { };
  axiom-cli = final.callPackage ./axiom-cli/package.nix { };

  # nixpkgs builds all four of Tempo's commands, three of which are the
  # server side of a trace store nothing here runs. Building only the CLI
  # takes the closure from 237 MiB to about 70 and keeps a binary called
  # `tempo` — which would read as the server — off PATH.
  tempo-cli = final.tempo.overrideAttrs (old: {
    pname = "tempo-cli";
    subPackages = [ "cmd/tempo-cli" ];
    meta = old.meta // {
      description = "Command line tool for Grafana Tempo";
      mainProgram = "tempo-cli";
    };
  });
}
