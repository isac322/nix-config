# Camofox on the unattended Mac.
#
# The browser API itself belongs to the logged-in Aqua session and is declared
# in home/roles/darwin-server.nix. The parts that need root live here: Apple's
# Screen Sharing daemon, its VNC password, and the noVNC bridge in front of its
# loopback-only legacy VNC connection.
#
# The browser API is loopback-only so local OMP can control it without exposing
# it on any network interface. screensharingd rejects legacy VNC anywhere
# except loopback, noVNC is the only process that connects to 127.0.0.1:5900,
# and noVNC refuses to start until WireGuard has published the one address it
# may bind.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.camofox;
  wireguardAddressFile = "/var/run/wireguard-addresses";
  vncSettingsFile = "/Library/Preferences/com.apple.VNCSettings.txt";

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

  # Apple stores a legacy VNC password as sixteen bytes, padded with NUL and
  # XORed with this fixed key. The file is uppercase hexadecimal, not the raw
  # bytes. stdin is deliberate: putting the password in perl's argv would make
  # it visible to every process on the machine through ps.
  vncSettingsPerl = ''
    my @key = (0x17, 0x34, 0x51, 0x6E, 0x8B, 0xA8, 0xC5, 0xE2,
               0xFF, 0x1C, 0x39, 0x56, 0x73, 0x90, 0xAD, 0xCA);
    my $password = do { local $/; <STDIN> };
    $password = "" unless defined $password;
    $password =~ s/\r?\n\z//;
    die "Camofox VNC password must be exactly 8 alphanumeric characters\n"
      unless $password =~ /\A[A-Za-z0-9]{8}\z/;
    $password .= "\0" x (16 - length($password));
    print join "", map {
      sprintf "%02X", ord(substr($password, $_, 1)) ^ $key[$_]
    } 0 .. 15;
  '';

  novnc = pkgs.writeShellScript "camofox-novnc" ''
    set -u

    # WireGuard and this daemon both start at boot, with no useful ordering
    # guarantee between them. Wait for the address file, but only for a bounded
    # interval: a non-zero exit lets launchd's KeepAlive retry while leaving a
    # clear line in the log. Binding the noVNC default, 0.0.0.0, is never a
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

    # nixpkgs patches this wrapper to use its packaged websockify and web tree.
    # It therefore neither discovers nor downloads anything at run time.
    exec ${pkgs.novnc}/bin/novnc \
      --listen "$address:${toString cfg.novncPort}" \
      --vnc 127.0.0.1:5900
  '';
in
{
  options.local.camofox = {
    enable = lib.mkEnableOption ''
      Camofox in the automatic Aqua session, with Apple Screen Sharing exposed
      through a noVNC bridge that listens only on this Mac's WireGuard address'';

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9377;
      description = "Loopback TCP port for the Camofox browser API.";
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
        Persistent eight-character password used by Apple's legacy VNC
        authentication behind noVNC. It is generated once when absent and kept
        root:wheel 0600; changing this path deliberately creates a new secret.
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
    ];

    # noVNC is a daemon rather than an agent. It needs no window server, and it
    # must be present before anyone can use the screen that automatic login
    # creates. The wrapper's non-zero readiness failure is supervised here.
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
      vncSettings=${lib.escapeShellArg vncSettingsFile}

      # The password is machine state, not generation state. Generate it only
      # when the path does not exist, then repair ownership and permissions on
      # every switch. Reboots and later generations therefore keep the same
      # credentials.
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
      /usr/sbin/chown root:wheel "$passwordFile"
      /bin/chmod 0600 "$passwordFile"

      # Render through a sibling and move it into place so screensharingd can
      # never observe half of the hexadecimal password. The secret is read on
      # stdin and never placed on a command line.
      umask 077
      /usr/bin/perl -e ${lib.escapeShellArg vncSettingsPerl} \
        < "$passwordFile" > "$vncSettings.new"
      /usr/sbin/chown root:wheel "$vncSettings.new"
      /bin/chmod 0400 "$vncSettings.new"
      /bin/mv -f "$vncSettings.new" "$vncSettings"
      /usr/sbin/chown root:wheel "$vncSettings"
      /bin/chmod 0400 "$vncSettings"

      # Legacy VNC is what noVNC speaks. It is deliberately accepted only from
      # localhost; screensharingd may still own a wildcard listening socket,
      # but it rejects direct VNC before authentication from any non-loopback
      # peer. noVNC is the sole network-facing entry point and is WireGuard-only.
      /usr/bin/defaults write /Library/Preferences/com.apple.RemoteManagement \
        VNCLegacyConnectionsEnabled -bool true
      /usr/bin/defaults write /Library/Preferences/com.apple.RemoteManagement \
        VNCOnlyLocalConnections -bool true

      # System Settings normally performs these launchctl operations. Repeat
      # them idempotently so a reboot reaches Screen Sharing without a person.
      # Apple's protected job can reject enable/bootstrap/kickstart on some OS
      # revisions. Report that, but do not abort an otherwise valid switch or
      # strand unrelated services that were already updated.
      if ! enableOut=$(/bin/launchctl enable system/com.apple.screensharing 2>&1); then
        echo "camofox: could not enable com.apple.screensharing: $enableOut" >&2
      fi

      if ! bootstrapOut=$(/bin/launchctl bootstrap system \
        /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>&1); then
        case "$bootstrapOut" in
          *"Input/output error"* | *already*) ;;
          *) echo "camofox: could not bootstrap com.apple.screensharing: $bootstrapOut" >&2 ;;
        esac
      fi

      if ! restartOut=$(/bin/launchctl kickstart -k \
        system/com.apple.screensharing 2>&1); then
        echo "camofox: com.apple.screensharing did not accept restart: $restartOut" >&2
      fi
    '';
  };
}
