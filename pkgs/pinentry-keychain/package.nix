# A pinentry that reads the macOS login keychain, because none of the
# ready-made ones fit a Mac with no one sitting at it.
#
# gpg-agent has no keychain support of its own. Every route to one goes through
# replacing the pinentry, and the three that exist all miss:
#
#   pinentry-mac does keep the passphrase in the keychain — that is its own
#   code, in KeychainSupport.m, not GnuPG's — but it draws its dialog on the
#   console. Over SSH the prompt is invisible and the request waits forever,
#   which is exactly the failure this replaces.
#
#   pinentry-mac-keychain proxies to pinentry-mac, so it inherits that.
#
#   pinentry-touchid gates on a fingerprint, which a machine with its lid shut
#   cannot offer. Neither is in nixpkgs.
#
# A pinentry is a small program speaking Assuan on stdin and stdout, and the
# part that matters here is three commands: SETKEYINFO carries the keygrip,
# GETPIN asks, and the answer is a `D` line then `OK`. Everything else can be
# acknowledged or handed to a real pinentry.
#
# So this looks the keygrip up in the keychain, and on a miss falls through to
# pinentry-tty and stores whatever was typed. The machine asks once, ever, and
# it asks over SSH where someone can answer.
{
  lib,
  writeScriptBin,
  pinentry-tty,
}:

