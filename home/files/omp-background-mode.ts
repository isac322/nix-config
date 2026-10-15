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

const SOL_PROFILE: Profile = {
	label: "Sol",
	mainModel: SOL,
	mainThinking: "xhigh",
	roles: {
		default: `${SOL}:xhigh`,
		// Planning inherits the base Argon plan role, so a different model family still
		// drafts plans for the Sol implementer; escalations go to Astra.
		slow: `${ASTRA}:xhigh`,
		task: `${SOL}:high`,
		advisor: `${SOL}:medium`,
		// smol receives prewalk and plan-yolo implementation handoffs.
		smol: `${SOL}:high`,
	},
	// Sol-authored work gets a review from another model family, and scout, sonic and
	// commit stay on the base Flash models.
	agents: {
		reviewer: "anthropic/claude-opus-5-5:medium",
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
		// Sol still implements, so the Opus reviewer stays in a different model family.
		agents: SOL_PROFILE.agents,
	},
};

const SUBCOMMANDS = [
	{ name: "on", description: "Sol main agent, roles re-curated around it" },
	{ name: "argon", description: "Trial: Gemini 4 Argon main agent, Sol implementer" },
	{ name: "off", description: "Restore the base config and the previous model" },
	{ name: "status", description: "Show the active profile and key roles" },
];

export default function (pi: ExtensionAPI) {
	const scope = pi.pi.settings;
	// Restores the model and thinking level that were active before the first profile switch.
	let restore: (() => Promise<void>) | undefined;
	let active: string | undefined;

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
