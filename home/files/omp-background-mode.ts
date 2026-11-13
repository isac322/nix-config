// `/bg` switches the current session to a background profile for work that can run
// slowly as long as quality holds. Each profile names a main model and re-curates only
// the roles and agents whose model differs from the base config; everything else
// inherits it. Overrides live in the runtime settings layer (never mutating config.yml
// on disk) and are re-applied automatically from the session transcript on resume until `/bg off`.
//
// - `on` (default): Claude Opus 5.5 main agent with GPT-6.1 Sol task subagents, keeping
//   orchestration on Opus while offloading implementation and review work from Anthropic quota.
// - `sol`: GPT-6.1 Sol main agent and subagents, spending ChatGPT Codex quota instead of
//   Anthropic quota wherever a measured equal exists.
// - `astra`: GPT-6 Astra main agent with GPT-6.1 Sol task subagents, spending ChatGPT Codex
//   quota instead of Anthropic quota.
// - `hydrogen`: Gemini 4 Hydrogen high main agent, which understands the problem and writes the
//   specs while Sol implements them.
// - `carbon`: Gemini 4 Carbon main agent with the same roles and agents as Hydrogen.
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { lookup } from "@oh-my-pi/pi-coding-agent/config/registry";
import { type Component, Container, Markdown, Spacer } from "@oh-my-pi/pi-tui";
import { getMarkdownTheme } from "@oh-my-pi/pi-tui/theme";
import { askToolRenderer } from "@oh-my-pi/pi-tui/tools/ask";
import { waitToolRenderer } from "@oh-my-pi/pi-tui/tools/wait";

type Profile = {
	label: string;
	mainModel: string;
	mainThinking: string;
	roles: Record<string, string>;
	agents: Record<string, string>;
};

const OPUS = "anthropic/claude-opus-5-5";
const SOL = "openai-codex/gpt-6.1-sol";
const HYDROGEN = "google-antigravity/gemini-4-hydrogen-high";
const CARBON = "google-antigravity/gemini-4-carbon";
const ASTRA = "openai-codex/gpt-6-astra";
const GROK = "xai-oauth/grok-4.7-build-fast";
const SONNET = "anthropic/claude-sonnet-5-5";
const PROC_STREAMS_PATH_RE = /^proc:\/\/[^/]+\/streams(?:\/.*)?$/;
const WAIT_POLL_TIMEOUT_RE =
	/(?:^|\n\n)(?:No job finished|No reply|No service finished) within (?:\d+(?:\.\d+)?s|\d+m); a back-to-back wait allows up to (?:\d+(?:\.\d+)?s|\d+m)\.(?: Read proc:\/\/ for status\.)?$/;
const BUILTIN_OMP_TOOLS: Record<string, true> = {
	read: true,
	bash: true,
	edit: true,
	write: true,
	grep: true,
	glob: true,
	find: true,
	task: true,
	wait: true,
	todo: true,
	ask: true,
	eval: true,
	web_search: true,
	goal: true,
};

// Byte-for-byte contiguous sections for GPT `/bg` profiles from:
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
	"Use plain, simple language: familiar words, concrete examples, and precise verbs. Prefer active voice and direct statements.",
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
	"- **DBR-01** 별도의 보안·네트워크·프라이버시 금지 계약이 없는 일반 저장소·도구·로그·문서 읽기(read-only) 확인으로 답할 수 있는 것은 `ask`로 묻지 않고 직접 확인한다(로컬 저장소 감사 중 표준 라이브러리나 일반 K8s 스펙을 확인하려고 외부 웹 문서 `https://...`를 느리게 조회하지 않는다). 에러(예: 400/500, 테스트·스키마 실패)가 발생하면 사용자에게 원인을 묻지 말고 코드와 로그를 먼저 추적해 구체적인 원인을 분리한다(이미 코드 수정이 승인된 작업이면 바로 수정하고, 분석 전용 요청이나 미승인 앱 코드라면 확인한 원인과 수정안을 보고한다).",
	"- **DBR-03 · DBR-04** 사용자가 특정 애플리케이션 코드 수정·구현을 이미 지시했거나 승인한 뒤에는, 그 승인된 동작을 완성·검증하기 위해 인과 경로상 직접 필요한 종속 수정(CLI 인자 연결, 스키마·어댑터 호환성 보정, 테스트·평가 하네스 보정, 승인된 데이터의 로더 플래그 반영)을 단계마다 쪼개 다시 묻지 않는다. 반면 분석 전용 요청이나 CI/인프라 전용 작업에서는 애플리케이션 코드를 임의로 수정하지 않는다.",
	"- **가짜 범위 선택지(\"전체 수정 vs 불완전 부분 수정\") 생성 금지 (DBR-09)**: 한 선택지는 \"문제를 제대로 고침\"이고 다른 선택지는 \"일부 파일만 고쳐 버그나 우회 경로를 남겨둠\"인 허수아비 선택지를 만들지 않는다. 이미 승인된 수정 범위라면 `ask` 없이 완전한 수정을 바로 수행하고, 최초 애플리케이션 코드 수정 승인이 필요한 경우라면 `\"제안된 수정 적용 (권장)\"`과 `\"수정 보류 (현재 상태 유지)\"` 또는 실제로 양립 가능한 설계·정책 대안만 제시한다.",
	"",
	"### 2. 사용자 결정이나 승인이 필요할 때의 설명과 `ask` 형식",
	"- **DBR-02 · DBR-12** 전역 승인 가드(미승인 앱 코드 수정, PR 머지, 파괴적 작업, 명시적 프라이버시·네트워크 경계)가 승인을 요구하거나, 사용자 의도에 따라 제품 동작·비용·보안·운영 정책이 달라지는 진정한 선택지가 있을 때만 `ask`를 호출한다. 서로 연관된 결정은 한 번의 `ask`로 묶어서 묻는다.",
	"- **DBR-06 (`ask` 호출 시 `brief` 필수 포함 및 `todo` 턴 분리 금지)**: 사용자는 에이전트가 내부에서 읽은 파일·도구 출력·서브에이전트 로그·`thinking` 블록을 보지 못하며, `ask` 하단 팝업창의 `question`은 최대 4줄만 표시된다. 단일 점검·감사 후 `ask`로 이어지는 작업에서는 `todo` 항목을 여러 개로 쪼개 만들어 `ask` 직전에 `todo(op=\"done\")` 전용 턴을 연달아 돌지 않는다(필요시 `todo`는 `ask`와 같은 턴에서 최대 1회만 병렬 호출). 설명을 이전 `todo` 턴에 먼저 쓰거나 `thinking`·`ask.questions` 인자 안에만 넣지 말고, **반드시 `ask` 도구의 `brief` 인자**(또는 같은 턴의 어시스턴트 채팅 본문 `text`; 단, 긴 마크다운 표를 `text`에 쓰고 `ask`를 함께 호출하면 스트림 오류가 날 수 있으므로 `text`를 비우고 `ask`의 `brief` 인자 안에 전체 브리프를 넣는 것을 권장)에 사용자와 같은 언어(한국어 대화에서는 평이한 한국어)로 다음 브리프 전체를 작성하고, `questions[].question`에는 4줄 팝업에 들어갈 1~2줄 핵심 질문만 넣는다:",
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
	"위 권장안으로 진행할까요, 아니면 다른 방향으로 조정할까요?",
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

