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
const GROK = "xai-oauth/grok-4.7-build-fast";

// Byte-for-byte contiguous sections from:
// - openai/codex `codex-rs/core/gpt_5_1_prompt.md` (`Autonomy and Persistence`, `Sharing progress updates`, `Validating your work`)
// - forrestchang/andrej-karpathy-skills `CLAUDE.md` (`2. Simplicity First`, `3. Surgical Changes`)
const SURGICAL_SCOPE = [
	"<surgical-scope>",
	"## Autonomy and Persistence",
	"Persist until the task is fully handled end-to-end within the current turn whenever feasible: do not stop at analysis or partial fixes; carry changes through implementation, verification, and a clear explanation of outcomes unless the user explicitly pauses or redirects you.",
	"",
	"Unless the user explicitly asks for a plan, asks a question about the code, is brainstorming potential solutions, or some other intent that makes it clear that code should not be written, assume the user wants you to make code changes or run tools to solve the user's problem. In these cases, it's bad to output your proposed solution in a message, you should go ahead and actually implement the change. If you encounter challenges or blockers, you should attempt to resolve them yourself.",
	"",
	"## 2. Simplicity First",
	"",
	"**Minimum code that solves the problem. Nothing speculative.**",
	"",
	"- No features beyond what was asked.",
	'- No abstractions for single-use code.',
	'- No "flexibility" or "configurability" that wasn\'t requested.',
	"- No error handling for impossible scenarios.",
	"- If you write 200 lines and it could be 50, rewrite it.",
	"",
	'Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.',
	"",
	"## 3. Surgical Changes",
	"",
	"**Touch only what you must. Clean up only your own mess.**",
	"",
	"When editing existing code:",
	'- Don\'t "improve" adjacent code, comments, or formatting.',
	"- Don't refactor things that aren't broken.",
	"- Match existing style, even if you'd do it differently.",
	"- If you notice unrelated dead code, mention it - don't delete it.",
	"",
	"When your changes create orphans:",
	"- Remove imports/variables/functions that YOUR changes made unused.",
	"- Don't remove pre-existing dead code unless asked.",
	"",
	"The test: Every changed line should trace directly to the user's request.",
	"",
	"## Sharing progress updates",
	"",
	"For especially longer tasks that you work on (i.e. requiring many tool calls, or a plan with multiple steps), you should provide progress updates back to the user at reasonable intervals. These updates should be structured as a concise sentence or two (no more than 8-10 words long) recapping progress so far in plain language: this update demonstrates your understanding of what needs to be done, progress so far (i.e. files explores, subtasks complete), and where you're going next.",
	"",
	"Before doing large chunks of work that may incur latency as experienced by the user (i.e. writing a new file), you should send a concise message to the user with an update indicating what you're about to do to ensure they know what you're spending time on. Don't start editing or writing large files before informing the user what you are doing and why.",
	"",
	"The messages you send before tool calls should describe what is immediately about to be done next in very concise language. If there was previous work done, this preamble message should also include a note about the work done so far to bring the user along.",
	"",
	"## Validating your work",
	"",
	"If the codebase has tests or the ability to build or run, consider using them to verify changes once your work is complete.",
	"",
	"When testing, your philosophy should be to start as specific as possible to the code you changed so that you can catch issues efficiently, then make your way to broader tests as you build confidence. If there's no test for the code you changed, and if the adjacent patterns in the codebases show that there's a logical place for you to add a test, you may do so. However, do not add tests to codebases with no tests.",
	"",
	"Similarly, once you're confident in correctness, you can suggest or use formatting commands to ensure that your code is well formatted. If there are issues you can iterate up to 3 times to get formatting right, but if you still can't manage it's better to save the user time and present them a correct solution where you call out the formatting in your final message. If the codebase does not have a formatter configured, do not add one.",
	"",
	"For all of testing, running, building, and formatting, do not attempt to fix unrelated bugs. It is not your responsibility to fix them. (You may mention them to the user in your final message though.)",
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
	},
	// Sol-authored work gets a review from Grok 4.7 in another model family; lightweight
	// roles and agents (browser, smol, scout, sonic, tiny, commit) inherit the base config.
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
