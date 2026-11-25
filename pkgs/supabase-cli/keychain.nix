# supabase on macOS, reading its access token through /usr/bin/security.
#
# The CLI keeps its access token in the login keychain (service
# "Supabase CLI", account = profile name) and reads it itself through
# Security.framework (@napi-rs/keyring). The upstream release binary is ad hoc
# signed, so every release has a new cdhash, macOS no longer recognizes it as
# the program the keychain item trusts, and every read draws an allow/deny
# dialog while the command waits (docs/decisions/0033).
#
# This wrapper keeps the token in the keychain but makes Apple-signed
# /usr/bin/security the only program that touches it. supabase always runs
# with SUPABASE_NO_KEYRING=1 and receives the token as SUPABASE_ACCESS_TOKEN,
# the variable it reads before the keychain. `login` and `logout` write and
# delete the keychain item here, because without the keyring the CLI saves
# the token to <SUPABASE_HOME>/access-token and deletes only that file.
#
# The profile is resolved the way the CLI does (command-settings.layer.ts):
# last --profile, else SUPABASE_PROFILE, else <SUPABASE_HOME>/profile, else
# "supabase". Only built-in profiles name their keychain account directly; a
# YAML profile file's account is the `name` inside it, so for those the
# wrapper injects nothing and refuses login/logout.
{
  lib,
  supabase-cli,
  symlinkJoin,
  writeShellApplication,
  keychain-unlocked,
}:

let
  wrapper = writeShellApplication {
    name = "supabase";

    text = ''
      [[ -n ''${HOME:-} ]] || {
        echo "supabase: HOME is not set" >&2
        exit 1
      }
      security=/usr/bin/security
      service="Supabase CLI"
      keychain="$HOME/Library/Keychains/login.keychain-db"
      real=${lib.getExe supabase-cli}
      export SUPABASE_NO_KEYRING=1

      die() {
        echo "supabase: $*" >&2
        exit 1
      }

      quote() {
        local s=''${1//\\/\\\\}
        printf '"%s"' "''${s//\"/\\\"}"
      }

      trim() {
        local s=$1
        s=''${s#"''${s%%[![:space:]]*}"}
        printf '%s' "''${s%"''${s##*[![:space:]]}"}"
      }

      unlocked() {
        ${lib.getExe keychain-unlocked} "$keychain"
      }

      # Prints the item's secret; exit 44 when there is none.
      read_item() {
        "$security" find-generic-password -s "$service" -a "$1" -w "$keychain" 2>/dev/null
      }

      # Only global flags can come before a top-level command, so the first
      # word that is neither a flag nor a global flag's value is the command.
      profile_flag=
      command=
      expect=
      for arg in "$@"; do
        if [[ -n $expect ]]; then
          [[ $expect == profile ]] && profile_flag=$arg
          expect=
          continue
        fi
        case $arg in
          --) break ;;
          --profile=*) profile_flag=''${arg#--profile=} ;;
          --profile) expect=profile ;;
          --output | -o | --output-format | --workdir | --network-id | --dns-resolver | --agent | --log-level)
            [[ -z $command ]] && expect=value
            ;;
          -*) ;;
          *) [[ -n $command ]] || command=$arg ;;
        esac
      done

      supabase_home=$(trim "''${SUPABASE_HOME:-}")
      [[ -n $supabase_home ]] || supabase_home=$HOME/.supabase
      if [[ -n $profile_flag ]]; then
        profile=$profile_flag
      elif [[ -n ''${SUPABASE_PROFILE:-} ]]; then
        profile=$SUPABASE_PROFILE
      else
        profile=
        [[ -r $supabase_home/profile ]] && profile=$(trim "$(<"$supabase_home/profile")")
        [[ -n $profile ]] || profile=supabase
      fi
      case ''${profile,,} in
        supabase | supabase-staging | supabase-local | snap) account=''${profile,,} ;;
        *) account= ;;
      esac

      case $command in
        login)
          [[ -n $account ]] ||
            die "profile '$profile' is not built in; its keychain account cannot be known here"
          token_file=$supabase_home/access-token
          [[ ! -e $token_file ]] ||
            die "$token_file holds a token outside the keychain; remove it, then log in again"
          unlocked || die "the login keychain is locked; unlock it and retry"
          status=0
          "$real" "$@" || status=$?
          if (( status == 0 )) && [[ -f $token_file ]]; then
            token=$(<"$token_file")
            # Through `security -i` on stdin so the token never reaches argv.
            # An item written by /usr/bin/security trusts it, so later reads
            # are silent.
            printf 'add-generic-password -U -s %s -a %s -T /usr/bin/security -w %s %s\n' \
              "$(quote "$service")" "$(quote "$account")" "$(quote "$token")" "$(quote "$keychain")" |
              "$security" -i >/dev/null ||
              die "could not store the token in the keychain; it is still in $token_file"
            unset token
            rm -f "$token_file"
          fi
          exit "$status"
          ;;
        logout)
          # The CLI asks for confirmation, removes the token file, and resets
          # telemetry; it reports "not logged in" because it sees no keyring.
          "$real" "$@" || exit
          [[ -n $account ]] ||
            die "profile '$profile' is not built in; its keychain account cannot be known here"
          unlocked || die "the login keychain is locked; unlock it and retry"
          "$security" delete-generic-password -s "$service" -a access-token "$keychain" >/dev/null 2>&1 || true
          if "$security" delete-generic-password -s "$service" -a "$account" "$keychain" >/dev/null 2>&1; then
            # Like the CLI's logout: once the profile's token is gone, every
            # other "$service" item goes too.
            while "$security" delete-generic-password -s "$service" "$keychain" >/dev/null 2>&1; do :; done
            echo "Deleted the '$account' access token from the login keychain."
          fi
          exit 0
          ;;
      esac

      if [[ -z ''${SUPABASE_ACCESS_TOKEN:-} && -n $account ]]; then
        state=0
        unlocked || state=$?
        case $state in
          0)
            token=
            for item_account in "$account" access-token; do
              status=0
              token=$(read_item "$item_account") || status=$?
              case $status in
                0) break ;;
                44) token= ;;
                *) die "keychain lookup for '$service' failed (security exit $status)" ;;
              esac
            done
            if [[ $token == go-keyring-base64:* ]]; then
              token=$(printf '%s' "''${token#go-keyring-base64:}" | /usr/bin/base64 -d)
            fi
            [[ -z $token ]] || export SUPABASE_ACCESS_TOKEN=$token
            unset token
            ;;
          1) echo "supabase: the login keychain is locked; running without the stored access token" >&2 ;;
          *) die "could not read the state of $keychain" ;;
        esac
      fi

      exec "$real" "$@"
    '';
  };
in
# Keep the upstream shell completions next to the wrapper.
symlinkJoin {
  pname = "supabase-cli";
  inherit (supabase-cli) version;
  paths = [
    wrapper
    supabase-cli
  ];
  passthru.unwrapped = supabase-cli;
  meta = supabase-cli.meta // {
    platforms = lib.platforms.darwin;
  };
}