const ON_PROFILE: Profile = {
	label: "Opus",
	mainModel: OPUS,
	mainThinking: "medium",
	roles: {
		default: `${OPUS}:medium`,
		// Planning inherits the base Argon plan role, so a different model family still
		// drafts plans for the Sol implementer; escalations go to Astra.
		slow: `${ASTRA}:xhigh`,
		task: `${SOL}:high`,
	},
	// Codex-authored work gets a review from Grok 4.7 first, falling back to Sonnet 5.5 in
	// another model family when Grok quota is depleted; advisor and lightweight roles/agents
	// (browser, smol, scout, sonic, tiny, commit) inherit the base config.
	agents: {
		reviewer: `${GROK}:low, ${SONNET}:high`,
		"security-reviewer": `${SOL}:max`,
	},
};

const PROFILES: Record<string, Profile> = {
	on: ON_PROFILE,
	sol: {
		label: "Sol",
		mainModel: SOL,
		mainThinking: "high",
		roles: {
			...ON_PROFILE.roles,
			default: `${SOL}:high`,
		},
		agents: ON_PROFILE.agents,
	},
	astra: {
		label: "Astra",
		mainModel: ASTRA,
		mainThinking: "medium",
		roles: {
			...ON_PROFILE.roles,
			default: `${ASTRA}:medium`,
		},
		agents: ON_PROFILE.agents,
	},
	hydrogen: {
		label: "Hydrogen",
		mainModel: HYDROGEN,
		mainThinking: "high",
		roles: {
			...ON_PROFILE.roles,
			default: `${HYDROGEN}:high`,
		},
		agents: ON_PROFILE.agents,
	},
	carbon: {
		label: "Carbon",
		mainModel: CARBON,
		mainThinking: "medium",
		roles: {
			...ON_PROFILE.roles,
			default: `${CARBON}:medium`,
		},
		agents: ON_PROFILE.agents,
	},
};

const SUBCOMMANDS = [
	{ name: "on", description: "Opus main agent, Sol implementer, roles re-curated around it" },
	{ name: "sol", description: "GPT-6.1 Sol main agent, Sol implementer, roles re-curated around it" },
	{ name: "astra", description: "GPT-6 Astra main agent, Sol implementer, roles re-curated around it" },
	{ name: "hydrogen", description: "Gemini 4 Hydrogen high main agent, Sol implementer, roles re-curated around it" },
	{ name: "carbon", description: "Gemini 4 Carbon main agent, Sol implementer, roles re-curated around it" },
	{ name: "off", description: "Restore the base config and the previous model" },
	{ name: "status", description: "Show the active profile and key roles" },
];

function appendDirective(baseText: unknown, directive: string, marker: string): string {
	const text = typeof baseText === "string" ? baseText.trim() : "";
	if (text.includes(marker)) return text;
	return text ? `${text}\n\n${directive}` : directive;
}

const BG_ENTRY_TYPE = "bg-mode";

type InferredBgState = {
	mode: string | undefined;
	prevModel: string | undefined;
	prevThinking: string | undefined;
	profileHash: string | undefined;
	savedRoles: Record<string, string> | undefined;
	savedAgents: Record<string, string> | undefined;
	inPlanMode: boolean;
};

function isStringRecord(val: unknown): val is Record<string, string> {
	if (!val || typeof val !== "object" || Array.isArray(val)) return false;
	return Object.values(val).every((v) => typeof v === "string");
}

function recordsMatch(a: Record<string, string>, b: Record<string, string>): boolean {
	const aKeys = Object.keys(a);
	const bKeys = Object.keys(b);
	if (aKeys.length !== bKeys.length) return false;
	return aKeys.every((k) => a[k] === b[k]);
}

function computeProfileHash(profile: Profile): string {
	const canonical = JSON.stringify({
		mainModel: profile.mainModel,
		mainThinking: profile.mainThinking,
		roles: Object.entries(profile.roles).sort(([a], [b]) => a.localeCompare(b)),
		agents: Object.entries(profile.agents).sort(([a], [b]) => a.localeCompare(b)),
	});
	return createHash("sha256").update(canonical).digest("hex").slice(0, 4);
}

const OMP_AGENT_DIR = join(homedir(), ".omp/agent");
const NIX_DARWIN_HOME_DIR = "/etc/nix-darwin/home";
const OMP_HASH_TTL_MS = 5_000;

function readTextSafe(filePath: string): string | undefined {
	try {
		return readFileSync(filePath, "utf8");
	} catch {
		return undefined;
	}
}

