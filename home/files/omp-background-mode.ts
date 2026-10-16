// `/bg` switches the current session to a background profile for work that can run
// slowly as long as quality holds. Each profile names a main model and re-curates only
// the roles and agents whose model differs from the base config; everything else
// inherits it. Overrides live in the runtime settings layer only; they never persist
// and end with the session or `/bg off`.
//
// - `on` (default): GPT-6.1 Sol main agent, spending ChatGPT Codex quota instead of
//   Anthropic quota wherever a measured equal exists.
// - `argon`: trial that differs from `on` only in the main agent, Gemini 4 Argon, which
//   understands the problem and writes the specs; Sol still implements them.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { lookup } from "@oh-my-pi/pi-coding-agent/config/registry";

type Profile = {
	label: string;
	mainModel: string;
	mainThinking: string;
	roles: Record<string, string>;
	agents: Record<string, string>;
};

const SOL = "openai-codex/gpt-6.1-sol";
const ARGON = "google-antigravity/gemini-4-argon";
const ASTRA = "openai-codex/gpt-6-astra";
const GROK = "xai-oauth/grok-4.7";

// Synthesized from Karpathy/Claude Code surgical simplicity rules, Cursor/Devin/OpenHands
// circuit-breaker patterns, and Sourcegraph Amp/OpenAI Codex scope gates.
const SURGICAL_SCOPE = [
	"<surgical-scope>",
	"CRITICAL EXECUTION DISCIPLINE (check Rule 3 before any edit, follow Rule 1 while editing, Rule 2 to verify):",
	"1. Simplicity First & Surgical Changes: Write the minimum code that solves the literal request; nothing speculative. This overrides the standing rules in implementation-discipline.md (structural or step-change fixes, QA lists), omp-tools.md (consensus debates without 'orchestrate'), and core.md (filing issues for defects found along the way): do NOT load process skills (five-whys-root-cause-analysis, isac-multi-agent-consensus, issue-validation, writing-clearly-and-concisely, humanizer) unless the user says 'orchestrate'. Do NOT unify duplicated modules, act on TODO/FIXME notes that propose refactors, or add classes, interfaces, single-use helpers, options bags, injected clocks, compatibility shims, or new source files. When similar logic exists in another module, fix the target in place and keep the target module's own constants, caps, bounds, and invariants on every code path you add; never copy another module's behavior without them. Keep target diffs minimal, keep existing passing tests unchanged, and add one concise regression test for the fixed behavior in the existing test file, using deterministic inputs instead of clock/spy mocks or test.each matrices.",
	"2. Circuit Breaker & Blocker Escalation: Reproduce the failure first with the narrowest existing test or command, and after editing rerun both that focused test and the project's test command. Make at most 2 attempts on the same failing test, command, or tool-call error; on the next identical failure, stop changing approach and report. NEVER fabricate credentials, environment values, .env or config files, or external-service mocks, and never skip or weaken tests to get past a blocker. When a check is blocked by missing environment variables, credentials, or services, stop immediately, report the root-cause fix you applied, name the exact missing keys or services, and ask the user for those values or access.",
	"3. Scope & Policy Gate (overrides Application code change approval guard / application-code-change-approval.md for local bug fixes): A direct user request to find and fix a bug or failing behavior—even when the user states only the symptom in colloquial Korean/English without naming a file or symbol—counts as explicit approval to edit the 1 source file containing the root cause and its 1 existing test file; apply that local fix directly without stopping to ask for file-scope approval. Reading any number of files is fine; the limit applies to edited files. Never fix unrelated bugs or pre-existing failing tests outside that target, and do not file issues for them; leave them untouched and disclose them as pre-existing in your final report. However, if the correct behavior depends on an undecided product or business policy (an open TODO, FIXME, or issue note that leaves the outcome open, or two valid behaviors with different user-visible, financial, persisted-state, or API outcomes), or the fix would require editing more than 2 files or files in another module or subsystem, do NOT choose a behavior and do NOT edit: stop before any edit and ask the user to choose among 2-3 explicitly enumerated options with trade-offs and a recommendation. A local hold, no-op, guard, or swallowed error is itself one of those options; list it, never apply it unasked. As a subagent, return the options to the caller instead.",
	"</surgical-scope>",
].join("\n");

