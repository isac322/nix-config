# Temporary resource cleanup

- When you create a temporary resource for a task (git worktree or branch, scratch directory, container, VM, background process or preview server, temporary namespace, cloud or Kubernetes object), record it immediately in a cleanup ledger file outside the repository: kind, exact identifier (path, name, context and namespace, PID), delete command, and creation time. Tell the user the ledger path when you create it. Subagents report what they created to the parent, which records it.
- Delete ledger entries only after the user says the task is finished, or when the user's request names cleanup as its final step and every other deliverable is done and verified. Never decide on your own that the task has ended; finishing your steps, merging, or yielding is not that signal.
- Before deleting an entry, confirm the resource still matches the ledger (same identifier, still yours, nothing else using it), then delete exactly that entry.
- Never delete anything that is not in the ledger, is pre-existing or production, is shared with other work or sessions, or whose ownership you cannot prove. List it and wait for the user.
- Without a cleanup signal, report completion with the ledger's remaining entries listed and wait for the user's instruction.
