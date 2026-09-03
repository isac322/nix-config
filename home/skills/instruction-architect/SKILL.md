---
name: instruction-architect
description: Use when the user asks to remember, persist, add, change, or organize a durable instruction, preference, rule, workflow, personality, or skill; including "기억해", "앞으로 항상", "지침에 추가", "규칙으로 만들어", or "스킬로 만들어".
---

# Instruction Architect

Persist the user's intent in canonical Nix sources under `/etc/nix-darwin`, never in generated files under `~/.omp`, `~/.claude`, `~/.codex`, or `~/.agents`.

## Canonical model

A policy body is stored once and compiled to the strongest delivery surface each harness supports.

- `home/agent-instruction-segments.nix` is the manifest. It assigns each segment a semantic class, harness scope, stable order, source body, and—when needed—a trigger description.
- `home/files/agent-instructions/segments/<name>.md` contains only the canonical Markdown body. Do not put target-specific frontmatter in it.
- `home/agent-instructions.nix` generates context files, OMP rules, Claude rules, OMP personality, and OMP skill filtering.
- `home/agent-skills.nix` deploys regular skills and generated on-demand policy skills to the harness-native skill trees.
- `home/skills/<name>/SKILL.md` is the canonical source for a personal-global reusable skill.
- `.agents/skills/<name>/SKILL.md` is a project-owned skill, discovered from that repository rather than deployed globally.

Generated targets are outputs, never authoring locations.

## Semantic classes

Classify by when the full body must be available, not by the filename shape you want to produce.

| Class | Meaning | OMP | Claude Code | Codex |
|---|---|---|---|---|
| `context` | Broad session-opening background | `AGENTS.md` | `CLAUDE.md` | `AGENTS.md` |
| `persistent` | Universal invariant that must remain prominent | `RULES.md` | unconditional user rule | `AGENTS.md` fallback |
| `onDemand` | Operation or task procedure safe to load when triggered | ordinary named rule | generated personal skill | generated personal skill |
| `critical` | Late, costly, or irreversible action guard that cannot rely on voluntary loading | `alwaysApply` rule | unconditional user rule | `AGENTS.md` fallback |
| `personality` | OMP main-agent response style | `PERSONALITY.md` | unsupported | unsupported |

Fallback composition does not create another canonical source. Claude or Codex may receive a body through a different surface, but the manifest still points to the same segment file.

## Mandatory duplicate check

Before adding or changing a segment or skill:

1. Search the manifest, segment bodies, regular skills, and project instructions for the same meaning.
2. Compare exact actors, operations, ordering, states, sets, exceptions, authorization scope, and completion criteria.
3. Update the existing canonical body when it already owns the meaning.
4. Split a policy into multiple segments only when the parts have genuinely different delivery classes. Each segment must own non-overlapping semantics.
5. Never copy an ordered workflow, state machine, decision matrix, or exception set into a second segment, skill, rule, or context fragment.

A workflow may refer to its critical guard by name. It must not restate the guard's authorization matrix. A reusable technique skill may explain how to evaluate work, but it must defer mandatory authority and completion gates to the applicable policy segment.

## Classification procedure

Resolve these questions in order:

1. **Enforcement:** If behavior must be mechanically guaranteed, use branch protection, a hook, permissions, or another enforcement mechanism. Prose alone is not a hard block.
2. **Ownership:** Decide whether the instruction is personal-global, project-owned, or temporary. Do not persist one-session preferences.
3. **Harness scope:** Set only the harnesses that need the meaning. A harness-specific tool preference does not belong in every harness.
4. **Availability:** Choose `context`, `persistent`, `onDemand`, `critical`, or `personality` from the failure mode above.
5. **Policy or skill:** Use a manifest segment for durable operating policy. Use a regular skill for a substantial reusable procedure or body of knowledge whose content is useful as a capability, not merely as an action guard.
6. **Granularity:** Give one cohesive semantic unit one source body. Adjacent topics remain separate unless the user explicitly requests consolidation.

