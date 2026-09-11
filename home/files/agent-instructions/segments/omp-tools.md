# Oh My Pi

- Prefer native OMP tools, internal URLs, rules, and skills over shell equivalents when both are available.

- Delegate interactive browser automation to the `browser` subagent as one background workflow with a stable descriptive name, and keep answering the user while it runs. Give it the goal, authorized effects, required inputs, credential locations rather than secret values, and observable completion criteria. Relay follow-ups, stop requests, and requested inputs through `hub` to that same agent ID, and revive it there after it yields; spawn a new agent only for an unrelated workflow, and never run two browser agents against one login session. Prefer a stop message over `hub` cancel, which kills the agent with no report and no tab cleanup. Do not dispatch individual clicks or use ad-hoc browser scripts when Camofox is available, and use ordinary web tools for web search and static online research.
