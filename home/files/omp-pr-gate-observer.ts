// Forwards each successful bash or eval command to `pr-gate trigger`, which owns
// the trigger grammar, debounce, and disable switch for every agent harness.
// Claude Code, Codex, and agy reach the same code through `pr-gate hook`.
import { spawn } from "node:child_process";
import { resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

// Cheap prefilter so ordinary commands do not start a Python process. Anything
// that passes is parsed for real by `pr-gate trigger`.
const MAYBE_TRIGGER_RE = /\b(?:git\b[\s\S]*\bpush|gh\s+pr\s+(?:create|ready))\b/;

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

export default function (pi: ExtensionAPI): void {
	pi.on("tool_result", (event, ctx) => {
		try {
			if (event.isError || process.env.PR_GATE_DISABLE === "1") return undefined;

			let command: string | undefined;
			let cwd = ctx.cwd;
			if (event.toolName === "bash") {
				command = getTextInput(event.input, "command");
				const inputCwd = getTextInput(event.input, "cwd");
				if (inputCwd) cwd = resolve(ctx.cwd, inputCwd);
			} else if (event.toolName === "eval") {
				command = getTextInput(event.input, "code");
			}
			if (!command || !MAYBE_TRIGGER_RE.test(command)) return undefined;

			const agentKind =
				ctx.agent?.name === "advisor" ? "advisor" : ctx.agent?.kind ?? "main";
			const child = spawn(
				"pr-gate",
				[
					"trigger",
					"--harness",
					"omp",
					"--cwd",
					cwd,
					"--agent-kind",
					agentKind,
					// `=` keeps a command that starts with `-` from reading as an option.
					// Stay far below ARG_MAX for very large eval cells.
					`--command=${command.slice(0, 100_000)}`,
				],
				{ detached: true, stdio: "ignore" },
			);
			child.once("error", reportError);
			child.unref();
		} catch (error) {
			reportError(error);
		}
		return undefined;
	});
}