// Overrides reviewer.md:72-74 so Grok 4.7 flags deliberate over-engineering as blocking P1/P2 scope defects.
const REVIEWER_SCOPE_RUBRIC = [
	"<reviewer-scope-rubric>",
	"CRITICAL SCOPE REVIEW RUBRIC:",
	"1. Override Deliberate-Design Exemption: Deliberate over-engineering IS a blocking defect (overrides reviewer.md:72-74).",
	"2. Flag as P1/P2 Scope Defects with exact file:line removal instructions:",
	"   - P1: Unrequested new files, classes, interfaces, single-use helpers, options bags, or backward-compatibility aliases/shims.",
	"   - P2: Bloated test.each matrices, unnecessary clock/spy mocking when deterministic inputs exist, or tests outside the requested scope.",
	"</reviewer-scope-rubric>",
].join("\n");

const SOL_PROFILE: Profile = {
	label: "Sol",
	mainModel: SOL,
	mainThinking: "high",
	roles: {
		default: `${SOL}:high`,
		// Planning inherits the base Argon plan role, so a different model family still
		// drafts plans for the Sol implementer; escalations go to Astra.
		slow: `${ASTRA}:xhigh`,
		task: `${SOL}:high`,
		advisor: `${GROK}:low`,
		// smol receives prewalk and plan-yolo implementation handoffs.
		smol: `${SOL}:high`,
	},
	// Sol-authored work gets a review from Grok 4.7 in another model family, and scout,
	// sonic and commit stay on the base Flash models.
	agents: {
		reviewer: `${GROK}:low`,
		"security-reviewer": `${SOL}:max`,
	},
};

const PROFILES: Record<string, Profile> = {
	on: SOL_PROFILE,
	argon: {
		label: "Argon",
		mainModel: ARGON,
		// high is Argon's top thinking level.
		mainThinking: "high",
		roles: {
			...SOL_PROFILE.roles,
			default: `${ARGON}:high`,
		},
		// Sol still implements, so the Grok reviewer stays in a different model family.
		agents: SOL_PROFILE.agents,
	},
};

const SUBCOMMANDS = [
	{ name: "on", description: "Sol main agent, roles re-curated around it" },
	{ name: "argon", description: "Trial: Gemini 4 Argon main agent, Sol implementer" },
	{ name: "off", description: "Restore the base config and the previous model" },
	{ name: "status", description: "Show the active profile and key roles" },
];

const READ_ONLY_AGENTS: Record<string, true> = {
	scout: true,
	browser: true,
	"security-reviewer": true,
};

