---
name: instruction-architect
description: Use when the user asks to remember, persist, add, change, or organize a durable instruction, preference, rule, workflow, personality, or skill; including "기억해", "앞으로 항상", "지침에 추가", "규칙으로 만들어", or "스킬로 만들어".
---

# Instruction Architect

Persist the user's intent in the canonical Nix sources under `/etc/nix-darwin`, not in generated files under `~/.omp`, `~/.claude`, `~/.codex`, or `~/.agents`.

## Goal

Turn a natural-language request into the smallest correct instruction unit, store it on the right surface, and let Nix compose or deploy it.

## Mandatory duplicate check

Before choosing a destination, inspect the canonical fragment, named-rule, and skill trees for an instruction with the same meaning.

- If an equivalent instruction already exists, report or update that source instead of creating another one.
- If one policy intentionally needs a cross-harness layer and an OMP compaction-safe layer, designate one canonical owner for the shared semantics. The secondary surface may contain only its delivery-specific delta.
- Never copy an ordered workflow, state machine, set definition, or decision matrix into multiple surfaces. Compare existing copies for drift, consolidate shared meaning into the owner, and delete or narrow the duplicate.
- Classify a new destination only when no existing source already covers the request.
- Matching delivery scope is not equivalent meaning. An aggregate fragment does not own every policy sent to the same harnesses; update it only when its topic and purpose already cover the request.

## Delivery semantics and canonical destinations

Choose a surface by how its body reaches the agent, how long it remains authoritative, and which harnesses receive it. Do not classify from prose shape alone.

- `home/files/agent-instructions/agents/*.md`: full text is composed into the user context files for OMP, Claude Code, and Codex. It is injected when a session opens, not repeated near every later turn, so use it for portable background and broad principles rather than the only copy of a late, costly action guard.
- `home/files/agent-instructions/harness/{omp,claude,codex}.md`: the same session-opening context-file delivery, limited to one harness. Use it for broad harness-specific behavior, not operation-specific runtime guards.
- `home/files/agent-instructions/personality/*.md`: OMP main-agent system-prompt style only. The composed `PERSONALITY.md` replaces OMP's bundled personality preset rather than extending it, and OMP subagents do not inherit it.
- `home/files/agent-instructions/sticky/*.md`: full text is composed into OMP `RULES.md`, converted to an always-apply rule, and kept near the current turn across long sessions and compaction. Reserve it for tiny universal OMP safety or truthfulness invariants.
- `home/files/agent-instructions/rules/*.md`: operation-, task-, path-, or file-specific OMP policy.
  - An ordinary named rule exposes its name and `description` in the system prompt; the model must select and read the body on demand. Use it only when delayed loading is safe.
  - `alwaysApply: true` injects the full rule body in the system prompt and preserves it across compaction. Use it when an OMP-specific conditional policy must already be present at a late or costly action.
  - Do not assume `globs` automatically select a rulebook rule; use a discriminative `description`, and use `alwaysApply` when voluntary selection is an unsafe dependency.
  - Approval-gated rule bodies must preserve exact action scope and immediate timing; apply the approval requirements in the editing workflow rather than relying on conversational presence.
- `home/skills/<name>/SKILL.md`: personal-global reusable procedures or knowledge packs. `home/agent-skills.nix` deploys each direct child to `~/.agents/skills`, where OMP can discover it across projects. This does not establish Claude Code or Codex delivery.
- `.agents/skills/<name>/SKILL.md`: project-owned reusable procedures or knowledge packs. OMP discovers these directly for sessions in this repository; Git owns the source and Nix must not deploy it to the user skill tree.
- Project-specific instruction files: session-opening guidance owned and versioned by that project.
- Hook, extension, permission, branch protection, or configuration: deterministic enforcement. Prose can guide a decision but cannot guarantee a block.

`home/agent-instructions.nix` composes shared and harness-specific fragments into `~/.omp/agent/AGENTS.md`, `~/.claude/CLAUDE.md`, and `~/.codex/AGENTS.md`. It separately composes OMP personality and sticky rules and deploys named rules. `home/agent-skills.nix` globally deploys every direct child of `home/skills/`; project skills under `.agents/skills/` need no Nix registry or deployment.

When reporting a classification, name the canonical repository source first. Paths under the user's home directory, such as `~/.omp`, `~/.claude`, `~/.codex`, and `~/.agents`, are deployment targets, never the place to author the instruction. A repository-local `.agents/skills/` path is a canonical project source.

