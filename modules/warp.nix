# Cloudflare WARP in Zero Trust mode, imported from modules/darwin.nix.
#
# Both Macs get exactly the same thing: the same client, enrolled in the same
# organisation. Nothing here is host-specific — WARP is an outbound client, so
# even the machine that stays on a desk uses it the same way, to reach services
# that are only visible from inside Zero Trust.
#
# From Homebrew rather than nixpkgs. nixpkgs does build cloudflare-warp for
# aarch64-darwin, but its darwin branch only lifts "Cloudflare WARP.app" out of
# the .pkg payload and symlinks warp-cli next to it. The privileged daemon the
# client actually runs on —
# /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist —
# is installed by the .pkg itself, which only the cask runs. Same shape as the
# Karabiner problem: a package that is really a system service cannot be
# installed from the store.
{ lib, ... }:

let
  # Zero Trust team name — the <team-name> in https://<team-name>.cloudflareaccess.com.
  organization = "runbear";

  # A service token turns enrolment into something a machine with no one sitting
  # at it can complete: without one, registering opens a browser for Access
  # login. Create it under Zero Trust > Access controls > Service credentials,
  # then allow it under Team & Resources > Devices > Management with a
  # "Service Auth" device enrolment policy.
  #
  # The secret does not belong in this repository. The activation script reads
  # it from the path below, which each machine provisions once:
  #
  #   sudo install -d -m 0700 /var/lib/cloudflare-warp
  #   sudo tee /var/lib/cloudflare-warp/service-token >/dev/null <<'EOF'
  #   CLIENT_ID=<...>.access
  #   CLIENT_SECRET=<...>
  #   EOF
  #   sudo chmod 0600 /var/lib/cloudflare-warp/service-token
  #
  # Encrypting it into the repo with agenix or sops-nix would remove even that
  # step; this is the version that needs no extra input.
  serviceTokenFile = "/var/lib/cloudflare-warp/service-token";

  mdmPath = "/Library/Application Support/Cloudflare/mdm.xml";
in
{
  homebrew.casks = [ "cloudflare-warp" ];

  # macOS reads mdm.xml before anyone logs in, so the organisation never has to
  # be typed on a machine. Values here overrule the dashboard's device settings,
  # so this stays limited to what belongs in the repo.
  #
  # service_mode "warp" is the full tunnel, which is what reaching internal-only
  # services requires; "1dot1" would only encrypt DNS. onboarding false skips
  # the interactive first-run screens, and auto_connect reconnects rather than
  # waiting for someone to flip the switch — both matter on a headless machine.
  #
  # preActivation, not postActivation, because of the very first activation on a
  # fresh machine. nix-darwin runs preActivation, then extraActivation, then
  # homebrew, then postActivation; the cask's .pkg starts the WARP daemon as it
  # installs. Written afterwards, the file would arrive too late to be read and
  # the machine would sit unenrolled until something restarted the daemon —
  # which, on the headless MacBook Pro, means noticing from somewhere else that
  # it never came back. Written first, the daemon finds its configuration
  # already there.
  system.activationScripts.preActivation.text = ''
    install -d -m 0755 "/Library/Application Support/Cloudflare"

    warpMdm=$(mktemp)
    trap 'rm -f "$warpMdm"' EXIT

    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
      echo '<plist version="1.0">'
      echo '<dict>'
      echo '  <key>organization</key><string>${organization}</string>'
      echo '  <key>service_mode</key><string>warp</string>'
      echo '  <key>auto_connect</key><integer>1</integer>'
      echo '  <key>onboarding</key><false/>'
    } > "$warpMdm"

    warpMode=0644
    if [ -r '${serviceTokenFile}' ]; then
      # shellcheck disable=SC1090,SC1091
      . '${serviceTokenFile}'
      if [ -n "''${CLIENT_ID:-}" ] && [ -n "''${CLIENT_SECRET:-}" ]; then
        {
          echo "  <key>auth_client_id</key><string>$CLIENT_ID</string>"
          echo "  <key>auth_client_secret</key><string>$CLIENT_SECRET</string>"
        } >> "$warpMdm"
        # The file now holds a credential, so it stops being world readable.
        warpMode=0600
      else
        echo "  ${serviceTokenFile} has no CLIENT_ID/CLIENT_SECRET, enrolling interactively" >&2
      fi
    else
      echo "  no service token at ${serviceTokenFile}; enrolment will need a browser" >&2
    fi

    { echo '</dict>'; echo '</plist>'; } >> "$warpMdm"

    if /usr/bin/plutil -lint "$warpMdm" > /dev/null; then
      install -m "$warpMode" "$warpMdm" '${mdmPath}'
    else
      echo "  generated mdm.xml is not a valid plist, leaving the existing one alone" >&2
    fi
  '';
}