writeScriptBin "pinentry-keychain" ''
  #!/usr/bin/perl
  use strict;
  use warnings;
  use IPC::Open2;

  $| = 1;

  my $SECURITY = "/usr/bin/security";
  my $SERVICE  = "GnuPG";
  my $FALLBACK = "${lib.getExe pinentry-tty}";

  # Assuan percent-encodes exactly these three in data lines, and nothing else.
  sub enc { my $s = shift; $s =~ s/%/%25/g; $s =~ s/\r/%0D/g; $s =~ s/\n/%0A/g; return $s }
  sub dec { my $s = shift; $s =~ s/%0D/\r/gi; $s =~ s/%0A/\n/gi; $s =~ s/%25/%/gi; return $s }

  my $keygrip;
  my @replay;
  my ($childOut, $childIn, $childPid);

  # The real pinentry is started only if it is needed, and is then given the
  # description and prompt that were set before we knew we would need it.
  sub fallbackStart {
    return 1 if $childPid;
    $childPid = open2($childOut, $childIn, $FALLBACK) or return 0;
    my $greeting = <$childOut>;
    for my $c (@replay) {
      print {$childIn} "$c\n";
      my $ignored = <$childOut>;
    }
    return 1;
  }

  # Relay one command to it and pass the answer straight through, keeping any
  # passphrase that comes back.
  sub fallbackAsk {
    my $cmd = shift;
    unless (fallbackStart()) {
      print "ERR 83886179 canceled\n";
      return (0, undef);
    }
    print {$childIn} "$cmd\n";
    my $pin;
    while (my $line = <$childOut>) {
      $line =~ s/\r?\n\z//;
      if ($line =~ /^D (.*)/) { $pin = dec($1); print "$line\n"; next }
      print "$line\n";
      return (($line =~ /^OK/ ? 1 : 0), $pin) if $line =~ /^(OK|ERR)/;
    }
    return (0, $pin);
  }

  # Under an alarm, and that is not belt and braces — it is the whole reason
  # this can be trusted on a machine with no one at it.
  #
  # A keychain item remembers which binaries may read it silently. An item
  # written by some other program — pinentry-mac, say — does not name this one,
  # so macOS answers the read by drawing a confirmation dialog on the console
  # and `security` waits for it. On a headless Mac that wait is unbounded, and
  # it is the exact failure this program was written to remove; inheriting it
  # here would be a joke at our own expense.
  #
  # So a read that does not answer quickly is treated as a miss. The fallback
  # then asks over SSH, and keychainPut rewrites the item with -A, after which
  # reads are silent for good. One awkward prompt, self-healed.
  sub keychainGet {
    return undef unless defined $keygrip;
    # security writes "item could not be found" and friends to stderr, which
    # gpg-agent logs. A miss is ordinary here, so it is not news.
    my $pid = open(my $fh, "-|", "-");
    return undef unless defined $pid;
    unless ($pid) {
      open(STDERR, ">", "/dev/null");
      exec($SECURITY, "find-generic-password", "-a", $keygrip, "-s", $SERVICE, "-w");
      exit 127;
    }

    my $pw;
    my $ok = eval {
      local $SIG{ALRM} = sub { die "timeout\n" };
      alarm 3;
      $pw = <$fh>;
      alarm 0;
      1;
    };

    unless ($ok) {
      kill "TERM", $pid;
      waitpid($pid, 0);
      close $fh;
      return undef;
    }

    close $fh;
    return undef if $? != 0;
    return undef unless defined $pw;
    $pw =~ s/\r?\n\z//;
    return length($pw) ? $pw : undef;
  }

  sub keychainPut {
    my $pw = shift;
    return unless defined $keygrip && defined $pw && length $pw;

    # -w is last so the value arrives on stdin. Given a value it would sit in
    # argv, which every process on the machine can read. -U updates an item
    # that is already there.
    #
    # -A lets any application read it without a prompt, and that is the line
    # that keeps this from breaking again: an item scoped to one binary stops
    # being readable the moment nixpkgs moves that binary to a new store path,
    # and macOS then asks for confirmation on a console nobody is watching —
    # indistinguishable from the hang this exists to remove. The keychain on
    # such a machine is already only as strong as /etc/kcpassword, which
    # automatic login made trivially reversible, so this gives up less than it
    # appears to.
    my $pid = open(my $fh, "|-", $SECURITY, "add-generic-password",
                   "-a", $keygrip, "-s", $SERVICE, "-U", "-A", "-w");
    return unless $pid;

    # Twice, because `security` asks twice — "password data for new item:" and
    # then "retype password for new item:". Sending it once looks like it works
    # and does not: the retype reads EOF, security says "passwords don't match",
    # and the item is never created. Which is a silent failure of exactly the
    # kind this file exists to avoid, so it is worth the sentence.
    print {$fh} "$pw\n$pw\n";
    close $fh;
  }

  print "OK Pleased to meet you\n";

  while (my $line = <STDIN>) {
    $line =~ s/\r?\n\z//;

    if ($line =~ /^SETKEYINFO\s+(\S+)/) {
      my $info = $1;
      # "x/<keygrip>", where x is the cache mode. The mode is not part of the
      # key's identity, so an ssh request and a signing request find one item.
      $keygrip = ($info =~ m{^./(.+)$}) ? $1 : $info;
      push @replay, $line;
      print "OK\n";
    }
    elsif ($line =~ /^(SETDESC|SETPROMPT|SETERROR|SETTITLE|SETOK|SETCANCEL|SETNOTOK|SETQUALITYBAR|SETQUALITYBAR_TT|SETREPEAT|SETREPEATERROR|SETTIMEOUT|OPTION)\b/) {
      push @replay, $line;
      print "OK\n";
    }
    elsif ($line =~ /^GETPIN\b/) {
      my $pw = keychainGet();
      if (defined $pw) {
        print "D " . enc($pw) . "\n";
        print "OK\n";
      } else {
        my ($ok, $typed) = fallbackAsk("GETPIN");
        keychainPut($typed) if $ok;
      }
    }
    elsif ($line =~ /^(CONFIRM|MESSAGE)\b/) {
      fallbackAsk($line);
    }
    elsif ($line =~ /^RESET\b/) {
      $keygrip = undef;
      @replay = ();
      print "OK\n";
    }
    elsif ($line =~ /^BYE\b/) {
      print "OK closing connection\n";
      last;
    }
    else {
      print "OK\n";
    }
  }

  if ($childPid) {
    print {$childIn} "BYE\n";
    close $childIn;
    close $childOut;
    waitpid($childPid, 0);
  }
''
