# Write a launchd script that Apple's /bin/bash interprets, so macOS privacy
# grants attach to the signed application it starts rather than to Nix bash.
#
# TCC charges an access to the responsible process. For a launchd job that is
# the first non-platform executable in the chain launchd started: platform
# binaries such as /bin/sh and /bin/bash pass responsibility on instead of
# keeping it. The server logged exactly that when /bin/bash ran a Nix-bash
# script as a child: every RustDesk and Orca request named the Nix bash store
# path as responsible, never /bin/bash, and the Screen Recording grant vanished
# with the next bash bump.
#
# So nothing non-platform may sit between launchd and the application. The
# script runs under /bin/bash (3.2, so it must avoid newer syntax) and starts
# the Developer ID signed application directly; that application is then the
# responsible process, and a grant to it survives Nix and application updates.
# Non-platform helpers the script runs as siblings do not matter.
{ writeTextFile }:
{
  writeLaunchdScript =
    name: text:
    writeTextFile {
      inherit name;
      executable = true;
      text = ''
        #!/bin/bash
        ${text}
      '';
      checkPhase = ''
        /bin/bash -n "$target"
      '';
    };
}
