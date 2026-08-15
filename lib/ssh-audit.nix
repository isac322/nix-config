# The ssh-audit hardening profile, shared by every host that answers on 22.
#
# Kept as plain data rather than a module for the same reason as caches.nix: the
# option path differs per platform. NixOS has a freeform `services.openssh
# .settings` that takes these directly, while on macOS they have to be rendered
# into a file in /etc/ssh/sshd_config.d — and, as modules/darwin.nix explains, a
# file whose name sorts early enough to beat Apple's own. The values are the
# same either way.
#
# Source: ssh-audit 3.9.0's built-in policy "Hardened OpenSSH Server v10.3
# (version 1)", cross-checked against the Ubuntu 26.04 hardening guide, with one
# deliberate compatibility override for KexAlgorithms. Both machines run an
# OpenSSH in that range: macOS 26 ships 10.3p1 and nixpkgs is at 10.4p1.
#
# Following the guide by hand is the thing this file exists to avoid, and
# .claude/skills/ssh-audit/ is how it is re-derived when upstream moves.
#
# Two guide differences are deliberate:
#
#   `GSSAPIKexAlgorithms` is not an OpenSSH directive. GSSAPI key exchange is a
#   Debian/Ubuntu patch, so the line only parses on their builds — on ours it is
#   a "Bad configuration option" and sshd refuses to start, which on the headless
#   Mac means locking the door and posting the key inside. Verified on both:
#   Apple's 10.3p1 and nixpkgs' 10.4p1 reject it, and neither lists a `gss-*`
#   entry in `ssh -Q kex`.
#
#   Upstream's KexAlgorithms list is exclusively post-quantum and requires a
#   recent client. This profile deliberately keeps the compatibility list that
#   was already deployed: one hybrid post-quantum exchange, both Curve25519
#   spellings, and the SHA-512/SHA-256 finite-field fallbacks. Remote
#   availability from an older or borrowed client wins over matching that one
#   upstream line. Keep the list explicit: Apple's crypto.conf otherwise
#   prepends vendor defaults before it.
{
  # Rendered as-is on both platforms. The NixOS option is spelled `Macs` rather
  # than the directive's `MACs`; sshd_config keywords are case-insensitive, so
  # one spelling serves both and matching the option is what avoids emitting the
  # directive twice.
  sshdSettings = {
    KexAlgorithms = [
      "sntrup761x25519-sha512@openssh.com"
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
      "diffie-hellman-group16-sha512"
      "diffie-hellman-group18-sha512"
      "diffie-hellman-group-exchange-sha256"
    ];

    # Ordered by key size rather than by speed: the larger keys come first as a
    # hedge against Grover's algorithm halving the effective strength.
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes256-ctr"
      "aes192-ctr"
      "aes128-gcm@openssh.com"
      "aes128-ctr"
    ];

    # Encrypt-then-MAC only. The two GCM ciphers above carry their own
    # authentication and ignore this list entirely.
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
      "umac-128-etm@openssh.com"
    ];

    # ED25519 ahead of RSA — same security, far less work per handshake. The
    # `sk-` entries are FIDO2 hardware keys and the `-cert-` ones are
    # certificate-signed keys; neither is in use here, and both are listed
    # because the profile is about what is refused, not about what happens to
    # exist today.
    HostKeyAlgorithms = [
      "sk-ssh-ed25519-cert-v01@openssh.com"
      "ssh-ed25519-cert-v01@openssh.com"
      "rsa-sha2-512-cert-v01@openssh.com"
      "rsa-sha2-256-cert-v01@openssh.com"
      "sk-ssh-ed25519@openssh.com"
      "ssh-ed25519"
      "rsa-sha2-512"
      "rsa-sha2-256"
    ];

    # What a client may authenticate with, and what a certificate authority may
    # have signed with. Same list, minus the certificate forms in the CA case —
    # a CA key is not itself a certificate.
    PubkeyAcceptedAlgorithms = [
      "sk-ssh-ed25519-cert-v01@openssh.com"
      "ssh-ed25519-cert-v01@openssh.com"
      "rsa-sha2-512-cert-v01@openssh.com"
      "rsa-sha2-256-cert-v01@openssh.com"
      "sk-ssh-ed25519@openssh.com"
      "ssh-ed25519"
      "rsa-sha2-512"
      "rsa-sha2-256"
    ];

    HostbasedAcceptedAlgorithms = [
      "sk-ssh-ed25519-cert-v01@openssh.com"
      "ssh-ed25519-cert-v01@openssh.com"
      "rsa-sha2-512-cert-v01@openssh.com"
      "rsa-sha2-256-cert-v01@openssh.com"
      "sk-ssh-ed25519@openssh.com"
      "ssh-ed25519"
      "rsa-sha2-512"
      "rsa-sha2-256"
    ];

    CASignatureAlgorithms = [
      "sk-ssh-ed25519@openssh.com"
      "ssh-ed25519"
      "rsa-sha2-512"
      "rsa-sha2-256"
    ];

    # The floor for any RSA key in the exchange, host and client alike. Distinct
    # from the 4096 below, which is what we generate rather than what we accept.
    RequiredRSASize = 3072;
  };

  # Host keys, and only these two. ECDSA is dropped — it is not weak, but it is
  # NIST-curve and the profile has no place for it, and leaving it declared
  # means offering it. The key file left behind on a machine that already has
  # one is inert once it stops being named in a HostKey line.
  #
  # 4096 rather than the 3072 that `ssh-keygen -t rsa` defaults to: the policy
  # checks the size of the key actually presented, not just the negotiated
  # algorithm. A machine that generated its RSA host key before this profile
  # existed keeps the smaller one — activation says so when it finds one.
  hostKeys = {
    ed25519 = {
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    };
    rsa = {
      type = "rsa";
      bits = 4096;
      path = "/etc/ssh/ssh_host_rsa_key";
    };
  };
}
