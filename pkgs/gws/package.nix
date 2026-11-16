# gws (Google Workspace CLI) on macOS, reading its key through /usr/bin/security.
#
# gws keeps the AES key for ~/.config/gws/credentials.enc in the login keychain
# and, by default, reads it itself through Security.framework. nixpkgs builds
# gws ad hoc signed, so every rebuild gives it a new cdhash, macOS no longer
# recognizes it as the program the keychain item trusts, and the next read
# draws an allow/deny dialog (docs/decisions/0033).
#
# This wrapper keeps the key in the keychain but makes Apple-signed
# /usr/bin/security the only program that reads it; that signature never
# changes. gws itself runs with its file backend, whose key file is a symlink
# to /dev/fd/3, and the wrapper feeds the key into fd 3 through a mode-0600
# FIFO. The key never reaches the disk or an argument list, and gws never
# talks to the keychain.
#
# gws deletes credentials.enc when it cannot decrypt it (auth.rs), so every
# check that can fail runs before gws starts.
{
  lib,
  gws,
  writeShellApplication,
  runCommandCC,
  coreutils,
}:

let
  # Reports whether the login keychain is unlocked without ever prompting.
  # Reading an item from a locked keychain draws an unlock dialog, and so does
  # `security show-keychain-info`; SecKeychainGetStatus does not.
  keychainUnlocked = runCommandCC "keychain-unlocked" { } ''
    mkdir -p $out/bin
    cat > main.c <<'EOF'
    #include <Security/Security.h>
    #include <stdio.h>

    int main(int argc, char **argv) {
      SecKeychainRef keychain = NULL;
      SecKeychainStatus status = 0;
      if (argc != 2) {
        fprintf(stderr, "usage: keychain-unlocked KEYCHAIN\n");
        return 2;
      }
      if (SecKeychainOpen(argv[1], &keychain) != errSecSuccess) return 2;
      OSStatus rc = SecKeychainGetStatus(keychain, &status);
      CFRelease(keychain);
      if (rc != errSecSuccess) return 2;
      return (status & kSecUnlockStateStatus) ? 0 : 1;
    }
    EOF
    $CC -Wno-deprecated-declarations -framework Security -framework CoreFoundation \
      -o $out/bin/keychain-unlocked main.c
  '';
