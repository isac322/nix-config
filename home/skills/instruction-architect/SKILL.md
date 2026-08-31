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
- If the same policy intentionally has an OMP sticky layer and a cross-harness portability layer, report both existing paths and keep their purposes distinct.
- Classify a new destination only when no existing source already covers the request.

## Canonical destinations

- `home/files/agent-instructions/agents/*.md`: concise principles shared by OMP, Claude Code, and Codex.
- `home/files/agent-instructions/harness/{omp,claude,codex}.md`: broad instructions specific to one harness.
- `home/files/agent-instructions/personality/*.md`: OMP main-agent response style only. The composed `PERSONALITY.md` replaces OMP's bundled personality preset rather than extending it, and OMP subagents do not inherit it.
- `home/files/agent-instructions/sticky/*.md`: tiny OMP invariants that must remain visible every turn; these compose `RULES.md`.
- `home/files/agent-instructions/rules/*.md`: conditional OMP policies with useful `description` frontmatter and optional `globs` or `alwaysApply`.
- `home/skills/<name>/SKILL.md`: reusable procedures, domain playbooks, or substantial task-specific knowledge. Put optional detail in `references/`, executable helpers in `scripts/`, and assets in `assets/`.

`home/agent-instructions.nix` composes shared and harness-specific fragments into `~/.omp/agent/AGENTS.md`, `~/.claude/CLAUDE.md`, and `~/.codex/AGENTS.md`. It separately composes OMP personality and sticky rules and deploys named rules. `home/agent-skills.nix` discovers every direct child of `home/skills/`; adding a local skill requires no registry edit.

## Classification

Classify the request before writing. Specific semantics take precedence over broad harness scope:

1. Deterministic enforcement requirement -> explain that prose is insufficient and use a hook, extension, permission, or configuration mechanism instead.
2. Multi-step procedure or reusable body of knowledge -> `skills`.
3. Conditional OMP policy triggered by a task, path, file type, or operation -> `rules`.
4. Universal OMP safety or truthfulness invariant that compaction must not weaken -> `sticky`. If it must also govern Claude Code or Codex, add the concise cross-harness principle to `agents` as a distinct portability layer.
5. OMP main-agent-only tone or presentation -> `personality`. If OMP subagents must follow it, use `harness/omp.md`; if every harness must follow it, use `agents`.
6. Broad principle for all harnesses -> `agents`.
7. Broad principle for one harness only -> that file under `harness`.
8. Project-specific knowledge -> that project's own instruction files, not this global repository.
9. One-session preference -> do not persist it.

## Authoritative boundary table

The following rows are normative. When a request matches one, use the listed destination; do not reinterpret it as a broader or more conditional category.

- Preserve unrelated user changes -> shared `agents`.
- Concise Korean for the OMP main agent only -> `personality`.
- Never claim an unexecuted verification passed -> OMP `sticky`. Use `sticky` even though the principle is broadly useful; add shared `agents` only when the user explicitly requests Claude Code or Codex coverage.
- Find every caller before changing an exported API -> named `rules/public-api.md`.
- Repeatable release commands and rollback -> a release `SKILL.md`. The destination is unambiguous; clarify missing operational details only while writing the skill.
- Prefer OMP internal URLs over shell equivalents -> `harness/omp.md`. A broad harness preference is not a named rule; named rules require a task, path, file-type, or operation trigger.
- A repository's database version -> that repository's own instruction file.
- Deterministically block force-push -> branch protection, hook, or equivalent enforcement configuration.

A request may need two surfaces only when the split has distinct purposes, such as a short broad principle plus a detailed conditional rule. Do not duplicate the same prose across surfaces.

## Socratic clarification

Infer scope from the request and existing files first. Ask one concise question only when different answers would select different destinations or enforcement mechanisms. Resolve, in order:

1. Personal global rule or project-specific rule?
2. Guidance or deterministic enforcement?
3. Procedure, conditional policy, always-visible invariant, response style, or broad principle?
4. Which harnesses and agents must receive it?

Offer 2-4 concrete choices when asking. Do not conduct an interview when the destination is already clear.

## Editing workflow

1. Read the relevant destination directory and nearby files.
2. Search for an existing instruction with the same meaning.
3. Update the existing source when possible; otherwise create one narrowly named Markdown file.
4. Keep `agents`, `harness`, `personality`, and `sticky` fragments self-contained. Only named rules and skills use frontmatter.
5. Give named rules an explicit, discriminative `description`. Add `alwaysApply: true` only when ordinary conditional loading is unsafe.
6. Give every skill explicit `name` and `description` frontmatter. Keep procedures in `SKILL.md`; move long supporting material to `references/`.
7. Never edit `~/.omp/agent/AGENTS.md`, `PERSONALITY.md`, `RULES.md`, `rules/`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or `~/.agents/skills` directly. They are deployment targets overwritten by Home Manager activation.
8. Stage only newly created flake-referenced source files before Nix evaluation so the Git-backed flake includes them. Never stage unrelated changes.

## Verification

After editing:

1. Run `nixfmt --check` on changed Nix files. If `nixfmt` is unavailable, run it through `nix shell nixpkgs#nixfmt -c nixfmt --check`.
2. Run `nix flake check --no-update-lock-file`.
3. Build the current host configuration without switching.
4. Inspect the built activation package or perform an approved Home Manager/darwin switch, then confirm that OMP, Claude Code, and Codex outputs contain their shared and harness-specific fragments and remain writable.
5. Report the chosen classification, canonical source path, generated target, and exact checks executed.

Do not claim the instruction is active until deployment has been verified.
