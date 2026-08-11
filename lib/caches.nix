# Extra binary caches, shared by every host.
#
# Kept as plain data rather than a module because the option path differs per
# platform: on macOS, Determinate Nix owns /etc/nix/nix.conf and these go into
# `determinateNix.customSettings`, while NixOS writes nix.conf itself and takes
# them through `nix.settings`. The values are the same either way.
{
  substituters = [
    # llm-agents prebuilt output. `omp` is a Rust + bun build that otherwise
    # pulls a 461 MiB toolchain and compiles from source.
    "https://cache.numtide.com"

    # Once a Cachix cache exists, its URL goes here and its public key below,
    # and every machine stops rebuilding the three packages in pkgs/ — no
    # public cache can have them, since two exist nowhere else and the third
    # is an override. Push with `nix run <flake>#cache-push -- <cache>`.
    # Deliberately left out rather than guessed: an entry whose key does not
    # match the cache is worse than no entry, because the substituter is then
    # contacted and its answers thrown away on every build.
    #   "https://<cache>.cachix.org"
  ];

  trustedPublicKeys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    #   "<cache>.cachix.org-1:<base64 key printed when the cache is created>"
  ];
}
