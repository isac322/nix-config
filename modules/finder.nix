# Finder defaults for the Macs, imported from modules/darwin.nix.
{ config, pkgs, ... }:

let
  inherit (config.system) primaryUser;

  # Sidebar favourites are not a preference key. They live in the shared file
  # list, whose backing store under ~/Library/Application Support is TCC
  # protected — even root cannot read it without Full Disk Access. The
  # LSSharedFileList API reaches the same list without touching those files, and
  # still works on macOS 26 despite being long deprecated. `mysides` would do
  # this too, but nixpkgs ships it as an x86_64 binary only.
  #
  # Removal is by resolved path, so it is idempotent: an entry that is already
  # gone simply does not match.
  sidebarFavorites = pkgs.runCommandCC "sidebar-favorites-remove" { } ''
    cat > remove.c <<'CEOF'
    #include <CoreServices/CoreServices.h>
    #include <stdio.h>
    #include <string.h>

    int main(int argc, char **argv) {
      if (argc < 2) { fprintf(stderr, "usage: %s <path>...\n", argv[0]); return 2; }

      LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListFavoriteItems, NULL);
      if (!list) { fprintf(stderr, "sidebar-favorites: list unavailable\n"); return 0; }

      UInt32 seed = 0;
      CFArrayRef items = LSSharedFileListCopySnapshot(list, &seed);
      if (!items) { CFRelease(list); return 0; }

      /* backwards: removing shifts the indices of everything after it */
      for (CFIndex i = CFArrayGetCount(items); i-- > 0; ) {
        LSSharedFileListItemRef it = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
        CFURLRef url = NULL;
        if (LSSharedFileListItemResolve(it, kLSSharedFileListNoUserInteraction, &url, NULL) != noErr || !url)
          continue;
        char path[PATH_MAX] = "";
        Boolean ok = CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path);
        CFRelease(url);
        if (!ok) continue;
        for (int a = 1; a < argc; a++) {
          if (strcmp(path, argv[a]) == 0) { LSSharedFileListItemRemove(list, it); break; }
        }
      }
      CFRelease(items);
      CFRelease(list);
      return 0;
    }
    CEOF
    mkdir -p $out/bin
    $CC -O2 -Wno-deprecated-declarations -framework CoreServices -o $out/bin/sidebar-favorites-remove remove.c
  '';

  # Icon view arrangement lives in nested dictionaries rather than a flat key,
  # so `defaults write` cannot reach it — writing the parent would replace the
  # whole dictionary and drop icon size, grid spacing and the rest. Exporting
  # the domain, editing, and importing it back goes through cfprefsd properly,
  # unlike editing ~/Library/Preferences/com.apple.finder.plist underneath it.
  #
  # These are the *defaults* for folders with no saved view settings of their
  # own. Folders that do — Downloads and the other special ones — keep what they
  # have, which is the intent: a baseline everywhere else.
  viewSettingsRoots = [
    "StandardViewSettings" # Finder windows
    "FK_StandardViewSettings" # the newer settings group
    "DesktopViewSettings" # desktop, in case icons are ever shown again
  ];

  # "name" keeps icon views sorted by name. Combined with _FXSortFoldersFirst
  # that puts folders first, then everything else alphabetically.
  setArrangeBy = root: ''
    "$PB" -c "Set :${root}:IconViewSettings:arrangeBy name" "$tmp" 2>/dev/null \
      || "$PB" -c "Add :${root}:IconViewSettings:arrangeBy string name" "$tmp" 2>/dev/null \
      || true
  '';
in
{
  # Folders before files, everywhere. The desktop keeps its own flag.
  system.defaults.finder._FXSortFoldersFirst = true;
  system.defaults.finder._FXSortFoldersFirstOnDesktop = true;

  # New windows open the home directory. Unset means Recents.
  system.defaults.finder.NewWindowTarget = "Home";

  # Extensions always visible. The checkbox in Finder writes the global domain,
  # so set that one too rather than only the Finder-scoped copy.
  system.defaults.finder.AppleShowAllExtensions = true;
  system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;

  system.defaults.CustomUserPreferences."com.apple.finder" = {
    # No tags in the sidebar. FavoriteTagNames is the list Finder shows there
    # and ships with the seven colours in it; an array holding only the empty
    # sentinel is how macOS represents "none chosen". ShowRecentTags is the
    # separate "Show recent tags" toggle underneath it.
    FavoriteTagNames = [ "" ];
    ShowRecentTags = false;

  };

  # Hidden files and folders are always visible.
  system.defaults.finder.AppleShowAllFiles = true;

  system.activationScripts.postActivation.text = ''
    runFinderCfgAsUser() {
      launchctl asuser "$(id -u -- ${primaryUser})" sudo --user=${primaryUser} -- "$@"
    }

    echo "trimming Finder sidebar favourites..." >&2
    runFinderCfgAsUser ${sidebarFavorites}/bin/sidebar-favorites-remove \
      ~${primaryUser}/Desktop ~${primaryUser}/Documents || true

    echo "configuring Finder view defaults..." >&2
    (
      PB=/usr/libexec/PlistBuddy
      tmp=$(mktemp)
      trap 'rm -f "$tmp"' EXIT

      if runFinderCfgAsUser /usr/bin/defaults export com.apple.finder "$tmp"; then
        ${toString (map setArrangeBy viewSettingsRoots)}
        runFinderCfgAsUser /usr/bin/defaults import com.apple.finder "$tmp"
      else
        echo "  could not export com.apple.finder, skipping" >&2
      fi
    )
  '';
}
