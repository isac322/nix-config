# Camofox on the unattended Mac.
#
# The browser, DeskPad virtual monitor, and application-filtered macVNC backend
# belong to the logged-in Aqua session and are declared in
# home/roles/darwin-server.nix. The root module owns the persistent VNC secret,
# derived RFB auth file, and HTTPS noVNC bridge.
#
# The browser API and VNC backend bind loopback only. noVNC is the sole
# network-facing component, and it refuses to start until WireGuard has
# published the one address it may bind.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.camofox;
  wireguardAddressFile = "/var/run/wireguard-addresses";
  primaryUser = config.system.primaryUser;

  # Eight characters from 62 possibilities, sampled without modulo bias. This
  # writes the secret itself to stdout; it is redirected straight into a
  # root-only file and never exists in argv or in the Nix store.
  passwordPerl = ''
    my @alphabet = ("A" .. "Z", "a" .. "z", "0" .. "9");
    open my $random, "<:raw", "/dev/urandom" or die "open /dev/urandom: $!\n";
    my $password = "";
    while (length($password) < 8) {
      read($random, my $byte, 1) == 1 or die "read /dev/urandom: $!\n";
      my $number = ord($byte);
      next if $number >= 248;
      $password .= $alphabet[$number % @alphabet];
    }
    print $password;
  '';

  validatePasswordPerl = ''
    my $password = do { local $/; <STDIN> };
    $password = "" unless defined $password;
    die "Camofox VNC password must be exactly 8 alphanumeric characters\n"
      unless $password =~ /\A[A-Za-z0-9]{8}\z/;
  '';

  novnc = pkgs.writeShellScript "camofox-novnc" ''
    set -u

    tlsDirectory=${lib.escapeShellArg cfg.tlsDirectory}
    certificateFile="$tlsDirectory/certificate.pem"
    keyFile="$tlsDirectory/key.pem"

    # WireGuard and this daemon both start at boot, with no useful ordering
    # guarantee between them. Wait for the address file, but only for a bounded
    # interval: a non-zero exit lets launchd's KeepAlive retry while leaving a
    # clear line in the log. Binding noVNC's default, 0.0.0.0, is never a
    # fallback.
    address=""
    waited=0
    while [ "$waited" -lt 60 ]; do
      if [ -s ${wireguardAddressFile} ]; then
        address=$(/usr/bin/head -n 1 ${wireguardAddressFile})
        case "$address" in
          "" | 0.0.0.0 | ::) address="" ;;
        esac
        [ -n "$address" ] && break
      fi
      /bin/sleep 2
      waited=$((waited + 2))
    done

    if [ -z "$address" ]; then
      echo "camofox-novnc: no usable WireGuard address after ''${waited}s." >&2
      echo "camofox-novnc: refusing noVNC's all-interfaces default; retrying." >&2
      exit 1
    fi

    # noVNC needs a secure browser context for Web Crypto. The address is
    # runtime machine state, so the self-signed certificate is generated here,
    # not in the Nix store. Regenerate it when WireGuard changes address or the
    # certificate has less than 30 days remaining.
    /usr/bin/install -d -m 0700 -o root -g wheel "$tlsDirectory"
    certificateAddress=""
    if [ -s "$certificateFile" ]; then
      certificateAddress=$(${pkgs.openssl}/bin/openssl x509 \
        -in "$certificateFile" -noout -ext subjectAltName 2>/dev/null |
        /usr/bin/sed -n 's/.*IP Address://p' |
        /usr/bin/tr -d '[:space:]')
    fi
    certificateValid=false
    if [ -s "$certificateFile" ] &&
      ${pkgs.openssl}/bin/openssl x509 -in "$certificateFile" \
        -noout -checkend 2592000 >/dev/null 2>&1; then
      certificateValid=true
    fi
    keyValid=false
    if [ -s "$keyFile" ] &&
      ${pkgs.openssl}/bin/openssl pkey -in "$keyFile" -noout >/dev/null 2>&1; then
      keyValid=true
    fi

    if [ "$certificateAddress" != "$address" ] ||
      [ "$certificateValid" != true ] ||
      [ "$keyValid" != true ]; then
      certificateTemp="$certificateFile.new.$$"
      keyTemp="$keyFile.new.$$"
      /bin/rm -f "$certificateTemp" "$keyTemp"
      if ! (
        umask 077
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
          -sha256 -days 825 \
          -subj "/CN=camofox-novnc" \
          -addext "subjectAltName=IP:$address" \
          -keyout "$keyTemp" -out "$certificateTemp"
      ); then
        /bin/rm -f "$certificateTemp" "$keyTemp"
        echo "camofox-novnc: could not generate a certificate for $address." >&2
        exit 1
      fi
      /usr/sbin/chown root:wheel "$certificateTemp" "$keyTemp"
      /bin/chmod 0600 "$certificateTemp" "$keyTemp"
      /bin/mv -f "$certificateTemp" "$certificateFile"
      /bin/mv -f "$keyTemp" "$keyFile"
      echo "camofox-novnc: generated a self-signed certificate for $address." >&2
    fi

    # Keep the daemon tied to the currently published WireGuard address. If
    # WireGuard replaces that address while noVNC is running, exit non-zero so
    # launchd retries, regenerates the SAN, and binds the new address.
    novncPid=0
    stopNovnc() {
      if [ "$novncPid" -gt 0 ]; then
        /bin/kill "$novncPid" 2>/dev/null || true
      fi
      exit 143
    }
    trap stopNovnc TERM INT

    # The Aqua LaunchAgent owns a password-protected LibVNCServer listener on
    # loopback. The standard noVNC client therefore negotiates VNCAuth type 2
    # without the Apple ARD compatibility patch used by the retired backend.
    ${pkgs.novnc}/bin/novnc \
      --listen "$address:${toString cfg.novncPort}" \
      --vnc "127.0.0.1:${toString cfg.vncPort}" \
      --web "${pkgs.novnc}/share/webapps/novnc" \
      --cert "$certificateFile" \
      --key "$keyFile" \
      --ssl-only &
    novncPid=$!

    while /bin/kill -0 "$novncPid" 2>/dev/null; do
      currentAddress=""
      if [ -s ${wireguardAddressFile} ]; then
        currentAddress=$(/usr/bin/head -n 1 ${wireguardAddressFile})
      fi
      if [ "$currentAddress" != "$address" ]; then
        echo "camofox-novnc: WireGuard address changed from $address to $currentAddress; restarting." >&2
        /bin/kill "$novncPid" 2>/dev/null || true
        wait "$novncPid" || true
        exit 1
      fi
      /bin/sleep 5
    done

    wait "$novncPid"
  '';