function computeDeployedOmpHash(ompDir = OMP_AGENT_DIR): string {
	const hash = createHash("sha256");
	const fixedFiles = [
		"AGENTS.md",
		"PERSONALITY.md",
		"RULES.md",
		"agents/browser.md",
		"config.yml",
		"extensions/background-mode.ts",
	];
	for (const rel of fixedFiles) {
		const content = readTextSafe(join(ompDir, rel));
		if (content !== undefined) {
			hash.update(`${rel}\0${content.trim()}\0`);
		}
	}
	try {
		const rulesDir = join(ompDir, "rules");
		const ruleFiles = readdirSync(rulesDir)
			.filter((name) => name.endsWith(".md"))
			.sort();
		for (const name of ruleFiles) {
			const content = readTextSafe(join(rulesDir, name));
			if (content !== undefined) {
				hash.update(`rules/${name}\0${content.trim()}\0`);
			}
		}
	} catch {}
	return hash.digest("hex").slice(0, 4);
}

function checkRepoUnswitched(ompDir = OMP_AGENT_DIR, nixHomeDir = NIX_DARWIN_HOME_DIR): boolean {
	const repoExt = readTextSafe(join(nixHomeDir, "files/omp-background-mode.ts"));
	const depExt = readTextSafe(join(ompDir, "extensions/background-mode.ts"));
	if (repoExt !== undefined && depExt !== undefined && repoExt.trim() !== depExt.trim()) {
		return true;
	}
	const repoCfg = readTextSafe(join(nixHomeDir, "files/omp-agent-config.yml"));
	const depCfg = readTextSafe(join(ompDir, "config.yml"));
	if (
		repoCfg !== undefined &&
		depCfg !== undefined &&
		!depCfg.trimStart().startsWith(repoCfg.trim())
	) {
		return true;
	}
	const repoBrowser = readTextSafe(join(nixHomeDir, "files/agent-instructions/agents/browser.md"));
	const depBrowser = readTextSafe(join(ompDir, "agents/browser.md"));
	if (repoBrowser !== undefined && depBrowser !== undefined && repoBrowser.trim() !== depBrowser.trim()) {
		return true;
	}
	try {
		const segmentsDir = join(nixHomeDir, "files/agent-instructions/segments");
		const segmentFiles = readdirSync(segmentsDir).filter(
			(name) => name.endsWith(".md") && name !== "claude-tools.md" && name !== "codex-tools.md",
		);
		const deployedBodies: string[] = [];
		for (const rel of ["AGENTS.md", "PERSONALITY.md", "RULES.md"]) {
			const text = readTextSafe(join(ompDir, rel));
			if (text !== undefined) deployedBodies.push(text);
		}
		const rulesDir = join(ompDir, "rules");
		for (const name of readdirSync(rulesDir).filter((n) => n.endsWith(".md"))) {
			const text = readTextSafe(join(rulesDir, name));
			if (text !== undefined) deployedBodies.push(text);
		}
		const combinedDeployed = deployedBodies.join("\n\n");
		for (const name of segmentFiles) {
			const segText = readTextSafe(join(segmentsDir, name))?.trim();
			if (segText && !combinedDeployed.includes(segText)) {
				return true;
			}
		}
	} catch {}
	return false;
}

const LOADED_OMP_HASH = computeDeployedOmpHash();
let cachedDiskCheck: { at: number; deployedHash: string; repoUnswitched: boolean } | undefined;

function getDiskVersionState(force = false): { deployedHash: string; repoUnswitched: boolean } {
	const now = Date.now();
	if (!force && cachedDiskCheck && now - cachedDiskCheck.at < OMP_HASH_TTL_MS) {
		return cachedDiskCheck;
	}
	const deployedHash = computeDeployedOmpHash();
	const repoUnswitched = checkRepoUnswitched();
	cachedDiskCheck = { at: now, deployedHash, repoUnswitched };
	return cachedDiskCheck;
}

