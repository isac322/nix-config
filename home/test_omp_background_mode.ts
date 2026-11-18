import { describe, expect, mock, test } from "bun:test";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";

mock.module("@oh-my-pi/pi-coding-agent", () => ({}));
mock.module("@oh-my-pi/pi-coding-agent/config/registry", () => ({ lookup: () => undefined }));
mock.module("@oh-my-pi/pi-tui", () => ({ Container: class {}, Markdown: class {}, Spacer: class {} }));
mock.module("@oh-my-pi/pi-tui/theme", () => ({ getMarkdownTheme: () => ({}) }));
mock.module("@oh-my-pi/pi-tui/tools/ask", () => ({ askToolRenderer: {} }));
mock.module("@oh-my-pi/pi-tui/tools/wait", () => ({ waitToolRenderer: {} }));

const mod = await import("./files/omp-background-mode.ts");
const { checkRepoUnswitched, defaultOmpRulesPath, parseManifestSegments } = mod;

type ManifestSegment = NonNullable<ReturnType<typeof parseManifestSegments>>[number];

const REAL_NIX_HOME = join(import.meta.dir);
const LIVE_OMP_DIR = join(homedir(), ".omp/agent");
const LIVE_OMP_RULES = defaultOmpRulesPath();

function asciiCompare(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

function removeTrailingNewline(text: string): string {
	return text.endsWith("\n") ? text.slice(0, -1) : text;
}

function writeFileEnsureDir(filePath: string, content: string): void {
	mkdirSync(dirname(filePath), { recursive: true });
	writeFileSync(filePath, content, "utf8");
}

function deployOmpFromHome(nixHomeDir: string, ompDir: string, ompRulesPath: string): void {
	const extText = readFileSync(join(nixHomeDir, "files/omp-background-mode.ts"), "utf8");
	writeFileEnsureDir(join(ompDir, "extensions/background-mode.ts"), extText);

	const browserText = readFileSync(join(nixHomeDir, "files/agent-instructions/agents/browser.md"), "utf8");
	writeFileEnsureDir(join(ompDir, "agents/browser.md"), browserText);

	const manifestText = readFileSync(join(nixHomeDir, "agent-instruction-segments.nix"), "utf8");
	const segments = parseManifestSegments(manifestText);
	if (!segments) throw new Error("test helper expected valid manifest");

	const cfgBase = readFileSync(join(nixHomeDir, "files/omp-agent-config.yml"), "utf8");
	const policySkills = segments.filter((s) => s.segClass === "onDemand").map((s) => s.name);
	const cfgFull =
		`${removeTrailingNewline(cfgBase)}\n` +
		`skills:\n  ignoredSkills:\n${policySkills.map((n) => `    - ${JSON.stringify(n)}\n`).join("")}` +
		`hindsight:\n  apiUrl: "https://hindsight-api.bhyoo.com"\n  scoping: per-project-tagged\n  globalScope: true\n`;
	writeFileEnsureDir(join(ompDir, "config.yml"), cfgFull);

	const ompSegments = segments.filter((s) => s.harnesses.includes("omp"));
	const compose = (cls: ManifestSegment["segClass"]) => {
		const bodies = ompSegments
			.filter((s) => s.segClass === cls)
			.map((s) => removeTrailingNewline(readFileSync(join(nixHomeDir, s.relPath), "utf8")));
		return `${bodies.join("\n\n")}\n`;
	};

	writeFileEnsureDir(join(ompDir, "AGENTS.md"), compose("context"));
	writeFileEnsureDir(join(ompDir, "PERSONALITY.md"), compose("personality"));
	writeFileEnsureDir(join(ompDir, "RULES.md"), compose("persistent"));

	mkdirSync(join(ompDir, "rules"), { recursive: true });
	const ompRules = ompSegments.filter((s) => s.segClass === "onDemand" || s.segClass === "critical");
	for (const seg of ompRules) {
		const body = removeTrailingNewline(readFileSync(join(nixHomeDir, seg.relPath), "utf8"));
		const alwaysApplyLine = seg.segClass === "critical" ? "alwaysApply: true\n" : "";
		const rendered = `---\ndescription: ${JSON.stringify(seg.description ?? "")}\n${alwaysApplyLine}---\n\n${body}\n`;
		writeFileEnsureDir(join(ompDir, "rules", `${seg.name}.md`), rendered);
	}

	const ruleNames = ompRules.map((s) => `${s.name}.md`).sort(asciiCompare);
	writeFileEnsureDir(ompRulesPath, ruleNames.map((n) => `${n}\n`).join(""));
}

function createMinimalNixHome(
	nixHomeDir: string,
	options?: {
		manifestBody?: string;
		extraFiles?: Record<string, string>;
		skipSegments?: boolean;
	},
): void {
	writeFileEnsureDir(join(nixHomeDir, "files/omp-background-mode.ts"), "// ext\nexport default function () {}\n");
	writeFileEnsureDir(join(nixHomeDir, "files/omp-agent-config.yml"), "setupVersion: 3\n");
	writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/agents/browser.md"), "# Browser\n");

	if (!options?.skipSegments) {
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/ctx.md"), "# Context\n");
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/pers.md"), "# Persistent\n");
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/ond.md"), "# OnDemand\n");
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/crit.md"), "# Critical\n");
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/sty.md"), "# Style\n");
		writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/agy.md"), "# AgyOnly\n");
	}

	const defaultBody = `let
  allHarnesses = [ "omp" "claude" "codex" "agy" ];
  segment = source: class: harnesses: order: {
    inherit class harnesses order source;
  };
in
{
  ctx = segment ./files/agent-instructions/segments/ctx.md "context" allHarnesses 100;
  agy-only = segment ./files/agent-instructions/segments/agy.md "context" [ "agy" ] 900;
  pers = segment ./files/agent-instructions/segments/pers.md "persistent" allHarnesses 100;
  ond = (segment ./files/agent-instructions/segments/ond.md "onDemand" allHarnesses 100) // { description = "On-demand rule."; };
  crit = (segment ./files/agent-instructions/segments/crit.md "critical" allHarnesses 100) // { description = "Critical rule."; };
  sty = segment ./files/agent-instructions/segments/sty.md "personality" [ "omp" "agy" ] 100;
}
`;
	writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), options?.manifestBody ?? defaultBody);

	for (const [rel, text] of Object.entries(options?.extraFiles ?? {})) {
		writeFileEnsureDir(join(nixHomeDir, rel), text);
	}
}

