import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type Trigger = "push" | "pr-create" | "pr-ready";

type ParsedTrigger = {
	trigger: Trigger;
	dirToken?: string;
};

type Candidate = ParsedTrigger & {
	index: number;
};

const TOKEN = `(?:"([^"]*)"|'([^']*)'|([^\\s;&|]+))`;
const PREFIX =
	`(?:env\\s+)?(?:(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\\s;&|]+))\\s+)*(?:command\\s+)?`;
const GIT_PUSH_RE = new RegExp(
	`(?:^|[\\s;&|])${PREFIX}git(?:\\s+-C\\s+${TOKEN})?\\s+push(?=\\s|$|[;&|])`,
	"g",
);
const GH_PR_RE = new RegExp(
	`(?:^|[\\s;&|])${PREFIX}gh\\s+pr\\s+(create|ready)(?=\\s|$|[;&|])`,
	"g",
);
const CD_RE = new RegExp(
	`(?:^|[;&|\\n]\\s*)cd\\s+${TOKEN}`,
	"g",
);

function tokenValue(match: RegExpExecArray, firstCapture: number): string | undefined {
	return match[firstCapture] ?? match[firstCapture + 1] ?? match[firstCapture + 2];
}

function shellSegment(command: string, index: number): string {
	const end = command.slice(index).search(/[;|\n]/);
	return end === -1 ? command.slice(index) : command.slice(index, index + end);
}

function hasFlag(segment: string, flag: RegExp): boolean {
	return /(?:^|\s)--help(?:=|\s|$)/.test(segment) || flag.test(segment);
}

function lastCdBefore(command: string, index: number): string | undefined {
	let last: string | undefined;
	for (const match of command.matchAll(CD_RE)) {
		if ((match.index ?? 0) >= index) break;
		last = tokenValue(match as RegExpExecArray, 1);
	}
	return last;
}

// Pure command matching: it only inspects the supplied text and returns a trigger.
function parseTrigger(command: string): ParsedTrigger | undefined {
	const candidates: Candidate[] = [];

	for (const match of command.matchAll(GIT_PUSH_RE)) {
		const index = match.index ?? 0;
		const segment = shellSegment(command, index);
		if (hasFlag(segment, /(?:^|\s)(?:--dry-run(?:=|\s|$)|-n(?:\s|$))/)) continue;
		candidates.push({
			trigger: "push",
			index,
			dirToken: tokenValue(match as RegExpExecArray, 1),
		});
	}

	for (const match of command.matchAll(GH_PR_RE)) {
		const index = match.index ?? 0;
		const segment = shellSegment(command, index);
		const subcommand = match[1];
		if (hasFlag(segment, /(?:^|\s)(?:--draft(?:=|\s|$)|-d(?:\s|$))/)) continue;
		if (subcommand === "ready" && /(?:^|\s)--undo(?:=|\s|$)/.test(segment)) continue;
		candidates.push({
			trigger: subcommand === "create" ? "pr-create" : "pr-ready",
			index,
		});
	}

	candidates.sort((a, b) => a.index - b.index);
	const candidate = candidates[0];
	if (!candidate) return undefined;

	return {
		trigger: candidate.trigger,
		dirToken: lastCdBefore(command, candidate.index) ?? candidate.dirToken,
	};
}

function resolveWorkdir(dirToken: string | undefined, cwd: string): string {
	if (!dirToken) return resolve(cwd);
	const expanded =
		dirToken === "~"
			? homedir()
			: dirToken.startsWith("~/")
				? resolve(homedir(), dirToken.slice(2))
				: dirToken;
	return isAbsolute(expanded) ? resolve(expanded) : resolve(cwd, expanded);
}

function getTextInput(input: unknown, key: string): string | undefined {
	if (!input || typeof input !== "object") return undefined;
	const value = (input as Record<string, unknown>)[key];
	return typeof value === "string" ? value : undefined;
}

let errorReported = false;
function reportError(error: unknown): void {
	if (errorReported) return;
	errorReported = true;
	try {
		process.stderr.write(
			`pr-gate observer: ${error instanceof Error ? error.message : String(error)}\n`,
		);
	} catch {
		// The observer must never affect the calling tool result.
	}
}

const lastSpawn = new Map<string, number>();
const DEBOUNCE_MS = 5_000;

function spawnObservation(
	parsed: ParsedTrigger,
	cwd: string,
	command: string,
	agentKind: string,
): void {
	const now = Date.now();
	for (const [key, at] of lastSpawn) {
		if (now - at >= DEBOUNCE_MS) lastSpawn.delete(key);
	}
	const key = `${cwd}\0${parsed.trigger}`;
	const previous = lastSpawn.get(key);
	if (previous !== undefined && now - previous < DEBOUNCE_MS) return;
	lastSpawn.set(key, now);

	const child = spawn(
		"pr-gate",
		[
			"observe",
			"--cwd",
			cwd,
			"--trigger",
			parsed.trigger,
			"--command",
			command.slice(0, 2_000),
		],
		{
			detached: true,
			stdio: "ignore",
			env: {
				...process.env,
				PR_GATE_AGENT_KIND: agentKind,
				PR_GATE_TRIGGER_TS: new Date().toISOString(),
			},
		},
	);
	child.once("error", reportError);
	child.unref();
}

export default function (pi: ExtensionAPI): void {
	pi.on("tool_result", (event, ctx) => {
		try {
			if (event.isError || process.env.PR_GATE_DISABLE === "1") return undefined;

			const inputCwd = getTextInput(event.input, "cwd");
			const baseCwd = inputCwd ? resolve(ctx.cwd, inputCwd) : ctx.cwd;
			let command: string | undefined;
			let cwd = baseCwd;

			if (event.toolName === "bash") {
				command = getTextInput(event.input, "command");
			} else if (event.toolName === "eval") {
				command = getTextInput(event.input, "code");
				cwd = ctx.cwd;
			}
			if (!command) return undefined;

			const parsed = parseTrigger(command);
			if (!parsed) return undefined;
			const agentKind =
				ctx.agent?.name === "advisor" ? "advisor" : ctx.agent?.kind ?? "main";
			spawnObservation(
				parsed,
				resolveWorkdir(parsed.dirToken, cwd),
				command,
				agentKind,
			);
		} catch (error) {
			reportError(error);
		}
		return undefined;
	});
}

if (import.meta.main) {
	const cases: Array<[string, Trigger | undefined]> = [
		["git push", "push"],
		["git -C ~/src/repo push origin main", "push"],
		["cd 'repo with spaces' && git push", "push"],
		["env FOO=1 git push", "push"],
		["GIT_SSH_COMMAND='ssh -i key' command git push", "push"],
		["git push --force-with-lease origin HEAD:branch", "push"],
		["git push origin main refs/heads/a:refs/heads/b", "push"],
		["git push origin main || true", "push"],
		["git push --dry-run", undefined],
		["git push -n origin main", undefined],
		["git push --help", undefined],
		["gh pr create --title change", "pr-create"],
		["gh pr create --draft", undefined],
		["gh pr create -d", undefined],
		["gh pr ready", "pr-ready"],
		["gh pr ready --undo", undefined],
		["git pushd", undefined],
		["echo 'git push'", undefined],
	];
	for (const [command, expected] of cases) {
		const actual = parseTrigger(command)?.trigger;
		if (actual !== expected) {
			throw new Error(`parser case failed: ${command} (${actual ?? "none"})`);
		}
	}
}