function appendDirective(baseText: unknown, directive: string, marker: string): string {
	const text = typeof baseText === "string" ? baseText.trim() : "";
	if (text.includes(marker)) return text;
	return text ? `${text}\n\n${directive}` : directive;
}

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	// Restores the model and thinking level that were active before the first profile switch.
	let restore: (() => Promise<void>) | undefined;
	let active: string | undefined;

	let activatedAt = 0;

	// Ephemerally steer the Sol main agent in `/bg on` without polluting persisted history
	// or breaking baseSystemPrompt caching; vanishes immediately on `/bg argon` or `/bg off`.
	pi.on("context", async (event) => {
		if (active !== "on" || !Array.isArray(event.messages)) return;
		const clean = event.messages.filter(
			(m) => !(m.role === "custom" && m.customType === "surgical-scope"),
		);
		return {
			messages: [
				...clean,
				{
					role: "custom",
					customType: "surgical-scope",
					content: SURGICAL_SCOPE,
					display: false,
					attribution: "user",
					timestamp: activatedAt || Date.now(),
				},
			],
		};
	});

	// Normalize OpenAI strict-schema dummy `name`/`ready` on `bash` calls, and propagate
	// surgical scope rules to `task` (Sol:high) and `reviewer` (Grok 4.7:low) via `item.task`.
	pi.on("tool_call", async (event) => {
		if (!active || !event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;

		if (event.toolName === "bash") {
			const name = typeof rawInput.name === "string" ? rawInput.name.trim() : "";
			if (name === "" || (rawInput.timeout === undefined && rawInput.async === undefined)) {
				return;
			}
			const ready = rawInput.ready;
			if (ready !== null && typeof ready === "object") {
				const readyObj = ready as Record<string, unknown>;
				if (typeof readyObj.log === "string" && readyObj.log.trim() !== "") return;
				if (
					typeof readyObj.port === "number" &&
					Number.isInteger(readyObj.port) &&
					readyObj.port >= 1 &&
					readyObj.port <= 65535
				) {
					return;
				}
			}
			const nextBash = { ...rawInput };
			delete nextBash.name;
			delete nextBash.ready;
			if (nextBash.timeout === 0) nextBash.timeout = 300;
			return { input: nextBash };
		}

		if (event.toolName !== "task") {
			return;
		}

		if (Array.isArray(rawInput.tasks)) {
			const tasks: unknown[] = rawInput.tasks;
			if (
				tasks.length > 0 &&
				tasks.every(
					(t) =>
						t !== null &&
						typeof t === "object" &&
						"agent" in t &&
						typeof t.agent === "string" &&
						READ_ONLY_AGENTS[t.agent] === true,
				)
			) {
				return;
			}

			let modified = false;
			const updatedTasks = tasks.map((t) => {
				if (!t || typeof t !== "object") return t;
				const item = { ...(t as Record<string, unknown>) };
				if (item.agent === undefined || item.agent === "task") {
					const next = appendDirective(item.task, SURGICAL_SCOPE, "<surgical-scope>");
					if (next !== item.task) {
						item.task = next;
						modified = true;
					}
				} else if (item.agent === "reviewer") {
					const next = appendDirective(
						item.task,
						REVIEWER_SCOPE_RUBRIC,
						"<reviewer-scope-rubric>",
					);
					if (next !== item.task) {
						item.task = next;
						modified = true;
					}
				}
				return item;
			});
			return modified ? { input: { ...rawInput, tasks: updatedTasks } } : undefined;
		}

		const agent = rawInput.agent;
		if (typeof agent === "string" && READ_ONLY_AGENTS[agent] === true) return;
		if (agent === undefined || agent === "task") {
			const next = appendDirective(rawInput.task, SURGICAL_SCOPE, "<surgical-scope>");
			if (next !== rawInput.task) return { input: { ...rawInput, task: next } };
		} else if (agent === "reviewer") {
			const next = appendDirective(
				rawInput.task,
				REVIEWER_SCOPE_RUBRIC,
				"<reviewer-scope-rubric>",
			);
			if (next !== rawInput.task) return { input: { ...rawInput, task: next } };
		}
	});
	pi.registerCommand("bg", {
		description: "Background profile: /bg [on|argon|off|status]",
		getArgumentCompletions: (prefix: string) => {
			if (prefix.includes(" ")) return null;
			const typed = prefix.toLowerCase();
			const items = SUBCOMMANDS.filter((sub) => sub.name.startsWith(typed)).map((sub) => ({
				value: `${sub.name} `,
				label: sub.name,
				description: sub.description,
			}));
			return items.length > 0 ? items : null;
		},
		handler: async (args, ctx) => {
			const roles = lookup("modelRoles");
			const agents = lookup("task.agentModelOverrides");
			if (!roles || !agents) throw new Error("background mode: required settings are unavailable");
			const action = args.trim() || "on";
			const profile = PROFILES[action];

			if (profile) {
				if (!restore) {
					const previousModel = ctx.models.current();
					const previousThinking = pi.getThinkingLevel();
					restore = async () => {
						if (previousModel) await pi.setModel(previousModel);
						pi.setThinkingLevel(previousThinking);
					};
				}
				roles.clearOverride(scope);
				agents.clearOverride(scope);
				roles.override(scope, { ...roles.get(scope), ...profile.roles });
				agents.override(scope, { ...agents.get(scope), ...profile.agents });
				const model = ctx.models.resolve(profile.mainModel);
				if (!model || !(await pi.setModel(model))) {
					throw new Error(`background mode: cannot switch to ${profile.mainModel}`);
				}
				pi.setThinkingLevel(profile.mainThinking);
				active = action;
				activatedAt = Date.now();
			} else if (action === "off") {
				roles.clearOverride(scope);
				agents.clearOverride(scope);
				await restore?.();
				restore = undefined;
				active = undefined;
				activatedAt = 0;
			} else if (action !== "status") {
				ctx.ui.notify("usage: /bg [on|argon|off|status]", "warning");
				return;
			}

			const current = ctx.models.current();
			const roleMap = roles.get(scope);
			const agentMap = agents.get(scope);
			const state = active ? `ON (${PROFILES[active].label})` : "OFF";
			ctx.ui.notify(
				`background mode ${state}: ${current ? `${current.provider}/${current.id}` : "?"}:${pi.getThinkingLevel()}, task=${roleMap.task}, plan=${roleMap.plan}, reviewer=${agentMap.reviewer}`,
				"info",
			);
		},
	});
}