function withCaseDir(
	fn: (dirs: { root: string; nixHomeDir: string; ompDir: string; ompRulesPath: string }) => void,
): void {
	const scratchBase = process.env.OMP_BG_TEST_SCRATCH || tmpdir();
	mkdirSync(scratchBase, { recursive: true });
	const root = mkdtempSync(join(scratchBase, "omp-bg-case-"));
	try {
		fn({
			root,
			nixHomeDir: join(root, "nix-home"),
			ompDir: join(root, "omp-agent"),
			ompRulesPath: join(root, "state/omp-rules"),
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

describe("omp-background-mode statusline switch check", () => {
	test("QA-7: named exports preserve default ExtensionAPI function", () => {
		expect(typeof mod.default).toBe("function");
		expect(typeof parseManifestSegments).toBe("function");
		expect(typeof checkRepoUnswitched).toBe("function");
		expect(typeof defaultOmpRulesPath).toBe("function");
	});

	test("QA-1: real /etc/nix-darwin/home with agy-tools matches freshly deployed OMP dir", () => {
		withCaseDir(({ ompDir, ompRulesPath }) => {
			deployOmpFromHome(REAL_NIX_HOME, ompDir, ompRulesPath);
			expect(checkRepoUnswitched(ompDir, REAL_NIX_HOME, ompRulesPath)).toBe(false);
		});
	});

	test("QA-1b: live ~/.omp/agent matches real manifest once background-mode.ts itself matches", () => {
		if (!existsSync(join(LIVE_OMP_DIR, "AGENTS.md"))) return;
		withCaseDir(({ ompDir, ompRulesPath }) => {
			for (const rel of ["AGENTS.md", "PERSONALITY.md", "RULES.md", "agents/browser.md", "config.yml"]) {
				writeFileEnsureDir(join(ompDir, rel), readFileSync(join(LIVE_OMP_DIR, rel), "utf8"));
			}
			cpSync(join(LIVE_OMP_DIR, "rules"), join(ompDir, "rules"), { recursive: true });
			writeFileEnsureDir(
				join(ompDir, "extensions/background-mode.ts"),
				readFileSync(join(REAL_NIX_HOME, "files/omp-background-mode.ts"), "utf8"),
			);
			if (existsSync(LIVE_OMP_RULES)) {
				writeFileEnsureDir(ompRulesPath, readFileSync(LIVE_OMP_RULES, "utf8"));
			}
			expect(checkRepoUnswitched(ompDir, REAL_NIX_HOME, ompRulesPath)).toBe(false);
		});
	});

	test("QA-2a: adding non-OMP context/persistent/critical/personality segments does not trigger switch", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir);
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/extra-ctx.md"), "# Extra\n");
			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/extra-pers.md"), "# ExtraPers\n");
			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/extra-crit.md"), "# ExtraCrit\n");
			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/extra-sty.md"), "# ExtraSty\n");
			const updated = `let
  allHarnesses = [ "omp" "claude" "codex" "agy" ];
  segment = source: class: harnesses: order: {
    inherit class harnesses order source;
  };
in
{
  ctx = segment ./files/agent-instructions/segments/ctx.md "context" allHarnesses 100;
  agy-only = segment ./files/agent-instructions/segments/agy.md "context" [ "agy" ] 900;
  extra-ctx = segment ./files/agent-instructions/segments/extra-ctx.md "context" [ "agy" "claude" ] 950;
  pers = segment ./files/agent-instructions/segments/pers.md "persistent" allHarnesses 100;
  extra-pers = segment ./files/agent-instructions/segments/extra-pers.md "persistent" [ "codex" ] 200;
  ond = (segment ./files/agent-instructions/segments/ond.md "onDemand" allHarnesses 100) // { description = "On-demand rule."; };
  crit = (segment ./files/agent-instructions/segments/crit.md "critical" allHarnesses 100) // { description = "Critical rule."; };
  extra-crit = segment ./files/agent-instructions/segments/extra-crit.md "critical" [ "claude" "agy" ] 200 // { description = "Claude/agy critical."; };
  sty = segment ./files/agent-instructions/segments/sty.md "personality" [ "omp" "agy" ] 100;
  extra-sty = segment ./files/agent-instructions/segments/extra-sty.md "personality" [ "agy" ] 200;
}
`;
			writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), updated);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);
		});
	});

	test("QA-2b: non-OMP onDemand segment mutates config.yml ignoredSkills and triggers switch until synced", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir);
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);

			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/codex-ond.md"), "# Codex\n");
			const withCodexOnDemand = readFileSync(join(nixHomeDir, "agent-instruction-segments.nix"), "utf8").replace(
				"}\n",
				'  codex-ond = segment ./files/agent-instructions/segments/codex-ond.md "onDemand" [ "codex" ] 200 // { description = "Codex only onDemand."; };\n}\n',
			);
			writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), withCodexOnDemand);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Deploy again so config.yml ignoredSkills includes codex-ond; verify false.
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			// Remove the trailing onDemand segment while leaving stale config.yml; hindsight anchor must catch it.
			const withoutCodexOnDemand = withCodexOnDemand.replace(
				'  codex-ond = segment ./files/agent-instructions/segments/codex-ond.md "onDemand" [ "codex" ] 200 // { description = "Codex only onDemand."; };\n',
				"",
			);
			writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), withoutCodexOnDemand);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
		});
	});

	test("QA-3: modifying any OMP segment body triggers switch", () => {
		const filesToMutate = [
			"files/agent-instructions/segments/ctx.md",
			"files/agent-instructions/segments/pers.md",
			"files/agent-instructions/segments/ond.md",
			"files/agent-instructions/segments/crit.md",
			"files/agent-instructions/segments/sty.md",
		];
		for (const rel of filesToMutate) {
			withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
				createMinimalNixHome(nixHomeDir);
				deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
				const prev = readFileSync(join(nixHomeDir, rel), "utf8");
				writeFileEnsureDir(join(nixHomeDir, rel), `${prev}\nextra\n`);
				expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
			});
		}
	});

	test("QA-4a: adding/removing/reordering OMP segments and editing class or description triggers switch", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir);
			writeFileEnsureDir(join(nixHomeDir, "files/agent-instructions/segments/ctx2.md"), "# Ctx2\n");
			const baseManifest = `let
  allHarnesses = [ "omp" "claude" "codex" "agy" ];
  segment = source: class: harnesses: order: {
    inherit class harnesses order source;
  };
in
{
  ctx = segment ./files/agent-instructions/segments/ctx.md "context" allHarnesses 100;
  ctx2 = segment ./files/agent-instructions/segments/ctx2.md "context" allHarnesses 200;
  pers = segment ./files/agent-instructions/segments/pers.md "persistent" allHarnesses 100;
  ond = segment ./files/agent-instructions/segments/ond.md "onDemand" allHarnesses 100 // { description = "On-demand rule."; };
  crit = segment ./files/agent-instructions/segments/crit.md "critical" allHarnesses 100 // { description = "Critical rule."; };
  sty = segment ./files/agent-instructions/segments/sty.md "personality" [ "omp" "agy" ] 100;
}
`;
			writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), baseManifest);
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			// Reorder ctx2 before ctx.
			writeFileEnsureDir(
				join(nixHomeDir, "agent-instruction-segments.nix"),
				baseManifest.replace("200;", "100;").replace("100;", "200;"),
			);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Switch ond -> critical.
			writeFileEnsureDir(
				join(nixHomeDir, "agent-instruction-segments.nix"),
				baseManifest.replace('"onDemand"', '"critical"'),
			);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Edit description.
			writeFileEnsureDir(
				join(nixHomeDir, "agent-instruction-segments.nix"),
				baseManifest.replace("On-demand rule.", "Changed description."),
			);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Remove ond rule while deployed rule still exists in omp-rules.
			writeFileEnsureDir(
				join(nixHomeDir, "agent-instruction-segments.nix"),
				baseManifest.replace(
					'  ond = segment ./files/agent-instructions/segments/ond.md "onDemand" allHarnesses 100 // { description = "On-demand rule."; };\n',
					"",
				),
			);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
		});
	});

	test("QA-4b: omp-rules ASCII .md sort boundary, empty class newline, and zero OMP rules", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir, {
				skipSegments: true,
				extraFiles: {
					"files/agent-instructions/segments/foo.md": "# Foo\n",
					"files/agent-instructions/segments/foo-approval.md": "# Foo Approval\n",
				},
				manifestBody: `let
  segment = source: class: harnesses: order: {
    inherit class harnesses order source;
  };
in
{
  foo = segment ./files/agent-instructions/segments/foo.md "onDemand" [ "omp" ] 100 // { description = "Foo"; };
  foo-approval = segment ./files/agent-instructions/segments/foo-approval.md "critical" [ "omp" ] 200 // { description = "Foo approval"; };
}
`,
			});
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(readFileSync(ompRulesPath, "utf8")).toBe("foo-approval.md\nfoo.md\n");
			expect(readFileSync(join(ompDir, "AGENTS.md"), "utf8")).toBe("\n");
			expect(readFileSync(join(ompDir, "PERSONALITY.md"), "utf8")).toBe("\n");
			expect(readFileSync(join(ompDir, "RULES.md"), "utf8")).toBe("\n");
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			// Empty AGENTS.md ("") instead of "\n" must trigger switch.
			writeFileEnsureDir(join(ompDir, "AGENTS.md"), "");
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Zero OMP rules with empty omp-rules passes.
			createMinimalNixHome(nixHomeDir, {
				skipSegments: true,
				manifestBody: `let
  segment = source: class: harnesses: order: {
    inherit class harnesses order source;
  };
in
{
}
`,
			});
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(readFileSync(ompRulesPath, "utf8")).toBe("");
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);
		});
	});

	test("QA-5a: parser handles valid Nix forms, comments, escapes, and literal strings", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			const manifest = `# Leading comment
let
  interactive = [ "omp" "agy" ];
  segment = source: class: harnesses: order: {
    inherit order source class harnesses; /* block comment */
  };
in
{
  /* block comment before entry */
  ctx-main = segment ./files/agent-instructions/segments/ctx.md "context" [ "omp" ] 100 // { description = "Optional on ctx"; };
  pers = (segment ./files/agent-instructions/segments/pers.md "persistent" [ "omp" ] 100);
  ond = (
    segment ./files/agent-instructions/segments/ond.md "onDemand" interactive 100
    // { description = "Handles segment ./files/fake.md # not comment \\"quote\\" and \\$VAR"; }
  );
  "2fa" = (segment ./files/agent-instructions/segments/crit.md "critical" [ "omp" ] 100) // { description = "Literal \\t\\r \\$foo"; };
  sty = segment ./files/agent-instructions/segments/sty.md "personality" interactive 100;
}
`;
			createMinimalNixHome(nixHomeDir, { manifestBody: manifest });
			const parsed = parseManifestSegments(manifest);
			expect(parsed).toBeDefined();
			expect(parsed?.find((s) => s.name === "ond")?.description).toBe(
				'Handles segment ./files/fake.md # not comment "quote" and $VAR',
			);
			expect(parsed?.find((s) => s.name === "2fa")?.description).toBe("Literal \t\r $foo");
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);
		});
	});

	test("QA-5b: parser fails closed on invalid/unsupported Nix and returns false when nixHomeDir missing", () => {
		const validLet = `let
  allHarnesses = [ "omp" "agy" ];
  segment = source: class: harnesses: order: { inherit class harnesses order source; };
in
`;
		const invalidManifests = [
			// Interpolation in description
			`${validLet}{ x = segment ./files/a.md "onDemand" allHarnesses 100 // { description = "hi \${x}"; }; }`,
			// Multiline '' string
			`${validLet}{ x = segment ./files/a.md "onDemand" allHarnesses 100 // { description = ''hi''; }; }`,
			// Unterminated block comment
			`${validLet}/* unterminated { }`,
			// Unknown harness binding
			`${validLet}{ x = segment ./files/a.md "context" unknownList 100; }`,
			// Missing segment constructor in let
			`let allHarnesses = [ "omp" ]; in { x = segment ./files/a.md "context" allHarnesses 100; }`,
			// Disallowed let binding
			`${validLet}extra = 123;`,
			// Non-segment entry
			`${validLet}{ x = { source = ./files/a.md; }; }`,
			// Trailing tokens after attrset
			`${validLet}{ x = segment ./files/a.md "context" allHarnesses 100; } // { }`,
			// Out-of-range order
			`${validLet}{ x = segment ./files/a.md "context" allHarnesses 99; }`,
			`${validLet}{ x = segment ./files/a.md "context" allHarnesses 1000; }`,
			// Duplicate path even via ./ normalization
			`${validLet}{ a = segment ./files/a.md "context" allHarnesses 100; b = segment ./files/./a.md "context" allHarnesses 200; }`,
			// Path escaping home/files via ..
			`${validLet}{ a = segment ./files/../secret.md "context" allHarnesses 100; }`,
			// Empty or multiline description
			`${validLet}{ a = segment ./files/a.md "onDemand" allHarnesses 100 // { description = ""; }; }`,
			`${validLet}{ a = segment ./files/a.md "onDemand" allHarnesses 100 // { description = "a\\nb"; }; }`,
			// Missing description on rule class
			`${validLet}{ a = segment ./files/a.md "critical" allHarnesses 100; }`,
			// Codex on personality
			`${validLet}{ a = segment ./files/a.md "personality" [ "codex" ] 100; }`,
			// Duplicate // { description = ...; }
			`${validLet}{ a = (segment ./files/a.md "onDemand" allHarnesses 100 // { description = "a"; }) // { description = "b"; }; }`,
		];

		for (const bad of invalidManifests) {
			expect(parseManifestSegments(bad)).toBeUndefined();
		}

		withCaseDir(({ root, nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir);
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);

			// Invalid manifest triggers fail-closed true.
			writeFileEnsureDir(join(nixHomeDir, "agent-instruction-segments.nix"), invalidManifests[0]);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Deleted manifest in existing nixHomeDir triggers true.
			rmSync(join(nixHomeDir, "agent-instruction-segments.nix"));
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);

			// Non-existent nixHomeDir returns false.
			expect(checkRepoUnswitched(ompDir, join(root, "does-not-exist"), ompRulesPath)).toBe(false);
		});
	});

	test("QA-6a: non-segment mismatches, missing deployed files, unmanaged rules, and missing registry fallback", () => {
		withCaseDir(({ nixHomeDir, ompDir, ompRulesPath }) => {
			createMinimalNixHome(nixHomeDir);
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);

			// Unmanaged user rule in ompDir/rules/ is ignored when omp-rules matches.
			writeFileEnsureDir(join(ompDir, "rules/user-custom.md"), "---\ndescription: mine\n---\n\nhi\n");
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			// Removing omp-rules falls back to rules/ directory comparison, catching user-custom.md mismatch.
			rmSync(ompRulesPath);
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
			rmSync(join(ompDir, "rules/user-custom.md"));
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);

			// Re-deploy and test individual artifact mismatches.
			deployOmpFromHome(nixHomeDir, ompDir, ompRulesPath);
			for (const rel of [
				"extensions/background-mode.ts",
				"agents/browser.md",
				"config.yml",
				"AGENTS.md",
				"rules/ond.md",
			]) {
				const target = join(ompDir, rel);
				const saved = readFileSync(target, "utf8");
				rmSync(target);
				expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
				writeFileEnsureDir(target, `# drift\n${saved}`);
				expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(true);
				writeFileEnsureDir(target, saved);
			}
			expect(checkRepoUnswitched(ompDir, nixHomeDir, ompRulesPath)).toBe(false);
		});
	});

	test("QA-6b: defaultOmpRulesPath rejects empty or relative XDG_STATE_HOME", () => {
		const prev = process.env.XDG_STATE_HOME;
		try {
			const fallback = join(homedir(), ".local/state/nix-managed-agent/omp-rules");
			process.env.XDG_STATE_HOME = "";
			expect(defaultOmpRulesPath()).toBe(fallback);
			process.env.XDG_STATE_HOME = "relative/state";
			expect(defaultOmpRulesPath()).toBe(fallback);
			process.env.XDG_STATE_HOME = "/tmp/custom-xdg-state";
			expect(defaultOmpRulesPath()).toBe("/tmp/custom-xdg-state/nix-managed-agent/omp-rules");
		} finally {
			if (prev === undefined) delete process.env.XDG_STATE_HOME;
			else process.env.XDG_STATE_HOME = prev;
		}
	});
});
