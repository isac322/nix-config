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
	"For especially longer tasks that you work on (i.e. requiring many tool calls, or a plan with multiple steps), you should provide progress updates back to the user at reasonable intervals. These updates should be structured as a concise sentence or two (no more than 8-10 words long) recapping progress so far in plain language: this update demonstrates your understanding of what needs to be done, progress so far (i.e. files explores, subtasks complete), and where you're going next.",
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

// Byte-for-byte contiguous sections from:
// - Claude Code community `CLAUDE.md` pre-ask rule
// - `home/skills/isac-decision-brief/SKILL.md` (`DBR-06`, `DBR-07`, `DBR-09`)
// - `home/skills/isac-decision-brief/references/examples.md` (`1. 승인·결정 질문 (DBR-06, DBR-08)`)
const DBR_CONTRACT = [
	"FOR EACH STAGE OF REVIEW: output the explanation and pros and cons of each stage's questions AND your opinionated recommendation and why, and then use AskUserQuestion.",
	"",
	"- **DBR-06** [U] 질문은 사전 맥락 없이 읽혀야 한다. 순서: 사용자가 보는 현상 → 원인 → 선택지마다 무엇이 바뀌는지와 트레이드오프 → 권장안. 평이한 한국어로 쓴다. 복수 선택지를 비교할 때는 선택지들이 공통으로 해결하는 것을 먼저 밝히고, 내부 구현 나열 대신 사용자가 실제로 행동할 때 상황별로 무엇이 달라지는지(작동 여부 비교표 등)를 본문에서 대조한다.",
	"- **DBR-07** [U] 내부 API·kind 이름·설계 라벨만으로 된 선택지(\"A만 (N개 전체)\", \"A + B\")를 쓰지 않는다. 식별자가 필요하면 사용자 효과를 먼저 풀어 쓰고 식별자는 괄호에 둔다.",
	"",
	"- **DBR-09** [U] 사용자가 근본 원인 해결이나 제품 완성을 goal·brief로 요구한 작업에서 범위 선택지(좁은 수정 / 전체 수정 / 중단)를 낼 때는 완전한 옵션을 권장한다. 런타임 수정과 나머지 기능 검증까지 포함하고, 임시 우회 대신 제품 lifecycle을 구현하는 옵션이다.",
	"",
	"## 1. 승인·결정 질문 (DBR-06, DBR-08)",
	"",
	"```",
	"**현상**: <사용자가 보는 증상 한두 문장. 언제, 어디서, 무엇이 안 되는지>",
	"**원인**: <확인한 원인. 근거는 파일:줄이나 실행 결과 한 줄. 추론이면 추론이라고 적는다>",
	"",
	"**공통 해결 내용**",
	"- <선택지들이 공통으로 해결하는 문제 범위와 기본 해결 내용>",
	"",
	"**선택지 비교**",
	"| 내가 하는 행동 / 상황 | 선택지 1 (권장: <사용자 효과 이름>) | 선택지 2 (<사용자 효과 이름>) |",
	"|---|---|---|",
	"| <상황 1> | 작동함 (<가시 결과>) | 작동 안 함 (<제약·남는 문제>) |",
	"| <상황 2> | <가시 결과> | <가시 결과> |",
	"",
	"- 선택지 1 영향: <파일·리소스 preview>, 트레이드오프: <비용·위험>",
	"- 선택지 2 영향: <…>, 트레이드오프: <…>",
	"- 중단: 지금 상태로 두면 <남는 문제>",
	"",
	"**권장 이유**: <한 줄>",
	"다른 방향이 있으면 직접 적어 주세요.",
	"```",
].join("\n");

