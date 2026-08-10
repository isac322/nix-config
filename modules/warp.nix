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
{ config, lib, ... }:

let
  inherit (config.system) primaryUser;

  # Zero Trust team name — the <team-name> in https://<team-name>.cloudflareaccess.com.
  # While this is empty the managed configuration is not written at all, and
  # enrolment is left to `warp-cli teams-enroll <team-name>` by hand.
  organization = "runbear";

  # A managed configuration file, which is the declarative half of this. macOS
  # reads /Library/Application Support/Cloudflare/mdm.xml and the service
  # applies it before anyone logs in, so the organisation does not have to be
  # typed on each machine. Settings here overrule the dashboard's device
  # settings, so keep it to what genuinely belongs in the repo.
  #
  # service_mode "warp" is the full tunnel, which is what reaching
  # internal-only services requires; "1dot1" would only encrypt DNS.
  mdmXml = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>organization</key>
      <string>${organization}</string>
      <key>service_mode</key>
      <string>warp</string>
    </dict>
    </plist>
  '';
in
{
  homebrew.casks = [ "cloudflare-warp" ];

  system.activationScripts.postActivation.text = lib.mkIf (organization != "") ''
    echo "writing the WARP managed configuration..." >&2
    install -d -m 0755 "/Library/Application Support/Cloudflare"
    cat > "/Library/Application Support/Cloudflare/mdm.xml" <<'WARP_MDM_EOF'
    ${mdmXml}
    WARP_MDM_EOF
    chmod 0644 "/Library/Application Support/Cloudflare/mdm.xml"
  '';
}
