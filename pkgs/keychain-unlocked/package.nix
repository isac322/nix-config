# Reports whether a keychain is unlocked without ever prompting: exit 0
# unlocked, 1 locked, 2 unknown. Reading an item from a locked keychain draws
# an unlock dialog, and so does `security show-keychain-info`;
# SecKeychainGetStatus does not.
#
# This is a Nix build, so it is ad hoc signed and its cdhash changes on every
# rebuild. That is fine only because it never touches a keychain item: the
# status call is not checked against any item's ACL or partition list
# (docs/decisions/0033).
{ runCommandCC }:

runCommandCC "keychain-unlocked" { meta.mainProgram = "keychain-unlocked"; } ''
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
''