function inferSessionBgState(entries: unknown[]): InferredBgState {
	let mode: string | undefined;
	let prevModel: string | undefined;
	let prevThinking: string | undefined;
	let profileHash: string | undefined;
	let savedRoles: Record<string, string> | undefined;
	let savedAgents: Record<string, string> | undefined;
	let inPlanMode = false;

	for (const raw of entries) {
		if (!raw || typeof raw !== "object") continue;
		const entry = raw as Record<string, unknown>;
		const type = entry.type;
		if (type === "session_init") {
			return {
				mode: undefined,
				prevModel: undefined,
				prevThinking: undefined,
				profileHash: undefined,
				savedRoles: undefined,
				savedAgents: undefined,
				inPlanMode: false,
			};
		}

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
					profileHash = undefined;
					savedRoles = undefined;
					savedAgents = undefined;
				} else if (typeof d.mode === "string" && PROFILES[d.mode]) {
					mode = d.mode;
					if (typeof d.prevModel === "string" && d.prevModel) prevModel = d.prevModel;
					if (typeof d.prevThinking === "string" && d.prevThinking) prevThinking = d.prevThinking;
					profileHash = typeof d.profileHash === "string" ? d.profileHash : undefined;
					savedRoles = isStringRecord(d.roles) ? d.roles : undefined;
					savedAgents = isStringRecord(d.agents) ? d.agents : undefined;
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
				if (mode !== "sol") {
					mode = "sol";
					profileHash = undefined;
					savedRoles = undefined;
					savedAgents = undefined;
				}
			} else if (model === ASTRA) {
				if (mode !== "astra") {
					mode = "astra";
					profileHash = undefined;
					savedRoles = undefined;
					savedAgents = undefined;
				}
			} else if (model === HYDROGEN) {
				if (mode !== "hydrogen") {
					mode = "hydrogen";
					profileHash = undefined;
					savedRoles = undefined;
					savedAgents = undefined;
				}
			} else if (model === CARBON || model === "google/gemini-4-carbon") {
				if (mode !== "carbon") {
					mode = "carbon";
					profileHash = undefined;
					savedRoles = undefined;
					savedAgents = undefined;
				}
			} else if (typeof model === "string" && model) {
				if (mode && PROFILES[mode]?.mainModel === model) {
					continue;
				}
				mode = undefined;
				profileHash = undefined;
				savedRoles = undefined;
				savedAgents = undefined;
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

	return { mode, prevModel, prevThinking, profileHash, savedRoles, savedAgents, inPlanMode };
}

function isNonOpusMainProfile(activeMode: string | undefined): boolean {
	if (!activeMode) return false;
	const mainModel = PROFILES[activeMode]?.mainModel;
	return typeof mainModel === "string" && !mainModel.includes("claude-opus-");
}

function isSubagentContext(ctx: unknown): boolean {
	if (!ctx || typeof ctx !== "object" || !("agent" in ctx)) return false;
	const agent = ctx.agent;
	if (!agent || typeof agent !== "object" || !("kind" in agent)) return false;
	return agent.kind === "sub";
}

function isOpusContextModel(ctx: unknown): boolean {
	if (!ctx || typeof ctx !== "object" || !("model" in ctx)) return false;
	const model = ctx.model;
	if (!model || typeof model !== "object" || !("id" in model)) return false;
	return typeof model.id === "string" && model.id.includes("claude-opus-");
}

function describePendingAsyncWork(ctx: unknown): string | undefined {
	if (!ctx || typeof ctx !== "object" || !("getAsyncJobSnapshot" in ctx)) return undefined;
	const getSnap = ctx.getAsyncJobSnapshot;
	if (typeof getSnap !== "function") return undefined;
	const snap: unknown = getSnap.call(ctx);
	if (!snap || typeof snap !== "object") return undefined;
	const runningRaw = "running" in snap && Array.isArray(snap.running) ? snap.running : [];
	const runningLabels: string[] = [];
	const runningIds = new Set<string>();
	for (const item of runningRaw) {
		if (!item || typeof item !== "object") continue;
		const id = "id" in item && typeof item.id === "string" ? item.id : "";
		const label = "label" in item && typeof item.label === "string" ? item.label : "";
		if (id) runningIds.add(id);
		runningLabels.push(label || id || "job");
	}
	let queuedCount = 0;
	let delivering = false;
	const pendingIds: string[] = [];
	if ("delivery" in snap && snap.delivery && typeof snap.delivery === "object") {
		const del = snap.delivery;
		if ("queued" in del && typeof del.queued === "number") queuedCount = del.queued;
		if ("delivering" in del && typeof del.delivering === "boolean") delivering = del.delivering;
		if ("pendingJobIds" in del && Array.isArray(del.pendingJobIds)) {
			for (const pid of del.pendingJobIds) {
				if (typeof pid === "string" && !runningIds.has(pid)) pendingIds.push(pid);
			}
		}
	}
	if (runningLabels.length === 0 && queuedCount === 0 && !delivering) {
		return undefined;
	}
	const labels = [...runningLabels, ...pendingIds];
	return labels.length > 0 ? labels.join(", ") : `${runningLabels.length + queuedCount} job(s)`;
}

function updateGoalContinuationOverride(
	scope: unknown,
	pendingAsyncWork: boolean,
): void {
	const contModes = lookup("goal.continuationModes");
	if (!contModes) return;
	if (pendingAsyncWork) {
		contModes.override(scope, []);
	} else {
		contModes.clearOverride(scope);
	}
}

// Module-scoped state so subagent ExtensionRunner instances bound in the same OMP
// process observe the active background profile without clobbering parent overrides.
let restore: (() => Promise<void>) | undefined;
let active: string | undefined;
let savedPrevModel: string | undefined;
let savedPrevThinking: string | undefined;
// Number of main-agent assistant messages since the last one that showed a decision brief in
// visible text or `ask.brief` (0 = the current message), or undefined when none did since the
// last user submission, executed `ask`, or session change.
let briefAge: number | undefined;
const suppressedBriefs = new Set<string>();
// Thresholds from 553 judged `ask` calls (2026-10-18..31): requiring one message with 200+
// visible characters within the last 6 assistant messages blocked none of the 331 calls
// with an adequate brief and all 147 without an explanation.
const BRIEF_MIN_CHARS = 200;
const BRIEF_MAX_AGE = 5;

// `ask` previews only four lines of its question, and thinking blocks never reach the
// user, so the brief must sit in visible text blocks or `ask.brief`.
function visibleText(content: unknown): string {
	if (!Array.isArray(content)) return "";
	return content
		.map((block) =>
			block && typeof block === "object" && "type" in block && block.type === "text" && "text" in block
				? String(block.text)
				: "",
		)
		.join("")
		.trim();
}

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	const completeScrollback = lookup("tui.completeScrollback");
	if (completeScrollback) {
		completeScrollback.override(scope, true);
	}

	function applyProfileOverrides(
		nextMode: string | undefined,
		rolesOverride?: Record<string, string>,
		agentsOverride?: Record<string, string>,
	): void {
		const roles = lookup("modelRoles");
		const agents = lookup("task.agentModelOverrides");
		if (!roles || !agents) return;
		roles.clearOverride(scope);
		agents.clearOverride(scope);
		const profile = nextMode ? PROFILES[nextMode] : undefined;
		if (profile) {
			roles.override(scope, { ...roles.get(scope), ...(rolesOverride ?? profile.roles) });
			agents.override(scope, { ...agents.get(scope), ...(agentsOverride ?? profile.agents) });
			active = nextMode;
		} else {
			active = undefined;
		}
	}

	function isProfileOutdatedForSession(ctx: unknown, inferred: InferredBgState): boolean {
		if (!inferred.mode) return false;
		const profile = PROFILES[inferred.mode];
		if (!profile) return false;
		if (inferred.profileHash !== undefined && inferred.profileHash !== computeProfileHash(profile)) {
			return true;
		}
		if (inferred.savedRoles !== undefined && !recordsMatch(inferred.savedRoles, profile.roles)) {
			return true;
		}
		if (inferred.savedAgents !== undefined && !recordsMatch(inferred.savedAgents, profile.agents)) {
			return true;
		}
		if (inferred.inPlanMode) return false;
		const c = ctx as {
			models?: { current?: () => { provider?: string; id?: string } | undefined };
			model?: { provider?: string; id?: string };
		};
		const current = c.models?.current?.() ?? c.model;
		if (current?.provider && current?.id) {
			const selector = `${current.provider}/${current.id}`;
			if (selector !== profile.mainModel) return true;
		}
		const currentThinking = pi.getThinkingLevel?.();
		if (typeof currentThinking === "string" && currentThinking && currentThinking !== profile.mainThinking) {
			return true;
		}
		return false;
	}

	function updateStatusLineBadge(ctx: unknown, inferred?: InferredBgState, forceDiskCheck = false): void {
		if (isSubagentContext(ctx) || !ctx || typeof ctx !== "object" || !("ui" in ctx)) return;
		const uiObj = ctx.ui;
		if (!uiObj || typeof uiObj !== "object" || !("setStatus" in uiObj)) return;
		const setStatus = uiObj.setStatus;
		if (typeof setStatus !== "function") return;
		const state =
			inferred ??
			(() => {
				if (!("sessionManager" in ctx) || !ctx.sessionManager || typeof ctx.sessionManager !== "object") {
					return undefined;
				}
				const sm = ctx.sessionManager;
				if (!("getBranch" in sm) || typeof sm.getBranch !== "function") return undefined;
				const branch: unknown = sm.getBranch.call(sm);
				return Array.isArray(branch) ? inferSessionBgState(branch) : undefined;
			})();
		const { deployedHash, repoUnswitched } = getDiskVersionState(forceDiskCheck);
		let verBadge = `#${LOADED_OMP_HASH}`;
		if (LOADED_OMP_HASH !== deployedHash) {
			verBadge = `#${LOADED_OMP_HASH}→#${deployedHash} ↻restart`;
		} else if (repoUnswitched) {
			verBadge = `#${LOADED_OMP_HASH} ⚠switch`;
		}
		const mode = state?.mode ?? active;
		if (mode && PROFILES[mode]) {
			const outdated = state ? isProfileOutdatedForSession(ctx, state) : false;
			const bgBadge = outdated ? `bg:${PROFILES[mode].label}(↻/bg)` : `bg:${PROFILES[mode].label}`;
			setStatus.call(uiObj, "bg-mode", `${bgBadge} ${verBadge}`);
		} else {
			setStatus.call(uiObj, "bg-mode", verBadge);
		}
	}

	function syncFromSession(ctx: unknown, forceDiskCheck = false): void {
		if (isSubagentContext(ctx) || !ctx || typeof ctx !== "object") return;
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
		const desiredRoles = inferred.savedRoles ?? targetProfile?.roles;
		const desiredAgents = inferred.savedAgents ?? targetProfile?.agents;
		const currentRoles = roles?.get(scope) ?? {};
		const currentAgents = agents?.get(scope) ?? {};
		const needsSync =
			active !== inferred.mode ||
			(targetProfile !== undefined &&
				desiredRoles !== undefined &&
				desiredAgents !== undefined &&
				(Object.entries(desiredRoles).some(([k, v]) => currentRoles[k] !== v) ||
					Object.entries(desiredAgents).some(([k, v]) => currentAgents[k] !== v)));
		if (needsSync) {
			applyProfileOverrides(inferred.mode, desiredRoles, desiredAgents);
		}
		updateGoalContinuationOverride(scope, Boolean(describePendingAsyncWork(ctx)));
		updateStatusLineBadge(ctx, inferred, forceDiskCheck);

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
		briefAge = undefined;
		suppressedBriefs.clear();
		syncFromSession(ctx);
	});
	pi.on("session_switch", (_event, ctx) => {
		briefAge = undefined;
		suppressedBriefs.clear();
		syncFromSession(ctx);
	});
	pi.on("session_branch", (_event, ctx) => {
		briefAge = undefined;
		suppressedBriefs.clear();
		syncFromSession(ctx);
	});
	pi.on("session_tree", (_event, ctx) => {
		briefAge = undefined;
		suppressedBriefs.clear();
		syncFromSession(ctx);
	});

	// Append `SURGICAL_SCOPE` only for a GPT main model with an active `/bg` profile,
	// never inside subagents.
	pi.on("before_agent_start", async (event, ctx) => {
		if (isSubagentContext(ctx)) return;
		syncFromSession(ctx);
		if (!active || !ctx.model?.id.startsWith("gpt-")) return;
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

	// A new user message starts a fresh decision context. `input` fires only for user
	// submissions, so goal continuations and background-job wakes keep a brief that the
	// previous turn just showed.
	pi.on("input", (event) => {
		// Slash commands such as `/bg status` are not new requests.
		if (typeof event.text === "string" && event.text.trimStart().startsWith("/")) return;
		briefAge = undefined;
		suppressedBriefs.clear();
	});

	// Track how recently the main agent showed a decision brief in visible text. This runs
	// before tool dispatch, so `tool_call` sees a brief from the same message. Even when a
	// turn stops with `MALFORMED_FUNCTION_CALL` (`stopReason === "error"`), OMP commits the
	// already-streamed visible text to the transcript, so 200+ visible characters still count.
	pi.on("assistant_message", (event, ctx) => {
		if (isSubagentContext(ctx)) return;
		const { stopReason, content } = event.message;
		if (stopReason === "aborted") return;
		const visText = visibleText(content);
		const hasVisibleBrief = visText.length >= BRIEF_MIN_CHARS;
		if (hasVisibleBrief && Array.isArray(content)) {
			for (const block of content) {
				if (
					block &&
					typeof block === "object" &&
					"type" in block &&
					block.type === "toolCall" &&
					"name" in block &&
					block.name === "ask" &&
					"arguments" in block &&
					block.arguments &&
					typeof block.arguments === "object" &&
					"brief" in block.arguments &&
					typeof block.arguments.brief === "string"
				) {
					const trimmed = block.arguments.brief.trim();
					if (trimmed && visText.includes(trimmed)) suppressedBriefs.add(trimmed);
				}
			}
		}
		if (!isNonOpusMainProfile(active)) return;
		if (hasVisibleBrief) briefAge = 0;
		else if (stopReason !== "error" && briefAge !== undefined) briefAge += 1;
	});

	// Pause `/goal` auto-continuation timers while background jobs are still running or
	// pending delivery so `InteractiveMode.#scheduleGoalContinuation` (which runs on the
	// session `agent_end` event BEFORE extension `agent_end` handlers) does not inject a
	// new `"Continue active goal"` prompt 800ms after the turn ends. Syncing on tool
	// execution and before/after each turn ensures `goal.continuationModes` is already `[]`
	// before the turn settles into `agent_end`, and restores it as soon as 0 jobs remain.
	pi.on("tool_execution_start", (_event, ctx) => {
		if (isSubagentContext(ctx)) return;
		updateGoalContinuationOverride(scope, Boolean(describePendingAsyncWork(ctx)));
	});
	pi.on("tool_execution_end", (_event, ctx) => {
		if (isSubagentContext(ctx)) return;
		updateGoalContinuationOverride(scope, Boolean(describePendingAsyncWork(ctx)));
	});
	pi.on("agent_end", (event, ctx) => {
		if (isSubagentContext(ctx)) return;
		syncFromSession(ctx);
		const awaiting =
			Boolean((event as Record<string, unknown>).awaitingAsyncWork) ||
			Boolean(describePendingAsyncWork(ctx));
		updateGoalContinuationOverride(scope, awaiting);
	});

	// In every main-agent session: block status polling and goal completion while
	//    background work is pending, regardless of model or background profile.
	//    Non-Opus background profiles also require a decision brief before `ask`.
	// Normalize OpenAI strict-schema dummy fields on `bash` and `task` calls.
	pi.on("tool_call", async (event, ctx) => {
		const subagent = isSubagentContext(ctx);
		if (!subagent) {
			syncFromSession(ctx);
		}
		if (!event.input || typeof event.input !== "object") {
			return;
		}
		const rawInput = event.input as Record<string, unknown>;
		if (!subagent && event.toolName === "goal" && rawInput.op === "complete") {
			const pending = describePendingAsyncWork(ctx);
			if (pending) {
				return {
					block: true,
					reason: `Cannot complete goal while background jobs are still running or pending delivery (${pending}). End your turn without completing the goal so OMP wakes this session automatically when the background work finishes.`,
				};
			}
		}
		if (!subagent && event.toolName === "read") {
			const path = typeof rawInput.path === "string" ? rawInput.path.trim() : "";
			if (
				path.startsWith("proc://") &&
				!PROC_STREAMS_PATH_RE.test(path) &&
				describePendingAsyncWork(ctx)
			) {
				return {
					block: true,
					reason:
						"Do NOT poll running background jobs via read(proc://...). Call wait to block until the next job finishes, or continue independent work.",
				};
			}
		}
		if (!active) {
			return;
		}
		if (!subagent && isNonOpusMainProfile(active) && event.toolName === "ask") {
			const askBrief = typeof rawInput.brief === "string" ? rawInput.brief.trim() : "";
			if (askBrief.length >= BRIEF_MIN_CHARS) {
				briefAge = 0;
			}
			if (briefAge === undefined || briefAge > BRIEF_MAX_AGE) {
				return {
					block: true,
					reason:
						"ask 호출에 사용자 브리프가 누락되었습니다. ask의 brief 인자 안에 진행 상황·현상·원인/배경·선택지 비교·권장 이유 전체(200자 이상)를 한국어 마크다운으로 담아 ask를 다시 호출하세요.",
				};
			}
		}
		const shouldNormalizeToolInput = subagent ? !isOpusContextModel(ctx) : isNonOpusMainProfile(active);
		if (!shouldNormalizeToolInput) {
			return;
		}
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
				if (Array.isArray(t.tools)) {
					const filtered = t.tools.filter(
						(name) => typeof name === "string" && !BUILTIN_OMP_TOOLS[name.trim()],
					);
					if (filtered.length === 0) {
						delete t.tools;
						changed = true;
					} else if (filtered.length !== t.tools.length) {
						t.tools = filtered;
						changed = true;
					}
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
	pi.on("tool_result", async (event, ctx) => {
		if (isSubagentContext(ctx)) return;
		syncFromSession(ctx);
		if (event.toolName === "ask") briefAge = undefined;
	});

	const z = pi.zod;
	type ToolDescription = Record<string, unknown> & { body?: unknown[] };
	const askRendererWithDescribe = askToolRenderer as typeof askToolRenderer & {
		describeCall?: (args: unknown, options?: unknown) => ToolDescription;
		describeResult?: (result: unknown, options?: unknown, args?: unknown) => ToolDescription;
	};
	function extractUnsuppressedBrief(args: unknown): string {
		const brief =
			args && typeof args === "object" && "brief" in args && typeof args.brief === "string"
				? args.brief.trim()
				: "";
		if (brief.length < BRIEF_MIN_CHARS || suppressedBriefs.has(brief)) {
			return "";
		}
		return brief;
	}
	function escapeAskHtml(text: string): string {
		return text
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;");
	}
	function withAskFormHtml(args: unknown): Record<string, unknown> {
		if (!args || typeof args !== "object") {
			return {};
		}
		const record = { ...(args as Record<string, unknown>) };
		if (typeof record.html === "string" && record.html.trim().length > 0) {
			return record;
		}
		if (!Array.isArray(record.questions) || record.questions.length === 0) {
			return record;
		}
		const fieldsets: string[] = [];
		for (const q of record.questions) {
			if (!q || typeof q !== "object") continue;
			const id = "id" in q && typeof q.id === "string" && q.id.trim() ? q.id.trim() : "q";
			const question = "question" in q && typeof q.question === "string" && q.question.trim() ? q.question.trim() : id;
			const multi = "multi" in q && q.multi === true;
			const recommended = "recommended" in q && typeof q.recommended === "number" ? q.recommended : 0;
			const options = "options" in q && Array.isArray(q.options) ? q.options : [];
			const controls: string[] = [];
			options.forEach((opt: unknown, idx: number) => {
				if (!opt || typeof opt !== "object") return;
				const label = "label" in opt && typeof opt.label === "string" ? opt.label.trim() : "";
				if (!label) return;
				const description =
					"description" in opt && typeof opt.description === "string" && opt.description.trim()
						? ` — ${escapeAskHtml(opt.description.trim())}`
						: "";
				const inputType = multi ? "checkbox" : "radio";
				const checkedAttr = !multi && idx === recommended ? " checked" : "";
				controls.push(
					`<label><input type="${inputType}" name="${escapeAskHtml(id)}" value="${escapeAskHtml(label)}"${checkedAttr}> <strong>${escapeAskHtml(label)}</strong>${description}</label>`,
				);
			});
			fieldsets.push(`<fieldset><legend>${escapeAskHtml(question)}</legend>${controls.join("")}</fieldset>`);
		}
		if (fieldsets.length > 0) {
			record.html = `<form>${fieldsets.join("")}</form>`;
		}
		return record;
	}
	function describeAskWithBrief(base: ToolDescription, args: unknown): ToolDescription {
		const brief = extractUnsuppressedBrief(args);
		if (!brief) {
			return base;
		}
		const prevBody = Array.isArray(base.body) ? base.body : [];
		return {
			...base,
			inline: false,
			open: true,
			preview: "none",
			body: [{ k: "md", p: { text: brief } }, ...prevBody],
		};
	}
	function renderAskWithBrief(card: Component, args: unknown): Component {
		const brief = extractUnsuppressedBrief(args);
		if (!brief) {
			return card;
		}
		const container = new Container();
		container.addChild(new Markdown(brief, 1, 0, getMarkdownTheme()));
		container.addChild(new Spacer(1));
		container.addChild(card);
		return container;
	}
	pi.registerTool({
		name: "ask",
		label: "Ask",
		approval: "read",
		concurrency: "exclusive",
		loadMode: "discoverable",
		mergeCallAndResult: true,
		description:
			"Ask the user for a decision when materially different tradeoffs or required approvals exist. Supply the full user-facing decision brief (**진행 상황**, **현상**, **원인 / 배경**, **선택지 비교** markdown table, **권장 이유**) in `brief` so it renders in the chat transcript above the 4-line popup.",
		parameters: z.object({
			i: z.string().optional().describe("Capitalized 2-6 word present-participle intent"),
			brief: z
				.string()
				.describe(
					"Self-contained decision brief in Markdown (**진행 상황**, **현상**, **원인 / 배경**, **선택지 비교** markdown table, **권장 이유**) rendered in the chat transcript above the question popup.",
				),
			questions: z
				.array(
					z.object({
						id: z.string(),
						question: z.string().describe("Concise 1-2 line question for the 4-line popup header"),
						header: z.string().optional().describe("Short display chip"),
						multi: z.boolean().optional(),
						recommended: z.number().optional().describe("0-based default index"),
						options: z.array(
							z.object({
								label: z.string(),
								description: z.string().optional(),
								preview: z.string().optional(),
							}),
						),
					}),
				)
				.min(1),
		}),
		describeCall(args: unknown, options: unknown) {
			return askRendererWithDescribe.describeCall?.(withAskFormHtml(args), options) ?? {};
		},
		describeResult(result: unknown, options: unknown, args: unknown) {
			const normalizedArgs = withAskFormHtml(args);
			const base = askRendererWithDescribe.describeResult?.(result, options, normalizedArgs) ?? {};
			return describeAskWithBrief(base, normalizedArgs);
		},
		renderCall(args, options, theme) {
			const normalizedArgs = withAskFormHtml(args);
			return askToolRenderer.renderCall(
				normalizedArgs as Parameters<typeof askToolRenderer.renderCall>[0],
				options,
				theme,
			);
		},
		renderResult(result, options, theme, args) {
			const normalizedArgs = withAskFormHtml(args);
			const card = askToolRenderer.renderResult(
				result as Parameters<typeof askToolRenderer.renderResult>[0],
				options,
				theme,
				normalizedArgs as Parameters<typeof askToolRenderer.renderResult>[3],
			);
			return renderAskWithBrief(card, normalizedArgs);
		},
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			type ScrollbackChatContainer = {
				children: Component[];
				insertChildAt: (comp: Component, idx: number) => void;
				peekFlushBatch: (cols: number) => unknown;
				peekFinalizedBatch?: (cols: number, maxLiveRows: number) => unknown;
			};
			let patchedChat: ScrollbackChatContainer | undefined;
			const brief = extractUnsuppressedBrief(params);
			if (brief && ctx.hasUI && typeof ctx.ui?.custom === "function") {
				await ctx.ui.custom((tui, _theme, _kb, done) => {
					const tuiObj: unknown = tui;
					const children =
						tuiObj && typeof tuiObj === "object" && "children" in tuiObj && Array.isArray(tuiObj.children)
							? tuiObj.children
							: undefined;
					const chat = children?.find(
						(c): c is ScrollbackChatContainer =>
							Boolean(
								c &&
									typeof c === "object" &&
									"children" in c &&
									Array.isArray(c.children) &&
									"insertChildAt" in c &&
									typeof c.insertChildAt === "function" &&
									"peekFlushBatch" in c &&
									typeof c.peekFlushBatch === "function",
							),
					);
					if (chat) {
						suppressedBriefs.add(brief);
						const md = new Markdown(brief, 1, 0, getMarkdownTheme());
						const unfinIdx = chat.children.findIndex((c: unknown) =>
							Boolean(
								c &&
									typeof c === "object" &&
									"isTranscriptBlockFinalized" in c &&
									typeof c.isTranscriptBlockFinalized === "function" &&
									c.isTranscriptBlockFinalized() === false,
							),
						);
						const askIdx = unfinIdx >= 0 ? unfinIdx : Math.max(0, chat.children.length - 1);
						chat.insertChildAt(md, askIdx);
						patchedChat = chat;
						chat.peekFinalizedBatch = (cols: number) => chat.peekFlushBatch(cols);
						for (const child of chat.children) {
							child.invalidate?.();
						}
						if (tuiObj && typeof tuiObj === "object" && "requestRender" in tuiObj && typeof tuiObj.requestRender === "function") {
							tuiObj.requestRender();
						}
					}
					done(undefined);
					return new Container();
				});
			}
			const { brief: _brief, ...restParams } = params as Record<string, unknown>;
			const nativeParams = withAskFormHtml(restParams);
			try {
				if (typeof ctx.invokeTool === "function") {
					return await ctx.invokeTool(nativeParams, { signal, onUpdate });
				}
				throw new Error("Native ask tool is unavailable in this context");
			} finally {
				if (patchedChat) {
					delete patchedChat.peekFinalizedBatch;
				}
			}
		},
	} as Parameters<typeof pi.registerTool>[0]);

	function isWaitPollTimeoutResult(result: unknown): boolean {
		if (!result || typeof result !== "object") return false;
		const r = result as {
			useless?: boolean;
			details?: {
				jobs?: Array<{ status?: string }>;
				cancelled?: unknown[];
				waited?: unknown[];
				interrupted?: boolean;
			};
			content?: Array<{ type?: string; text?: string }>;
		};
		if (r.useless !== true || !r.details || !Array.isArray(r.details.jobs)) return false;
		if (r.details.interrupted || r.details.cancelled?.length || r.details.waited?.length) return false;
		if (!r.details.jobs.every((job) => job?.status === "running")) return false;
		if (!Array.isArray(r.content) || r.content.length === 0) return false;
		const firstText =
			r.content[0]?.type === "text" && typeof r.content[0]?.text === "string" ? r.content[0].text : "";
		return WAIT_POLL_TIMEOUT_RE.test(firstText);
	}
	function stripSettleWindowTimeoutFooter<T>(result: T): T {
		if (!result || typeof result !== "object") return result;
		const r = result as {
			details?: { jobs?: Array<{ status?: string }> };
			content?: Array<{ type?: string; text?: string }>;
		};
		if (
			!Array.isArray(r.details?.jobs) ||
			!r.details.jobs.some((job) => job?.status !== "running") ||
			!Array.isArray(r.content) ||
			r.content.length === 0
		) {
			return result;
		}
		const firstBlock = r.content[0];
		if (!firstBlock || firstBlock.type !== "text" || typeof firstBlock.text !== "string") {
			return result;
		}
		if (!WAIT_POLL_TIMEOUT_RE.test(firstBlock.text)) return result;
		const cleanedText = firstBlock.text.replace(WAIT_POLL_TIMEOUT_RE, "");
		return {
			...result,
			content: [{ ...firstBlock, text: cleanedText }],
		};
	}
	pi.registerTool({
		name: "wait",
		label: "Wait",
		summary: "Wait for the next result of a background job or service you started, or a reply you asked for",
		approval: "read",
		loadMode: "essential",
		strict: true,
		interruptible: true,
		handlesToolInterrupt: true,
		intent: "optional",
		description: [
			"Wait only when blocked with nothing else to do.",
			"Blocks on background jobs/services you started, or on the answer to a question you sent this run.",
			"Nothing you started running and no answer owed? Returns at once.",
			"- MUST wait only on your own jobs/services, or rarely the answer to a question that blocks you.",
			"- NEVER wait for another agent's progress or for messages nobody owes you.",
			"- Result in, other jobs still running? SHOULD act on it before waiting again.",
			"Results and messages auto-deliver. NEVER poll while work remains.",
		].join("\n"),
		parameters: z.object({
			i: z.string().optional().describe("Capitalized 2-6 word present-participle intent"),
		}),
		...waitToolRenderer,
		describeResult(result, options) {
			return waitToolRenderer.describeResult(result, options) ?? {};
		},
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			if (typeof ctx.invokeTool !== "function") {
				throw new Error("Native wait tool is unavailable in this context");
			}
			const { i: _intent, ...nativeParams } = (params ?? {}) as Record<string, unknown>;
			while (true) {
				const result = await ctx.invokeTool(nativeParams, { signal, onUpdate });
				if (signal?.aborted || !isWaitPollTimeoutResult(result)) {
					return stripSettleWindowTimeoutFooter(result);
				}
			}
		},
	} as Parameters<typeof pi.registerTool>[0]);

	pi.registerCommand("bg", {
		description: "Background profile: /bg [on|sol|astra|hydrogen|carbon|off|status]",
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
				applyProfileOverrides(action, profile.roles, profile.agents);
				const model = ctx.models.resolve(profile.mainModel);
				if (!model || !(await pi.setModel(model))) {
					throw new Error(`background mode: cannot switch to ${profile.mainModel}`);
				}
				pi.setThinkingLevel(profile.mainThinking);
				pi.appendEntry(BG_ENTRY_TYPE, {
					mode: action,
					profileHash: computeProfileHash(profile),
					roles: profile.roles,
					agents: profile.agents,
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
				ctx.ui.notify("usage: /bg [on|sol|astra|hydrogen|carbon|off|status]", "warning");
				return;
			}

			syncFromSession(ctx, true);
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
