#!/usr/bin/env bash

NEW="README.new.md"
CURR="README.md"

export HELP_CODESPACE_CMD_OUTPUT="$(./codespace -h)"
export HELP_CODESPACE_STACK_CMD_OUTPUT="$(./codespace stack -h)"

#shellcheck disable=SC2016
cat <<'EOF' | envsubst '$HELP_CODESPACE_CMD_OUTPUT $HELP_CODESPACE_STACK_CMD_OUTPUT' > "$NEW"
# codespace

git worktrees, with convenience.

<!-- 
NOTE: THIS FILE IS AUTO-GENERATED. DO NOT EDIT MANUALLY.

EDIT gen.README.md.sh instead.
-->

## features

- post-create scripts
  - install dependencies, link files, etc
- simple setup for storing files outside main repository (e.g. AGENTS.md with your preferences)
  - while still tracking in git, just in a separate repo

## use-cases

- working on multiple features at the same time
- reviewing PRs locally
- running multiple agents in parallel on the same task, comparing output, picking best results
- fast iteration in feature-based development
  - customizable pre-defined stacks of repositories to create codespaces from
  - work in parallel on different features
  - shared context for agents - access to all repos involving a feature
- ...

## setup

by default, will install to `$HOME/.local/bin/`:

```sh
./install.sh
```

or, custom prefix (results in `/usr/local/bin/`):

```sh
PREFIX="/usr/local" ./install.sh
```

#### recommended aliases

```sh
git config --global alias.cs "\!codespace"
git config --global alias.css "\!codespace stack"
```

## usage

### codespace

```console
$ codespace -h

$HELP_CODESPACE_CMD_OUTPUT
```

### codespace stack

```console
$ codespace stack -h

$HELP_CODESPACE_STACK_CMD_OUTPUT
```

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

## testing

bats-based test suite covering config resolution & post-create behavior.

```sh
./test/setup.sh   # one-time: vendor bats-core + helpers into test/vendor/
./test/run.sh     # run all tests; forwards args to bats
```

#### sample stacks.json

```json
{
    "version": "0",
    "stacks": {
    	"default": [
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" }
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" },
    	],
        "all": [
            { "name": "admin", "cloneURL": "git@github.com:kiprasmel/admin.git" },
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" },
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" },
            { "name": "infra", "cloneURL": "git@github.com:kiprasmel/infra.git" },
            { "name": "mobile", "cloneURL": "git@github.com:kiprasmel/mobile.git" }
        ],
        "fe": [
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" }
        ],
        "be": [
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" }
        ]
    }
}
```

EOF

test -n "$GIT_PAGER" && {
	diff -u "$CURR" "$NEW" | $GIT_PAGER
	DIFF_EXIT=$?
} || {
	diff -u "$CURR" "$NEW"
	DIFF_EXIT=$?
}

if [ $DIFF_EXIT -eq 0 ]; then
	>&2 echo "no diff"
	rm "$NEW"
else
	mv -f "$NEW" "$CURR"
fi
