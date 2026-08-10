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
  ];

  trustedPublicKeys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
}
