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
const SONNET = "anthropic/claude-sonnet-5-5";

// Byte-for-byte contiguous sections from:
// - openai/codex `codex-rs/core/gpt_5_1_prompt.md` (`Autonomy and Persistence`, `Sharing progress updates`, `Validating your work`)
// - openai/codex `codex-rs/core/gpt_5_2_prompt.md` (`Task execution`, coding guidelines, `Presenting your work` brevity relaxation)
// - openai/codex `codex-rs/core/gpt-5.2-codex_prompt.md` (`Presenting your work and final message`)
// - forrestchang/andrej-karpathy-skills `CLAUDE.md` (`2. Simplicity First`, `3. Surgical Changes`)
const SURGICAL_SCOPE = [
	"## Autonomy and Persistence",
	"Persist until the task is fully handled end-to-end within the current turn whenever feasible: do not stop at analysis or partial fixes; carry changes through implementation, verification, and a clear explanation of outcomes unless the user explicitly pauses or redirects you.",
	"",
	"## Task execution",
	"",
	"You are a coding agent. You must keep going until the query or task is completely resolved, before ending your turn and yielding back to the user. Persist until the task is fully handled end-to-end within the current turn whenever feasible and persevere even when function calls fail. Only terminate your turn when you are sure that the problem is solved. Autonomously resolve the query to the best of your ability, using the tools available to you, before coming back to the user. Do NOT guess or make up an answer.",
	"",
	"If completing the user's task requires writing or modifying files, your code and final answer should follow these coding guidelines, though user instructions (i.e. AGENTS.md) may override these guidelines:",
	"",
	"- Fix the problem at the root cause rather than applying surface-level patches, when possible.",
	"- Avoid unneeded complexity in your solution.",
	"- Do not attempt to fix unrelated bugs or broken tests. It is not your responsibility to fix them. (You may mention them to the user in your final message though.)",
	"- Update documentation as necessary.",
	"- Keep changes consistent with the style of the existing codebase. Changes should be minimal and focused on the task.",
	"",
	"## 2. Simplicity First",
	"",
	"**Minimum code that solves the problem. Nothing speculative.**",
	"",
	"- No features beyond what was asked.",
	"- No abstractions for single-use code.",
	"- No \"flexibility\" or \"configurability\" that wasn't requested.",
	"- No error handling for impossible scenarios.",
	"- If you write 200 lines and it could be 50, rewrite it.",
	"",
	"Ask yourself: \"Would a senior engineer say this is overcomplicated?\" If yes, simplify.",
	"",
	"## 3. Surgical Changes",
	"",
	"**Touch only what you must. Clean up only your own mess.**",
	"",
	"When editing existing code:",
	"- Don't \"improve\" adjacent code, comments, or formatting.",
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
	"For especially longer tasks that you work on (i.e. requiring many tool calls, or a plan with multiple steps), you should provide progress updates back to the user at reasonable intervals. Except when calling `ask`, these updates should be structured as a concise sentence or two (no more than 8-10 words long) recapping progress so far in plain language: this update demonstrates your understanding of what needs to be done, progress so far (i.e. files explores, subtasks complete), and where you're going next.",
	"",
	"Before doing large chunks of work that may incur latency as experienced by the user (i.e. writing a new file), you should send a concise message to the user with an update indicating what you're about to do to ensure they know what you're spending time on. Don't start editing or writing large files before informing the user what you are doing and why.",
	"",
	"Brevity is very important as a default. You should be very concise (i.e. no more than 10 lines), but can relax this requirement for tasks where additional detail and comprehensiveness is important for the user's understanding.",
	"",
	"- Skip heavy formatting for simple confirmations.",
	"",
	"- The user does not command execution outputs. When asked to show the output of a command (e.g. `git show`), relay the important details in your answer or summarize the key lines so the user understands the result.",
	"",
	"- Tone: collaborative, concise, factual; present tense, active voice; self‑contained; no \"above/below\"; parallel wording.",
	"",
	"- When calling `ask`, the popup only displays 4 lines of `question` and the user cannot see tool or subagent outputs: in your message text before the `ask` tool call (never only inside `ask.questions`), output a self-contained plain-Korean brief with `**현상**` (including whether any previously reported issue is already resolved, with exact metrics/counts), `**원인**` (every confirmed defect from the files you inspected, citing exact `PR #...`, `file:line`, retry/fallback amplification counts, and any stripped or swallowed error codes/headers), `**공통 해결 내용**`, and a `**선택지 비교**` markdown table. In `ask`, write each `options[].label` itself (not just `description`) as the concrete user-visible behavior or fix target (e.g. `\"kqueue fd 누수만 수정 (P1)\"`, NEVER bare ID labels like `\"P1만 수정\"`, `\"P2만 수정\"`, `\"A+B\"`, or `\"B5\"`), and when offering scope options between a partial fix and the complete end-to-end fix, recommend the complete option (for a simple PR merge confirmation naming the PR and target branch, one sentence is enough).",
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
	},
	// Sol-authored work gets a review from Grok 4.7 first, falling back to Sonnet 5.5 in
	// another model family when Grok quota is depleted; advisor and lightweight roles/agents
	// (browser, smol, scout, sonic, tiny, commit) inherit the base config.
	agents: {
		reviewer: `${GROK}:low, ${SONNET}:medium`,
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
		agents: SOL_PROFILE.agents,
	},
};

const SUBCOMMANDS = [
	{ name: "on", description: "Sol main agent, roles re-curated around it" },
	{ name: "argon", description: "Trial: Gemini 4 Argon main agent, Sol implementer" },
	{ name: "off", description: "Restore the base config and the previous model" },
	{ name: "status", description: "Show the active profile and key roles" },
];

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
	// Append `SURGICAL_SCOPE` to the turn's systemPrompt in `/bg on` via `before_agent_start`
	// instead of injecting a custom message into `event.messages`. This keeps conversation
	// messages untouched, prevents terminal-message hijacking, preserves prompt caching
	// across tool calls, and clears automatically on `/bg argon` or `/bg off`.
	pi.on("before_agent_start", async (event) => {
		if (active !== "on") return;
		const sys = (event as Record<string, unknown>).systemPrompt;
		if (Array.isArray(sys)) {
			if (
				sys.some(
					(block) =>
						typeof block === "string" &&
						block.includes("## Autonomy and Persistence"),
				)
			) {
				return { systemPrompt: sys };
			}
			return { systemPrompt: [...sys, SURGICAL_SCOPE] };
		}
		if (typeof sys === "string") {
			return {
				systemPrompt: appendDirective(
					sys,
					SURGICAL_SCOPE,
					"## Autonomy and Persistence",
				),
			};
		}
	});

	// Normalize OpenAI strict-schema dummy `name`/`ready` on `bash` calls so OMP's bash
	// tool does not reject ordinary commands as invalid service-mode invocations.
	pi.on("tool_call", async (event) => {
		if (!active || event.toolName !== "bash" || !event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;
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
		if (nextBash.timeout === 0 && nextBash.async !== true) nextBash.timeout = 300;
		return { input: nextBash };
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
			} else if (action === "off") {
				roles.clearOverride(scope);
				agents.clearOverride(scope);
				await restore?.();
				restore = undefined;
				active = undefined;
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
