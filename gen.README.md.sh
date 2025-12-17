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

if [ $DIFF_EXIT -ne 0 ]; then
	>&2 echo "no diff"
	rm "$NEW"
else
	mv -f "$NEW" "$CURR"
fi
