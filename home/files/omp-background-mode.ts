// `/bg` switches the current session to a background profile for work that can run
// slowly as long as quality holds. The main agent runs on GPT-6.1 Sol and every other
// role and agent is re-curated around it, spending ChatGPT Codex quota instead of
// Anthropic quota wherever a measured equal exists. Overrides live in the runtime
// settings layer only; they never persist and end with the session or `/bg off`.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { lookup } from "@oh-my-pi/pi-coding-agent/config/registry";

const MAIN_MODEL = "openai-codex/gpt-6.1-sol";
const MAIN_THINKING = "xhigh";

const ROLE_OVERRIDES: Record<string, string> = {
	default: `${MAIN_MODEL}:${MAIN_THINKING}`,
	// A different model drafts plans and handles escalations for the Sol implementer.
	plan: "openai-codex/gpt-6-astra:high",
	slow: "openai-codex/gpt-6-astra:xhigh",
	task: `${MAIN_MODEL}:high`,
	advisor: `${MAIN_MODEL}:medium`,
	// smol receives prewalk and plan-yolo implementation handoffs.
	smol: `${MAIN_MODEL}:high`,
	browser: "google/gemini-3.8-flash:medium",
	vision: "google/gemini-3.8-flash:high",
	tiny: "google/gemini-3.5-flash-lite:minimal",
	commit: "anthropic/claude-haiku-5-5:low",
	TRIVIAL: "google/gemini-3.8-flash:medium",
};

const AGENT_OVERRIDES: Record<string, string> = {
	// Sol-authored work gets a review from another model family.
	reviewer: "anthropic/claude-opus-5-5:medium",
	"security-reviewer": `${MAIN_MODEL}:max`,
	sonic: "anthropic/claude-haiku-5-5:low",
	scout: "google/gemini-3.8-flash:medium",
};

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	// Restores the model and thinking level that were active before `/bg on`.
	let restore: (() => Promise<void>) | undefined;

	pi.registerCommand("bg", {
		description: "Background profile: /bg [on|off|status] — GPT-6.1 Sol main agent, roles re-curated around it",
		handler: async (args, ctx) => {
			const roles = lookup("modelRoles");
			const agents = lookup("task.agentModelOverrides");
			if (!roles || !agents) throw new Error("background mode: required settings are unavailable");
			const action = args.trim() || "on";

			if (action === "on") {
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
				roles.override(scope, { ...roles.get(scope), ...ROLE_OVERRIDES });
				agents.override(scope, { ...agents.get(scope), ...AGENT_OVERRIDES });
				const model = ctx.models.resolve(MAIN_MODEL);
				if (!model || !(await pi.setModel(model))) throw new Error(`background mode: cannot switch to ${MAIN_MODEL}`);
				pi.setThinkingLevel(MAIN_THINKING);
			} else if (action === "off") {
				roles.clearOverride(scope);
				agents.clearOverride(scope);
				await restore?.();
				restore = undefined;
			} else if (action !== "status") {
				ctx.ui.notify("usage: /bg [on|off|status]", "warning");
				return;
			}

			const current = ctx.models.current();
			const roleMap = roles.get(scope);
			const agentMap = agents.get(scope);
			ctx.ui.notify(
				`background mode ${restore ? "ON" : "OFF"}: ${current ? `${current.provider}/${current.id}` : "?"}:${pi.getThinkingLevel()}, task=${roleMap.task}, plan=${roleMap.plan}, reviewer=${agentMap.reviewer}`,
				"info",
			);
		},
	});
}
