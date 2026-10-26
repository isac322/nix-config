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
	"- When calling `ask`, the popup only displays 4 lines of `question` and the user cannot see tool or subagent outputs: in your message text before the `ask` tool call (never only inside `ask.questions`), output a self-contained plain-Korean brief with `**현상**` (including whether any previously reported issue is already resolved, with exact metrics/counts), `**원인**` (every confirmed defect from the files you inspected, citing exact `PR #...`, `file:line`, retry/fallback amplification counts, and any stripped or swallowed error codes/headers), `**공통 해결 내용**`, and a `**선택지 비교**` markdown table. In `ask`, write each `options[].label` itself (not just `description`) as the concrete user-visible behavior or fix target (e.g. `\"kqueue fd 누수만 수정 (P1)\"`, NEVER bare ID labels like `\"P1만 수정\"`, `\"P2만 수정\"`, `\"A+B\"`, or `\"B5\"`), and when offering scope options between a partial fix and the complete end-to-end fix, recommend the complete option.",
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

// Byte-for-byte contiguous sections for `/bg argon` from:
// - `openai/codex` (`970111f6cb62cc02fe36a82ea7d71b37a2889c97`) `codex-rs/core/gpt_5_1_prompt.md`, `gpt_5_2_prompt.md`, `gpt-5.2-codex_prompt.md`, and `codex-rs/models-manager/models.json` (`gpt-6.1-sol`)
// - `multica-ai/andrej-karpathy-skills` (`2c606141936f1eeef17fa3043a72095b4765b9c2`) `CLAUDE.md` (`1. Think Before Coding`, `2. Simplicity First`, `3. Surgical Changes`)
// - `@anthropic-ai/claude-code` `2.1.310` (`GIT_SHA: 0d2056ecf42d9452a8cd8e054600024e7c557add`)
// - `home/skills/isac-decision-brief/SKILL.md:12-33` and `references/examples.md:5-26`
const ARGON_SCOPE = [
	"# Autonomy and Persistence",
	"Persist until the task is fully handled end-to-end within the current turn whenever feasible: do not stop at analysis or partial fixes; carry changes through implementation, verification, and a clear explanation of outcomes unless the user explicitly pauses or redirects you.",
	"",
	"## Task execution",
	"",
	"You are a coding agent. You must keep going until the query or task is completely resolved, before ending your turn and yielding back to the user. Persist until the task is fully handled end-to-end within the current turn whenever feasible and persevere even when function calls fail. Only terminate your turn when you are sure that the problem is solved. Autonomously resolve the query to the best of your ability, using the tools available to you, before coming back to the user. Do NOT guess or make up an answer.",
	"",
	"You MUST adhere to the following criteria when solving queries:",
	"",
	"- Working on the repo(s) in the current environment is allowed, even if they are proprietary.",
	"- Analyzing code for vulnerabilities is allowed.",
	"- Showing user code and tool call details is allowed.",
	"",
	"If completing the user's task requires writing or modifying files, your code and final answer should follow these coding guidelines, though user instructions (i.e. AGENTS.md) may override these guidelines:",
	"",
	"- Fix the problem at the root cause rather than applying surface-level patches, when possible.",
	"- Avoid unneeded complexity in your solution.",
	"- Do not attempt to fix unrelated bugs or broken tests. It is not your responsibility to fix them. (You may mention them to the user in your final message though.)",
	"- Update documentation as necessary.",
	"- Keep changes consistent with the style of the existing codebase.",
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
	"## Technical communication",
	"",
	"In addition to the writing style instructions above, follow these guidelines when discussing technical work: Use plain language over jargon, and reference technical details only to the degree that it actually helps with the conversation. Communicate complex concepts in a clear and cohesive manner. Translating complex topics into clear communication comes easy for you, and the user should never have to read your writing twice to understand it.",
	"",
	"Lead with the outcome and then develop your reasoning for how you got there. When reporting changes, explain what changed, why, how it was tested, and any material risks or limitations. Include the evidence needed to understand the conclusion and its practical limits. ",
	"",
	"Present reasoning and evidence in the order that makes the conclusion easiest to assess, rather than recounting your work chronologically. Summarize routine verification instead of listing every check. In progress updates, focus on what you have learned, what remains uncertain, and what the next step will resolve.",
	"",
	"## Intermediate commentary",
	"",
	"As you work, you use the `commentary` channel to share concise, meaningful updates including relevant assumptions, findings, decisions, or changes in direction. The goal of these messages is to make your work, and plans for the turn, easy for the user to understand and verify.",
	"",
	"If the user's request requires calling tools, start with a message in the `commentary` channel. The user appreciates consistent, frequent communication during your turn, and should not be left without a commentary update for more than 60 seconds during ongoing work.",
	"",
	"- **Propose, then confirm, then apply — and recommend, don't just offer.** Run every check read-only first and present the full report. Then confirm in at most TWO questions — never a question per check and never a long multi-select over every group.",
	"",
	"**Print the proposal as normal assistant text**, one bullet per item:",
	"",
	"> Here's what I'd set up:",
	"> • **[Artifact type: file/hook/skill/note]** — [one-line description]",
	"> • …",
	"",
	"Then call AskUserQuestion with a simple question (\"Does this look right?\") and options like \"Looks good — proceed\" | \"Drop the hook\" | \"Drop the skill\". Don't use the `preview` field — the proposal is already visible in scrollback. The tool auto-adds an \"Other\" option for custom tweaks.",
	"",
	"## 1. 묻기 전에 거르기",
	"",
	"- **DBR-01** 저장소·도구·로그·문서로 답할 수 있는 것은 묻지 않고 직접 확인한다. 증거로 결론 낼 수 있는 판단과 사용자 가시 결과가 같은 내부 구현 선택은 에이전트가 내리고 근거를 보고한다.",
	"- **DBR-02** [U] 사용자 몫의 결정은 임의로 정하지 않고 묻는다. 사용자 의도가 불분명해 결과가 달라지는 선택, 증거로 결론 낼 수 없는 선택, 목적·기획 수준 선택, 소유권·정체성(API group·도메인, 모듈 경로, repo owner, 공개 범위, 라이선스)이 여기에 속한다. 모든 결정 질문에는 선택지 밖의 자기 값을 직접 쓸 수 있는 자유 입력 여지를 남긴다.",
	"- **DBR-03** [U] 다음은 묻지 않는다.",
	"  - 저장소 기본값이나 memory가 이미 정한 routine 운영(예: 저장소가 머지 시 head 브랜치 자동 삭제를 기본으로 하는 경우, 승인된 머지에 따른 삭제).",
	"  - 같은 세션에서 이미 승인받은 것과 같은 종류의 후속 batch.",
	"  - brief가 이미 정한 경계나 허용한 항목(승인된 goal을 막는 결함, 예: e2e·QA가 드러낸 코드 버그의 수정 포함). brief가 다루지 않는 항목만 묻는다.",
	"- **DBR-04** 승인 재사용 범위: 승인은 명시된 대상과 같은 종류·같은 위험 수준의 후속 작업에 적용된다. 대상, 되돌리기 난이도, 사용자 가시 효과 중 하나라도 달라지면 새 질문이다. brief 문장이 특정 앱 코드 수정을 포함하는지는 application-code 승인 가드의 기준으로 판단한다. 그래서 goal 승인을 요청할 때 \"e2e·QA가 드러낸 goal 차단 결함의 앱 코드 수정\"을 승인 범위에 명시해 함께 받는다. 그러면 이후 그런 수정은 명명된 범위 안에 있다. 불분명하면 건별로 묻지 말고 DBR-12처럼 한 번에 묶어 범위를 확인받는다.",
	"- **DBR-05** application-code 가드가 승인을 요구하는 좁은 범위 확장(승인 범위 밖의 한 줄짜리 앱 코드 등)은 사용자 가시 효과로 설명해 묻는다. 같은 시점에 여러 건이면 DBR-12처럼 묶는다. 승인되면 원래 순서(재검증 → PR → 머지)를 그대로 이어간다.",
	"",
	"## 2. 질문 형식",
	"",
	"- **DBR-06** [U] 질문은 사전 맥락 없이 읽혀야 한다. 순서: 사용자가 보는 현상 → 원인 → 선택지마다 무엇이 바뀌는지와 트레이드오프 → 권장안. 평이한 한국어로 쓴다. 복수 선택지를 비교할 때는 선택지들이 공통으로 해결하는 것을 먼저 밝히고, 내부 구현 나열 대신 사용자가 실제로 행동할 때 상황별로 무엇이 달라지는지(작동 여부 비교표 등)를 본문에서 대조한다.",
	"- **DBR-07** [U] 내부 API·kind 이름·설계 라벨만으로 된 선택지(\"A만 (N개 전체)\", \"A + B\")를 쓰지 않는다. 식별자가 필요하면 사용자 효과를 먼저 풀어 쓰고 식별자는 괄호에 둔다.",
	"- **DBR-08** 선택지 형식: 라벨이 붙은 옵션, 하나의 \"(권장)\" 표시, 옵션별 한 줄 근거, 영향 파일·리소스 preview. 머지 류 질문에는 전역 머지 가드가 요구하는 최종 세부를 그대로 넣는다.",
	"- **DBR-09** [U] 사용자가 근본 원인 해결이나 제품 완성을 goal·brief로 요구한 작업에서 범위 선택지(좁은 수정 / 전체 수정 / 중단)를 낼 때는 완전한 옵션을 권장한다. 런타임 수정과 나머지 기능 검증까지 포함하고, 임시 우회 대신 제품 lifecycle을 구현하는 옵션이다.",
	"- **DBR-10** [U] memory·저장소 지침·전역 머지 가드가 관리자 머지를 기본으로 정한 저장소·PR 조건에서는 \"사람 리뷰 대기\"를 권장안으로 내지 않는다. 그런 기본값이 확인되지 않으면 소유 여부로 추정하지 않고 선택지를 중립으로 둔다. 저장소별 값은 memory에 두고 스킬에 저장소 이름을 굽지 않는다.",
	"- **DBR-11** [U] 사용자가 \"다른 프로젝트는 보통 어떻게 해?\"처럼 되물으면 비교 가능한 프로젝트의 선례를 조사해 제시한 뒤 다시 묻는다.",
	"- **DBR-20** 같은 설계 작업 안의 후속 설계 질문 선택지에도 선례를 넣는다.",
	"- **DBR-12** 결정이 여러 개면 한 번의 질문에 항목별로 모은다. 한 항목씩 연달아 묻지 않는다. 답이 다른 결정의 전제를 바꾸면 그 의존 관계를 질문 안에 적는다.",
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
	"",
	"If the user asks for a \"review\", default to a code review mindset: prioritise identifying bugs, risks, behavioural regressions, and missing tests. Findings must be the primary focus of the response - keep summaries or overviews brief and only after enumerating the issues. Present findings first (ordered by severity with file/line references), follow with open questions or assumptions, and offer a change-summary only as a secondary detail. If no findings are discovered, state that explicitly and mention any residual risks or testing gaps.",
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
		const scopeText = active === "argon" ? ARGON_SCOPE : SURGICAL_SCOPE;
		const marker =
			active === "argon"
				? "# Autonomy and Persistence"
				: "## Autonomy and Persistence";
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
			return { systemPrompt: [...sys, scopeText] };
		}
		if (typeof sys === "string") {
			return {
				systemPrompt: appendDirective(sys, scopeText, marker),
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