## Fragment granularity

Choose the file within a destination by topic ownership, not merely by shared delivery scope:

- `home/files/agent-instructions/agents/00-core.md` is reserved for universal, organization-agnostic operating principles that apply across ordinary work.
- A cross-harness policy tied to a named organization, account, person, bot, external service, operation, exception matrix, or specialized workflow belongs in its own narrowly named `agents/<topic>.md` fragment.
- Update an existing fragment only when its current heading and body already own the requested topic. A broad filename does not widen that ownership. This applies to every `agents`, `harness`, `personality`, and `sticky` fragment.
- Never rename or broaden a fragment's heading or topic merely to absorb an adjacent request. If the request falls outside the existing scope, create a narrowly named sibling fragment. Because `harness/` composes only `omp.md`, `claude.md`, and `codex.md`, add a distinct heading inside the applicable harness file instead of creating a sibling there.
- Broaden or consolidate fragments only when the user explicitly requests it. Before doing so, audit every existing statement and restate its original operation, actor, service, path, exception, permission, and requirement scope explicitly. An unqualified existing statement must not silently inherit the broader heading.
- Keep one cohesive policy in one topic fragment. For example, a fragment headed `Pull request creation` owns creation even if its filename is `pull-requests.md`; a merge policy belongs in a sibling fragment unless the user explicitly requests consolidation. The creation policy's OMP compaction-safe execution guard may separately live in an `alwaysApply` named rule such as `rules/pull-request-creation.md`.

## Classification

Classify by failure mode and delivery requirements before content shape:

1. If the behavior must be mechanically blocked or guaranteed, prose is insufficient. Use an enforcement mechanism and add explanatory guidance only if it still helps the agent.
2. Decide whether the instruction is personal-global, project-owned, or temporary. Project session guidance belongs to that project's instruction files; a substantial reusable project procedure belongs in `.agents/skills`; a one-session preference should not be persisted.
3. Decide which agents must receive the body: OMP main agent, OMP including subagents, one harness, or every harness. Never treat the shared `~/.agents/skills` deployment as verified cross-harness delivery.
4. Decide when the full body must be available:
   - A universal OMP invariant that must survive compaction -> `sticky`.
   - An operation-specific OMP policy needed before a late, costly, or irreversible action -> `rules` with `alwaysApply: true`.
   - Session-opening context is sufficient -> `agents` or the relevant `harness` file.
   - Voluntary on-demand reading is safe -> an ordinary named `rule` or a `skill`.
5. Within on-demand content, classify operation-, task-, path-, or file-triggered policy as `rules` before considering `skills`.
6. Use `skills` only for a substantial reusable procedure, domain playbook, or body of knowledge whose delayed loading is acceptable.
7. Use `personality` for OMP main-agent-only tone or presentation. If OMP subagents must follow it, use `harness/omp.md`; if every harness must follow it, use `agents`.
8. Use `agents` for a broad portable principle and `harness/<name>.md` for a broad principle limited to one harness.

A request may need two surfaces when it has two distinct delivery obligations. Choose one canonical owner for the shared semantics and limit the other surface to its delivery-specific delta. For a portable workflow with an OMP late-action guard, the `agents` fragment owns the workflow and the `alwaysApply` rule contains only the irreducible compaction-safe guard. Never duplicate the ordered procedure, state model, set definitions, or decision criteria across both.

## General decision examples

These examples exercise the classification rules; they are not an exhaustive lookup table:

- A late, irreversible OMP action plus a requirement that other harnesses know the complete workflow -> the `agents` fragment owns the portable workflow, while an `alwaysApply` rule contains only the OMP-specific late-action guard that must survive compaction.
- A substantial optional maintenance playbook that is safe to load when the task starts -> a `SKILL.md`.
- A repository's database version or release convention -> that repository's own instruction file.
- A requirement to prevent force-push regardless of model behavior -> branch protection, a hook, or equivalent enforcement configuration.
- A broad OMP tool preference used throughout a session -> `harness/omp.md`.

## Normative repository anchors

The following meanings are already owned by exact canonical sources in this repository. The mandatory duplicate check must resolve matching requests to these files; do not reinterpret them as a different surface merely because their wording could fit a broader category:

