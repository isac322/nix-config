# BearDrive destination adapter

BearDrive installation is common, but project onboarding and synchronization are node-specific. The adapter may write a report artifact only at an explicitly selected path. It must not guess a folder, hub, project, or authentication state.

## Semantic report

Create content fields before rendering:

- `title`
- `audience`
- `purpose`
- `summary`
- `sections` with headings, body, emphasis, and claim references
- `unknowns`
- `source_refs`
- `priority` only when supplied

The agent owns content and ordering. BearDrive owns HTML, CSS, layout, and presentation. Do not treat rendered HTML as evidence. Do not include `<script>`, `<style>`, layout markup, shell commands, credentials, private paths, or a claim that synchronization happened unless a source record proves it.

## Modes

- `content_plan`: choose the report structure and emphasis from the source ledger.
- `compose`: write semantic report content.
- `edit`: change only the requested semantic fields.
- `publish`: render or sync only after the destination path and user authorization are explicit.

A draft or benchmark run must not call `bdrive init`, authenticate, or synchronize. Report the artifact path and validation state separately from any later node onboarding.
