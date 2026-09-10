# Runbear Slack automation guard

- Use the installed `slack` CLI for every Runbear Slack automation task.
- The only permitted Slack authentication credential is the `isacbear` user token for `isac@runbear.io`, stored in macOS Keychain with service `slack:isacbear` and account `isac@runbear.io`.
- When authentication is required, retrieve that credential with `/usr/bin/security find-generic-password -s "slack:isacbear" -a "isac@runbear.io" -w` and supply it to the Slack CLI without printing, logging, or persisting it elsewhere.
- Never authenticate with, select, or substitute another Slack account or credential, including an unrelated existing Slack CLI session, browser login, environment token, or manually supplied token.
- If the Keychain credential is missing or inaccessible, stop and ask the user to restore access to that credential. If it lacks a required Slack permission or scope, ask the user to add that permission to the same account; never work around the restriction by using another account.
- Read-only operations may proceed without approval in any Slack public or private channel, direct message, or group direct message.
- Before any non-read-only Slack operation, state the exact target conversation, the exact thread or top-level destination, and the operation to perform, then obtain the user's explicit approval.
- Approval authorizes only the described operation in the described conversation and thread, remains valid only until that operation is completed or the user revokes it, and never becomes standing authorization. A change to the conversation, thread, destination, or operation requires new explicit approval.
- Channels whose names start with `isac-test` and the direct-message conversation with Slack user `Isac Yoo` are exempt from the approval requirement; non-read-only operations there may proceed without approval.
- Use `isac-test-3` as the default QA and test channel unless the user specifies another destination.
