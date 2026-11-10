// omp 18.18.4 paused Google Antigravity: sign-ins from omp were getting Google
// accounts restricted. The pause is compiled into the binary, and there is no
// settings switch. Registering a login under the same provider id is the
// upstream escape hatch. That registration is consulted before the built-in
// key formatter and before token refresh, so this file supplies both and
// delegates the exchange itself to the built-in refresher. Stored logins stay
// on disk. Delete this file to restore the pause.
import { refreshOAuthToken } from "@oh-my-pi/pi-ai/oauth";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const PROVIDER = "google-antigravity";
export default function (pi: ExtensionAPI) {
	pi.registerProvider(PROVIDER, {
		oauth: {
			name: "Google Antigravity (Gemini, Claude, GPT-OSS)",
			// A registered login is consulted before the built-in key formatter.
			// Antigravity requests expect the structured credential, not the raw token.
			getApiKey: (credentials) =>
				JSON.stringify({
					apiEndpoint: credentials.apiEndpoint,
					token: credentials.access,
					enterpriseUrl: credentials.enterpriseUrl,
					projectId: credentials.projectId,
					refreshToken: credentials.refresh,
					expiresAt: credentials.expires,
					email: credentials.email,
					accountId: credentials.accountId,
				}),
			login: async () => {
				throw new Error(
					"Google Antigravity login is handled by the built-in provider. This registration only lifts the pause.",
				);
			},
			refreshToken: (credentials, signal) => refreshOAuthToken(PROVIDER, credentials, signal),
		},
	});
	// Auth storage loads before extensions. While the provider is still paused
	// that load caches no credentials, and lifting the pause does not reread
	// them. Reload once the registration has been applied.
	pi.on("session_start", async (_event, ctx) => {
		await ctx.modelRegistry.authStorage.credentials.reload();
	});
}
