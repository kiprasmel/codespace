## agent integration (optional)

extras to make AI agents (e.g. [Cursor](https://cursor.com)) work *inside* a
codespace and stay anchored to it as the conversation grows. these live outside
this repo, under `~/.cursor/`. tweak to taste.

### `/codespace` slash command

save as `~/.cursor/commands/codespace.md` (copy to `cs.md` for a `/cs` alias).
then `/codespace <task>` tells the agent to spin up an isolated codespace, `cd`
into it, mark it, and do the work there — picking stack vs worktree for you:

```md
spin up an isolated codespace for the task described in this message, then do all the work inside it.

pick mode:
- if the task explicitly says stack or worktree, use that.
- else run `codespace current kind`: if it prints `stack` (you're already in a stack), make a stack.
- else make a single worktree.

create it (under cursor, prompts + editor auto-skip; fresh off remote HEAD):
- worktree: `codespace <branch> --no-edit`
- stack:    `codespace stack create <branch> --no-edit`   (no stacks.json? it auto-falls back to a worktree)
where <branch> is a short kebab-case name from the task.

then:
- enter it: `cd "$(codespace find <branch>)"`
- record the anchor: `codespace mark-current "<one-line summary of the task>"`
- treat that dir as the project root: base every shell command and file path on it,
  never touch the original checkout. if unsure where you are, run `codespace current`.
- do the task.
```

### keep agents anchored (global AGENTS.md)

add to `~/.cursor/AGENTS.md` (or any always-applied rule) so the agent
re-orients off the `.codespace/current` marker instead of drifting back to the
original checkout when context grows:

```md
## Codespaces

Before/while working, run `codespace current` (or walk up cwd for a `.codespace/current` file). If it exists, you're in a codespace created for this task: its `path=` is your project root and `task=` is the goal — work there, base all paths on it, and don't edit any other checkout. If you lose track, re-read it. (See the `/codespace` command.)
```