in
{
  options.local.camofox = {
    enable = lib.mkEnableOption ''
      Camofox in the automatic Aqua session, with Camofox-only native VNC
      exposed through WireGuard-only HTTPS noVNC'';
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9377;
      description = "Loopback TCP port for the Camofox browser API.";
    };

    vncPort = lib.mkOption {
      type = lib.types.port;
      default = 5901;
      description = "Loopback TCP port for the Camofox-only native VNC backend.";
    };

    displayWidth = lib.mkOption {
      type = lib.types.ints.between 640 7680;
      default = 1920;
      description = "Pixel width of the Camofox virtual display.";
    };

    displayHeight = lib.mkOption {
      type = lib.types.ints.between 480 4320;
      default = 1080;
      description = "Pixel height of the Camofox virtual display.";
    };

    novncPort = lib.mkOption {
      type = lib.types.port;
      default = 6080;
      description = "TCP port for noVNC on the active WireGuard address.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-darwin/camofox-vnc-password";
      description = ''
        Persistent eight-character VNC password. Activation generates this
        root-owned master once and never places the secret in the Nix store.
      '';
    };

    rfbAuthFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/camofox/vnc-auth";
      description = ''
        Runtime LibVNCServer password file derived from passwordFile. It is
        generated atomically on every switch and readable only by the primary
        Aqua user.
      '';
    };

    vncViewOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable remote keyboard and pointer input in macVNC. This is intended
        only for diagnosis before macVNC receives Accessibility permission.
      '';
    };

    retireScreenSharing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable and stop the native Screen Sharing migration console during
        activation. Set this only after macVNC has both Screen Recording and
        Accessibility permission and its noVNC path has been verified.
      '';
    };

    tlsDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-darwin/camofox-novnc-tls";
      description = ''
        Root-only directory for the self-signed noVNC certificate and key.
        The certificate is generated at runtime with the current WireGuard
        address in its IP subjectAltName and regenerated when that address
        changes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.local.autoLogin.enable;
        message = ''
          local.camofox.enable requires local.autoLogin.enable: the Camofox
          browser is headful and must run in an automatically-created Aqua
          session after an unattended reboot.
        '';
      }
      {
        assertion = config.local.wireguard.enable;
        message = ''
          local.camofox.enable requires local.wireguard.enable: noVNC is not
          allowed to fall back to an ordinary network interface.
        '';
      }
      {
        assertion =
          cfg.apiPort != cfg.vncPort && cfg.apiPort != cfg.novncPort && cfg.vncPort != cfg.novncPort;
        message = "Camofox API, VNC, and noVNC ports must be distinct.";
      }
      {
        assertion = cfg.passwordFile != cfg.rfbAuthFile;
        message = "Camofox master password and RFB auth paths must differ.";
      }
    ];

    # noVNC needs no window server, so keep it in the system domain. The Aqua
    # LaunchAgent may arrive later; websockify connects to the loopback backend
    # only when a browser client requests a VNC session.
    launchd.daemons.camofox-novnc = {
      # Like the WireGuard daemon, use `command` so nix-darwin puts wait4path in
      # front of the store path during early boot.
      command = "${novnc}";
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ThrottleInterval = 10;
        StandardOutPath = "/var/log/camofox-novnc.log";
        StandardErrorPath = "/var/log/camofox-novnc.log";
      };
    };

    system.activationScripts.postActivation.text = ''
      passwordFile=${lib.escapeShellArg cfg.passwordFile}
      passwordDir=${lib.escapeShellArg (dirOf cfg.passwordFile)}
      rfbAuthFile=${lib.escapeShellArg cfg.rfbAuthFile}
      rfbAuthDir=${lib.escapeShellArg (dirOf cfg.rfbAuthFile)}

      # The master password is machine state, not generation state. Generate it
      # once, validate it before every use, and keep it out of argv and the Nix
      # store.
      /usr/bin/install -d -m 0700 -o root -g wheel "$passwordDir"
      if [ ! -e "$passwordFile" ]; then
        umask 077
        /usr/bin/perl -e ${lib.escapeShellArg passwordPerl} > "$passwordFile.new"
        /usr/sbin/chown root:wheel "$passwordFile.new"
        /bin/chmod 0600 "$passwordFile.new"
        /bin/mv -f "$passwordFile.new" "$passwordFile"
      fi

      if [ ! -f "$passwordFile" ]; then
        echo "Camofox VNC password path is not a regular file: $passwordFile" >&2
        exit 1
      fi
      /usr/bin/perl -e ${lib.escapeShellArg validatePasswordPerl} < "$passwordFile"
      /usr/sbin/chown root:wheel "$passwordFile"
      /bin/chmod 0600 "$passwordFile"

      # LibVNCServer's password file is the eight-byte password encrypted with
      # the RFB fixed DES key. Generate it in a root-owned directory, then make
      # only the Aqua user able to read it. The password never enters argv.
      /usr/bin/install -d -m 0711 -o root -g wheel "$rfbAuthDir"
      umask 077
      if ! /usr/bin/head -c 8 "$passwordFile" |
        ${pkgs.openssl}/bin/openssl enc -des-ecb \
          -provider legacy -provider default \
          -K e84ad660c4721ae0 -nopad -nosalt > "$rfbAuthFile.new"; then
        /bin/rm -f "$rfbAuthFile.new"
        echo "camofox: could not generate the LibVNCServer password file." >&2
        exit 1
      fi
      if [ "$(/usr/bin/stat -f %z "$rfbAuthFile.new")" -ne 8 ]; then
        /bin/rm -f "$rfbAuthFile.new"
        echo "camofox: generated LibVNCServer password file is not eight bytes." >&2
        exit 1
      fi
      /usr/sbin/chown ${lib.escapeShellArg primaryUser}:staff "$rfbAuthFile.new"
      /bin/chmod 0400 "$rfbAuthFile.new"
      /bin/mv -f "$rfbAuthFile.new" "$rfbAuthFile"
      /usr/sbin/chown ${lib.escapeShellArg primaryUser}:staff "$rfbAuthFile"
      /bin/chmod 0400 "$rfbAuthFile"

      # The open-source macVNC backend uses ordinary RFB authentication on
      # loopback. Retire the Apple-specific credential immediately. Keep the
      # native Screen Sharing service as an independent migration console until
      # the operator explicitly confirms macVNC capture and input both work.
      /usr/bin/defaults write /Library/Preferences/com.apple.RemoteManagement \
        VNCLegacyConnectionsEnabled -bool false
      /bin/rm -f /Library/Preferences/com.apple.VNCSettings.txt

      ${lib.optionalString cfg.retireScreenSharing ''
        if ! disableOut=$(/bin/launchctl disable \
          system/com.apple.screensharing 2>&1); then
          echo "camofox: could not disable retired Screen Sharing backend: $disableOut" >&2
        fi
        if ! bootoutOut=$(/bin/launchctl bootout system \
          /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>&1); then
          case "$bootoutOut" in
            *"No such process"* | *"Could not find service"*) ;;
            *) echo "camofox: could not stop retired Screen Sharing backend: $bootoutOut" >&2 ;;
          esac
        fi
      ''}
      ${lib.optionalString (!cfg.retireScreenSharing) ''
        echo "camofox: keeping native Screen Sharing as the migration console." >&2
      ''}
    '';
  };
}
