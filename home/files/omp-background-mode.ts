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

// Karpathy + Claude Code + OpenAI Codex surgical simplicity rules.
// Counteracts Sol high/xhigh over-engineering and overrides implementation-discipline.md:3
// unless the user or task explicitly requests an architectural refactor.
const BG_SURGICAL_SCOPE = [
	"<bg-surgical-scope>",
	"CRITICAL BACKGROUND-MODE IMPLEMENTATION DISCIPLINE:",
	"1. Override Step-Change Expansion: This directive overrides implementation-discipline.md:3 ('propose the structural fix... look for step-change improvements'). Do NOT perform architectural rewrites or speculative generalizations unless explicitly requested.",
	"2. Minimal Surgical Diff & Clean Cutover: Touch only the lines and files required to solve the literal request. Migrate callers required by a rename or signature change, and delete replaced code without leaving dead shims.",
	"3. Zero Unrequested Abstractions: NEVER create unrequested files, classes, interfaces, helper functions for single-use logic, options bags/optional config parameters for fixed behavior, backward-compatibility aliases, or defensive wrappers.",
	"4. Proportionate Verification: Write concise regression tests for the changed behavior only. Avoid clock/spy mocking when a deterministic input exists, and NEVER invent combinatorial test.each matrices for unrequested edge cases.",
	"5. Pragmatic Intent & Anti-Runaway: Interpret short or colloquial user instructions by their practical intent rather than literal pedantry. Do not silently chain 30+ tool calls on an ambiguous request; state your concise conclusion first, or ask one direct question when scope is genuinely ambiguous.",
	"</bg-surgical-scope>",
].join("\n");

// Overrides reviewer.md:72-74 so Grok 4.7 flags deliberate over-engineering as blocking P1/P2 scope defects.
const BG_REVIEWER_SCOPE_RUBRIC = [
	"<bg-reviewer-scope-rubric>",
	"CRITICAL BACKGROUND-MODE SCOPE REVIEW RUBRIC:",
	"1. Override Deliberate-Design Exemption: In /bg mode, deliberate over-engineering IS a blocking defect (overrides reviewer.md:72-74).",
	"2. Flag as P1/P2 Scope Defects with exact file:line removal instructions:",
	"   - P1: Unrequested new files, classes, interfaces, single-use helpers, options bags, or backward-compatibility aliases/shims.",
	"   - P2: Bloated test.each matrices, unnecessary clock/spy mocking when deterministic inputs exist, or tests outside the requested scope.",
	"</bg-reviewer-scope-rubric>",
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
			(m) => !(m.role === "custom" && m.customType === "bg-surgical-scope"),
		);
		return {
			messages: [
				...clean,
				{
					role: "custom",
					customType: "bg-surgical-scope",
					content: BG_SURGICAL_SCOPE,
					display: false,
					attribution: "user",
					timestamp: activatedAt || Date.now(),
				},
			],
		};
	});

	// Propagate surgical scope rules to `task` (Sol:high) and anti-bloat review criteria
	// to `reviewer` (Grok 4.7:low) via `item.task`, leaving read-only scouts untouched.
	pi.on("tool_call", async (event) => {
		if (!active || event.toolName !== "task" || !event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;

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
					const next = appendDirective(item.task, BG_SURGICAL_SCOPE, "<bg-surgical-scope>");
					if (next !== item.task) {
						item.task = next;
						modified = true;
					}
				} else if (item.agent === "reviewer") {
					const next = appendDirective(
						item.task,
						BG_REVIEWER_SCOPE_RUBRIC,
						"<bg-reviewer-scope-rubric>",
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
			const next = appendDirective(rawInput.task, BG_SURGICAL_SCOPE, "<bg-surgical-scope>");
			if (next !== rawInput.task) return { input: { ...rawInput, task: next } };
		} else if (agent === "reviewer") {
			const next = appendDirective(
				rawInput.task,
				BG_REVIEWER_SCOPE_RUBRIC,
				"<bg-reviewer-scope-rubric>",
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