in
writeShellApplication {
  name = "gws";
  runtimeInputs = [ coreutils ];

  text = ''
    [[ -n ''${HOME:-} ]] || {
      echo "gws: HOME is not set" >&2
      exit 1
    }
    security=/usr/bin/security
    service=gws-cli
    account=$(/usr/bin/id -un)
    keychain="$HOME/Library/Keychains/login.keychain-db"

    die() {
      echo "gws: $*" >&2
      exit 1
    }

    quote() {
      local s=''${1//\\/\\\\}
      printf '"%s"' "''${s//\"/\\\"}"
    }

    # Logout only removes credential and token files and never reads the key,
    # so it goes straight to gws: it must work when the keychain item is
    # missing or locked and when the checks below would refuse the directory.
    if [[ ''${1:-} == auth && ''${2:-} == logout ]]; then
      exec ${lib.getExe gws} "$@"
    fi

    # The same directory gws would pick (auth_commands.rs config_dir): the
    # variable when set, else ~/.config/gws if it exists, else the legacy
    # macOS directory if that exists, else ~/.config/gws. An explicitly empty
    # variable would make gws use the working directory; refuse it.
    if [[ -v GOOGLE_WORKSPACE_CLI_CONFIG_DIR ]]; then
      cfg=$GOOGLE_WORKSPACE_CLI_CONFIG_DIR
      [[ -n $cfg ]] || die "GOOGLE_WORKSPACE_CLI_CONFIG_DIR is set but empty"
    elif [[ ! -e $HOME/.config/gws && -e "$HOME/Library/Application Support/gws" ]]; then
      cfg="$HOME/Library/Application Support/gws"
    else
      cfg="$HOME/.config/gws"
    fi
    # The key FIFO is created in this directory, and gws reads and writes
    # credentials here, so it must be this user's and closed to everyone else.
    # A directory that already exists is checked, never re-permissioned.
    if [[ ! -e $cfg ]]; then
      mkdir -p "$(dirname "$cfg")"
      mkdir -m 700 "$cfg"
    fi
    # Check and use the resolved path, so no symlink, `.` or `..` component
    # can point later operations somewhere other than what was checked.
    cfg=$(realpath -e -- "$cfg") || die "cannot resolve the gws config directory"
    [[ -d $cfg && -O $cfg ]] ||
      die "$cfg must be a directory owned by $account"
    (( (8#$(stat -c %a "$cfg") & 8#077) == 0 )) ||
      die "$cfg must not be accessible to group or others (chmod 700 it)"
    # Nobody else may be able to rename the directory or one of its parents
    # out from under the checked path: every ancestor must belong to this
    # user or root, and one that others can write needs the sticky bit and a
    # root owner (as /private/tmp has).
    uid=$(id -u)
    dir=$cfg
    while [[ $dir != / ]]; do
      dir=$(dirname "$dir")
      read -r owner mode < <(stat -c '%u %a' "$dir")
      [[ $owner == "$uid" || $owner == 0 ]] ||
        die "$dir, a parent of $cfg, belongs to another user"
      if (( (8#$mode & 8#022) != 0 )); then
        (( owner == 0 && (8#$mode & 8#1000) != 0 )) ||
          die "$dir, a parent of $cfg, is writable by others"
      fi
    done
    export GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$cfg"
    export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file

    # gws in keyring mode unlinks this path after reading the keychain, and
    # gws in file mode generates a new key when it is missing, which would
    # orphan credentials.enc. Restore the link on every run; never replace a
    # regular key file, which may be the only copy of a key.
    link="$cfg/.encryption_key"
    if [[ -L $link ]]; then
      [[ $(readlink "$link") == /dev/fd/3 ]] || ln -sfn /dev/fd/3 "$link"
    elif [[ -e $link ]]; then
      die "$link is a regular file. Move its key into the keychain item '$service' or remove it before using gws."
    else
      ln -s /dev/fd/3 "$link"
    fi

    unlocked=0
    ${keychainUnlocked}/bin/keychain-unlocked "$keychain" || unlocked=$?
    case $unlocked in
      0) ;;
      1) die "the login keychain is locked; unlock it and retry" ;;
      *) die "could not read the state of $keychain" ;;
    esac

    status=0
    key=$("$security" find-generic-password -s "$service" -a "$account" -w "$keychain" 2>/dev/null) || status=$?
    case $status in
      0) ;;
      44)
        [[ ! -e $cfg/credentials.enc ]] ||
          die "keychain item '$service' is missing but $cfg/credentials.enc exists; restore the item or run 'gws auth logout' first"
        key=$(/usr/bin/openssl rand -base64 32)
        # Through `security -i` on stdin so the key never reaches argv. An
        # item created by /usr/bin/security trusts it, so later reads are
        # silent.
        printf 'add-generic-password -s %s -a %s -T /usr/bin/security -w %s %s\n' \
          "$(quote "$service")" "$(quote "$account")" "$(quote "$key")" "$(quote "$keychain")" |
          "$security" -i >/dev/null || die "could not create keychain item '$service'"
        ;;
      *) die "keychain lookup for '$service' failed (security exit $status)" ;;
    esac

    bytes=$(printf '%s' "$key" | base64 -d 2>/dev/null | wc -c) || bytes=0
    (( bytes == 32 )) || die "keychain item '$service' does not hold a base64 32-byte key"

    # A FIFO rather than a pipe: gws warns when its key file is readable by
    # group or others, and a pipe's mode cannot be changed on macOS.
    # Opening it read-write first means neither open blocks, so no
    # background writer is needed.
    fifo_dir=$(mktemp -d "$cfg/.key-fifo.XXXXXX")
    mkfifo -m 600 "$fifo_dir/key"
    exec 3<>"$fifo_dir/key"
    exec 4<"$fifo_dir/key"
    rm -rf "$fifo_dir"
    printf '%s' "$key" >&3
    unset key
    exec 3>&- 3<&4 4<&-

    exec ${lib.getExe gws} "$@"
  '';

  passthru.unwrapped = gws;
  meta = gws.meta // {
    mainProgram = "gws";
    platforms = lib.platforms.darwin;
  };
}
