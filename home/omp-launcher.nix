# The `omp` on PATH: starts the real binary, with memory turned off when
# another OMP agent is the one starting it.
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
# "an OMP agent started this". Such runs get a one-process settings overlay
# that turns memory off; an `omp` started from a terminal or an app is
# unchanged. A nested run that really needs memory sets OMP_NESTED_MEMORY=1.
#
# The script runs under /bin/sh and execs the binary, so on macOS no
# non-platform executable sits in front of omp and TCC still charges omp's own
# grant (see tcc-responsible.nix).
{ writeText, writeTextFile }:
target:
let
  noMemory = writeText "omp-nested-no-memory.yml" ''
    memory:
      backend: "off"
  '';
in
writeTextFile {
  name = "omp-launcher";
  destination = "/bin/omp";
  executable = true;
  text = ''
    #!/bin/sh
    if [ -n "''${PI_SESSION_FILE+set}" ] && [ "''${OMP_NESTED_MEMORY:-}" != 1 ]; then
      exec "${target}" --config ${noMemory} "$@"
    fi
    exec "${target}" "$@"
  '';
  checkPhase = ''
    /bin/sh -n "$target"
  '';
  meta.mainProgram = "omp";
}
