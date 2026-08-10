# Appearance and Spotlight privacy settings, imported from modules/darwin.nix.
#
# None of these three have a nix-darwin option, and none were findable by
# reading the system: the keys below were identified by snapshotting every
# preference domain, changing the settings once in System Settings, and diffing.
{ config, ... }:

let
  inherit (config.system) primaryUser;

  # Liquid Glass: 0 is Clear, 1 is Tinted. macOS exposes this to applications as
  # NSGlassEffectView.Legibility (.standard / .increased) and the Appearance
  # pane calls setSystemLegibility, but that is a Swift-only API — the installed
  # SDK headers do not even declare it — so the preference it lands on is what
  # gets written here.
  glassTinted = 1;

  # Spotlight's "관련 콘텐츠 보기". Despite the name, EnabledPreferenceRules
  # gains an entry when the setting is turned *off*; it went from empty to
  # holding this one string. It is a list, and other Spotlight categories land
  # in the same array, so the entry is appended if missing rather than the array
  # being written wholesale — that would drop anything else switched off later.
  relatedContentsRule = "Custom.relatedContents";
in
{
  system.defaults.CustomUserPreferences = {
    NSGlobalDomain.NSGlassDiffusionSetting = glassTinted;

    # "Apple에 기여하기" for search. 2 is opted out, matching the Siri-side
    # "Siri Data Sharing Opt-In Status" that was already at 2.
    "com.apple.assistant.support"."Search Queries Data Sharing Status" = 2;
  };

  system.activationScripts.postActivation.text = ''
    echo "disabling Spotlight related content..." >&2
    runAppearanceAsUser() {
      launchctl asuser "$(id -u -- ${primaryUser})" sudo --user=${primaryUser} -- "$@"
    }

    if ! runAppearanceAsUser /usr/bin/defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null \
         | grep -q '"${relatedContentsRule}"'; then
      runAppearanceAsUser /usr/bin/defaults write com.apple.Spotlight EnabledPreferenceRules \
        -array-add '${relatedContentsRule}'
    fi
  '';
}