- Never claim that an unexecuted verification passed -> `home/files/agent-instructions/sticky/00-guardrails.md`, not shared `agents`. It is an existing OMP truthfulness invariant that must survive compaction.
- Concise Korean responses for the OMP main agent only -> `home/files/agent-instructions/personality/00-default.md`, not `harness/omp.md`. It is main-agent response style; update the existing personality source if the requested language behavior is not already fully expressed.
- Find every caller before changing a public or exported API -> `home/files/agent-instructions/rules/public-api.md`, not a skill or sticky rule. It is an existing operation-triggered named policy.
- Prefer OMP native tools or internal URLs over shell equivalents as a broad harness behavior -> `home/files/agent-instructions/harness/omp.md`, not a named rule. A broad session-wide harness preference has no task, path, file-type, or operation trigger.

## Socratic clarification

Infer scope and delivery requirements from the request and existing files first. Ask one concise question only when different answers would select different destinations or enforcement mechanisms. Resolve, in order:

1. Personal-global, project-owned, or one-session?
2. Guidance or deterministic enforcement?
3. Which harnesses and agents must receive the full body?
4. Must the instruction be present at session opening, survive compaction, or may it be loaded on demand?
5. Is it an operation-specific policy, universal invariant, broad principle, response style, or substantial reusable procedure?

Offer 2-4 concrete choices when asking. Do not conduct an interview when the destination is already clear.

## Editing workflow

1. Read the relevant destination directory and nearby files.
2. Search for an existing instruction with the same meaning.
3. When the same policy appears on multiple surfaces, compare their exact actors, operations, ordering, state, sets, exceptions, and completion criteria. Select one canonical owner for shared semantics, then remove or reduce every secondary copy to a delivery-specific delta.
4. Update an existing source only when its current heading and body already own the requested topic. Otherwise create one narrowly named Markdown file; for `harness/`, add a distinct heading inside the applicable fixed harness file. Do not use an aggregate fragment as a catch-all for every policy with the same delivery scope.
5. Do not rename or broaden a fragment to claim an adjacent topic. This applies to `agents`, `harness`, `personality`, and `sticky`. If the user explicitly requests consolidation, audit and restate every existing instruction so its original scope remains explicit under the broader heading.
6. Keep `agents`, `harness`, `personality`, and `sticky` fragments self-contained. Only named rules and skills use frontmatter.
7. Give named rules an explicit, discriminative `description`. Add `alwaysApply: true` when failure to select the rule before a late, costly, or irreversible action would be unsafe. If an `agents` fragment already owns the workflow, keep the rule to the irreducible guard instead of restating the procedure.
8. When authoring an approval-gated policy, define exactly what grants authorization, its action and target scope, how long it remains valid, what final details must be presented, and which material changes require new approval. Do not automatically invalidate a direct instruction to perform the guarded action merely because it preceded finalization; preserve it as standing authorization when that policy permits. When no standing authorization exists, require the acting agent to present the exact target and material options and obtain explicit approval before execution. Approval for a different action or target never transfers.
9. Give every skill explicit `name` and `description` frontmatter. Keep procedures in `SKILL.md`; move long supporting material to `references/`. Use `home/skills` only for requested personal-global skills and `.agents/skills` for project-owned skills. Do not use a skill when its body must already be active at the guarded action.
10. Never edit `~/.omp/agent/AGENTS.md`, `PERSONALITY.md`, `RULES.md`, `rules/`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or `~/.agents/skills` directly. They are Home Manager deployment targets. Repository-local `.agents/skills` is canonical project source and may be edited.
11. Stage only newly created flake-referenced source files before Nix evaluation so the Git-backed flake includes them. Never stage unrelated changes.

## Verification

After editing:

1. Run `nixfmt --check` on changed Nix files. If `nixfmt` is unavailable, run it through `nix shell nixpkgs#nixfmt -c nixfmt --check`.
2. Run `nix flake check --no-update-lock-file`.
3. Build the current host configuration without switching.
4. For Nix-managed instructions, inspect the built activation package or perform an approved Home Manager/darwin switch, then confirm the generated outputs. For a project skill, run OMP from the project with the user skill source disabled and confirm `skill://<name>` resolves to `.agents/skills/<name>/SKILL.md`.
5. Report the chosen classification, canonical source path, generated target when applicable, and exact checks executed.
6. Do not claim a Nix-managed instruction is active until deployment has been verified. A project skill becomes discoverable from the repository checkout and requires no Home Manager deployment.
