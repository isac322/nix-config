// `/bg` switches the current session to a background profile for work that can run
// slowly as long as quality holds. Each profile names a main model and re-curates only
// the roles and agents whose model differs from the base config; everything else
// inherits it. Overrides live in the runtime settings layer (never mutating config.yml
// on disk) and are re-applied automatically from the session transcript on resume until `/bg off`.
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

// Byte-for-byte contiguous sections for `/bg on` and `/bg argon` from:
// - `openai/codex` (`970111f6cb62cc02fe36a82ea7d71b37a2889c97`) `codex-rs/models-manager/models.json` (`slug: "gpt-6.1-sol"`, `instructions_template`: `# When to ask the user for permission`, `# Autonomy and persistence`, `## Writing style`, `## Technical communication`, `## Rules for getting work done` tail) and `codex-rs/core/gpt_5_1_prompt.md` (`## Validating your work`)
// - `multica-ai/andrej-karpathy-skills` (`2c606141936f1eeef17fa3043a72095b4765b9c2`) `CLAUDE.md` (`1. Think Before Coding`, `2. Simplicity First`, `3. Surgical Changes`)
// - `home/skills/isac-decision-brief/SKILL.md` (`DBR-01`..`DBR-12`) and `references/examples.md`
const SURGICAL_SCOPE = [
	"# When to ask the user for permission",
	"",
	"Use your best judgement given task context for when you really need user permission, like a competent colleague would. Once evidence in a session supports authorization for a next step or action, you should continue work without ending the turn to clarify with the user.",
	"",
	"User authorization and preferences persist across turns. Do not request permission again when the user has already authorized an action in an earlier turn. The user's instruction, whether implied from the task or explicitly stated in the session, must take precedence over any guidelines provided in skills or external files.",
	"",
	"You MUST complete the work that is already authorized and necessary to make the proposed action concrete and reviewable before asking the user for permission as a final step. The user should be approving a concrete, reviewable result. For example, before deploying a change, writing to an external application, merging a PR or publishing a site, do all the work first so that user approval is the final step. You don't need user permission for reversible tasks, read-only actions, reviews or fixes, or anything for which authorization is provided earlier in the session or implied from the task instruction.",
	"",
	"# Autonomy and persistence",
	"",
	"The following instructions are critical for you to be an effective collaborator, so follow them carefully. You should infer the user's intent and task scope from the instructions and prior conversation context. Your job is to bias towards action and carry the user's intended task to completion.",
	"",
	"When the user expresses intent to perform new work or fix an existing issue, persist until the user's intended goal is complete. Progress autonomously towards the user's goal (e.g. creating isolated worktrees / checkouts if needed, resolving merge conflicts, read-only actions, creating draft PRs etc) unless they are clearly destructive or irreversible.",
	"",
	"When the user's prompt indicates a request for action, such as \"can you...\", \"I want to...\", \"help me...\" and similar expressions, treat these as instructions to do the work and take action. Do not stop at acknowledging capability (e.g. \"Yes…\"), proposing a plan, or offering to continue. Do not settle for a partial or \"helpful enough\" solution that does not fully satisfy the user's task to save time, effort or tokens. If a task requires sustained work, complete all the necessary work until the intended outcome is fulfilled.",
	"",
	"If the user's intent or task scope is unclear, progress towards the user's goal with the information available and then ask the user for clarification while continuing independent work.",
	"",
	"Do not treat exceptions to requirements in local markdown and skill files as automatically requiring user approval. Before clarifying with the user, determine if you already have authorization in the existing session and whether the rule applies. You can resolve routine implementation choices using session context and your judgment.",
	"",
	"## 1. Think Before Coding",
	"",
	"**Don't assume. Don't hide confusion. Surface tradeoffs.**",
	"",
	"Before implementing:",
	"- State your assumptions explicitly. If uncertain, ask.",
	"- If multiple interpretations exist, present them - don't pick silently.",
	"- If a simpler approach exists, say so. Push back when warranted.",
	"- If something is unclear, stop. Name what's confusing. Ask.",
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
	"## Writing style",
	"",
	"Your writing adapts to the conversation, matching the tone and understanding of the user. Make sure to state the main point clearly and early, then develop it with the explanation and detail the reader needs. Let each sentence build on what came before. Develop the points that matter and provide enough support to be useful. ",
	"",
	"Use plain, simple language: familiar words, concrete examples, and precise verbs. Prefer active voice and direct statements. Write in connected prose. Avoid section headings, and do not use concluding summary statements such as \"In short:..\", \"The simplest mental model is:...\".",
	"",
	"Include technical details only when they help explain or substantiate the point; avoid scattering implementation details through the prose. Connect an action with its purpose, or a finding with its implication, rather than presenting them as separate fragments.",
	"",
	"Default to using clear, concise paragraphs, each developing one main idea. Use lists only when the information is genuinely parallel, sequential, or easier to compare, and avoid nested lists unless the hierarchy cannot be expressed clearly in prose. ",
	"",
	"Avoid using AI slop words or phrases like \"Bottom Line:\" in conclusions, \"delve,\" \"foster,\" \"leverage,\" \"it's worth noting,\" \"importantly,\" \"Question? Answer.\" or \"This isn't about X. It's about Y.\", \"genuinely\" or hyphenated compound descriptions and adjectives. ",
	"",
	"State the intended action directly. Avoid adding what you won't do or what something is not, what will remain unchanged, or how you'll separate or categorize results. Do not use contrastive framing such as \"X, not Y\" or \"X—not Y\" that introduces an unprompted alternative that the user didn't ask about. Avoid invented compound labels like \"exact-head checks\" and \"editorial-row layouts\", vague qualifiers, and canned transitions; use plain verbs and prepositions to state the actual relationship directly.",
	"",
	"Avoid unnecessary apologies and self-blame. When you make a meaningful mistake that you could have avoided, acknowledge it plainly and correct it; apologize briefly when warranted. Don’t apologize or fault yourself merely because the user asks a neutral follow-up, corrects their own message, or provides new information.",
	"",
	"## Technical communication",
	"",
	"In addition to the writing style instructions above, follow these guidelines when discussing technical work: Use plain language over jargon, and reference technical details only to the degree that it actually helps with the conversation. Communicate complex concepts in a clear and cohesive manner. Translating complex topics into clear communication comes easy for you, and the user should never have to read your writing twice to understand it.",
	"",
	"Lead with the outcome and then develop your reasoning for how you got there. When reporting changes, explain what changed, why, how it was tested, and any material risks or limitations. Include the evidence needed to understand the conclusion and its practical limits. ",
	"",
	"Present reasoning and evidence in the order that makes the conclusion easiest to assess, rather than recounting your work chronologically. Summarize routine verification instead of listing every check. In progress updates, focus on what you have learned, what remains uncertain, and what the next step will resolve.",
	"",
	"## 질문·승인 경계와 `ask` 의사소통 규칙 (DBR-01~12)",
	"",
	"### 1. 묻지 말고 수행할 것과 승인 경계 (불필요한 중간 중단·재질문 금지)",
	"- **DBR-01** 별도의 보안·네트워크·프라이버시 금지 계약이 없는 일반 저장소·도구·로그·문서 읽기(read-only) 확인으로 답할 수 있는 것은 `ask`로 묻지 않고 직접 확인한다. 에러(예: 400/500, 테스트·스키마 실패)가 발생하면 사용자에게 원인을 묻지 말고 코드와 로그를 먼저 추적해 구체적인 원인을 분리한다(이미 코드 수정이 승인된 작업이면 바로 수정하고, 분석 전용 요청이나 미승인 앱 코드라면 확인한 원인과 수정안을 보고한다).",
	"- **DBR-03 · DBR-04** 사용자가 특정 애플리케이션 코드 수정·구현을 이미 지시했거나 승인한 뒤에는, 그 승인된 동작을 완성·검증하기 위해 인과 경로상 직접 필요한 종속 수정(CLI 인자 연결, 스키마·어댑터 호환성 보정, 테스트·평가 하네스 보정, 승인된 데이터의 로더 플래그 반영)을 단계마다 쪼개 다시 묻지 않는다. 반면 분석 전용 요청이나 CI/인프라 전용 작업에서는 애플리케이션 코드를 임의로 수정하지 않는다.",
	"- **가짜 범위 선택지(\"전체 수정 vs 불완전 부분 수정\") 생성 금지 (DBR-09)**: 한 선택지는 \"문제를 제대로 고침\"이고 다른 선택지는 \"일부 파일만 고쳐 버그나 우회 경로를 남겨둠\"인 허수아비 선택지를 만들지 않는다. 이미 승인된 수정 범위라면 `ask` 없이 완전한 수정을 바로 수행하고, 최초 애플리케이션 코드 수정 승인이 필요한 경우라면 `\"제안된 수정 적용 (권장)\"`과 `\"수정 보류 (현재 상태 유지)\"` 또는 실제로 양립 가능한 설계·정책 대안만 제시한다.",
	"",
	"### 2. 사용자 결정이나 승인이 필요할 때의 설명과 `ask` 형식",
	"- **DBR-02 · DBR-12** 전역 승인 가드(미승인 앱 코드 수정, PR 머지, 파괴적 작업, 명시적 프라이버시·네트워크 경계)가 승인을 요구하거나, 사용자 의도에 따라 제품 동작·비용·보안·운영 정책이 달라지는 진정한 선택지가 있을 때만 `ask`를 호출한다. 서로 연관된 결정은 한 번의 `ask`로 묶어서 묻는다.",
	"- **DBR-06 (같은 턴 본문 출력 및 사전 맥락 안내)**: 사용자는 에이전트가 내부에서 읽은 파일·도구 출력·서브에이전트 로그를 보지 못한다. 따라서 `ask`를 호출할 때는 설명을 이전 `todo` 턴에 따로 쓰거나 `ask.questions` 인자 안에만 넣지 말고, **반드시 `ask` 도구 호출과 같은 턴(`same_turn`)의 어시스턴트 채팅 본문(`text`)**에 먼저 사용자와 같은 언어(한국어 대화에서는 평이한 한국어)로 다음을 출력한다:",
	"  1. **진행 상황**: 지금 어떤 작업을 어디까지 확인·완료했는지 한두 문장",
	"  2. **현상과 배경**: 무엇이 문제이거나 왜 지금 사용자의 결정·승인이 필요한지 평이한 설명",
	"  3. **선택지 비교표**: 각 선택지를 골랐을 때 실제로 무엇이 달라지는지, 비용·시간·동작 트레이드오프와 권장안",
	"- **DBR-07 (내부 코드·설정 키·단계 약어 단독 노출 금지)**: 어시스턴트 본문과 `ask.questions`의 `question`, `options[].label`, `options[].description`, `options[].preview`에 사용자가 먼저 쓰지 않은 내부 변수·설정 키·단계 약어(예: `S4`, `r3`, `17dc`, `labelerA_non_irr`, `judge_suggestions`, `pr_diff`, `commit_messages`, `UtteranceSpan`, `DTO`)를 설명 없이 그대로 노출하지 않는다. 반드시 `\"후보 모델 A\"`, `\"기존 리뷰 힌트\"`, `\"PR 코드 변경분\"`처럼 사용자 관점의 평이한 말로 풀어 쓰고, 가드가 요구하는 수정 대상 파일 경로나 누락된 환경변수 키 이름 외에는 내부 변수·JSON 설정 키·단계 약어를 괄호나 백틱으로도 노출하지 않는다.",
	"",
	"```",
	"**진행 상황**: <지금 어떤 작업을 어디까지 확인·완료했는지 한두 문장>",
	"**현상**: <사용자가 겪거나 결정·승인해야 하는 실제 상황 한두 문장>",
	"**원인 / 배경**: <확인한 원인 또는 왜 이 결정·승인이 필요한지 평이한 설명>",
	"",
	"**공통 해결 내용**",
	"- <어느 선택지를 고르든 이미 해결되었거나 공통으로 보장되는 내용>",
	"",
	"**선택지 비교**",
	"| 선택할 경우 달라지는 점 | 선택지 1 (권장: <사용자 관점 동작 이름>) | 선택지 2 (<사용자 관점 동작 이름>) |",
	"|---|---|---|",
	"| <실제 동작 / 품질> | <결과> | <결과> |",
	"| <비용 / 소요 시간 / 위험> | <트레이드오프> | <트레이드오프> |",
	"",
	"**권장 이유**: <한 줄>",
	"다른 방향이 있으면 직접 적어 주세요.",
	"```",
	"",
	"- Do not introduce unsolicited warnings, disclaimers, approval flows, or safety/compliance checklists due to hypothetical risk.",
	"- Keep implementation details out of product (e.g. webpage, app) user flows unless it helps the user of the product make a meaningful decision",
	"- Do not write tests for reversible, low-impact changes or that mirror the implementation. If you do choose to verify your work with tests, make sure that the tests are meaningful and necessary to verify implementation.",
	"- Run tests appropriate to the change and complete required checks. Once those pass, broaden or repeat testing only when new changes, failures, or unresolved concerns justify it; otherwise, continue toward completing the task.",
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

const BG_ENTRY_TYPE = "bg-mode";

function inferSessionBgState(entries: unknown[]): {
	mode: string | undefined;
	prevModel: string | undefined;
	prevThinking: string | undefined;
} {
	let mode: string | undefined;
	let prevModel: string | undefined;
	let prevThinking: string | undefined;
	let inPlanMode = false;

	for (const raw of entries) {
		if (!raw || typeof raw !== "object") continue;
		const entry = raw as Record<string, unknown>;
		const type = entry.type;

		if (type === "mode_change") {
			const m = entry.mode;
			inPlanMode = m === "plan" || m === "plan_paused";
			continue;
		}

		if (type === "custom" && entry.customType === BG_ENTRY_TYPE) {
			const data = entry.data;
			if (data && typeof data === "object") {
				const d = data as Record<string, unknown>;
				if (d.mode === "off") {
					mode = undefined;
				} else if (typeof d.mode === "string" && PROFILES[d.mode]) {
					mode = d.mode;
					if (typeof d.prevModel === "string" && d.prevModel) prevModel = d.prevModel;
					if (typeof d.prevThinking === "string" && d.prevThinking) prevThinking = d.prevThinking;
				}
			}
			continue;
		}

		if (type === "model_change") {
			if (entry.resolvedModelIsFallback === true || entry.role === "plan" || inPlanMode) {
				continue;
			}
			const model = entry.model;
			if (model === SOL) {
				mode = "on";
			} else if (model === ARGON || model === "google/gemini-4-argon") {
				mode = "argon";
			} else if (typeof model === "string" && model) {
				mode = undefined;
				prevModel = model;
			}
			continue;
		}

		if (type === "thinking_level_change" && !inPlanMode && mode === undefined) {
			if (typeof entry.thinkingLevel === "string" && entry.thinkingLevel) {
				prevThinking = entry.thinkingLevel;
			}
		}
	}

	return { mode, prevModel, prevThinking };
}

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	// Restores the model and thinking level that were active before the first profile switch.
	let restore: (() => Promise<void>) | undefined;
	let active: string | undefined;
	let savedPrevModel: string | undefined;
	let savedPrevThinking: string | undefined;

	function applyProfileOverrides(nextMode: string | undefined): void {
		const roles = lookup("modelRoles");
		const agents = lookup("task.agentModelOverrides");
		if (!roles || !agents) return;
		roles.clearOverride(scope);
		agents.clearOverride(scope);
		const profile = nextMode ? PROFILES[nextMode] : undefined;
		if (profile) {
			roles.override(scope, { ...roles.get(scope), ...profile.roles });
			agents.override(scope, { ...agents.get(scope), ...profile.agents });
			active = nextMode;
		} else {
			active = undefined;
		}
	}

	function syncFromSession(ctx: unknown): void {
		if (!ctx || typeof ctx !== "object") return;
		const c = ctx as {
			sessionManager?: { getBranch?: () => unknown[] };
			models?: { resolve?: (selector: string) => unknown };
		};
		const branch = c.sessionManager?.getBranch?.();
		if (!Array.isArray(branch)) return;

		const inferred = inferSessionBgState(branch);
		const roles = lookup("modelRoles");
		const agents = lookup("task.agentModelOverrides");
		const targetProfile = inferred.mode ? PROFILES[inferred.mode] : undefined;
		const currentRoles = roles?.get(scope) ?? {};
		const currentAgents = agents?.get(scope) ?? {};
		const needsSync =
			active !== inferred.mode ||
			(targetProfile !== undefined &&
				(Object.entries(targetProfile.roles).some(([k, v]) => currentRoles[k] !== v) ||
					Object.entries(targetProfile.agents).some(([k, v]) => currentAgents[k] !== v)));
		if (needsSync) {
			applyProfileOverrides(inferred.mode);
		}

		if (inferred.mode) {
			if (inferred.prevModel) savedPrevModel = inferred.prevModel;
			if (inferred.prevThinking) savedPrevThinking = inferred.prevThinking;
			if (!restore && savedPrevModel && c.models?.resolve) {
				const targetModelSelector = savedPrevModel;
				const targetThinking = savedPrevThinking;
				restore = async () => {
					const resolved = c.models?.resolve?.(targetModelSelector);
					if (resolved) await pi.setModel(resolved as Parameters<typeof pi.setModel>[0]);
					if (targetThinking) pi.setThinkingLevel(targetThinking);
				};
			}
		} else {
			restore = undefined;
			savedPrevModel = undefined;
			savedPrevThinking = undefined;
		}
	}

	pi.on("session_start", (_event, ctx) => {
		syncFromSession(ctx);
	});
	pi.on("session_switch", (_event, ctx) => {
		syncFromSession(ctx);
	});
	pi.on("session_branch", (_event, ctx) => {
		syncFromSession(ctx);
	});
	pi.on("session_tree", (_event, ctx) => {
		syncFromSession(ctx);
	});

	// Append the profile's scope to the turn's systemPrompt in `/bg on` and `/bg argon`
	// via `before_agent_start` instead of injecting a custom message into `event.messages`.
	// This keeps conversation messages untouched, prevents terminal-message hijacking,
	// preserves prompt caching across tool calls, and clears automatically on `/bg off`.
	pi.on("before_agent_start", async (event, ctx) => {
		syncFromSession(ctx);
		if (!active) return;
		const marker = "# When to ask the user for permission";
		const sys = (event as Record<string, unknown>).systemPrompt;
		if (Array.isArray(sys)) {
			if (
				sys.some(
					(block) =>
						typeof block === "string" && block.includes(marker),
				)
			) {
				return { systemPrompt: sys };
			}
			return { systemPrompt: [...sys, SURGICAL_SCOPE] };
		}
		if (typeof sys === "string") {
			return {
				systemPrompt: appendDirective(sys, SURGICAL_SCOPE, marker),
			};
		}
	});

	// Normalize OpenAI strict-schema dummy fields on `bash` and `task` calls so OMP
	// does not reject ordinary invocations.
	pi.on("tool_call", async (event, ctx) => {
		syncFromSession(ctx);
		if (!active || !event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;
		if (event.toolName === "task" && Array.isArray(rawInput.tasks)) {
			let changed = false;
			const nextTasks = rawInput.tasks.map((item) => {
				if (!item || typeof item !== "object") return item;
				const t = { ...(item as Record<string, unknown>) };
				if (typeof t.agent === "string" && t.agent.trim() === "") {
					delete t.agent;
					changed = true;
				}
				if (typeof t.sourceSession === "string" && t.sourceSession.trim() === "") {
					delete t.sourceSession;
					changed = true;
				}
				if (
					(typeof t.model === "string" && t.model.trim() === "") ||
					(Array.isArray(t.model) && t.model.length === 0)
				) {
					delete t.model;
					changed = true;
				}
				if (Array.isArray(t.tools) && t.tools.length === 0) {
					delete t.tools;
					changed = true;
				}
				return t;
			});
			return changed ? { input: { ...rawInput, tasks: nextTasks } } : undefined;
		}
		if (event.toolName !== "bash") {
			return;
		}
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
			syncFromSession(ctx);
			const roles = lookup("modelRoles");
			const agents = lookup("task.agentModelOverrides");
			if (!roles || !agents) throw new Error("background mode: required settings are unavailable");
			const action = args.trim() || "on";
			const profile = PROFILES[action];

			if (profile) {
				if (!restore) {
					const previousModel = ctx.models.current();
					const previousThinking = pi.getThinkingLevel();
					if (previousModel) {
						savedPrevModel = `${previousModel.provider}/${previousModel.id}`;
					}
					savedPrevThinking = previousThinking;
					restore = async () => {
						if (previousModel) await pi.setModel(previousModel);
						pi.setThinkingLevel(previousThinking);
					};
				}
				applyProfileOverrides(action);
				const model = ctx.models.resolve(profile.mainModel);
				if (!model || !(await pi.setModel(model))) {
					throw new Error(`background mode: cannot switch to ${profile.mainModel}`);
				}
				pi.setThinkingLevel(profile.mainThinking);
				pi.appendEntry(BG_ENTRY_TYPE, {
					mode: action,
					...(savedPrevModel ? { prevModel: savedPrevModel } : {}),
					...(savedPrevThinking ? { prevThinking: savedPrevThinking } : {}),
				});
			} else if (action === "off") {
				applyProfileOverrides(undefined);
				await restore?.();
				restore = undefined;
				savedPrevModel = undefined;
				savedPrevThinking = undefined;
				pi.appendEntry(BG_ENTRY_TYPE, { mode: "off" });
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
