# TOTP codes generated on this machine from secrets in the login keychain.
#
# Ente Auth has no API to sync from, so secrets arrive once through its
# plain-text export (one otpauth:// URI per line). `totp import` stores only
# the entries the caller names, each as a generic password with service
# `totp`, the entry name as the account, and the whole URI as the secret, so
# digits, period, and algorithm travel with it.
#
# The secret never appears in argv: it goes into the keychain through
# `security -i` on stdin and into oathtool as the `-` key on stdin. Items
# created by /usr/bin/security trust it by default, which is what lets an
# unattended session read them back without a dialog.
{
  lib,
  writeShellApplication,
  oath-toolkit,
}:

writeShellApplication {
  name = "totp";
  runtimeInputs = [ oath-toolkit ];

  text = ''
    service=totp
    security=/usr/bin/security
    keychain="$HOME/Library/Keychains/login.keychain-db"

    usage() {
      cat >&2 <<'EOF'
    usage: totp code NAME             print the current code for NAME
           totp list                  list stored entry names
           totp import FILE PATTERN...
                                      store otpauth:// entries from FILE (- for
                                      stdin) whose name contains a PATTERN
                                      (case-insensitive); with no PATTERN, only
                                      list the names FILE holds
           totp remove NAME           delete a stored entry
    EOF
      exit 2
    }

    die() {
      echo "totp: $*" >&2
      exit 1
    }

    urldecode() {
      local s=''${1//+/ }
      printf '%b' "''${s//%/\\x}"
    }

    # param KEY QUERY: the decoded value of KEY in an otpauth query string.
    param() {
      local kv
      local IFS='&'
      for kv in $2; do
        if [[ ''${kv%%=*} == "$1" ]]; then
          urldecode "''${kv#*=}"
          return
        fi
      done
    }

    # parse URI: sets type, name, query; fails on anything but an otpauth URI.
    parse() {
      local rest label issuer
      [[ $1 == otpauth://* ]] || return 1
      rest=''${1#otpauth://}
      type=''${rest%%/*}
      rest=''${rest#*/}
      label=$(urldecode "''${rest%%\?*}")
      query=""
      [[ $rest == *\?* ]] && query=''${rest#*\?}
      issuer=$(param issuer "$query")
      name=''${label/: /:}
      if [[ $name != *:* && -n $issuer ]]; then
        name="$issuer:$name"
      fi
      [[ -n $name ]]
    }

    quote() {
      local s=''${1//\\/\\\\}
      printf '"%s"' "''${s//\"/\\\"}"
    }

    lookup() {
      local status=0
      "$security" find-generic-password -s "$service" -a "$1" -w "$keychain" 2>/dev/null || status=$?
      case $status in
        0) ;;
        44) die "no entry named '$1' (see: totp list)" ;;
        36) die "the login keychain is locked" ;;
        *) die "keychain lookup for '$1' failed (security exit $status)" ;;
      esac
    }

    cmd_code() {
      [[ $# -eq 1 ]] || usage
      local uri type name query secret alg digits period now remaining
      uri=$(lookup "$1")
      parse "$uri" || die "entry '$1' does not hold an otpauth URI"
      [[ $type == totp ]] || die "entry '$1' is $type, not totp"
      secret=$(param secret "$query")
      alg=$(param algorithm "$query")
      alg=''${alg:-SHA1}
      digits=$(param digits "$query")
      period=$(param period "$query")
      period=''${period:-30}
      [[ -n $secret ]] || die "entry '$1' has no secret"
      [[ $period =~ ^[0-9]+$ && $period -gt 0 ]] || die "entry '$1' has an invalid period"

      # A code with a second or two left expires before a login form submits
      # it; wait for the next window instead.
      printf -v now '%(%s)T' -1
      remaining=$((period - now % period))
      if ((remaining < 3)); then
        sleep "$remaining"
      fi

      printf '%s\n' "$secret" |
        oathtool --totp="''${alg^^}" --digits="''${digits:-6}" \
          --time-step-size="''${period}s" --base32 -
    }

    cmd_list() {
      [[ $# -eq 0 ]] || usage
      "$security" dump-keychain "$keychain" | awk -v svc="\"$service\"" '
        function flush() { if (cls && s == svc && a != "") print a; cls = 0; s = ""; a = "" }
        /^keychain: / { flush() }
        /^class: "genp"/ { cls = 1 }
        /"svce"<blob>=/ { sub(/.*"svce"<blob>=/, ""); s = $0 }
        /"acct"<blob>=/ { sub(/.*"acct"<blob>=/, ""); gsub(/^"|"$/, ""); a = $0 }
        END { flush() }
      ' | sort
    }

    cmd_import() {
      [[ $# -ge 1 ]] || usage
      local file=$1
      shift
      local line type name query pattern selected stored=0 seen=0
      local -a names=()
      local -A pending=()
      [[ $file == - ]] && file=/dev/stdin
      [[ -r $file ]] || die "cannot read $file"

      shopt -s nocasematch
      while IFS= read -r line || [[ -n $line ]]; do
        line=''${line%$'\r'}
        parse "$line" || continue
        seen=$((seen + 1))
        if [[ $type != totp ]]; then
          echo "skipped (not totp): $name" >&2
          continue
        fi
        # Ente exports entries still in its trash, flagged inside codeDisplay.
        if [[ $(param codeDisplay "$query") == *'"trashed":true'* ]]; then
          echo "skipped (in Ente trash): $name" >&2
          continue
        fi
        if [[ $# -eq 0 ]]; then
          names+=("$name")
          continue
        fi
        selected=0
        for pattern in "$@"; do
          [[ $name == *"$pattern"* ]] && selected=1
        done
        ((selected)) || continue
        [[ -n $(param secret "$query") ]] || die "entry '$name' has no secret"
        [[ -z ''${pending[$name]+x} ]] ||
          die "two entries are named '$name'; rename one in Ente and export again"
        pending[$name]=$line
      done <"$file"
      shopt -u nocasematch

      ((seen > 0)) || die "no otpauth:// URIs found in $file"
      if [[ $# -eq 0 ]]; then
        printf '%s\n' "''${names[@]}"
        echo "nothing stored; name entries to import as PATTERN arguments" >&2
        return
      fi
      ((''${#pending[@]} > 0)) || die "no entry matched: $*"

      for name in "''${!pending[@]}"; do
        printf 'add-generic-password -U -s %s -a %s -l %s -w %s %s\n' \
          "$(quote "$service")" "$(quote "$name")" "$(quote "TOTP: $name")" \
          "$(quote "''${pending[$name]}")" "$(quote "$keychain")"
      done | "$security" -i >/dev/null

      # `security -i` reports failures on stderr but exits 0; reading every
      # entry back is the only reliable check.
      for name in "''${!pending[@]}"; do
        if [[ $(lookup "$name") == "''${pending[$name]}" ]]; then
          echo "stored: $name"
          stored=$((stored + 1))
        else
          die "failed to store '$name'"
        fi
      done
      echo "$stored stored; delete the export file now" >&2
    }

    cmd_remove() {
      [[ $# -eq 1 ]] || usage
      "$security" delete-generic-password -s "$service" -a "$1" "$keychain" >/dev/null 2>&1 ||
        die "no entry named '$1'"
      echo "removed: $1"
    }

    [[ $# -ge 1 ]] || usage
    sub=$1
    shift
    case $sub in
      code) cmd_code "$@" ;;
      list) cmd_list "$@" ;;
      import) cmd_import "$@" ;;
      remove) cmd_remove "$@" ;;
      *) usage ;;
    esac
  '';

  meta = {
    description = "Generate TOTP codes from otpauth URIs stored in the macOS login keychain";
    license = lib.licenses.mit;
    mainProgram = "totp";
    platforms = [ "aarch64-darwin" ];
  };
}
