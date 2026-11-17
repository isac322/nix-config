# The `omp` on PATH: starts the real binary, with memory turned off when
# another coding agent (OMP or agy) is the one starting it.
#
# Agents launch `omp` themselves to reproduce bugs and run prompt experiments,
# usually from a scratch directory and often resuming a copied session. With
# Hindsight memory on, each of those runs created a bank for its scratch
# directory, and every resumed copy was retained again under a new session id.
# On 2026-10-31 that re-sent one 330 KB session 17 times, and by then 1,390 of
# the 1,428 banks were empty experiment leftovers; together they filled the
# Hindsight PostgreSQL volume.
#
# OMP hands PI_SESSION_FILE to every command its bash tool and eval kernels
# run, and never sets it in its own process environment, so its presence means
# "an OMP agent started this". agy marks the commands it runs the same way
# with ANTIGRAVITY_AGENT=1, and both agents write the same Hindsight bank.
# Such runs get a one-process settings overlay that turns memory off; an `omp`
# started from a terminal or an app is unchanged. A nested run that really
# needs memory sets OMP_NESTED_MEMORY=1.
#
# The script runs under /bin/sh and execs the binary, so on macOS no
# non-platform executable sits in front of omp and TCC still charges omp's own
# grant (see tcc-responsible.nix).
{
  writeText,
  writeTextFile,
  isDarwin,
  sops,
}:
target:
let
  noMemory = writeText "omp-nested-no-memory.yml" ''
    memory:
      backend: "off"
  '';
  tokenCommand =
    if isDarwin then
      ''/usr/bin/security find-generic-password -s "hindsight-api.bhyoo.com" -a "$USER" -w''
    else
      ''${sops} --decrypt --extract '["apiToken"]' "$HOME/.config/hindsight/token.sops.yaml"'';
in
writeTextFile {
  name = "omp-launcher";
  destination = "/bin/omp";
  executable = true;
  text = ''
    #!/bin/sh
    if { [ -n "''${PI_SESSION_FILE+set}" ] || [ "''${ANTIGRAVITY_AGENT:-}" = 1 ]; } \
      && [ "''${OMP_NESTED_MEMORY:-}" != 1 ]; then
      exec "${target}" --config ${noMemory} "$@"
    fi
    # OMP supports a token environment variable, not a credential command.
    # Read it at launch so it never enters config.yml or the Nix store.
    if [ -z "''${HINDSIGHT_API_TOKEN:-}" ]; then
      if ! HINDSIGHT_API_TOKEN=$(${tokenCommand}) || [ -z "$HINDSIGHT_API_TOKEN" ]; then
        echo "omp: Hindsight token is missing or inaccessible; provision this machine's credential before starting memory-enabled OMP." >&2
        exit 1
      fi
      export HINDSIGHT_API_TOKEN
    fi
    exec "${target}" "$@"
  '';
  checkPhase = ''
    /bin/sh -n "$target"
  '';
  meta.mainProgram = "omp";
}
