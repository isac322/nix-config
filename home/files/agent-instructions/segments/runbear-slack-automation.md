# Runbear Slack automation guard

- Use the installed `slack` CLI for every Runbear Slack automation task.
- The only permitted Slack authentication identity is `isac@runbear.io`, using the credential stored in macOS Keychain with service `slack:isacbear` and account `isac@runbear.io`.
- When authentication is required, retrieve that credential with `/usr/bin/security find-generic-password -s "slack:isacbear" -a "isac@runbear.io" -w` and supply it to the Slack CLI without printing, logging, or persisting it elsewhere.
- Never authenticate with, select, or substitute another Slack account or credential, including an unrelated existing Slack CLI session, browser login, environment token, or manually supplied token.
- If the Keychain credential is missing or inaccessible, stop and ask the user to restore access to that credential. If it lacks a required Slack permission or scope, ask the user to add that permission to the same account; never work around the restriction by using another account.
