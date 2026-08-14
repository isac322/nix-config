# Automatic login, done by script rather than by clicking.
#
# Why a Mac that nobody sits at needs to log itself in at all:
# [0028](../docs/decisions/0028-orca-runtime-on-the-server-mac.md). The Orca
# runtime is an Electron application, so it has to be a LaunchAgent, and a
# LaunchAgent only starts when a session is created. Everything else on that
# machine is a root daemon precisely so it needs none of this.
#
# macOS puts two things in the way and both are handled here:
#
#   `/etc/kcpassword` — the login password, obfuscated. Automatic login means
#   storing the password on disk; there is no version of it that does not.
#   nix-darwin writes only the `autoLoginUser` key and never this file
#   (`kcpassword` appears nowhere in its source), so activation writes it.
#
#   FileVault — has to be off. Its pre-boot unlock runs before the network does,
#   so an unattended reboot would stop at a keyboard that is not there.
#
# The password cannot come from this repository, which is public. It comes from
# one file on the machine, the same shape as the WARP service token
# ([0017](../docs/decisions/0017-warp-enrollment-via-mdm-xml.md)) — and that
# file existing is also the consent for both actions. Nothing here turns off
# disk encryption on a machine whose owner has not put the password there on
# purpose.
{ config, lib, ... }:

let
  cfg = config.local.autoLogin;

  # Apple's obfuscation, unchanged since Panther: 11 bytes, repeating, XORed
  # over the password. It is padded with NULs to a multiple of 12 — and by a
  # further 12 when the length already divides evenly, which is the detail that
  # makes an exactly-12-character password fail if it is missed.
  #
  # Read on stdin rather than taken as an argument, because argv is visible in
  # `ps` to every process on the machine.
  kcpasswordPerl = ''
    my @key = (0x7D,0x89,0x52,0x23,0xD2,0xBC,0xDD,0xEA,0xA3,0xB9,0x1F);
    my $pw = <STDIN>;
    $pw = "" unless defined $pw;
    $pw =~ s/\r?\n\z//;
    $pw .= "\0" x (12 - (length($pw) % 12));
    print join "", map { chr(ord(substr($pw,$_,1)) ^ $key[$_ % 11]) } 0 .. length($pw)-1;
  '';

  # `fdesetup`'s man page documents `disable [-verbose]` and no non-interactive
  # form, so this feeds it a plist on stdin — the shape its other subcommands
  # take — and gives up rather than waiting. An activation script that blocks on
  # a prompt nobody can answer is worse than one that reports and moves on,
  # especially over SSH, so the whole thing runs under an alarm.
  fdesetupPerl = ''
    my $pid = open(my $fh, "|-", "/usr/bin/fdesetup", "disable", "-inputplist") or exit 70;
    eval {
      local $SIG{ALRM} = sub { kill "TERM", $pid; die "timeout\n" };
      alarm 30;
      print $fh $ARGV[0];
      close $fh;
      alarm 0;
      1;
    } or exit 71;
    exit($? == 0 ? 0 : 72);
  '';

  # Built in perl rather than in the shell so the password never becomes an
  # argument, and so XML metacharacters in it cannot break the plist.
  fvPlistPerl = ''
    my $u = $ARGV[0];
    my $p = <STDIN>;
    $p = "" unless defined $p;
    $p =~ s/\r?\n\z//;
    for ($u, $p) { s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; }
    print qq{<?xml version="1.0" encoding="UTF-8"?>\n};
    print qq{<plist version="1.0"><dict>};
    print qq{<key>Username</key><string>$u</string>};
    print qq{<key>Password</key><string>$p</string>};
    print qq{</dict></plist>\n};
  '';
in
{
  options.local.autoLogin = {
    enable = lib.mkEnableOption ''
      logging this machine's primary user in without anyone present.

      A security trade rather than a convenience: it stores the login password
      on disk and requires FileVault to be off. Worth it only on a machine that
      is physically secure and has to come back from a reboot on its own'';

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      defaultText = lib.literalExpression "config.system.primaryUser";
      description = "Account to log in automatically.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-darwin/login-password";
      description = ''
        Path to a file whose first line is that account's password. Placed once
        per machine, outside this repository, mode 0600.

        Activation gives it to that account rather than to root. It is the
        user's own password, so they can read it anyway, and the agent that
        unlocks their login keychain after an automatic login has to be able to
        read it too — see home/roles/darwin-server.nix.

        Its absence is not an error — it means automatic login has not been set
        up here, and activation says what to write. Its presence is what
        authorises turning FileVault off.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The half nix-darwin does have an option for.
    system.defaults.loginwindow.autoLoginUser = cfg.user;

    system.activationScripts.postActivation.text = ''
      if [ ! -f ${lib.escapeShellArg cfg.passwordFile} ]; then
        echo "" >&2
        echo "  Automatic login is on but ${cfg.passwordFile} is missing, so this" >&2
        echo "  machine still stops at the login window after a reboot — and the" >&2
        echo "  Orca runtime needs a session to start in." >&2
        echo "" >&2
        echo "  The password cannot live in this repository, which is public." >&2
        echo "  Write it once, here, and every switch after this does the rest:" >&2
        echo "" >&2
        echo "    sudo install -d -m 0700 ${dirOf cfg.passwordFile}" >&2
        echo "    sudo tee ${cfg.passwordFile} >/dev/null <<'EOF'" >&2
        echo "    <${cfg.user}'s login password>" >&2
        echo "    EOF" >&2
        echo "    sudo chown ${cfg.user} ${cfg.passwordFile}" >&2
        echo "    sudo chmod 0600 ${cfg.passwordFile}" >&2
        echo "" >&2
        echo "  Writing it also authorises turning FileVault off, which automatic" >&2
        echo "  login requires. Nothing does that on its own." >&2
        echo "" >&2
      else
        # Owned by the account whose password it is, and readable by nobody
        # else. Re-applied every switch so a file placed as root still ends up
        # right.
        chown ${cfg.user} ${lib.escapeShellArg cfg.passwordFile}
        chmod 0600 ${lib.escapeShellArg cfg.passwordFile}

        # /etc/kcpassword stays root-only, and never wider than what wrote it.
        umask 077

        /usr/bin/perl -e ${lib.escapeShellArg kcpasswordPerl} \
          < ${lib.escapeShellArg cfg.passwordFile} > /etc/kcpassword.new
        chmod 0600 /etc/kcpassword.new
        chown root:wheel /etc/kcpassword.new
        mv -f /etc/kcpassword.new /etc/kcpassword

        if /usr/bin/fdesetup isactive >/dev/null 2>&1; then
          fvPlist=$(/usr/bin/perl -e ${lib.escapeShellArg fvPlistPerl} \
            ${lib.escapeShellArg cfg.user} < ${lib.escapeShellArg cfg.passwordFile})

          if /usr/bin/perl -e ${lib.escapeShellArg fdesetupPerl} "$fvPlist"; then
            echo "  FileVault disabled; decryption continues in the background." >&2
          else
            echo "" >&2
            echo "  FileVault is on and could not be turned off from here, so this" >&2
            echo "  machine will stop at its pre-boot unlock screen on the next" >&2
            echo "  reboot rather than logging itself in. That screen comes up" >&2
            echo "  before the network does, so nothing can answer it remotely." >&2
            echo "" >&2
            echo "  At this machine's own console:" >&2
            echo "" >&2
            echo "    sudo fdesetup disable" >&2
            echo "" >&2
          fi
          unset fvPlist
        fi
      fi
    '';
  };
}
