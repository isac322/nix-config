# home-manager configuration for the Macs that run unattended.
#
# A server Mac runs the same shell, editor and CLI tools as any other — those
# are in home/common.nix and home/darwin.nix — and the only thing it does not
# want is the desktop applications, which it gets by not importing the laptop
# role. What lands here is tooling this machine alone has a use for.
{ lib, pkgs, ... }:

{
  # sshd on this machine takes keys and nothing else (modules/roles/
  # darwin-server.nix), which means a machine with no key installed is a locked
  # door with no handle — and the first switch is exactly when that is true.
  # Speak up then, and only then.
  #
  # The key is not declared in this repository, and not because a public key is
  # a secret; it is not. It is that this repository is public and there is one
  # key for every machine — the GPG authentication subkey is the SSH identity,
  # see home/darwin.nix — so committing it would publish, in one line, the name
  # of the credential that opens all of them. The private half is kept out for
  # the same reason and handled the same way: the switch says what to run, and a
  # person runs it.
  #
  # Which is also why nothing has to be carried here from another machine. The
  # agent on this one already holds the identity the others authenticate with,
  # so the machine authorizes itself out of its own agent.
  home.activation.sshAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -s "$HOME/.ssh/authorized_keys" ]; then
      echo "" >&2
      echo "  No ~/.ssh/authorized_keys. sshd is on and takes keys only, so" >&2
      echo "  nothing can log in to this machine yet." >&2
      echo "" >&2
      echo "  At this machine's own console, once the GPG key is in place:" >&2
      echo "" >&2
      echo "    mkdir -p ~/.ssh && chmod 700 ~/.ssh" >&2
      echo "    ssh-add -L >> ~/.ssh/authorized_keys" >&2
      echo "    chmod 600 ~/.ssh/authorized_keys" >&2
      echo "" >&2
      echo "  That is the same key the other machines use, so there is nothing" >&2
      echo "  to copy between them. If ssh-add -L prints nothing, the GPG key" >&2
      echo "  is what is missing — that step reports itself separately." >&2
      echo "" >&2
    fi
  '';

  # Rust straight from nixpkgs, not through rustup.
  #
  # rustup earns its place when a project pins a toolchain in
  # rust-toolchain.toml, or when several versions have to coexist and switch
  # per directory. Neither applies here — one current toolchain is the whole
  # requirement — and what it costs is the property this repository exists for:
  # rustup downloads its toolchains into ~/.rustup at run time, so the compiler
  # on this machine would be whatever it last fetched rather than what
  # flake.lock pins, and a rebuild from this flake would not reproduce it.
  # rust-overlay or fenix is the declarative answer if per-project pinning ever
  # does become the requirement; rustup is not.
  #
  # wasm needs no extra step. nixpkgs configures rustc with
  # `--target=wasm32-unknown-unknown,wasm32v1-none,…` next to the host target,
  # so the standard library for both is built into the package already and
  # `cargo build --target wasm32-unknown-unknown` works as it stands. There is
  # nothing here corresponding to `rustup target add`. What is genuinely
  # separate is the tooling that wraps the output — wasm-bindgen-cli,
  # wasm-pack, binaryen — and none of it is listed because nothing has asked
  # for it yet.
  #
  # Both packages are needed: rustc is the compiler alone, and cargo is a
  # separate derivation in nixpkgs rather than something it brings along.
  #
  # The two language servers are here rather than in home/darwin.nix because
  # this is the machine an editor or a coding agent actually runs on. Neither
  # is configured: an LSP client starts the binary and speaks to it over stdio,
  # so being on PATH under the name the client looks for is the whole
  # integration.
  #
  # `rust-analyzer`, not `rust-analyzer-unwrapped`. The plain attribute is a
  # wrapper whose only job is to set RUST_SRC_PATH to rustPlatform.rustLibSrc,
  # and without it the server runs perfectly well while knowing nothing about
  # the standard library — no completion or go-to-definition on anything from
  # std. That fails as missing features rather than as an error, which is the
  # kind of wrong that goes unnoticed.
  #
  # terraform-ls is HashiCorp's own and, unlike terraform itself, is still
  # MPL-2.0 — so it needs no allowUnfreePredicate entry. It shells out to
  # `terraform` for validation, and finds the one from home/darwin.nix.
  home.packages = [
    pkgs.cargo
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.terraform-ls
  ];
}
