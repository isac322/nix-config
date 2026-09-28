# Run a launchd job under Apple's /bin/bash so macOS privacy grants survive
# Nix updates.
#
# TCC charges every access to the job's responsible process: the one launchd
# started. For a Nix-built script that is Nix bash, whose ad-hoc signature is
# its content hash and whose store path changes on every bash bump, so each
# grant (Full Disk Access, Screen Recording, Accessibility) was tied to one
# build and its children kept prompting. /bin/bash is a platform binary with a
# fixed path and Apple signature, so one grant to it holds across updates.
#
# That only works while /bin/bash stays the process launchd started: `exec`
# would hand the pid, and with it the identity, to the Nix script. So it runs
# the script as a child and forwards the stop signals launchd and
# `launchctl kickstart -k` send. The child keeps its own interpreter; only this
# stub is written for bash 3.2.
{
  launchdProgramArguments = script: [
    "/bin/bash"
    "-c"
    ''
      child=
      forward() { [ -n "$child" ] && kill -"$1" "$child" 2>/dev/null; }
      trap 'forward TERM' TERM
      trap 'forward INT' INT
      trap 'forward HUP' HUP
      "$0" &
      child=$!
      while :; do
        wait "$child"
        status=$?
        kill -0 "$child" 2>/dev/null || break
      done
      exit "$status"
    ''
    "${script}"
  ];
}
