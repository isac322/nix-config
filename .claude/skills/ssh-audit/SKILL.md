---
name: ssh-audit
description: Re-check this repo's sshd hardening against what ssh-audit recommends today, and audit the running daemons. Use when asked to review, refresh, or verify SSH server configuration, sshd hardening, ssh-audit compliance, or after an OpenSSH version bump.
---

# ssh-audit

[ssh-audit](https://github.com/jtesta/ssh-audit) publishes a hardening
recommendation that moves — most recently when post-quantum key exchange
replaced every classical one. This repo carries a copy of that recommendation in
`lib/ssh-audit.nix`, applied to all three hosts. A copy goes stale, so this is
how it is re-derived and re-checked.

Two separate questions, and both are worth asking:

1. **Does our profile still match the recommendation?** Offline, cheap, no
   machine has to be reachable. `check-drift.py`.
2. **Does the running daemon actually behave that way?** Only a live scan
   answers this — a config that evaluates is not a daemon that reloaded.

## 1. Drift

```sh
python3 .claude/skills/ssh-audit/check-drift.py
```

It pulls the current guide out of ssh-audit itself (`--get-hardening-guide`,
whose payload is literal sshd_config text), renders `lib/ssh-audit.nix` into the
same form, and diffs. Exit 0 means agreement, 1 means drift, 2 means it could
not tell. `--guide "<name>"` picks a different one;
`nix run nixpkgs#ssh-audit -- --list-hardening-guides` lists them.

The default is the newest server guide for the OpenSSH 10.x line. Every modern
guide emits identical directives — the OS-specific part is the surrounding shell
(where the file lands, how the service restarts), and neither of our platforms
uses that. If a newer OS appears in the list, switch the default and say so in
the commit.

**Drift is a decision, not a task.** Before adopting a new directive:

- Check both sshd builds accept it. `GSSAPIKexAlgorithms` is in every guide and
  is a Debian patch — Apple's sshd and nixpkgs' both refuse to start on it.
  ```sh
  printf 'HostKey /etc/ssh/ssh_host_ed25519_key\n<DIRECTIVE>\n' > /tmp/t.conf
  /usr/sbin/sshd -t -f /tmp/t.conf                                  # Apple's
  nix shell nixpkgs#openssh -c sshd -t -f /tmp/t.conf               # nixpkgs'
  ```
- If one rejects it, record **why** in `lib/ssh-audit.nix` next to the existing
  `NOT_UPSTREAM` note and add it to that set in `check-drift.py`. A directive
  dropped without a reason comes back as drift every time this is run.
- If a change narrows what is accepted, think about who is locked out. The kex
  list is exclusively post-quantum; an old client fails the handshake outright
  rather than negotiating down.

Change `lib/ssh-audit.nix` only. Both platforms read it — `modules/darwin.nix`
renders it into `/etc/ssh/sshd_config.d/010-ssh-audit-hardening.conf`, and
`modules/nixos.nix` feeds it to `services.openssh.settings`.

## 2. Live scan

Needs the daemon reachable. From any machine:

```sh
# Server Mac (OpenSSH 10.3p1), NixOS server (10.4p1)
nix run nixpkgs#ssh-audit -- -P "Hardened OpenSSH Server v10.3 (version 1)" bhyoo-macbook-pro
nix run nixpkgs#ssh-audit -- -P "Hardened OpenSSH Server v10.4 (version 1)" <nixos-host>
```

The policy name has to match the target's OpenSSH version, or the report is
against the wrong baseline. Check what is actually running first — a plain
`nix run nixpkgs#ssh-audit -- <host>` prints the banner along with the graded
algorithm list, and `nix run nixpkgs#ssh-audit -- -L` lists the policy names.

The laptop leaves `services.openssh.enable` at null, so it usually has no
daemon to scan. That is deliberate (ADR 0026), not an omission — but the crypto
profile applies to it anyway, so if Remote Login is on it should pass the same
policy.

One expected failure mode: the RSA **host key size**. A machine that generated
its key before this profile keeps 3072 bits; the policy wants 4096, and a switch
will not replace an existing host key. Activation on the Macs says so when it
finds one. See `docs/operations.md`.

## Verifying a change without deploying it

`sshd -T` resolves a full config the way the daemon would, which is the only
reliable way to check the macOS include ordering. Apple's `100-macos.conf` pulls
in `/etc/ssh/crypto.conf`, sshd keeps the **first** value per keyword, and the
glob expands lexically — so a fragment named `100-nix-darwin.conf` loses on
exactly the directives that matter, silently, while looking correct on disk.
That is why ours is `010-`.

```sh
# macOS: render every fragment, drop them in a directory, resolve
nix eval --raw '.#darwinConfigurations.bhyoo-macbook-pro.config.environment.etc."ssh/sshd_config.d/010-ssh-audit-hardening.conf".text'
/usr/sbin/sshd -T -f <main.conf including all fragments> | grep -E '^(kex|ciphers|macs)'

# NixOS: cannot be realised from a Mac (aarch64-linux), so read the settings
nix eval --json '.#nixosConfigurations.server.config.services.openssh.settings'
```

## When to run this

After an ssh-audit release, after an OpenSSH bump on either platform, or when
touching sshd config for any reason. Quarterly is enough otherwise — the
recommendation changes on the order of once a year, and the last change (Debian
12 → 13) was the post-quantum cutover.

## What this does not cover

`ssh-audit` also grades **clients** (`-c`), and this repo does not configure an
`ssh_config` at all. Worth doing, not done — do not silently extend
`lib/ssh-audit.nix` with client directives without deciding where they go.