const INVESTIGATION_TOOLS: Record<string, true> = {
	read: true,
	grep: true,
	glob: true,
	find: true,
	bash: true,
	eval: true,
	task: true,
};

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
	let postInvestigationTextLen = 0;
	let guardedOnce = false;
	// Append `SURGICAL_SCOPE` to the turn's systemPrompt in `/bg on` via `before_agent_start`
	// instead of injecting a custom message into `event.messages`. This keeps conversation
	// messages untouched, prevents terminal-message hijacking, preserves prompt caching
	// across tool calls, and clears automatically on `/bg argon` or `/bg off`.
	pi.on("before_agent_start", async (event) => {
		postInvestigationTextLen = 0;
		guardedOnce = false;
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

	pi.on("message_end", async (event) => {
		if (!active) return;
		const msg = (event as Record<string, unknown>)?.message as Record<string, unknown> | undefined;
		if (!msg) return;
		if (msg.role === "user") {
			postInvestigationTextLen = 0;
			guardedOnce = false;
		} else if (msg.role === "toolResult") {
			const tname = String(msg.toolName ?? "");
			if (tname === "ask" && !msg.isError) {
				postInvestigationTextLen = 0;
				guardedOnce = false;
			} else if (INVESTIGATION_TOOLS[tname] === true) {
				const content = Array.isArray(msg.content) ? msg.content : [];
				const first = content[0] as Record<string, unknown> | undefined;
				const firstText = typeof first?.text === "string" ? first.text : "";
				if (!firstText.startsWith("[Skill file:")) {
					postInvestigationTextLen = 0;
					guardedOnce = false;
				}
			}
		} else if (msg.role === "assistant" && Array.isArray(msg.content)) {
			const hasInvTool = msg.content.some((c) => {
				const item = c as Record<string, unknown> | null;
				return (
					item !== null &&
					typeof item === "object" &&
					item.type === "toolCall" &&
					INVESTIGATION_TOOLS[String(item.name ?? "")] === true
				);
			});
			if (hasInvTool && !guardedOnce) {
				postInvestigationTextLen = 0;
			} else {
				for (const c of msg.content) {
					const item = c as Record<string, unknown> | null;
					if (
						item !== null &&
						typeof item === "object" &&
						item.type === "text" &&
						typeof item.text === "string"
					) {
						postInvestigationTextLen += item.text.trim().length;
					}
				}
			}
		}
	});

	// Normalize OpenAI strict-schema dummy `name`/`ready` on `bash` calls, enforce pre-ask
	// decision briefs on `ask` calls, and propagate surgical scope rules to `task` (Sol:high)
	// subagents via `item.task`.
	pi.on("tool_call", async (event) => {
		if (!active || !event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;

		if (event.toolName === "ask" && !guardedOnce) {
			const qs = Array.isArray(rawInput.questions) ? rawInput.questions : [];
			const qBlob = JSON.stringify(qs);
			const isSimpleMergeConfirm =
				/squash|merge|머지/i.test(qBlob) &&
				/(PR\s*#\d+|#\d+)/i.test(qBlob) &&
				/main|master/i.test(qBlob);
			const hasBareInternalLabel = qs.some((q) => {
				const qObj = q as Record<string, unknown> | null;
				const opts = Array.isArray(qObj?.options) ? qObj.options : [];
				return opts.some((o) => {
					const oObj = o as Record<string, unknown> | null;
					const lbl = String(oObj?.label ?? "").trim();
					return /^([PA]\d+|B\d+)(\s*[+·,]\s*([PA]\d+|B\d+))*\s*(만\s*(수정|구현|적용|승인)|수정|구현|적용|승인)?\s*(\(권장\)|\(Recommended\))?$/i.test(
						lbl,
					);
				});
			});
			if ((!isSimpleMergeConfirm && postInvestigationTextLen < 150) || hasBareInternalLabel) {
				guardedOnce = true;
				return {
					block: true,
					reason: `Pre-Ask Decision Brief Required (user cannot see tool/subagent outputs, and ask-dialog truncates question to 4 lines):\n\n${DBR_CONTRACT}\n\nOutput the full Korean decision brief in your assistant message text first (including concrete PR/file:line/telemetry facts and answering any diagnostic questions the user asked), then call \`ask\` in the same turn with user-effect option labels (and concrete PR/file:line in question).`,
				};
			}
			return;
		}

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
					const next = appendDirective(
						item.task,
						SURGICAL_SCOPE,
						"## Autonomy and Persistence",
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
			const next = appendDirective(
				rawInput.task,
				SURGICAL_SCOPE,
				"## Autonomy and Persistence",
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
			} else if (action === "off") {
				roles.clearOverride(scope);
				agents.clearOverride(scope);
				await restore?.();
				restore = undefined;
				active = undefined;
				postInvestigationTextLen = 0;
				guardedOnce = false;
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
