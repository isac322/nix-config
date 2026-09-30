// `/bg` switches the current session to a background profile: the main agents run on
// GPT-6.1 Sol (slower, cheaper, no Anthropic quota) and reviewers move to Opus so
// Sol-authored work still gets a cross-family review. Overrides live in the runtime
// settings layer only; they never persist and end with the session or `/bg off`.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { lookup } from "@oh-my-pi/pi-coding-agent/config/registry";

const MAIN_MODEL = "openai-codex/gpt-6.1-sol";
const MAIN_THINKING = "xhigh";

const ROLE_OVERRIDES: Record<string, string> = {
	default: `${MAIN_MODEL}:${MAIN_THINKING}`,
	task: `${MAIN_MODEL}:${MAIN_THINKING}`,
};

const AGENT_OVERRIDES: Record<string, string> = {
	reviewer: "anthropic/claude-opus-5-5:medium",
	"security-reviewer": "anthropic/claude-opus-5-5:medium",
};

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	// Restores the model and thinking level that were active before `/bg on`.
	let restore: (() => Promise<void>) | undefined;

	pi.registerCommand("bg", {
		description: "Background profile: /bg [on|off|status] — main agents on GPT-6.1 Sol, reviewers on Opus",
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
			ctx.ui.notify(
				`background mode ${restore ? "ON" : "OFF"}: ${current ? `${current.provider}/${current.id}` : "?"}:${pi.getThinkingLevel()}, task=${roles.get(scope).task}, reviewer=${agents.get(scope).reviewer}`,
				"info",
			);
		},
	});
}
