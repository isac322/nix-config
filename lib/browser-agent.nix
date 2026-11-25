# The Camofox browser subagent is written once, for OMP, in
# home/files/agent-instructions/agents/browser.md. Other harnesses receive the
# same procedure with OMP's tool names and parent channel translated; each
# translation must still find every phrase it rewrites, so an edit to the OMP
# file fails evaluation instead of shipping a half-translated agent.
{ lib }:

let
  source = builtins.readFile ../home/files/agent-instructions/agents/browser.md;
  parts = lib.splitString "\n---\n" source;
  frontmatter = lib.splitString "\n" (builtins.head parts);
  body = lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (lib.drop 1 parts));

  descriptionLine = lib.findFirst (lib.hasPrefix "description: ") null frontmatter;

  # OMP asks `Main` mid-run and waits. Harnesses whose subagents cannot wait on
  # their parent stop instead and are resumed on the same tab with the answer.
  hubAsk = "ask `Main` through `hub` with `await: true` and `timeoutMs: 120000`";
  hubWait = " A reply that does not answer your request is steering: act on it and keep waiting for the answer. If no answer arrives, yield `blocked` with the request and the retained `tabId`; a later message revives you on the same tab.";
in
{
  description =
    assert lib.assertMsg (descriptionLine != null) "agents/browser.md lost its description line";
    lib.removePrefix "description: " descriptionLine;

  # Camofox MCP tool names without OMP's `mcp__` prefix, such as `camofox_click`.
  camofoxTools = map (line: lib.removePrefix "  - mcp__" line) (
    lib.filter (lib.hasPrefix "  - mcp__camofox_") frontmatter
  );

  # `channel` is either "message" (the subagent asks through `askMain`) or
  # "resume" (the subagent stops `blocked` and the parent resumes it).
  procedure =
    {
      camofoxPrefix,
      shell,
      channel,
      askMain ? null,
    }:
    let
      replacements = {
        "mcp__camofox_" = camofoxPrefix;
        "`bash`" = shell;
      }
      // (
        if channel == "message" then
          { ${hubAsk} = askMain; }
        else
          {
            "keep the tab open and ${hubAsk}." =
              "keep the tab open, stop, and yield `blocked` with the request and the retained `tabId`; `Main` resumes you on the same tab with the answer.";
            ${hubWait} = "";
          }
      );
      froms = builtins.attrNames replacements;
      missing = lib.filter (from: !lib.hasInfix from body) froms;
      translated = builtins.replaceStrings froms (map (from: replacements.${from}) froms) body;
    in
    assert lib.assertMsg (
      missing == [ ]
    ) "agents/browser.md no longer contains: ${lib.concatStringsSep ", " missing}";
    assert lib.assertMsg (
      !lib.any (needle: lib.hasInfix needle translated) [
        "`hub`"
        "`bash`"
      ]
    ) "agents/browser.md gained an OMP tool name the translation does not cover";
    translated;
}