Ask one concise clarification question only when different answers would change ownership, harness scope, class, or enforcement mechanism.

## Manifest rules

Every manifest entry must have:

- a lowercase hyphenated name;
- one canonical `source` under `home/files/agent-instructions/segments`;
- one class;
- a non-empty explicit harness list;
- a stable three-digit `order` within its class;
- a discriminative `description` for `onDemand` and `critical` segments.

The compiler generates OMP and skill frontmatter. Never add `---` frontmatter to the canonical segment body. Do not point two entries at the same source file.

For approval-gated policy, define exactly:

- what grants authorization;
- the authorized action and target;
- how long authorization remains valid;
- the final details that must be presented;
- which material changes require new approval;
- whether any owner or repository exceptions exist.

Keep that matrix in the `critical` segment. The corresponding `onDemand` workflow should only prepare the target, run prerequisites, invoke the guard, and execute the authorized action.

## Skills

Use `home/skills` for personal-global skills. Nix copies regular skills to both `~/.agents/skills` and `~/.claude/skills`; the former serves OMP and Codex, while the latter is Claude Code's native user-skill tree.

`onDemand` policy segments are also rendered as skills for Claude and Codex because those harnesses lack OMP's named policy-rule surface. OMP receives the same bodies as native named rules and ignores the generated policy-skill names, so it never sees duplicate capabilities.

SkillClaw synchronizes only `~/.agents/skills`. Nix-managed regular and generated policy skill names are protected from pull replacement; Claude's copied tree is not a separate synchronization source.

Keep Nix managed-name registries under `$XDG_STATE_HOME/nix-managed-agent` (default `~/.local/state/nix-managed-agent`), keyed by target. Never place ownership metadata inside a rule or skill tree that another tool discovers, synchronizes, or mutates.

Keep long supporting material inside the skill directory under `references/`. Do not turn a critical action guard into a regular skill: delayed loading is unsafe for that class.

## Editing workflow

1. Read the manifest entry, canonical body, and any related skill or project policy.
2. Search for semantic duplication before choosing a destination.
3. Modify or create the smallest canonical segment or skill that owns the request.
4. If a policy spans classes, partition workflow, persistent invariant, and critical guard without repeating meaning.
5. Update harness scopes and order in the manifest; never hand-author generated target files.
6. When adding a new flake-referenced file, stage only that new source before Nix evaluation so Git-backed flakes can see it.
7. Remove obsolete canonical copies during the same cutover. Do not leave aliases, legacy fragment trees, or duplicate skill sources.
8. Update existing operations or reference documentation when deployment paths or maintenance procedures change.

Never edit these deployment targets directly:

- `~/.omp/agent/AGENTS.md`, `RULES.md`, `PERSONALITY.md`, or `rules/`;
- `~/.claude/CLAUDE.md`, `rules/`, or `skills/`;
- `~/.codex/AGENTS.md`;
- `~/.agents/skills`.

## Repository anchors

Current canonical meanings include:

- universal truthfulness and secret-handling invariants: `guardrails` (`persistent`);
- OMP response style: `response-style` (`personality`, OMP only);
- public API migration checks: `public-api` (`onDemand`);
- destructive operation preparation: `destructive-operations` (`onDemand`);
- completion evidence: `verification` (`onDemand`);
- pull request creation, review, and merge: paired non-overlapping `onDemand` workflow and `critical` guard segments;
- reusable review evaluation technique: `home/skills/receiving-code-review/SKILL.md`.

## Verification

After editing:

1. Run `nixfmt --check` on changed Nix files.
2. Run `nix flake check --no-update-lock-file`.
3. Build the current host configuration without switching.
4. Inspect the built activation and generated OMP, Claude, and Codex outputs. Confirm each body appears only on the intended target surfaces.
5. Smoke-test OMP rule discovery and Claude/Codex skill discovery when their routing changed.
6. Report the canonical source, semantic class, harness scope, generated targets, and exact checks executed.

Do not claim a Nix-managed instruction is active until deployment has been verified.
